[
  {
    'accept' => [
      'Bug-.*',
      {
        'accept_after' => 'Bug',
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'type' => 'list'
      }
    ],
    'element' => [
      'Synopsis',
      {
        'summary' => 'short description of the patch',
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warn_if_match' => {
          '.{60,}' => {
            'msg' => 'Synopsis is too long. '
          }
        },
        'warn_unless' => {
          'empty' => {
            'code' => 'defined $_ && /\\w/ ? 1 : 0 ;',
            'fix' => '$_ = ucfirst( $self->parent->index_value )  ;
s/-/ /g;
',
            'msg' => 'Empty synopsis'
          }
        }
      },
      'Description',
      {
        'description' => 'verbose explanation of the patch and its history.',
        'type' => 'leaf',
        'value_type' => 'string'
      },
      'Subject',
      {
        'type' => 'leaf',
        'value_type' => 'string'
      },
      'Bug',
      {
        'cargo' => {
          'type' => 'leaf',
          'value_type' => 'uniline'
        },
        'type' => 'list'
      },
      'Forwarded',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Author',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Origin',
      {
        'type' => 'leaf',
        'value_type' => 'string'
      },
      'From',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Reviewed-by',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Acked-by',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Last-Update',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'Applied-Upstream',
      {
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'diff',
      {
        'description' => 'This element contains the diff that will be used to patch the source. Do not modify.',
        'summary' => 'actual patch',
        'type' => 'leaf',
        'value_type' => 'string'
      }
    ],
    'name' => 'Dpkg::Patch',
    'read_config' => [
      {
        'backend' => 'Dpkg::Patch',
        'config_dir' => 'debian/patches'
      }
    ]
  }
]
;

