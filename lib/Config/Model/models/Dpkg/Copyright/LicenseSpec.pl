[
  {
    'accept' => [
      '.*',
      {
        'description' => 'license short_name. Example: GPL-1 LPL-2.1+',
        'type' => 'leaf',
        'value_type' => 'string'
      }
    ],
    'author' => [
      'Dominique Dumont'
    ],
    'class_description' => 'Stand-alone license paragraph. This paragraph is used to describe licenses which are used somewhere else in the Files paragraph.',
    'copyright' => [
      '2010',
      '2011 Dominique Dumont'
    ],
    'element' => [
      'text',
      {
        'compute' => {
          'allow_override' => '1',
          'formula' => 'require Software::LicenseUtils ;
my $h = { 
  short_name => &index( - ), 
  holder => \'foo\' 
} ;

# no need to fail if short_name is unknown
eval {
  Software::LicenseUtils->new_from_short_name($h)->summary ; 
} ;',
          'undef_is' => '\'\'',
          'use_eval' => '1'
        },
        'description' => 'Full license text.',
        'type' => 'leaf',
        'value_type' => 'string'
      }
    ],
    'license' => 'LGPL2',
    'name' => 'Dpkg::Copyright::LicenseSpec'
  }
]
;

