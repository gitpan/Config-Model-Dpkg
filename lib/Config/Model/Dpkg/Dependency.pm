package Config::Model::Dpkg::Dependency ;

use 5.10.1;

use Any::Moose;
use namespace::autoclean;

# Debian only module
use lib '/usr/share/lintian/lib' ;
use Lintian::Relation ;

use DB_File ;
use Log::Log4perl qw(get_logger :levels);
use Module::CoreList;
use version ;

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

# called with $self,$pending_check,$apply_fix, \@fixed_dep
check_depend: depend alt_depend(s?) eofile { 
    @{$arg[3]} = ($item{depend}, @{$item[2]}) ;
    $arg[0]->check_depend_chain( @arg[1..3] ) ;
    $return = 1;
  }

depend: pkg_dep | variable

alt_depend: '|' depend  

# For the allowed stuff after ${foo}, see #702792
variable: /\${[\w:\-]+}[\w\.\-~+]*/

pkg_dep: pkg_name dep_version arch_restriction(?) {
    # pass dep_version by ref so they can be modified
    my @dep_info = ( $item{pkg_name}, @{ $item{dep_version} } ) ;
    $arg[0]->check_or_fix_dep( @arg[1..2], \@dep_info) ;
    $return = \@dep_info ;
   } 
 | pkg_name arch_restriction(?) {
    my @dep_info = ( $item{pkg_name} ) ;
    $arg[0]->check_or_fix_pkg_name($arg[2], \@dep_info) ;
    $arg[0]->check_or_fix_essential_package($arg[2], \@dep_info) ;
    $return = \@dep_info ;
   }

arch_restriction: '[' arch(s) ']'
dep_version: '(' oper version ')' { $return = [ $item{oper}, $item{version} ] ;} 
pkg_name: /[a-z0-9][a-z0-9\+\-\.]+/
oper: '<<' | '<=' | '=' | '>=' | '>>'
version: variable | /[\w\.\-~:+]+/
eofile: /^\Z/
arch: not(?) /[\w-]+/
not: '!'

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

    # check_value is always called with a callback. This callback must
    # must called *after* all aysnchronous calls are done (which depends on the
    # packages listed in the dependency)
    my $pending_check = AnyEvent->condvar ;

    # value is one dependency, something like "perl ( >= 1.508 )"
    # or exim | mail-transport-agent or gnumach-dev [hurd-i386]

    # see http://www.debian.org/doc/debian-policy/ch-relationships.html
    
    # to get package list
    # wget -q -O - 'http://qa.debian.org/cgi-bin/madison.cgi?package=perl-doc&text=on'

    $value = $self->{data} if $apply_fix ; # check_value may have modified data in this case

    my $old = $value ;
    my @fixed_dep ; # filled by callback and used when applying fixes
    
    my $on_check_all_done = sub {
        if ($logger->is_debug) {
            $async_log->debug("in check_dependency callback for ",$self->element_name);
            my $new = $value // '<undef>' ;
            $logger->debug("'$old' done".($apply_fix ? " changed to '$new'" : ''));
        }

        # "ideal" dependency is always computed, but it does not always change
        my $new = $self->struct_to_dep(@fixed_dep) ;

        {
            no warnings 'uninitialized';
            $self->_store_fix($old, $new) if $apply_fix and $new ne $old;
        }
        $callback->(%args) if $callback ;
        $pending_check->send ;
    } ;
    
    $async_log->debug("begin for ",$self->element_name) if $async_log->debug;
    $pending_check->begin($on_check_all_done) ;
    
    if (defined $value) {
        $logger->debug("'$value', calling check_depend with Parse::RecDescent");
        dep_parser->check_depend ( $value,1,$self,$pending_check,$apply_fix, \@fixed_dep) 
            // $self->add_error("dependency '$value' does not match grammar") ;

    }
    
    $async_log->debug("waiting end for ",$self->element_name) if $async_log->debug;
    $pending_check->end; 
    $async_log->debug("end for ",$self->element_name) if $async_log->debug;
    
    $async_log->debug("waiting until all results for ",$self->element_name," are back")
        if $async_log->debug;
    $pending_check->recv; # block until all checks are done
    $async_log->debug("all results for ",$self->element_name, " are back") 
        if $async_log->debug;
}

