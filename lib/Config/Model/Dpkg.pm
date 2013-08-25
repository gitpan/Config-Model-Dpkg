package Config::Model::Dpkg;

our $VERSION='2.038';

1;

=pod

=head1 NAME

Config::Model::Dpkg - Edit and validate Dpkg source files

=head1 SYNOPSIS

=head2 invoke editor

The following command must be run in a package source directory. Whenrun, L<cme> 
will load most files from C<debian> directory and launch a graphical editor:

 cme edit dpkg
 
You can choose to edit only C<debian/control> or C<debian/copyright>:

 cme edit dpkg-control
 cme edit dpkg-copyright

=head2 Just check dpkg files

You can also use L<cme> to run sanity checks on the source files:

 cme check dpkg 

=head2 Fix warnings

When run, cme may issue several warnings regarding the content of your file. 
You can choose to  fix (most of) these warnings with the command:

 cme fix dpkg

=head2 programmatic

This code snippet will change the maintainer address in control file:

 use Config::Model ;
 use Log::Log4perl qw(:easy) ;
 my $model = Config::Model -> new ( ) ;
 my $inst = $model->instance (root_class_name => 'Dpkg');
 $inst -> config_root ->load("control source Maintainer=foo@bedian.arg") ;
 $inst->write_back() ;

=head1 DESCRIPTION

This module provides a configuration editor (and models) for the 
files of a Debian source package. (i.e. most of the files contained in the
C<debian> directory of a source package).

This module can also be used to modify safely the
content of these files from a Perl programs.

=head1 user interfaces

As mentioned in L<cme>, several user interfaces are available:

=over

=item *

A graphical interface is proposed by default if L<Config::Model::TkUI> is installed.

=item *

A L<Fuse> virtual file system with option C<< cme fusefs dpkg -fuse_dir <mountpoint> >> 
if L<Fuse> is installed (Linux only)

=back

=head1 BUGS

Config::Model design does not really cope well with a some detail of
L<Debian patch header specification|http://dep.debian.net/deps/dep3/> (aka DEP-3).
Description and subject are both authorized, but only B<one> of them is
required and using the 2 is forbidden. So, both fields are accepted,
but subject is stored as description in the configuration tree.
C<cme fix> or C<cme edit> will write back a description field.

=head1 AUTHOR

Dominique Dumont, (dod at debian dot org)

=head1 SEE ALSO

=over

=item *

L<cme>

=item *

L<Config::Model>

=item *

http://github.com/dod38fr/config-model/wiki/Using-config-model

=back

