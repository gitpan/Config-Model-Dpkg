[
  {
    'author' => [
      'Dominique Dumont'
    ],
    'class_description' => 'Model of Debian source package files (e.g debian/control, debian/copyright...)',
    'copyright' => [
      '2010,2011 Dominique Dumont'
    ],
    'element' => [
      'my_config',
      {
        'config_class_name' => 'Dpkg::Meta',
        'description' => 'This element contains a set of parameters to tune the behavior of this dpkg editor. You can for instance specify e-mail replacements. These parameters are stored in ~/.dpkg-meta.yml or ~/.local/share/.dpkg-meta.yml. These parameters can be applied to all Debian packages you maintain in this unix account.',
        'type' => 'node'
      },
      'control',
      {
        'config_class_name' => 'Dpkg::Control',
        'description' => 'Package control file. Specifies the most vital (and version-independent) information about the source package and about the binary packages it creates.',
        'type' => 'node'
      },
      'rules',
      {
        'description' => 'debian/rules is a makefile containing all intructions required to build a debian package.',
        'summary' => 'package build rules',
        'type' => 'leaf',
        'value_type' => 'string'
      },
      'copyright',
      {
        'config_class_name' => 'Dpkg::Copyright',
        'description' => 'copyright and license information of all files contained in this package',
        'summary' => 'copyright and license information',
        'type' => 'node'
      },
      'source',
      {
        'config_class_name' => 'Dpkg::Source',
        'type' => 'node'
      },
      'clean',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'description' => 'list of files to remove when dh_clean is run. Files names can include wild cards. For instance:

 build.log
 Makefile.in
 */Makefile.in
 */*/Makefile.in

',
        'summary' => 'list of files to clean',
        'type' => 'list'
      },
      'patches',
      {
        'cargo' => {
          'config_class_name' => 'Dpkg::Patch',
          'type' => 'node'
        },
        'index_type' => 'string',
        'ordered' => '1',
        'type' => 'hash'
      },
      'compat',
      {
        'default' => '9',
        'description' => 'compat file defines the debhelper compatibility level',
        'type' => 'leaf',
        'value_type' => 'integer'
      },
      'dirs',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline',
          'warn' => 'Make sure that this directory is actually needed. See L<http://www.debian.org/doc/manuals/maint-guide/dother.en.html#dirs> for details'
        },
        'description' => 'This file specifies any directories which we need but which are not created by the normal installation procedure (make install DESTDIR=... invoked by dh_auto_install). This generally means there is a problem with the Makefile.

Files listed in an install file don\'t need their directories created first. 

It is best to try to run the installation first and only use this if you run into trouble. There is no preceding slash on the directory names listed in the dirs file. ',
        'summary' => 'Extra directories',
        'type' => 'list'
      },
      'docs',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'description' => 'This file specifies the file names of documentation files we can have dh_installdocs(1) install into the temporary directory for us.

By default, it will include all existing files in the top-level source directory that are called BUGS, README*, TODO etc. ',
        'type' => 'list'
      }
    ],
    'license' => 'LGPL2',
    'name' => 'Dpkg',
    'read_config' => [
      {
        'auto_create' => '1',
        'backend' => 'Dpkg',
        'config_dir' => 'debian',
        'file' => 'clean'
      }
    ]
  }
]
;

