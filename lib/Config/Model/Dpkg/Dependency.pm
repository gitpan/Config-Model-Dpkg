package Config::Model::Dpkg::Dependency ;

use 5.10.1;

use Mouse;
use namespace::autoclean;

# Debian only module
use lib '/usr/share/lintian/lib' ;
use Lintian::Relation ;

use DB_File ;
use Log::Log4perl qw(get_logger :levels);
use Module::CoreList;
use version ;

use Parse::RecDescent ;

use AnyEvent::HTTP ;

# available only in debian. Black magic snatched from 
# /usr/share/doc/libapt-pkg-perl/examples/apt-version 
use AptPkg::Config '$_config';
use AptPkg::System '$_system';
use AptPkg::Version;
use AptPkg::Cache ;

use vars qw/$test_filter/ ;
$test_filter = ''; # reserved for tests

my $logger = get_logger("Tree::Element::Value::Dependency") ;
my $async_log = get_logger("Async::Value::Dependency") ;

# initialise the global config object with the default values
$_config->init;

# determine the appropriate system type
$_system = $_config->system;

# fetch a versioning system
my $vs = $_system->versioning;

my $apt_cache = AptPkg::Cache->new ;

# end black magic

extends qw/Config::Model::Value/ ;

# when apply_fix is used ($arg[1]), this grammer will modify inline
# the dependency value through the value ref ($arg[2])
my $grammar = << 'EOG' ;

{
    my @dep_errors ;
    my $add_error = sub {
        my ($err, $txt) = @_ ;
        push @dep_errors, "$err: '$txt'" ;
        return ; # to ensure production error
    } ;
}

# comment this out when modifying the grammar
<nocheck>

dependency: { @dep_errors = (); } <reject>

dependency: depend(s /\|/) eofile {
    $return = [ 1 , @{$item[1]} ] ;
  }
  |  {
    push( @dep_errors, "Cannot parse: '$text'" ) unless @dep_errors ;
    $return =  [ 0, @dep_errors ];
  }

depend: pkg_dep | variable

# For the allowed stuff after ${foo}, see #702792
variable: /\${[\w:\-]+}[\w\.\-~+]*/

pkg_dep: pkg_name dep_version(?) arch_restriction(?) {
    my $dv = $item[2] ;
    my $ar = $item[3] ;
    my @ret = ( $item{pkg_name} ) ;
    if    (@$dv and @$ar) { push @ret, @{$dv->[0]}, @{$ar->[0]} ;}
    elsif (@$dv)          { push @ret, @{$dv->[0]} ;}
    elsif (@$ar)          { push @ret, undef, undef, @{$ar->[0]} ;}
    $return = \@ret ; ;
   } 

arch_restriction: '[' osarch(s) ']'
    {
        my $mismatch = 0;
        my $ref = $item[2] ;
        for (my $i = 0; $i < $#$ref -1 ; $i++ ) {
            $mismatch ||= ($ref->[$i][0] xor $ref->[$i+1][0]) ;
        }
        my @a = map { ($_->[0] || '') . ($_->[1] || '') . $_->[2] } @$ref ;
        if ($mismatch) {
            $add_error->("some names are prepended with '!' while others aren't.", "@a") ;
        }
        else {
            $return = \@a ;
        }
    }

dep_version: '(' oper version ')' { $return = [ $item{oper}, $item{version} ] ;} 

