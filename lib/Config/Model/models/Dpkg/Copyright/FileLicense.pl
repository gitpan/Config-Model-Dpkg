[
  {
    'author' => [
      'Dominique Dumont'
    ],
    'copyright' => [
      '2010,2011 Dominique Dumont'
    ],
    'element' => [
      'short_name',
      {
        'description' => 'abbreviated name for the license. If empty, it is given the default 
value \'other\'. Only one license per file can use this default value; if there is more 
than one license present in the package without a standard short name, an arbitrary 
short name may be assigned for these licenses. These arbitrary names are only guaranteed 
to be unique within a single copyright file.

The name given must match a License described in License element in root node
',
        'grammar' => 'check: <rulevar: local $found = 0> <rulevar: local $ok = 1 >
check: license alternate(s?) <reject: $text or not $found or not $ok >
alternate: comma(?) oper license 
comma: \',\'
oper: \'and\' | \'or\' 
license: /[^\\s,]+/i
   { # PRD action to check if the license text is provided
     my $abbrev = $item[1] ;
     $found++ ;
     my $elt = $arg[0]->grab(step => "!Dpkg::Copyright License", mode => \'strict\', type => \'hash\') ;
     if ($elt->defined($abbrev) or $arg[0]->grab("- full_license")->fetch) {
        $ok &&= 1;
     }
     else { 
     	 $ok = 0 ;
         ${$arg[1]} .= "license $abbrev is not declared in main License section. Expected ".join(" ",$elt->fetch_all_indexes) ;
     }
   } ',
        'help' => {
          'Apache' => 'Apache license. For versions, consult the Apache_Software_Foundation.',
          'Artistic' => 'Artistic license. For versions, consult the Perl_Foundation',
          'BSD-2-clause' => 'Berkeley software distribution license, 2-clause version',
          'BSD-3-clause' => 'Berkeley software distribution license, 3-clause version',
          'BSD-4-clause' => 'Berkeley software distribution license, 4-clause version',
          'CC-BY' => 'Creative Commons Attribution license',
          'CC-BY-NC' => 'Creative Commons Attribution Non-Commercial',
          'CC-BY-NC-ND' => 'Creative Commons Attribution Non-Commercial No Derivatives',
          'CC-BY-NC-SA' => 'Creative Commons Attribution Non-Commercial Share Alike',
          'CC-BY-ND' => 'Creative Commons Attribution No Derivatives',
          'CC-BY-SA' => 'Creative Commons Attribution Share Alike license',
          'CC0' => 'Creative Commons Universal waiver',
          'CDDL' => 'Common Development and Distribution License. For versions, consult Sun Microsystems.',
          'CPL' => 'IBM Common Public License. For versions, consult the IBM_Common_Public License_(CPL)_Frequently_asked_questions.',
          'EFL' => 'The Eiffel Forum License. For versions, consult the Open_Source_Initiative',
          'Expat' => 'The Expat license',
          'FreeBSD' => 'FreeBSD Project license',
          'GFDL' => 'GNU Free Documentation License',
          'GFDL-NIV' => 'GNU Free Documentation License, with no invariant sections',
          'GPL' => 'GNU General Public License',
          'ISC' => 'Internet_Software_Consortium\'s license, sometimes also known as the OpenBSD License',
          'LGPL' => 'GNU Lesser General Public License, (GNU Library General Public License for versions lower than 2.1)',
          'LPPL' => 'LaTeX Project Public License',
          'MPL' => 'Mozilla Public License. For versions, consult Mozilla.org',
          'Perl' => 'Perl license (equates to "GPL-1+ or Artistic-1")',
          'Python-CNRI' => 'Python Software Foundation license. For versions, consult the Python_Software Foundation',
          'QPL' => 'Q Public License',
          'W3C' => 'W3C Software License. For more information, consult the W3C IntellectualRights FAQ and the 20021231 W3C_Software_notice_and_license',
          'ZLIB' => 'zlib/libpng_license',
          'Zope' => 'Zope Public License. For versions, consult Zope.org'
        },
        'migrate_from' => {
          'formula' => '$replace{$alias}',
          'replace' => {
            'Perl' => 'Artistic or GPL-1+'
          },
          'variables' => {
            'alias' => '- - License-Alias'
          }
        },
        'type' => 'leaf',
        'value_type' => 'uniline',
        'warp' => {
          'rules' => [
            '&location !~ /Global/',
            {
              'mandatory' => '1'
            }
          ]
        }
      },
      'exception',
      {
        'description' => 'License exception',
        'help' => {
          'Font' => 'The GPL "Font" exception refers to the text added to the license notice of each file as specified at How_does_the_GPL_apply_to_fonts?. The precise text corresponding to this exception is:
As a special exception, if you create a document which uses this
font, and embed this font or unaltered portions of this font into the
document, this font does not by itself cause the resulting document
to be covered by the GNU General Public License. This exception does
not however invalidate any other reasons why the document might be
covered by the GNU General Public License. If you modify this font,
you may extend this exception to your version of the font, but you
are not obligated to do so. If you do not wish to do so, delete this
exception statement from your version.',
          'OpenSSL' => 'The GPL "OpenSSL" exception gives permission to link GPL-licensed code with the OpenSSL library, which contains GPL-incompatible clauses. For more information, see "The_-OpenSSL_License_and_The_GPL" by Mark McLoughlin and the message "middleman_software_license_conflicts_with_OpenSSL" by Mark McLoughlin on the debian-legal mailing list. The text corresponding to this exception is:
In addition, as a special exception, the copyright holders give
permission to link the code of portions of this program with the
OpenSSL library under certain conditions as described in each
individual source file, and distribute linked combinations including
the two.

You must obey the GNU General Public License in all respects for all
of the code used other than OpenSSL. If you modify file(s) with this
exception, you may extend this exception to your version of the file
(s), but you are not obligated to do so. If you do not wish to do so,
delete this exception statement from your version. If you delete this
exception statement from all source files in the program, then also
delete it here.'
        },
        'type' => 'leaf',
        'value_type' => 'uniline'
      },
      'full_license',
      {
        'description' => 'if left blank here, the file must include a stand-alone License section matching each license short name listed on the first line (see the Standalone License Section section). Otherwise, this field should either include the full text of the license(s) or include a pointer to the license file under /usr/share/common-licenses. This field should include all text needed in order to fulfill both Debian Policy requirement for including a copy of the software distribution license, and any license requirements to include warranty disclaimers or other notices with the binary package.
',
        'type' => 'leaf',
        'value_type' => 'string'
      }
    ],
    'license' => 'LGPL2',
    'name' => 'Dpkg::Copyright::FileLicense'
  }
]
;

