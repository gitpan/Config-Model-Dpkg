# -*- cperl -*-

BEGIN {
    # dirty trick to create a Memoize cache so that test will use this instead
    # of getting values through the internet
    no warnings 'once';
    %Config::Model::Dpkg::Dependency::cache = (
        'libarchive-extract-perl' => 'jessie 0.68-1 sid 0.68-1',
        'perl-modules' => 'lenny 5.10.0-19lenny3 squeeze 5.10.1-17 sid 5.10.1-17 experimental 5.12.0-2 experimental 5.12.2-2',
        'perl' => 'lenny 5.10.0-19lenny3 squeeze 5.10.1-17 sid 5.10.1-17 experimental 5.12.0-2 experimental 5.12.2-2',
        'debhelper' => 'etch 5.0.42 backports/etch 7.0.15~bpo40+2 lenny 7.0.15 backports/lenny 8.0.0~bpo50+2 squeeze 8.0.0 wheezy 8.1.2 sid 8.1.2',
        'libcpan-meta-perl' => 'squeeze 2.101670-1 wheezy 2.110580-1 sid 2.110580-1',
        'libmodule-build-perl' => 'etch 0.26-1 backports/etch 0.2808.01-2~bpo40+1 lenny 0.2808.01-2 squeeze 0.360700-1 wheezy 0.380000-1 sid 0.380000-1', 
        'xserver-xorg-input-evdev' => 'etch 1:1.1.2-6 lenny 1:2.0.8-1 squeeze 1:2.3.2-6 wheezy 1:2.3.2-6 sid 1:2.6.0-2 experimental 1:2.6.0-3',
        'lcdproc' => 'etch 0.4.5-1.1 lenny 0.4.5-1.1 squeeze 0.5.2-3 wheezy 0.5.2-3.1 sid 0.5.2-3.1',
        'libsdl1.2' => '', # only source
        'dpkg' => 'squeeze 1.15 wheezy 1.16 sid 1.16',
        makedev => 'squeeze 2.3.1-89 wheezy 2.3.1-92 jessie 2.3.1-92 sid 2.3.1-93',
        udev => 'squeeze 164-3 wheezy 175-7.2 jessie 175-7.2 sid 175-7.2',
    );
    my $t = time ;
    map { $_ = "$t $_"} values %Config::Model::Dpkg::Dependency::cache ;
}

use ExtUtils::testlib;
use Test::More ;
use Test::Memory::Cycle;
use Test::Differences;
use Config::Model ;
use Config::Model::Value ;
use Log::Log4perl qw(:easy) ;
use File::Path ;
use File::Copy ;
use Test::Warn ;
use 5.10.0;

eval { require AptPkg::Config ;} ;
if ( $@ ) {
    plan skip_all => "AptPkg::Config is not installed";
}
elsif ( -r '/etc/debian_version' ) {
    plan tests => 58;
}
else {
    plan skip_all => "Not a Debian system";
}

use warnings;

use strict;

my $arg = shift || '';
my ($log,$show,$one) = (0) x 3 ;

my $trace = $arg =~ /t/ ? 1 : 0 ;
$log                = 1 if $arg =~ /l/;
Config::Model::Exception::Any->Trace(1) if $arg =~ /e/;

use Log::Log4perl qw(:easy) ;
my $home = $ENV{HOME} || "";
my $log4perl_user_conf_file = "$home/.log4config-model";

if ($log and -e $log4perl_user_conf_file ) {
    Log::Log4perl::init($log4perl_user_conf_file);
}
else {
    Log::Log4perl->easy_init($ERROR);
}
$show               = 1 if $arg =~ /s/;
$one                = 1 if $arg =~ /1/;

{
    no warnings qw/once/;
    $::RD_HINT  = 1 if $arg =~ /rdt?h/;
    $::RD_TRACE = 1 if $arg =~ /rdh?t/;
}

my $model = Config::Model -> new ( ) ;

{
    no warnings qw/once/ ;
    $Dpkg::Dependency::test_filter='lenny'; 
}

my $control_text = <<'EOD' ;
Source: libdist-zilla-plugins-cjm-perl
Section: perl
Priority: optional
Build-Depends: debhelper, libsdl1.2, dpkg
Build-Depends-Indep: libcpan-meta-perl, perl (>= 5.10) | libmodule-build-perl,
Maintainer: Debian Perl Group <pkg-perl-maintainers@lists.alioth.debian.org>
Uploaders: Dominique Dumont <dominique.dumont@hp.com>
Standards-Version: 3.9.4
Homepage: http://search.cpan.org/dist/Dist-Zilla-Plugins-CJM/

Package: libdist-zilla-plugins-cjm-perl
Architecture: all
Depends: ${misc:Depends}, ${perl:Depends}, libcpan-meta-perl ,
 perl (>= 5.10.1), dpkg (>= 0.01), perl-modules,  dpkg (<< ${source:Version}.1~)