pkg_name: /[a-z0-9][a-z0-9\+\-\.]+(?=\s|\Z|\(|\[)/
    | /\S+/ { $add_error->("bad package name", $item[1]) ;}

oper: '<<' | '<=' | '=' | '>=' | '>>'
    | /\S+/ { $add_error->("bad dependency version operator", $item[1]) ;}

version: variable | /[\w\.\-~:+]+(?=\s|\)|\Z)/
    | /\S+/ { $add_error->("bad dependency version", $item[1]) ;}

# valid arch are listed by dpkg-architecture -L
osarch: not(?) os(?) arch
    {
        $return =  [ $item[1][0], $item[2][0], $item[3] ];
    }

not: '!'

os: /(any|uclibc-linux|linux|kfreebsd|knetbsd|kopensolaris|hurd|darwin|freebsd|netbsd|openbsd|solaris|uclinux)
   -/x
   | /\w+/ '-' { $add_error->("bad os in architecture specification", $item[1]) ;}

arch: / (any |alpha|amd64 |arm\b |arm64 |armeb |armel |armhf |avr32
        |hppa |i386 |ia64 |lpia |m32r |m68k |mips\b |mipsel |powerpc
        |powerpcspe |ppc64 |s390 |s390x |sh3\b |sh3eb |sh4\b |sh4eb |sparc\b |sparc64 |x32 )
        (?=(\]| ))
      /x
      | /\w+/ { $add_error->("bad arch in architecture specification", $item[1]) ;}


eofile: /^\Z/

EOG

my $parser ;

sub dep_parser {
    $parser ||= Parse::RecDescent->new($grammar) ;
    return $parser ;
}

# this method may recurse bad:
# check_dep -> meta filter -> control maintainer -> create control class
# autoread started -> read all fileds -> read dependency -> check_dep ...

sub check_value {
    my $self = shift ;
    my %args = @_ > 1 ? @_ : (value => $_[0]) ;
    my $cb = delete $args{callback} || sub {} ;
    my $my_cb = sub {
        $self->check_dependency(@_, callback => $cb) ;
    } ;
    
    $args{fix} //= 0;
    $self->SUPER::check_value(%args, callback => $my_cb) ;

}

sub check_dependency {
    my $self = shift;
    my %args = @_ ;

    my ($value, $check, $silent, $notify_change, $ok, $callback,$apply_fix) 
        = @args{qw/value check silent notify_change ok callback fix/} ;

    # value is one dependency, something like "perl ( >= 1.508 )"
    # or exim | mail-transport-agent or gnumach-dev [hurd-i386]

    # see http://www.debian.org/doc/debian-policy/ch-relationships.html
    
    # to get package list
    # wget -q -O - 'http://qa.debian.org/cgi-bin/madison.cgi?package=perl-doc&text=on'

    my @dep_chain ;
    if (defined $value) {
        $logger->debug("calling check_depend with Parse::RecDescent with '$value'");
        my $ret = dep_parser->dependency ( $value ) ;
        my $ok = shift @$ret ;
        if ($ok) {
            @dep_chain = @$ret ;
        }
        else {
            $self->add_error(@$ret) ;
        }
    }

    # check_dependency is always called with a callback. This callback must
    # must called *after* all asynchronous calls are done (which depends on the
    # packages listed in the dependency). So use begin and end on this condvar and
    # nothing else, not send/recv
    my $pending_check = AnyEvent->condvar ;

    my $old = $value ;

    my $check_depend_chain_cb = sub {
        # blocking with inner async calls
        $self->check_depend_chain($apply_fix, \@dep_chain, $old ) ;
        $self->on_check_all_done($apply_fix,\@dep_chain,$old, sub { $callback->(%args) if $callback; });
    } ;
    
    $async_log->debug("begin for ",$self->composite_name, " fix is $apply_fix") if $async_log->is_debug;
    $pending_check->begin($check_depend_chain_cb) ;
    
    foreach my $dep (@dep_chain) {
        next unless ref($dep) ; # no need to check variables
        $pending_check->begin ;
        my $cb = sub {
            $self->check_or_fix_essential_package($apply_fix, $dep, $old) ; # sync
            $self->check_or_fix_dep($apply_fix, $dep, $old, sub { $pending_check -> end}) ; # async
        };
        $self->check_or_fix_pkg_name($apply_fix, $dep, $old, $cb) ; # async
    }

    
    $async_log->debug("end for ",$self->composite_name) if $async_log->is_debug;
    $pending_check->end;
}

