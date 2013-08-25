# -*- cperl -*-

use ExtUtils::testlib;
use Test::More ;
use Test::Differences;
use Config::Model::Dpkg::Dependency ;
use Log::Log4perl qw(:easy) ;
use 5.10.0;

use warnings;

use strict;

my $arg = shift || '';
my ($log,$show,$one) = (0) x 3 ;

use Log::Log4perl qw(:easy) ;
my $home = $ENV{HOME} || "";
my $log4perl_user_conf_file = "$home/.log4config-model";

if ($log and -e $log4perl_user_conf_file ) {
    Log::Log4perl::init($log4perl_user_conf_file);
}
else {
    Log::Log4perl->easy_init($ERROR);
}

{
    no warnings qw/once/;
    $::RD_HINT  = 1 if $arg =~ /rdt?h/;
    $::RD_TRACE = 1 if $arg =~ /rdh?t/;
}

my $parser = Config::Model::Dpkg::Dependency::dep_parser ;

exit main( @ARGV );

sub main {
    my ($do, $pattern)  = @_;

    test_good($pattern) if not $do or $do eq 'g';
    test_errors($pattern) if not $do or $do eq 'e';

    done_testing;
    return 0;
}


sub test_good {
    # dep, data struct
    my $pat = shift;
    my @tests = (
        [ 'foo' ,  ['foo']  ],
        [ 'foo | bar ' , ['foo' ], ['bar'] ],
        [ 'foo | bar | baz ' , ['foo' ], ['bar'], ['baz'] ],

        [ 'foo ( >= 1.24 )| bar ' , ['foo','>=','1.24' ], ['bar'] ],
        [ 'foo ( >= 1.24 )| bar ( << 1.3a3)' , ['foo','>=','1.24' ], [qw/bar << 1.3a3/] ],
        [ 'foo(>=1.24)|bar(<<1.3a3)  ' , ['foo','>=','1.24' ], [qw/bar << 1.3a3/] ],

        [ 'foo ( >= 1.24 )| bar [ linux-any]' , ['foo','>=','1.24' ], ['bar', undef, undef, 'linux-any'] ],
        [ 'xserver-xorg-input-evdev [alpha amd64 hurd-arm linux-armeb]' ,
            [ 'xserver-xorg-input-evdev', undef, undef, qw[alpha amd64 hurd-arm linux-armeb] ],
         ],
        [ 'xserver-xorg-input-evdev [!alpha !amd64 !arm !armeb]' , [ 'xserver-xorg-input-evdev', undef, undef,
                                                                   qw[!alpha !amd64 !arm !armeb]
                                                                ],
         ],
        [ 'hal (>= 0.5.12~git20090406) [kfreebsd-any]', [ 'hal', '>=','0.5.12~git20090406', 'kfreebsd-any']],

        [ ('${foo}') x 2 ],
        [ ('${foo}.1-2~') x 2 ],
    ) ;

    foreach my $td ( @tests ) {
        my ($dep,@exp) = @$td ;
        next if $pat and $dep !~ /$pat/;
        unshift @exp, 1; # match what's returned when there's no errors
        my $ret = $parser->dependency($dep) ;
        eq_or_diff ($ret, \@exp,"parsed $dep");
    }
}

sub test_errors {
    my $pat = shift;
    my @tests = (
        [ 'foo@' , q!bad package name: '%%'! ],
        [ 'foo ( >= 3.24' , q!Cannot parse: '%%'! ],
        [ 'foo ( >= 3.!4 )' , q(bad dependency version: '3.!4') ],
        [ 'bar( >= 1.1) | foo ( >= 3.!4 )' , q(bad dependency version: '3.!4') ],
        [ 'bar( >= 1.!1) | foo ( >= 3.14 )' , q{bad dependency version: '1.!1)'} ],
        [ 'foo ( <> 3.24 )' , q!bad dependency version operator: '<>'! ],

        [ 'foo ( >= 1.24 )| bar [ binux-any]' , q!bad os in architecture specification: 'binux'!, 
                                                q!bad arch in architecture specification: 'binux'! ],
        [ 'foo ( >= 1.24 )| bar [ linux-nany]' , q!bad arch in architecture specification: 'nany'! ],

        [ 'xserver-xorg-input-evdev [alpha !amd64 !arm armeb]' ,
            q(some names are prepended with '!' while others aren't.: 'alpha !amd64 !arm armeb') ],

    ) ;

    foreach my $td ( @tests ) {
        my ($dep,@errs) = @$td ;
        next if $pat and $dep !~ /$pat/;
        my $ret = $parser->dependency($dep) ;
        map { s/%%/$dep/;} @errs ;
        unshift @errs, 0; # match what's returned when there's an error
        is_deeply($ret,\@errs,"test error message for $dep") ;
    }
}