sub check_debhelper {
    my ($self, $apply_fix, $depend) = @_ ;
    my ( $dep_name, $oper, $dep_v ) = @$depend ;

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
        if( ref ($d) and @$d and @$d) {
            $line .= "$d->[0]";
            # skip test for relations like << or < 
            $skip ++ if defined $d->[1] and $d->[1] =~ /</ ;
            $line .= " ($d->[1] $d->[2])" if defined $d->[2];
        }
        elsif (not ref($d) and $d) { 
            $line .= $d ; 
        } ;

        push @alternatives, $line if $line ;
    }
    
    my $actual_dep = @alternatives ? join (' | ',@alternatives) : undef ;

    return wantarray ? ($actual_dep, $skip) : $actual_dep ;
}

# called in Parse::RecDescent grammar
# @input contains the alternates dependencies (without '|') of one dependency values
# a bit like @input = split /|/, $dependency

# will modify @input (array of ref) when applying fix
sub check_depend_chain {
    my ($self, $pending_check, $apply_fix, $input) = @_ ;
    
    my ($actual_dep, $skip) = $self->struct_to_dep (@$input);
    my $ret = 1 ;

    return 1 unless defined $actual_dep; # may have been cleaned during fix
    $logger->debug("called with $actual_dep with apply_fix $apply_fix");

    if ($skip) {
        $logger->debug("skipping '$actual_dep': has a < relation ship") ;
        return $ret ;
    }
    
    $async_log->debug("begin check alternate deps for $actual_dep") ;
    $pending_check->begin;
    foreach my $depend (@$input) {
        if (ref ($depend)) {
            # is a dependency (not a variable a la ${perl-Depends})
            my ($dep_name, $oper, $dep_v) = @$depend ;
            $logger->debug("scanning dependency $dep_name"
                .(defined $dep_v ? " $dep_v" : ''));
            if ($dep_name =~ /lib([\w+\-]+)-perl/) {
                my $pname = $1 ;
                # AnyEvent condvar is involved in this method
                $ret &&= $self->check_perl_lib_dep ($apply_fix, $pname, $actual_dep, $depend,$input);
                last;
            }
        }
    }
    $async_log->debug("waiting end check alternate deps for $actual_dep") ;
    $pending_check->end ;
    $async_log->debug("end check alternate deps for $actual_dep") ;
    
    if ($logger->is_debug and $apply_fix) {
        my $str = $self->struct_to_dep(@$input) ;
        $str //= '<undef>' ;
        $logger->debug("new dependency is $str");
    }
    
    return $ret ;
}