# this callback will be launched when all checks are done. this can be at
# the 'end' call at this end of this sub if all calls of check_depend are
# synchronous (which may be the case if all dependency informations are in cache)
# or it can be in one of the call backs
sub on_check_all_done {
    my ($self, $apply_fix, $dep_chain, $old, $next) = @_ ;

    # "ideal" dependency is always computed, but it does not always change
    my $new = $self->struct_to_dep(@$dep_chain);

    if ( $logger->is_debug ) {
        my $new //= '<undef>';
        $async_log->debug( "in on_check_all_done callback for ",
            $self->composite_name, " ($new) fix is $apply_fix" )
          if $async_log->is_debug;
        no warnings 'uninitialized';
        $logger->debug( "'$old' done" . ( $apply_fix ? " changed to '$new'" : '' ) );
    }

    {
        no warnings 'uninitialized';
        $self->_store_fix( $old, $new ) if $apply_fix and $new ne $old;
    }
    $next->();
}

sub check_debhelper_version {
    my ($self, $apply_fix, $depend) = @_ ;
    my ( $dep_name, $oper, $dep_v, @archs ) = @$depend ;

    my $dep_string = $self->struct_to_dep($depend) ;
    my $lintian_dep = Lintian::Relation->new( $dep_string ) ;
    $logger->debug("checking '$dep_string' with lintian");

    # using mode loose because debian-control model can be used alone
    # and compat is outside of debian-control
    my $compat = $self->grab_value(mode => 'loose', step => "!Dpkg compat") ;
    return unless defined $compat ;

    my $min_dep = Lintian::Relation->new("debhelper ( >= $compat)") ;
    $logger->debug("checking if ".$lintian_dep->unparse." implies ". $min_dep->unparse);
    
    return if $lintian_dep->implies ($min_dep) ;
    
    $logger->debug("'$dep_string' does not imply debhelper >= $compat");
    
    # $show_rel avoids undef warnings
    my $show_rel = join(' ', map { $_ || ''} ($oper, $dep_v));
    if ($apply_fix) {
        @$depend = ( 'debhelper', '>=', $compat ) ; # notify_change called in check_value
        $logger->info("fixed debhelper dependency from "
            ."$dep_name $show_rel -> ".$min_dep->unparse." (for compat $compat)");
    }
    else {
        $self->{nb_of_fixes}++ ;
        my $msg = "should be (>= $compat) not ($show_rel) because compat is $compat" ;
        $self->add_warning( $msg );
        $logger->info("will warn: $msg (fix++)");
    }
}

my @deb_releases = qw/etch lenny squeeze wheezy/;

my %deb_release_h ;
while (@deb_releases) {
    my $k = pop @deb_releases ;
    my $regexp = join('|',@deb_releases,$k);
    $deb_release_h{$k} = qr/$regexp/;
}

# called in check_versioned_dep and in Parse::RecDescent grammar 
sub xxget_pkg_versions {
    my ($self,$cb,$pkg) = @_ ;
    $logger->debug("get_pkg_versions: called with $pkg");

    # check if Debian has version older than required version
    my ($has_info, @dist_version) = $self->get_available_version($pkg) ;
    # print "\t'$pkg' => '@dist_version',\n";

    return () unless $has_info ;

    return @dist_version ;
}

