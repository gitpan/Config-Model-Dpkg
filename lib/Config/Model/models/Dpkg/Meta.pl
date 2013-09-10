[
  {
    'author' => [
      'Dominique Dumont'
    ],
    'class_description' => 'This class contains parameters to tune the behavior of the Dpkg model. For instance, user can specify rules to update e-mail addresses.',
    'copyright' => [
      '2010,2011 Dominique Dumont'
    ],
    'element' => [
      'email',
      {
        'compute' => {
          'allow_override' => '1',
          'formula' => '$ENV{DEBEMAIL} ;',
          'use_eval' => '1'
        },
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'email-updates',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'description' => 'Specify old email as key. The value is the new e-mail address that will be substituted',
        'index_type' => 'string',
        'summary' => 'email update hash',
        'type' => 'hash'
      },
      'dependency-filter',
      {
        'choice' => [
          'etch',
          'lenny',
          'squeeze',
          'wheezy'
        ],
        'description' => 'Specifies the dependency filter to be used. The release specified mentions the most recent release to be filtered out. Older release will also be filtered.

For instance, if the dependency filter is \'lenny\', all \'lenny\' and \'etch\' dependencies are filtered out.',
        'type' => 'leaf',
        'value_type' => 'enum'
      },
      'group-dependency-filter',
      {
        'cargo' => {
          'choice' => [
            'etch',
            'lenny',
            'squeeze',
            'wheezy'
          ],
          'type' => 'leaf',
          'value_type' => 'enum'
        },
        'default_with_init' => {
          'Debian Perl Group <pkg-perl-maintainers@lists.alioth.debian.org>' => 'etch'
        },
        'description' => 'Dependency filter tuned by Maintainer field. Use this to override the main dependency-filter value.',
        'index_type' => 'string',
        'type' => 'hash'
      },
      'package-dependency-filter',
      {
        'cargo' => {
          'choice' => [
            'etch',
            'lenny',
            'squeeze',
            'wheezy'
          ],
          'compute' => {
            'allow_override' => '1',
            'formula' => '$group_filter || $dependency_filter ;',
            'undef_is' => '\'\'',
            'use_eval' => '1',
            'variables' => {
              'dependency_filter' => '- dependency-filter',
              'group_filter' => '- group-dependency-filter:"$maintainer"',
              'maintainer' => '! control source Maintainer'
            }
          },
          'type' => 'leaf',
          'value_type' => 'enum'
        },
        'description' => 'Dependency filter tuned by package. Use this to override the main dependency-filter value.',
        'index_type' => 'string',
        'type' => 'hash'
      }
    ],
    'license' => 'LGPL2',
    'name' => 'Dpkg::Meta',
    'read_config' => [
      {
        'auto_create' => '1',
        'backend' => 'Yaml',
        'config_dir' => '~/',
        'file' => '.dpkg-meta.yml',
        'full_dump' => '0'
      }
    ]
  }
]
;

