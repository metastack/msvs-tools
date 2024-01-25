@rem ********************************************************************************************* *
@rem MetaStack Solutions Ltd.                                                                      *
@rem ********************************************************************************************* *
@rem AppVeyor CI Configuration                                                                     *
@rem ********************************************************************************************* *
@rem Copyright (c) 2024 David Allsopp Ltd.                                                         *
@rem ********************************************************************************************* *
@rem Author: David Allsopp                                                                         *
@rem 25-Jan-2024                                                                                   *
@rem ********************************************************************************************* *
@rem Redistribution and use in source and binary forms, with or without modification, are          *
@rem permitted provided that the following two conditions are met:                                 *
@rem     1. Redistributions of source code must retain the above copyright notice, this list of    *
@rem        conditions and the following disclaimer.                                               *
@rem     2. Neither the name of MetaStack Solutions Ltd. nor the names of its contributors may be  *
@rem        used to endorse or promote products derived from this software without specific prior  *
@rem        written permission.                                                                    *
@rem                                                                                               *
@rem This software is provided by the Copyright Holder 'as is' and any express or implied          *
@rem warranties including, but not limited to, the implied warranties of merchantability and       *
@rem fitness for a particular purpose are disclaimed. In no event shall the Copyright Holder be    *
@rem liable for any direct, indirect, incidental, special, exemplary, or consequential damages     *
@rem (including, but not limited to, procurement of substitute goods or services; loss of use,     *
@rem data, or profits; or business interruption) however caused and on any theory of liability,    *
@rem whether in contract, strict liability, or tort (including negligence or otherwise) arising in *
@rem any way out of the use of this software, even if advised of the possibility of such damage.   *
@rem ********************************************************************************************* *

@setlocal
@echo off

set "RETURN_CWD=%CD%"

call %SCRIPT%

cd "%RETURN_CWD%"

where cl.exe

set CHERE_INVOKING=true
set FAILED=0
set THIS=%1-%2

echo Environment set to %THIS%
for /f "delims=" %%f in ('dir /b *.clean') do call :test %%f

exit /b %FAILED%

:test
for /f "tokens=1,2 delims=-" %%a in ('echo %1') do (
  set ARCH=%%b
  set VER=%%a
)
set ARCH=%ARCH:~0,-6%
echo Testing %VER%-%ARCH%
bash -lc "diff -u %1 <(./msvs-detect --arch=%ARCH% --output=data -- %VER%)"
if %ERRORLEVEL% gtr 0 set FAILED=1
if "%VER%-%ARCH%" neq "%THIS%" goto :EOF
bash -lc "diff -u <(head -n 2 %1) <(./msvs-detect --arch=%ARCH% --output=data -- @)"
if %ERRORLEVEL% gtr 0 set FAILED=1

goto :EOF