#
# New subroutine "struct_to_dep" extracted - Mon Aug 27 13:45:02 2012.
#
sub struct_to_dep {
    my $self = shift ;
    my @input = @_ ;

    my $skip = 0 ;
    my @alternatives ;
    foreach my $d (@input) {
        my $line = '';
        # empty str or ref to empty array are skipped
        if( ref ($d) and @$d) {
            $line .= "$d->[0]";

            # skip test for relations like << or < 
            $skip ++ if defined $d->[1] and $d->[1] =~ /</ ;
            $line .= " ($d->[1] $d->[2])" if defined $d->[2];

            if (@$d > 3) {
                $line .= ' ['. join(' ',@$d[3..$#$d]) .']' ;
            }

        }
        elsif (not ref($d) and $d) { 
            $line .= $d ; 
        } ;

        push @alternatives, $line if $line ;
    }
    
    my $actual_dep = @alternatives ? join (' | ',@alternatives) : undef ;

    return wantarray ? ($actual_dep, $skip) : $actual_dep ;
}

# @input contains the alternates dependencies (without '|') of one dependency values
# a bit like @input = split /|/, $dependency

# will modify @input (array of ref) when applying fix
sub check_depend_chain {
    my ($self, $apply_fix, $input, $old) = @_ ;
    
    my ($actual_dep, $skip) = $self->struct_to_dep (@$input);
    my $ret = 1 ;

    return 1 unless defined $actual_dep; # may have been cleaned during fix
    $logger->debug("called with $actual_dep with apply_fix $apply_fix");

    if ($skip) {
        $logger->debug("skipping '$actual_dep': has a < relation ship") ;
        return $ret ;
    }
    
    $async_log->debug("begin check alternate deps for $actual_dep") ;
    foreach my $depend (@$input) {
        if (ref ($depend)) {
            # is a dependency (not a variable a la ${perl-Depends})
            my ($dep_name, $oper, $dep_v) = @$depend ;
            $logger->debug("scanning dependency $dep_name"
                .(defined $dep_v ? " $dep_v" : ''));
            if ($dep_name =~ /lib([\w+\-]+)-perl/) {
                my $pname = $1 ;
                # AnyEvent condvar is involved in this method, blocks while inner async call are in progress
                $ret &&= $self->check_perl_lib_dep ($apply_fix, $pname, $actual_dep, $depend,$input);
                last;
            }
        }
    }
    $async_log->debug("end check alternate deps for $actual_dep") ;
    
    if ($logger->is_debug and $apply_fix) {
        my $str = $self->struct_to_dep(@$input) ;
        $str //= '<undef>' ;
        $logger->debug("new dependency is $str");
    }
    
    return $ret ;
}

# called through check_depend_chain
# does modify $input when applying fix
sub check_perl_lib_dep {
    my ($self, $apply_fix, $pname, $actual_dep, $depend, $input) = @_;
    $logger->debug("called with $actual_dep with apply_fix $apply_fix");

    my ( $dep_name, $oper, $dep_v ) = @$depend;
    my $ret = 1;

    $pname =~ s/-/::/g;

    # The dependency should be in the form perl (>= 5.10.1) | libtest-simple-perl (>= 0.88)".
    # cf http://pkg-perl.alioth.debian.org/policy.html#debian_control_handling
    # If the Perl version is not available in sid, the order of the dependency should be reversed
    # libcpan-meta-perl | perl (>= 5.13.10)
    # because buildd will use the first available alternative

    # check for dual life module, module name follows debian convention...
    my @dep_name_as_perl = Module::CoreList->find_modules(qr/^$pname$/i) ;
    return $ret unless @dep_name_as_perl;

    return $ret if defined $dep_v && $dep_v =~ m/^\$/ ;

    # here we have async consecutive calls to get_available_version, check_versioned_dep
    # and get_available_version. Must block and return once they are done
    # hence the condvar
    my $perl_dep_cv = AnyEvent->condvar ;
    
    my @ideal_perl_dep = qw/perl/ ;
    my @ideal_lib_dep ;
    my @ideal_dep_chain = (\@ideal_perl_dep);

    my ($on_get_lib_version, $on_perl_check_done, $check_perl_lib, $get_perl_versions, $on_get_perl_versions) ;

    my ($v_normal) ;

    # check version for the first available version in Debian: debian
    # dep may have no version specified but older versions can be found
    # in CPAN that were never packaged in Debian
    $on_get_lib_version = sub {
        $async_log->debug("on_get_lib_version called with @_") ;
        # get_available_version returns oldest first, like (etch,1.2,...)
        my $oldest_lib_version_in_debian = $_[1] ;
        # lob off debian release number
        $oldest_lib_version_in_debian =~ s/-.*//;
        my $check_v = $dep_v || $oldest_lib_version_in_debian ;
        $logger->debug("dual life $dep_name has oldest debian $oldest_lib_version_in_debian, using $check_v");
        my ($cpan_dep_v, $epoch_dep_v) ;

        ($cpan_dep_v, $epoch_dep_v) = reverse split /:/ ,$check_v if defined $check_v ;
        my $v_decimal = Module::CoreList->first_release(
            $dep_name_as_perl[0],
            version->parse( $cpan_dep_v )
        );

        if (defined $v_decimal) {
            $v_normal = version->new($v_decimal)->normal;
            $v_normal =~ s/^v//;    # loose the v prefix
            if ( $logger->is_debug ) {
                my $dep_str = $dep_name . ( defined $check_v ? ' ' . $check_v : '' );
                $logger->debug("dual life $dep_str aka $dep_name_as_perl[0] found in Perl core $v_normal");
            }
            $self->check_versioned_dep( $on_perl_check_done , ['perl', '>=', $v_normal] );
        }
        else {
            # no need to check further. Call send to unblock wait done with recv
            AnyEvent::postpone { $perl_dep_cv->send };
        }
    };

    
    $on_perl_check_done =  sub {
        my $has_older_perl = shift ;
        $async_log->debug("on_perl_check_done called") ;
        push @ideal_perl_dep, '>=', $v_normal if $has_older_perl;
        $check_perl_lib->($has_older_perl) ;
    } ;

    $check_perl_lib = sub {
        my $has_older_perl = shift;
        $async_log->debug( "check_perl_lib called with dep_v " . ( $dep_v // 'undef' ) );

        my $on_perl_lib_check_done = sub {
            my $has_older_lib = shift;
            $async_log->debug("on_perl_lib_check_done called");
            if ($has_older_perl) {
                push @ideal_lib_dep, $dep_name;
                push @ideal_lib_dep, '>=', $dep_v if $has_older_lib;
            }
            $get_perl_versions->();
        };

        if ( defined $dep_v ) {
            $self->check_versioned_dep( $on_perl_lib_check_done, $depend );
        }
        else {
            $on_perl_lib_check_done->(0);
        }
    };

    $get_perl_versions = sub {
        $self->get_available_version($on_get_perl_versions, 'perl');
    } ;
    
    $on_get_perl_versions = sub {
        my %perl_version = @_ ;
        $async_log->debug("running on_get_perl_versions for $actual_dep") ;
        my $has_older_perl_in_sid = ( $vs->compare( $v_normal, $perl_version{sid} ) < 0 ) ? 1 : 0;
        $logger->debug(
            "perl $v_normal is",
            $has_older_perl_in_sid ? ' ' : ' not ',
            "older than perl in sid ($perl_version{sid})"
        );

        my @ordered_ideal_dep = $has_older_perl_in_sid ? 
            ( \@ideal_perl_dep, \@ideal_lib_dep ) :
            ( \@ideal_lib_dep, \@ideal_perl_dep ) ;
        my $ideal_dep = $self->struct_to_dep( @ordered_ideal_dep );

        if ( $actual_dep ne $ideal_dep ) {
            if ($apply_fix) {
                @$input = @ordered_ideal_dep ; # notify_change called in check_value
                $logger->info("fixed dependency with: $ideal_dep, was @$depend");
            }
            else {
                $self->{nb_of_fixes}++;
                my $msg = "Dependency of dual life package should be '$ideal_dep' not '$actual_dep'";
                $self->add_warning ($msg);
                $logger->info("will warn: $msg (fix++)");
            }
            $ret = 0;
        }
        $perl_dep_cv->send ;
    } ;

    # start the whole async stuff
    $self->get_available_version($on_get_lib_version, $dep_name);


    $async_log->debug("waiting for $actual_dep") ;
    $perl_dep_cv->recv ;
    $async_log->debug("waiting done for $actual_dep") ;
    return $ret ;
}

sub check_versioned_dep {
    my ($self, $callback ,$dep_info) = @_ ;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;
    $logger->debug("called with '" . $self->struct_to_dep($dep_info) ."'") if $logger->is_debug;

    # special case to keep lintian happy
    $callback->(1) if $pkg eq 'debhelper' ;

    my $cb = sub {
        my @dist_version = @_ ;
        $async_log->debug("in check_versioned_dep callback with ". $self->struct_to_dep($dep_info)
            ." -> @dist_version") if $async_log->is_debug;

        if ( @dist_version  # no older for unknow packages
             and defined $oper 
             and $oper =~ />/ 
             and $vers !~ /^\$/  # a dpkg variable
        ) {
            my $src_pkg_name = $self->grab_value("!Dpkg::Control source Source") ;
        
            my $filter = $test_filter || $self->grab_value(
                step => qq{!Dpkg my_config package-dependency-filter:"$src_pkg_name"},
                mode => 'loose',
            ) || '';
            $callback->($self->has_older_version_than ($pkg, $vers,  $filter, \@dist_version ));
        }
        else {
            $callback->(1) ;
        }
    };

    # check if Debian has version older than required version
    $self->get_available_version($cb, $pkg) ;

}

sub has_older_version_than {
    my ($self, $pkg, $vers, $filter, $dist_version ) = @_;

    $logger->debug("using filter $filter") if $filter;
    my $regexp = $deb_release_h{$filter} ;

    $logger->debug("using regexp $regexp") if defined $regexp;
    
    my @list ;
    my $has_older = 0;
    while (@$dist_version) {
        my ($d,$v) = splice @$dist_version,0,2 ;
 
        next if defined $regexp and $d =~ $regexp ;

        push @list, "$d -> $v;" ;
        
        if ($vs->compare($vers,$v) > 0 ) {
            $has_older = 1 ;
        }
    }

    $logger->debug("$pkg $vers has_older is $has_older (@list)");

    return 1 if $has_older ;
    return wantarray ? (0,@list) : 0 ;
}

#
# New subroutine "check_essential_package" extracted - Thu Aug 30 14:14:32 2012.
#
sub check_or_fix_essential_package {
    my ( $self, $apply_fix, $dep_info ) = @_;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;
    $logger->debug("called with '", scalar $self->struct_to_dep($dep_info), "' and fix $apply_fix") if $logger->is_debug;

    # Remove unversioned dependency on essential package (Debian bug 684208)
    # see /usr/share/doc/libapt-pkg-perl/examples/apt-cache

    my $cache_item = $apt_cache->get($pkg);
    my $is_essential = 0;
    $is_essential++ if (defined $cache_item and $cache_item->get('Flags') =~ /essential/i);
    
    if ($is_essential and not defined $oper) {
        $logger->debug( "found unversioned dependency on essential package: $pkg");
        if ($apply_fix) {
            @$dep_info = ();
            $logger->info("fix: removed unversioned essential dependency on $pkg");
        }
        else {
            my $msg = "unnecessary unversioned dependency on essential package: $pkg";
            $self->add_warning($msg);
            $self->{nb_of_fixes}++;
            $logger->info("will warn: $msg (fix++)");
        }
    }
}


my %pkg_replace = (
    'perl-module' => 'perl' ,
) ;

sub check_or_fix_pkg_name {
    my ( $self, $apply_fix, $dep_info, $old, $next ) = @_;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;

    $logger->debug("called with '", scalar $self->struct_to_dep($dep_info), "' and fix $apply_fix")
        if $logger->is_debug;

    my $new = $pkg_replace{$pkg} ;
    if ( $new ) {
        if ($apply_fix) {
            $logger->info("fix: changed package name from $pkg to $new");
            $dep_info->[0] = $pkg = $new;
        }
        else {
            my $msg = "dubious package name: $pkg. Preferred package is $new";
            $self-> add_warning ($msg);
            $self->{nb_of_fixes}++;
            $logger->info("will warn: $msg (fix++)");
        }
    }
    
    # check if this package is defined in current control file
    if ($self->grab(step => "- - binary:$pkg", qw/mode loose autoadd 0/)) {
        $logger->debug("dependency $pkg provided in control file") ;
        $next->() ;
    }
    else {
        my $cb = sub {
            if ( @_ == 0 ) {
                # no version found for $pkg
                # don't know how to distinguish virtual package from source package
                $logger->debug("unknown package $pkg");
                $self->add_warning(
                    "package $pkg is unknown. Check for typos if not a virtual package.");
            }
            $async_log->debug("callback for check_or_fix_pkg_name -> end for $pkg");
            $next->( );
        };

        # is asynchronous
        $async_log->debug("begin on $pkg");
        $self->get_available_version( $cb, $pkg );

        # if no pkg was found
    }
}

# all subs but one there are synchronous
sub check_or_fix_dep {
    my ( $self, $apply_fix, $dep_info, $old, $next ) = @_;
    my ( $pkg,  $oper,      $vers, @archs )    = @$dep_info;

    $logger->debug("called with '", scalar $self->struct_to_dep($dep_info), "' and fix $apply_fix")
        if $logger->is_debug;

    if(not defined $pkg) {
        # pkg may be cleaned up during fix
        $next->() ;
    }
    elsif ( $pkg eq 'debhelper' ) {
        $self->check_debhelper_version( $apply_fix, $dep_info );
        $next->() ;
    }
    else {
        my $cb = sub {
            my ( $vers_dep_ok, @list ) = @_ ;
            $async_log->debug("callback for check_or_fix_dep with @_") ;
            $self->warn_or_remove_vers_dep ($apply_fix, $dep_info, \@list) unless $vers_dep_ok ;

            $async_log->debug("callback for check_or_fix_dep -> end") ;
            $next->() ;
        } ;

        $async_log->debug("begin") ;
        $self->check_versioned_dep($cb,  $dep_info );

    }
}

sub warn_or_remove_vers_dep {
    my ( $self, $apply_fix, $dep_info, $list ) = @_;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;

    if ($apply_fix) {
        splice @$dep_info, 1, 2;    # remove versioned dep, notify_change called in check_value
        $logger->info("fix: removed versioned dependency from @$dep_info -> $pkg");
    }
    else {
        $self->{nb_of_fixes}++;
        my $msg = "unnecessary versioned dependency: @$dep_info. Debian has @$list";
        $self->add_warning( $msg);
        $logger->info("will warn: $msg (fix++)");
    }
}

use vars qw/%cache/ ;

# Set up persistence
my $cache_file_name = $ENV{HOME}.'/.config_model_depend_cache' ;

# this condition is used during tests
if (not %cache) {
    tie %cache => 'DB_File', $cache_file_name, 
} 

# required to write data back to DB_File
END { 
    untie %cache ;
}

my %requested ;

sub push_cb {
    my $pkg = shift;
    my $ref = $requested{$pkg} ||= [] ;
    push @$ref, @_ ;
}

sub call_cbs {
    my $pkg = shift;
    return unless $requested{$pkg} ;
    my $ref = delete $requested{$pkg} ;
    map { $_->(@_) } @$ref ;
}


# asynchronous method
sub get_available_version {
    my ($self, $callback,$pkg_name) = @_ ;

    $async_log->debug("called on $pkg_name");

    my ($time,@res) = split / /, ($cache{$pkg_name} || '');
    if (defined $time and $time =~ /^\d+$/ and $time + 24 * 60 * 60 * 7 > time) {
        $async_log->debug("using cached info for $pkg_name");
        $callback->(@res) ;
        return;
    }

    # package info was requested but info is still not there
    # this may be called twice for the same package: one for source, one
    # for binary package
    if ($requested{$pkg_name}){
        push_cb($pkg_name,$callback) ;
        return ;
    } ;

    my $url = "http://qa.debian.org/cgi-bin/madison.cgi?package=$pkg_name&text=on" ;

    push_cb($pkg_name,$callback);

    say "Connecting to qa.debian.org to check $pkg_name versions. Please wait..." ;

    my $request;
    $request = http_request(
        GET => $url,
        timeout => 20, # seconds
        sub {
            my ($body, $hdr) = @_;
            $async_log->debug("callback of get_available_version called on $pkg_name");
            if ($hdr->{Status} =~ /^2/) {
                my @res ;
                foreach my $line (split /\n/, $body) {
                    my ($name,$available_v,$dist,$type) = split /\s*\|\s*/, $line ;
                    $type =~ s/\s//g ;
                    push @res , $dist,  $available_v unless $type eq 'source';
                }
                say "got info for $pkg_name" ;
                $cache{$pkg_name} = time ." @res" ;
                call_cbs($pkg_name,@res) ;
            }
            else {
                say "Error for $url: ($hdr->{Status}) $hdr->{Reason}";
                delete $requested{$pkg_name} ; # trash the callbacks
            }
            undef $request;
        }
    );
}

__PACKAGE__->meta->make_immutable;

1;

=head1 NAME

Config::Model::Dpkg::Dependency - Checks Debian dependency declarations

=head1 SYNOPSIS

 use Config::Model ;
 use Log::Log4perl qw(:easy) ;
 use Data::Dumper ;

 Log::Log4perl->easy_init($WARN);

 # define configuration tree object
 my $model = Config::Model->new ;
 $model ->create_config_class (
    name => "MyClass",
    element => [ 
        Depends => {
            'type'       => 'leaf',
            'value_type' => 'uniline',
            class => 'Config::Model::Dpkg::Dependency',
        },
    ],
 ) ;

 my $inst = $model->instance(root_class_name => 'MyClass' );

 my $root = $inst->config_root ;

 $root->load( 'Depends="libc6 ( >= 1.0 )"') ;
 # Connecting to qa.debian.org to check libc6 versions. Please wait ...
 # Warning in 'Depends' value 'libc6 ( >= 1.0 )': unnecessary
 # versioned dependency: >= 1.0. Debian has lenny-security ->
 # 2.7-18lenny6; lenny -> 2.7-18lenny7; squeeze-security ->
 # 2.11.2-6+squeeze1; squeeze -> 2.11.2-10; wheezy -> 2.11.2-10; sid
 # -> 2.11.2-10; sid -> 2.11.2-11;

=head1 DESCRIPTION

This class is derived from L<Config::Model::Value>. Its purpose is to
check the value of a Debian package dependency for the following:

=over 

=item *

syntax as described in http://www.debian.org/doc/debian-policy/ch-relationships.html

=item *

Whether the version specified with C<< > >> or C<< >= >> is necessary.
This module will check with Debian server whether older versions can be
found in Debian old-stable or not. If no older version can be found, a
warning will be issued. Note a warning will also be sent if the package
is not found on madison and if the package is not virtual.

=item * 

Whether a Perl library is dual life. In this case the dependency is checked according to
L<Debian Perl policy|http://pkg-perl.alioth.debian.org/policy.html#debian_control_handling>.
Because Debian auto-build systems (buildd) will use the first available alternative, 
the dependency should be in the form :

=over 

=item * 

C<< perl (>= 5.10.1) | libtest-simple-perl (>= 0.88) >> when
the required perl version is available in sid. ".

=item *

C<< libcpan-meta-perl | perl (>= 5.13.10) >> when the Perl version is not available in sid

=back

=back

=head1 Cache

Queries to Debian server are cached in C<~/.config_model_depend_cache>
for about one month.

=head1 BUGS

=over

=item *

Virtual package names are found scanning local apt cache. Hence an unknown package 
on your system may a virtual package on another system.

=item *

More advanced checks can probably be implemented. The author is open to
new ideas. He's even more open to patches (with tests).

=back

=head1 AUTHOR

Dominique Dumont, ddumont [AT] cpan [DOT] org

=head1 SEE ALSO

L<Config::Model>,
L<Config::Model::Value>,
L<Memoize>,
L<Memoize::Expire>