Description: collection of CJM's plugins for Dist::Zilla
 Collection of Dist::Zilla plugins. This package features the 
 following [snip]  
EOD

ok(1,"compiled");

# pseudo root where config files are written by config-model
my $wr_root = 'wr_root';

# cleanup before tests
rmtree($wr_root);
mkpath($wr_root, { mode => 0755 }) ;

my $wr_dir = $wr_root.'/test' ;
mkpath($wr_dir."/debian/", { mode => 0755 }) ;
my $control_file = "$wr_dir/debian/control" ;

open(my $control_h,"> $control_file" ) || die "can't open $control_file: $!";
print $control_h $control_text ;
close $control_h ;

{

# instance to check one dependency at a time
my $unit = $model->instance (
    root_class_name => 'Dpkg::Control',
    root_dir        => $wr_dir,
    # skip_read       => 1,
    instance_name   => "unittest",
);

warning_like {
    $unit->config_root->init ;
}
 [ qr/is unknown/, qr/unnecessary/, (qr/dual life/) , qr/unnecessary/,
   ( qr/dual life/) x 2 , (qr/unnecessary/) x 1 ] ,
  "test BDI warn on unittest instance";

my $c_unit = $unit->config_root ;
my $dep_value = $c_unit->grab("binary:dummy Depends:0");

my @struct_2_dep = (
    [['foo']] => 'foo',
    [['foo'],['bar']] => 'foo | bar',
    [[ 'foo', '>=' , '2.15']] => 'foo (>= 2.15)',
    [[ 'foo', '>=' , '2.15', 'linux-i386', 'hurd']] => 'foo (>= 2.15) [linux-i386 hurd]',
    [[ 'foo', undef , undef, 'linux-i386', 'hurd']] => 'foo [linux-i386 hurd]',
    [[ 'udev', undef , undef, 'linux-any'],[ 'makedev', undef , undef, 'linux-any']] => 'udev [linux-any] | makedev [linux-any]',
);

while (@struct_2_dep) {
    my $data = shift @struct_2_dep ;
    my $str = shift @struct_2_dep ;
    is(
        $dep_value->struct_to_dep(@$data),
        $str,
        "test struct_to_dep -> $str"
    ) ;
}


warning_like {
    $dep_value->store('perl') ;
}
 [ qr/better written/ ] ,
  "test warn on perl dep";
is($dep_value->_pending_store, 0,"check that no pending store is left") ;

is($dep_value->fetch, 'perl', "check stored dependency value") ;

warning_like {
    $dep_value->store('perl (  >= 5.6.0)') ;
}
 [ qr/unnecessary/ ] ,
  "test warn on perl dep with old version";

is($dep_value->_pending_store, 0,"check that no pending store is left") ;

my $ok_cb = sub {is($_[0],0,"check perl (>= 5.6.0) dependency: no older version"); };
$dep_value->check_versioned_dep( $ok_cb, ['perl','>=','5.6.0'] ) ;


# $dep_value->store('libcpan-meta-perl') ;
# exit ;
my @chain_tests = (
    # tag name for display, test data, expected result: 1 (good dep) or expected fixed structure
    'libcpan-meta-perl' => [ ['libcpan-meta-perl']]  => [['libcpan-meta-perl'],[qw/perl >= 5.13.10/]],
    'libmodule-build-perl' => [ [qw/perl >= 5.10/], ['libmodule-build-perl']]  => [['perl'],[]],
    # test Debian #719225
    'libarchive-extract-perl' => [ [qw/libarchive-extract-perl >= 0.68/] , [qw/perl >= 5.17.9/]]  =>  [ ['libarchive-extract-perl'] , [qw/perl >= 5.17.9/]],
    'libarchive-extract-perl' => [ ['libarchive-extract-perl'] , [qw/perl >= 5.17.9/]]  => 1,
);

while (@chain_tests) {
    my ($tag,$dep,$expect) = splice @chain_tests,0,3;
    my $ret = $dep_value->check_depend_chain (1, $dep);
    if (ref $expect) {
        # $dep was not correct
        is($ret, 0, "check dual life of $tag") ;
        eq_or_diff ($dep,$expect,"check fixed value of dual life $tag");
    }
    else {
        is($ret, $expect, "check dual life of $tag") ;
    }
}

}

my $inst = $model->instance (
    root_class_name => 'Dpkg::Control',
    root_dir        => $wr_dir,
    instance_name   => "deptest",
);

warning_like {
    $inst->config_root->init ;
}
 [ qr/is unknown/, qr/unnecessary/, (qr/dual life/) , qr/unnecessary/,
   ( qr/dual life/) x 2 , (qr/unnecessary/) x 1 ] ,
  "test BDI warn";

ok($inst,"Read $control_file and created instance") ;

my $control = $inst -> config_root ;

if ($trace) {
    my $dump =  $control->dump_tree ();
    print $dump ;
}

