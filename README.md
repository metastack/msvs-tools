[![Build status](https://ci.appveyor.com/api/projects/status/xkv71sbva7v9w6ts/branch/master?svg=true)](https://ci.appveyor.com/project/dra27/msvs-tools-9m37n/branch/master)

# Microsoft Visual Studio Helper Scripts

Various scripts provided for integrating with the Microsoft C Compiler from Microsoft Visual Studio.
These scripts have been authored primarily for use in the OCaml ecosystem, but may be useful for
other language environments or systems.

### msvs-detect

`msvs-detect` is designed to be run from Cygwin's bash and should have no package dependencies over
a "base" installation of Cygwin. It scans the system for Microsoft C Compilers provided both by
Windows SDKs and Microsoft Visual Studio packages. It detects all versions of Visual Studio from
.NET 2002 (version 7.0) onwards. Furthermore, it detects if the installation has the Microsoft C
runtime library and Windows SDK Headers and Libraries.

The script can be used in three ways:

 1. To provide the environment variables for a C compiler, without requiring the user to start
    Cygwin from a Visual Studio or SDK Command Prompt.
 2. To determine the complementary C compiler for the one in the environment, if the script is run
    from a Visual Studio Command Prompt or the user has manually configured their environment with
    the required values. This means that if the environment contains an x86 C compiler, determine
    the variables needed to select the x64 compiler for the same version and vice versa. 
 3. To choose between multiple installed versions (including the version found in the environment)
    based on required tools and architectures - e.g. versions installed with the Manifest Tool,
    versions installed with an assembler.

The output of the tool (unless run with `--all`) is commands for setting environment variables, so
the tool would normally be invoked as `eval $(./msvs-detect ...)`. It sets `MSVS_PATH`, `MSVS_INC`
and `MSVS_LIB` with the values that need to prepended to `PATH`, `INCLUDE` and `LIB` respectively
(`MSVS_PATH` is in Cygwin format, and the variables always end with the appropriate separator).
Additionally, if `--with-assembler` is specified, `MSVS_ML` contains the name of the assembler (ml
or ml64). By default, the tool searches for installations providing both x86 and x64 (the `--arch`
switch allows searching for a single architecture) so the `MSVS_` variables contain the x86 compiler
details and `MSVS64_` the x64 details. When `--arch` is specified, no `MSVS64_` variables are
shown.

If no compiler is found matching the requirements then nothing is displayed, but the tool sets the
exit status to 1.

Examples

 - `./msvs-detect --all` -- displays all the available C compilers (including the identity of the
   environment C compiler, if it can be determined).
 - `./msvs-detect --all --with-mt --with-assembler` -- displays all the available C compilers which
   include an assembler (ml or ml64) and the Microsoft Manifest Tool.
 - `./msvs-detect --arch=x86` -- displays the details for an x86 C compiler.
 - `./msvs-detect --arch=x64 "14.0;@"` -- displays the details for an x64 compiler preferring
   Visual Studio 2015 but otherwise selecting whatever is in the environment.

### msvs-promote-path

`msvs-promote-path` is designed to solve a conflict between Microsoft's Linker (link.exe) and the
link command from GNU coreutils. In a default Cygwin installation, `/usr/bin` appears at the front
of `PATH` which means that if Cygwin is launched from a Visual Studio Command Prompt (or simply
launched from the Start Menu but where the user has manually registered the environment variables
for Visual Studio) then the command `link` will refer to `/usr/bin/link` and not the (probably)
desired Microsoft Linker. The coreutils `link` command has very few uses on Windows.

The simplest solution is to reconfigure Cygwin to put `/usr/bin` at the end of `PATH`, but this will
cause coreutils's `sort` and findutils's `find` commands to be replaced by the Windows versions
which is usually not desirable.

There are multiple solutions to this problem, `msvs-promote-path` provides just one. It is intended
to be invoked:

```
eval $(msvs-promote-path)
```

The script checks whether the `cl` and `link` commands are coming from the same directory in `PATH`.
If not, it moves the directory for `cl` to the start of `PATH`, and also displays a message that
it has done so. It is safe to run the command multiple times, if `cl` and `link` are from the same
directory, no change is made.
