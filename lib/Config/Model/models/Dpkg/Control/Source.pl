[
  {
    'author' => [
      'Dominique Dumont'
    ],
    'copyright' => [
      '2010,2011 Dominique Dumont'
    ],
    'element' => [
      'Source',
      {
        'mandatory' => '1',
        'match' => '\\w[\\w+\\-\\.]{1,}',
        'summary' => 'source package name',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Maintainer',
      {
        'description' => 'The package maintainer\'s name and email address. The name must come first, then the email address inside angle brackets <> (in RFC822 format).

If the maintainer\'s name contains a full stop then the whole field will not work directly as an email address due to a misfeature in the syntax specified in RFC822; a program using this field as an address must check for this and correct the problem if necessary (for example by putting the name in round brackets and moving it to the end, and bringing the email address forward). ',
        'mandatory' => '1',
        'summary' => 'package maintainer\'s name and email address',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Uploaders',
      {
        'cargo' => {
          'replace_follow' => '!Dpkg my_config email-updates',
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'type' => 'list'
      },
      'Section',
      {
        'description' => 'The packages in the archive areas main, contrib and non-free are
grouped further into sections to simplify handling.

The archive area and section for each package should be specified in
the package\'s Section control record (see 
L<Section 5.6.5|http://www.debian.org/doc/debian-policy/ch-controlfields.html#s-f-Section>). 
However, the maintainer of the Debian archive may override
this selection to ensure the consistency of the Debian
distribution. The Section field should be of the form:

'.'=over

'.'=item * 

section if the package is in the main archive area,

'.'=item *

area/section if the package is in the contrib or non-free archive areas.

'.'=back

',
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warn_unless' => {
          'area' => {
            'code' => '(not defined) or m!^((contrib|non-free)/)?\\w+$!;',
            'msg' => 'Bad area. Should be \'non-free\' or \'contrib\''
          },
          'empty' => {
            'code' => 'defined and length',
            'msg' => 'Section is empty'
          },
          'section' => {
            'code' => '(not defined) or m!^([-\\w]+/)?(admin|cli-mono|comm|database|devel|debug|doc|editors|education|electronics|embedded|fonts|games|gnome|graphics|gnu-r|gnustep|hamradio|haskell|httpd|interpreters|introspection|java|kde|kernel|libs|libdevel|lisp|localization|mail|math|metapackages|misc|net|news|ocaml|oldlibs|otherosfs|perl|php|python|ruby|science|shells|sound|tex|text|utils|vcs|video|web|x11|xfce|zope)$!;',
            'msg' => 'Bad section.'
          }
        }
      },
      'XS-Testsuite',
      {
        'description' => 'Enable a testsuite to be used with this package. Currently only the \'autopkgtest\' name is allowed. For more details see L<README.package-tests|http://anonscm.debian.org/gitweb/?p=autopkgtest/autopkgtest.git;f=doc/README.package-tests;hb=HEAD>',
        'summary' => 'name of the non regression test suite',
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warn_unless_match' => {
          '^autopkgtest$' => {
            'fix' => '$_ = undef; # restore default value',
            'msg' => 'Currently, only "autopkgtest" is supported'
          }
        }
      },
      'XS-Autobuild',
      {
        'default' => '0',
        'description' => 'Read the full description from 
L<section 5.10.5|http://www.debian.org/doc/manuals/developers-reference/pkgs.html#non-free-buildd> 
in Debian developer reference.',
        'level' => 'hidden',
        'summary' => 'Allow automatic build of non-free or contrib package',
        'type' => 'leaf',
        'value_type' => 'boolean',
        'warp' => {
          'follow' => {
            'section' => '- Section'
          },
          'rules' => [
            '$section =~ m!^(contrib|non-free)/!',
            {
              'level' => 'normal'
            }
          ]
        },
        'write_as' => [
          'no',
          'yes'
        ]
      },
      'Priority',
      {
        'choice' => [
          'required',
          'important',
          'standard',
          'optional',
          'extra'
        ],
        'help' => {
          'extra' => 'This contains all packages that conflict with others with required, important, standard or optional priorities, or are only likely to be useful if you already know what they are or have specialized requirements (such as packages containing only detached debugging symbols).',
          'important' => 'Important programs, including those which one would expect to find on any Unix-like system. If the expectation is that an experienced Unix person who found it missing would say "What on earth is going on, where is foo?", it must be an important package.[5] Other packages without which the system will not run well or be usable must also have priority important. This does not include Emacs, the X Window System, TeX or any other large applications. The important packages are just a bare minimum of commonly-expected and necessary tools.',
          'optional' => '(In a sense everything that isn\'t required is optional, but that\'s not what is meant here.) This is all the software that you might reasonably want to install if you didn\'t know what it was and don\'t have specialized requirements. This is a much larger system and includes the X Window System, a full TeX distribution, and many applications. Note that optional packages should not conflict with each other. ',
          'required' => 'Packages which are necessary for the proper functioning of the system (usually, this means that dpkg functionality depends on these packages). Removing a required package may cause your system to become totally broken and you may not even be able to use dpkg to put things back, so only do so if you know what you are doing. Systems with only the required packages are probably unusable, but they do have enough functionality to allow the sysadmin to boot and install more software. ',
          'standard' => 'These packages provide a reasonably small but not too limited character-mode system. This is what will be installed by default if the user doesn\'t select anything else. It doesn\'t include many large applications. '
        },
        'type' => 'leaf',
        'value_type' => 'enum'
      },
      'Build-Depends',
      {
        'cargo' => {
          'class' => 'Config::Model::Dpkg::Dependency',
          'type' => 'leaf',
          'value_type' => 'uniline',
          'warn_if_match' => {
            'libpng12-dev' => {
              'fix' => '$_ = \'libpng-dev\';',
              'msg' => 'This dependency is deprecated and should be replaced with libpng-dev. See BTS 650601 for details'
            }
          }
        },
        'duplicates' => 'warn',
        'type' => 'list'
      },
      'Build-Depends-Indep',
      {
        'cargo' => {
          'class' => 'Config::Model::Dpkg::Dependency',
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'duplicates' => 'warn',
        'type' => 'list'
      },
      'Build-Conflicts',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'type' => 'list'
      },
      'Standards-Version',
      {
        'default' => '3.9.4',
        'description' => 'This field indicates the debian policy version number this package complies to',
        'match' => '\\d+\\.\\d+\\.\\d+(\\.\\d+)?',
        'summary' => 'Debian policy version number this package complies to',
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warn_unless_match' => {
          '3\\.9\\.4' => {
            'fix' => '$_ = undef; # restore default value',
            'msg' => 'Current standards version is 3.9.4'
          }
        }
      },
      'Vcs-Browser',
      {
        'compute' => {
          'allow_override' => '1',
          'formula' => '$maintainer =~ /pkg-perl/ ? "http://anonscm.debian.org/gitweb/?p=pkg-perl/packages/$pkgname.git" : undef ;',
          'use_eval' => '1',
          'variables' => {
            'maintainer' => '- Maintainer',
            'pkgname' => '- Source'
          }
        },
        'description' => 'Value of this field should be a http:// URL pointing to a web-browsable copy of the Version Control System repository used to maintain the given package, if available.

The information is meant to be useful for the final user, willing to browse the latest work done on the package (e.g. when looking for the patch fixing a bug tagged as pending in the bug tracking system). ',
        'match' => '^https?://',
        'summary' => 'web-browsable URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Arch',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Bzr',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Cvs',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Darcs',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Git',
      {
        'compute' => {
          'allow_override' => '1',
          'formula' => '$maintainer =~ /pkg-perl/ ? "git://anonscm.debian.org/pkg-perl/packages/$pkgname.git" : \'\' ;',
          'use_eval' => '1',
          'variables' => {
            'maintainer' => '- Maintainer',
            'pkgname' => '- Source'
          }
        },
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Hg',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Mtn',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Vcs-Svn',
      {
        'description' => 'Value of this field should be a string identifying unequivocally the location of the Version Control System repository used to maintain the given package, if available. * identify the Version Control System; currently the following systems are supported by the package tracking system: arch, bzr (Bazaar), cvs, darcs, git, hg (Mercurial), mtn (Monotone), svn (Subversion). It is allowed to specify different VCS fields for the same package: they will all be shown in the PTS web interface.

The information is meant to be useful for a user knowledgeable in the given Version Control System and willing to build the current version of a package from the VCS sources. Other uses of this information might include automatic building of the latest VCS version of the given package. To this end the location pointed to by the field should better be version agnostic and point to the main branch (for VCSs supporting such a concept). Also, the location pointed to should be accessible to the final user; fulfilling this requirement might imply pointing to an anonymous access of the repository instead of pointing to an SSH-accessible version of the same. ',
        'summary' => 'URL of the VCS repository',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'DM-Upload-Allowed',
      {
        'description' => 'If this field is present, then any Debian Maintainers listed in the Maintainer or Uploaders fields may upload the package directly to the Debian archive.  For more information see the "Debian Maintainer" page at the Debian Wiki - http://wiki.debian.org/DebianMaintainer',
        'match' => 'yes',
        'status' => 'deprecated',
        'summary' => 'The package may be uploaded by a Debian Maintainer',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Homepage',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'XS-Python-Version',
      {
        'experience' => 'advanced',
        'status' => 'deprecated',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'X-Python-Version',
      {
        'description' => 'This field specifies the versions of Python (not versions of Python 3) supported by the source package.  When not specified, they default to all currently supported Python (or Python 3) versions. For more detail, See L<python policy|http://www.debian.org/doc/packaging-manuals/python-policy/ch-module_packages.html#s-specifying_versions>',
        'experience' => 'advanced',
        'migrate_from' => {
          'formula' => 'my $old = $xspython ;
my $new ;
if ($old =~ /,/) {
   # list of versions
   my @list = sort split /\\s*,\\s*/, $old ; 
   $new = ">= ". (shift @list) . ", << " .  (pop @list) ;
}
elsif ($old =~ /-/) {
   my @list = sort grep { $_ ;} split /\\s*-\\s*/, $old ; 
   $new = ">= ". shift @list ;
   $new .= ", << ". pop @list if @list ;
}
else {
   $new = $old ;
}
$new ;',
          'use_eval' => '1',
          'variables' => {
            'xspython' => '- XS-Python-Version'
          }
        },
        'summary' => 'supported versions of Python ',
        'type' => 'leaf',
        'upstream_default' => 'all',
        'value_type' => 'uniline'
      },
      'X-Python3-Version',
      {
        'description' => 'This field specifies the versions of Python 3 supported by the package. For more detail, See L<python policy|http://www.debian.org/doc/packaging-manuals/python-policy/ch-module_packages.html#s-specifying_versions>',
        'experience' => 'advanced',
        'summary' => 'supported versions of Python3 ',
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'XS-Ruby-Versions',
      {
        'description' => 'indicate the versions of the interpreter
supported by the library',
        'level' => 'hidden',
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warp' => {
          'follow' => {
            'section' => '- Section'
          },
          'rules' => [
            '$section =~ m!ruby$!',
            {
              'level' => 'normal'
            }
          ]
        }
      }
    ],
    'license' => 'LGPL2',
    'name' => 'Dpkg::Control::Source'
  }
]
;

