????-??-?? David Allsopp <david.allsopp -at- metastack.com>
  Next
* Improve tail-stripping of MSVS_PATH to prevent path blow-out. More recent
  Visual Studios add some elements for extensions to the end of PATH. This
  should eliminate msvs-detect ever including the original PATH in MSVS_PATH
* Erase %ORIGINALPATH% to deal with SetEnv scripts overridding PATH. Doesn't
  appear to be needed for the newer equivalent VSCMD variable
* Ensure PATH-mangling never overrides Cygwin bin (in particular, ensure `which`
  is always from the same Cygwin as the script)

2019-06-13 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.4.0
* Fix error excluding environment compiler when either LIB or INCLUDE is not
  set (report from npmazzuca -at- gmail.com)
* Workaround MSYS2's cmd script
* Add support for MSYS2 bash
* Add metadata for Visual Studio 2019

2018-01-03 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.3.2
* Ensure commands run by msvs-promote-path don't write to stderr
* Fix selection of Visual Studio 2017 in MSVS_PREFERENCE (updates have unique
  version numbers, which prevented automatic selection).
* Use = instead of unnecessary := for assignment for --output=make
* Don't add double-quotes around strings for --output=make
* Fix escaping of single quote for --output=shell
* Fix escaping of # and $ for --output=make

2017-08-18 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.3.1
* Complete the support for newer Cygwin tools

2017-08-17 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.3.0
* Add support for Visual Studio 2017
* Add support for newer Cygwin tools

2016-03-26 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.2.0
* Add MSVS_NAME to environment variables.

2016-02-23 David Allsopp <david.allsopp -at- metastack.com>
  Version 0.1.0
* Initial release.