my $perl_dep = $control->grab("binary:libdist-zilla-plugins-cjm-perl Depends:3");
is($perl_dep->fetch,"perl (>= 5.10.1)","check dependency value from config tree");

my @ret = $perl_dep->check_versioned_dep(
    sub { is($_[0],1,"check perl (>= 5.28.1) dependency: has older version");},
    ['perl','>=','5.28.1']
) ;

@ret = $perl_dep->check_versioned_dep(
    sub {is($_[0],0,"check perl (>= 5.6.0) dependency: no older version"); },
    ['perl','>=','5.6.0']
) ;

my $dpkg_dep = $control->grab("source Build-Depends:2");
is($dpkg_dep->fetch,"dpkg",'check dpkg value') ;
# test fixes
is($dpkg_dep->has_fixes,1, "test presence of fixes");
$dpkg_dep->apply_fixes;
is($dpkg_dep->has_fixes,0, "test that fixes are gone");

is($dpkg_dep->fetch,undef,'check fixed dpkg value') ;

$dpkg_dep = $control->grab("binary:libdist-zilla-plugins-cjm-perl Depends:4");
is($dpkg_dep->fetch,"dpkg (>= 0.01)",'check dpkg value with unnecessary versioned dep') ;
# test fixes
is($dpkg_dep->has_fixes,1, "test presence of fixes");
$dpkg_dep->apply_fixes;
is($dpkg_dep->has_fixes,0, "test that fixes are gone");
is($dpkg_dep->fetch,undef,'check fixed dpkg value') ;

warning_like {
    $perl_dep->store("perl ( >= 5.6.0 )") ;
}
qr/unnecessary versioned/,"check perl (>= 5.6.0) store: no older version warning" ;

my @msgs = $perl_dep->warning_msg ;
is(scalar @msgs,1,"check nb of warning with store with old version");
like($msgs[0],qr/unnecessary versioned dependency/,"check store with old version");

$control->load(q{binary:libdist-zilla-plugins-cjm-perl Depends:4="perl [!i386] | perl [amd64] "}) ;
ok( 1, "check_depend on arch stuff rule");

$control->load(
    "binary:libdist-zilla-plugins-cjm-perl ".
    q{Depends:5="xserver-xorg-input-evdev [alpha amd64 arm armeb armel hppa i386 ia64 lpia m32r m68k mips mipsel powerpc sparc]"}
);
ok( 1, "check_depend on xorg arch stuff rule");

$control->load(q{binary:libdist-zilla-plugins-cjm-perl Depends:6="lcdproc (= ${binary:Version})"});
ok( 1, "check_depend on lcdproc where version is a variable");

$control->load(q{binary:libdist-zilla-plugins-cjm-perl Depends:7="udev [linux-any] | makedev [linux-any]"});
ok( 1, "check_depend on lcdproc with 2 alternate deps with arch restriction");

# reset change tracker
$inst-> clear_changes ;

# test fixes
is($perl_dep->has_fixes,1, "test presence of fixes");
$perl_dep->apply_fixes;
is($perl_dep->fetch,'${perl:Depends}',"check fixed dependency value");
is(
    $control->grab_value("binary:libdist-zilla-plugins-cjm-perl Depends:7"),
    'udev [linux-any] | makedev [linux-any]',
    "test fixed alternate deps with arch restriction"
);
is($perl_dep->has_fixes,0, "test that fixes are gone");
is($perl_dep->has_warning,0,"check that warnings are gone");

is($inst->c_count, 2,"check that fixes are tracked with notify changes") ;
print scalar $inst->list_changes,"\n" if $trace ;

my $perl_bdi = $control->grab("source Build-Depends-Indep:1");

my $bdi_val ;
# since warnings were already issued during config_root->init, we don;t
# get warnings here
warning_like { $bdi_val = $perl_bdi->fetch ; } [ ], "check that no BDI warn are shown";

is($bdi_val,"perl (>= 5.10) | libmodule-build-perl","check B-D-I dependency value from config tree");
my $msgs = $perl_bdi->warning_msg ;
print "bdi warning: $msgs" if $trace ;
like($msgs,qr/dual life/,"check store with old version: trap perl | libmodule");
like($msgs,qr/unnecessary versioned dependency/,"check store with old version: trap version");

$inst-> clear_changes ;

# test fixes
is($perl_bdi->has_fixes,2, "test presence of fixes");

{
    local $Config::Model::Value::nowarning = 1 ;
    $perl_bdi->apply_fixes;
    ok(1,"apply_fixes done");
}

is($perl_bdi->has_fixes,0, "test that fixes are gone");
is($perl_bdi->has_warning,0,"check that warnings are gone");

is($perl_bdi->fetch,"perl","check fixed B-D-I dependency value");

print scalar $inst->list_changes,"\n" if $trace ;
is($inst->c_count, 1,"check that fixes are tracked with notify changes") ;

memory_cycle_ok($model);
