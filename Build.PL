#    Copyright (c) 2005-2012 Dominique Dumont.
#
#    This file is part of Config-Model-Dpkg.
#
#    Config-Model-Dpkg is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser Public License as
#    published by the Free Software Foundation; either version 2.1 of
#    the License, or (at your option) any later version.
#
#    Config-Model-Dpkg is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser Public License for more details.
#
#    You should have received a copy of the GNU Lesser Public License
#    along with Config-Model; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
#    02110-1301 USA

use Module::Build;

use warnings FATAL => qw(all);
use strict;

require 5.010001 ;

my $class = Module::Build->subclass(
    class => "Module::Build::Custom",
    code => <<'SUBCLASS' );

sub ACTION_build {
    my $self = shift;
    # below requires Config::Model 2.026, and need to use local library
    system ($^X, qw!-Ilib -S cme gen-class-pod!) ;
    $self->SUPER::ACTION_build;
}
SUBCLASS

my %appli_files = map { ( $_, $_ ) } glob("lib/Config/Model/*.d/*");

my $build = $class->new(
    module_name => 'Config::Model::Dpkg',
    license       => 'lgpl',
    appli_files   => \%appli_files,
    dist_abstract => 'Edit and validate dpkg source files with cme',
    dist_author   => 'Dominique Dumont (dod at debian dot org)',

  'build_requires' => {
    'File::Copy::Recursive' => '0',
    'Module::Build' => '0.34',
    'Path::Class' => '0',
    'Probe::Perl' => '0',
    'Test::Command' => '0.08',
    'Test::Differences' => '0',
    'Test::Exception' => '0',
    'Test::File::Contents' => '0',
    'Test::Memory::Cycle' => '0',
    'Test::More' => '0',
    'Test::Warn' => '0.11'
  },
  'requires' => {
    'Config::Model' => '2.026',
    'Any::Moose' => '0',
    'AnyEvent' => '0',
    'AnyEvent::HTTP' => '0',
    'Carp::Assert::More' => '0',
    'DB_File' => '0',
    'Exception::Class' => '0',
    'File::HomeDir' => '0',
    'File::Path' => '2.07',
    'Hash::Merge' => '0.12',
    'IO::File' => '0',
    'List::MoreUtils' => '0',
    'Log::Log4perl' => '1.11',
    'Mouse' => '0',
    'MouseX::NativeTraits' => '0',
    'MouseX::StrictConstructor' => '0',
    'Parse::RecDescent' => 'v1.90.0',
    'Pod::POM' => '0',
    'Scalar::Util' => '0',
    'Term::ReadLine' => '0',
    'Text::Autoformat' => '0',
    'Text::Diff' => '0',
    'namespace::autoclean' => '0'
  },

    meta_merge => {
        resources => {
            homepage => 'https://github.com/dod38fr/config-model/wiki',
            MailingList =>
              'https://lists.sourceforge.net/lists/listinfo/config-model-users',
            repository =>
              'git://github.com/dod38fr/config-model.git',
        },
    },

    # cleanup required by t/auto_read.t
    add_to_cleanup => [ qw/wr_root r_root/ ],
);

$build->add_build_element('pl');
$build->add_build_element('appli');

$build->create_build_script;