# called in Parse::RecDescent grammar through check_depend_chain
# does modify $input when applying fix
sub check_perl_lib_dep {
    my ($self, $apply_fix, $pname, $actual_dep, $depend, $input) = @_;
    $logger->debug("called with $actual_dep with apply_fix $apply_fix");

    my ( $dep_name, $oper, $dep_v ) = @$depend;
    my $ret = 1;

    $pname =~ s/-/::/g;

    # check for dual life module, module name follows debian convention...
    my @dep_name_as_perl = Module::CoreList->find_modules(qr/^$pname$/i) ; 
    return $ret unless @dep_name_as_perl;

    return $ret if defined $dep_v && $dep_v =~ m/^\$/ ;

    my ($cpan_dep_v, $epoch_dep_v) ;
    ($cpan_dep_v, $epoch_dep_v) = reverse split /:/ ,$dep_v if defined $dep_v ;
    my $v_decimal = Module::CoreList->first_release( 
        $dep_name_as_perl[0], 
        version->parse( $cpan_dep_v )
    );

    return $ret unless defined $v_decimal;

    my $v_normal = version->new($v_decimal)->normal;
    $v_normal =~ s/^v//;    # loose the v prefix
    if ( $logger->debug ) {
        my $dep_str = $dep_name . ( defined $dep_v ? ' ' . $dep_v : '' );
        $logger->debug("dual life $dep_str aka $dep_name_as_perl[0] found in Perl core $v_normal");
    }

    # Here the dependency should be in the form perl (>= 5.10.1) | libtest-simple-perl (>= 0.88)".
    # cf http://pkg-perl.alioth.debian.org/policy.html#debian_control_handling
    # If the Perl version is not available in sid, the order of the dependency should be reversed
    # libcpan-meta-perl | perl (>= 5.13.10)
    # because buildd will use the first available alternative

    # here we have 3 async consecutive calls to check_versioned_dep 
    # and get_available_version. Must block and return once they are done
    # hence the condvar
    my $perl_dep_cv = AnyEvent->condvar ;
    
    my @ideal_perl_dep = qw/perl/ ;
    my @ideal_lib_dep ;
    my @ideal_dep_chain = (\@ideal_perl_dep);

    my ($check_perl_lib, $get_perl_versions, $on_get_perl_versions) ;
    
    my $on_perl_check_done =  sub {
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
    
    $self->check_versioned_dep( $on_perl_check_done , ['perl', '>=', $v_normal] );

    $async_log->debug("waiting for $actual_dep") ;
    $perl_dep_cv->recv ;
    $async_log->debug("waiting done for $actual_dep") ;
    return $ret ;
}

sub check_versioned_dep {
    my ($self, $callback ,$dep_info) = @_ ;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;
    $async_log->debug("called with @$dep_info");

    # special case to keep lintian happy
    $callback->(1) if $pkg eq 'debhelper' ;

    my $cb = sub {
        my @dist_version = @_ ;
        $async_log->debug("in check_versioned_dep callback with @$dep_info -> @dist_version");

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
    $logger->debug("called with @$dep_info");

    # Remove unversioned dependency on essential package (Debian bug 684208)
    # see /usr/share/doc/libapt-pkg-perl/examples/apt-cache

    my $cache_item = $apt_cache->get($pkg);
    my $is_essential = 0;
    $is_essential++ if (defined $cache_item and $cache_item->get('Flags') =~ /essential/i);
    
    if ($is_essential and @$dep_info == 1) {
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
    my ( $self, $apply_fix, $dep_info ) = @_;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;
    $logger->debug("called with @$dep_info");

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
        return;
    }

    my $cb  = sub {
        if (@_ == 0) { # no version found for $pkg
            # don't know how to distinguish virtual package from source package
            $logger->debug("unknown package $pkg") ;
            $self->add_warning("package $pkg is unknown. Check for typos if not a virtual package.") ;
        }
    } ;
   
    $self->get_available_version($cb,$pkg ) ;
    # if no pkg was found
}

# all subs but one there are synchronous
sub check_or_fix_dep {
    my ( $self, $pending_check_cv, $apply_fix, $dep_info ) = @_;
    my ( $pkg,  $oper,      $vers )    = @$dep_info;
    $logger->debug("called with @$dep_info");

    if ( $pkg eq 'debhelper' ) {
        $self->check_debhelper( $apply_fix, $dep_info );
        return;
    }

    $self->check_or_fix_pkg_name($apply_fix, $dep_info) ;

    my $cb = sub {
        my ( $vers_dep_ok, @list ) = @_ ;
        $async_log->debug("callback for check_or_fix_dep with @_") ;
        $self->warn_or_remove_vers_dep ($apply_fix, $dep_info, \@list) unless $vers_dep_ok ;

        $self->check_or_fix_essential_package ($apply_fix, $dep_info);
        $async_log->debug("callback for check_or_fix_dep -> end") ;
        $pending_check_cv->end ;
    } ;
    $async_log->debug("begin") ;
    $pending_check_cv->begin ;
    $self->check_versioned_dep($cb,  $dep_info );


    return 1;
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

__PACKAGE__->meta->make_immutable;


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