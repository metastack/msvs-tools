<#
.SYNOPSIS
Microsoft C Compiler Environment Detection Script

.DESCRIPTION
Queries the environment and registry to locate Visual Studio / Windows SDK
installations and uses their initialisation scripts (SetEnv.cmd, vcvarsall.bat,
etc.) to determine INCLUDE, LIB and PATH alterations.

The script outputs PowerShell environment variable assignments that can be
evaluated using Invoke-Expression (iex):
    .\msvs-detect.ps1 | iex

This is equivalent to bash's: eval $(./msvs-detect)

.PARAMETER All
Display all available compiler packages

.PARAMETER Installed
Display all detected compiler packages; similarly to -All, except the list
includes versions and may include packages which don't include the required
compiler, tools, or libraries.

.PARAMETER Arch
Only consider packages for ARCH (x86 or x64). Default is to return packages
containing both architectures. Valid values: x86, x64, x86_32, x86_64, 86, 64

.PARAMETER Output
Set final output format. Default is shell. Valid values:
  shell - PowerShell assignments, for use with Invoke-Expression
  make  - make assignments, for inclusion in a Makefile
  data  - raw data, for parsing in other systems

.PARAMETER Debug
Set debug messages level (0-4). Higher values produce more detailed output.

.PARAMETER WithMt
Only consider packages including the Manifest Tool

.PARAMETER WithAssembler
Only consider packages including an assembler (ml or ml64)

.PARAMETER Version
Display the version information

.PARAMETER Help
Display this help screen

.PARAMETER MsvsPreference
Semicolon-separated list of preferred versions. Three kinds of version notation:
  1. @ - refers to the C compiler found in PATH (if it can be identified)
  2. mm.n - Visual Studio version (e.g. 14.0, 7.1)
  3. SPEC - package specification (e.g. VS14.0, SDK7.1, VS15.*)

.EXAMPLE
.\msvs-detect.ps1
Detect the default compiler for both x86 and x64 architectures

.EXAMPLE
.\msvs-detect.ps1 | iex
Set MSVS environment variables in the current PowerShell session

.EXAMPLE
.\msvs-detect.ps1 -All
Display all available compiler packages

.EXAMPLE
.\msvs-detect.ps1 -Arch x64 -WithAssembler
Find an x64 compiler that includes an assembler

.EXAMPLE
.\msvs-detect.ps1 -Output make "14.0;@"
Prefer Visual Studio 2015, fall back to environment, output in make format

.NOTES
################################################################################################
MetaStack Solutions Ltd.
################################################################################################
Microsoft C Compiler Environment Detection Script
################################################################################################
Copyright (c) 2016, 2017, 2018, 2019, 2020, 2021 MetaStack Solutions Ltd.
Copyright (c) 2022, 2024, 2025 David Allsopp Ltd.
################################################################################################
Author: David Allsopp
16-Feb-2016 (bash version)
2025-11-20 (PowerShell conversion)
################################################################################################
Redistribution and use in source and binary forms, with or without modification, are permitted
provided that the following two conditions are met:
    1. Redistributions of source code must retain the above copyright notice, this list of
       conditions and the following disclaimer.
    2. Neither the name of MetaStack Solutions Ltd. nor the names of its contributors may be
       used to endorse or promote products derived from this software without specific prior
       written permission.

This software is provided by the Copyright Holder 'as is' and any express or implied warranties
including, but not limited to, the implied warranties of merchantability and fitness for a
particular purpose are disclaimed. In no event shall the Copyright Holder be liable for any
direct, indirect, incidental, special, exemplary, or consequential damages (including, but not
limited to, procurement of substitute goods or services; loss of use, data, or profits; or
business interruption) however caused and on any theory of liability, whether in contract,
strict liability, or tort (including negligence or otherwise) arising in any way out of the use
of this software, even if advised of the possibility of such damage.
################################################################################################
#>

[CmdletBinding(DefaultParameterSetName='Default')]
param(
    [Parameter(ParameterSetName='All')]
    [Alias('a')]
    [switch]$All,

    [Parameter(ParameterSetName='Installed')]
    [Alias('i')]
    [switch]$Installed,

    [Parameter(ParameterSetName='Default')]
    [ValidateSet('x86', 'x64', 'x86_32', 'x86_64', '86', '64')]
    [Alias('x')]
    [string]$Arch,

    [ValidateSet('shell', 'make', 'data')]
    [Alias('o')]
    [string]$Output = 'shell',

    [Alias('d')]
    [ValidateRange(0, 4)]
    [int]$DebugLevel = 0,

    [switch]$WithMt,
    [switch]$WithAssembler,

    [Parameter(ParameterSetName='Version')]
    [Alias('v')]
    [switch]$Version,

    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$MsvsPreference
)

$ErrorActionPreference = 'Stop'
$Script:ScriptVersion = "0.8.1~dev"

# Script-level variables for state management
$Script:DebugLevelValue = $DebugLevel
$Script:ML_REQUIRED = $WithAssembler.IsPresent
$Script:MT_REQUIRED = $WithMt.IsPresent
$Script:OUTPUT_MODE = switch ($Output) {
    'shell' { 0 }
    'make'  { 1 }
    'data'  { 2 }
}

# Determine operation mode
$Script:MODE = if ($All) { 1 }
               elseif ($Installed) { 2 }
               elseif ($Version) { 4 }
               else { 0 }

# Normalize architecture
$Script:TARGET_ARCH = if ($Arch) {
    switch ($Arch) {
        { $_ -in '86', 'x86', 'x86_32' } { 'x86' }
        { $_ -in '64', 'x64', 'x86_64' } { 'x64' }
    }
} else { $null }

# Set LEFT_ARCH and RIGHT_ARCH based on TARGET_ARCH
if ($Script:TARGET_ARCH) {
    $Script:LEFT_ARCH = $Script:TARGET_ARCH
    $Script:RIGHT_ARCH = $Script:TARGET_ARCH
} else {
    $Script:LEFT_ARCH = 'x86'
    $Script:RIGHT_ARCH = 'x64'
}

# Handle version display
if ($Version) {
    Write-Host "Microsoft C Compiler Environment Detection Script"
    Write-Host "Version $Script:ScriptVersion"
    exit 0
}

#region Utility Functions

function Write-DebugMessage {
    param(
        [string]$Message,
        [int]$Level = 2
    )

    if ($Script:DebugLevelValue -ge $Level) {
        Write-Host $Message -ForegroundColor Gray
    }
}

function Write-WarningMessage {
    param([string]$Message)

    if ($Script:DebugLevelValue -gt 0) {
        Write-Warning $Message
    }
}

function Get-RegistryString {
    param(
        [string]$Path,
        [string]$Name,
        [switch]$Force64bit
    )

    try {
        # Convert registry path format
        $psPath = $Path -replace '^HKLM\\', 'HKLM:\'

        # Handle WOW64 redirection
        if ($Force64bit -and [Environment]::Is64BitOperatingSystem) {
            # Access 64-bit registry view
            $psPath = $psPath -replace '^HKLM:\\SOFTWARE\\', 'HKLM:\SOFTWARE\'
        } elseif (-not $Force64bit -and [Environment]::Is64BitOperatingSystem -and [Environment]::Is64BitProcess) {
            # Access 32-bit registry view (WOW6432Node)
            $psPath = $psPath -replace '^HKLM:\\SOFTWARE\\Microsoft', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft'
        }

        $value = Get-ItemProperty -Path $psPath -Name $Name -ErrorAction SilentlyContinue
        if ($value) {
            return $value.$Name
        }
    }
    catch {
        Write-DebugMessage "Registry access failed: $Path\$Name" 4
    }

    return $null
}

function Test-FileInPaths {
    param(
        [string]$PathList,  # Semicolon-separated paths
        [string]$FileName
    )

    Write-DebugMessage "Looking for $FileName in $PathList" 4

    if ([string]::IsNullOrEmpty($PathList)) {
        return $false
    }

    $paths = $PathList -split ';' | Where-Object { $_ -ne '' }
    foreach ($path in $paths) {
        $fullPath = Join-Path $path $FileName
        if (Test-Path $fullPath) {
            return $true
        }
    }

    Write-DebugMessage "$FileName not found" 4
    return $false
}

function Test-Environment {
    <#
    .SYNOPSIS
    Verifies that PATH, INC and LIB provide a complete compiler

    .DESCRIPTION
    Checks for the presence of various files to verify a valid compiler installation.
    Returns 0 if valid, non-zero otherwise. Sets $Script:ASSEMBLER to ml.exe or ml64.exe.
    #>
    param(
        [string]$Path,     # Semicolon-separated
        [string]$Inc,      # Semicolon-separated
        [string]$Lib,      # Semicolon-separated
        [string]$Name,
        [string]$Arch
    )

    Write-DebugMessage "Checking $Name ($Arch)" 4
    $Script:RET = 0

    # Check for compiler tools
    foreach ($tool in @('cl.exe', 'rc.exe', 'link.exe')) {
        if (-not (Test-FileInPaths $Path $tool)) {
            $Script:RET++
        }
    }

    if ($Script:RET -gt 0) {
        Write-WarningMessage "Microsoft C Compiler tools not all found - $Name ($Arch) excluded"
        return $false
    }

    # Check for Windows SDK
    $Script:RET = 0
    if (-not (Test-FileInPaths $Inc 'windows.h')) { $Script:RET++ }
    if (-not (Test-FileInPaths $Lib 'kernel32.lib')) { $Script:RET++ }

    if ($Script:RET -gt 0) {
        Write-WarningMessage "Windows SDK not all found - $Name ($Arch) excluded"
        return $false
    }

    # Check for C Runtime
    $Script:RET = 0
    if (-not (Test-FileInPaths $Inc 'stdlib.h')) { $Script:RET++ }
    if (-not (Test-FileInPaths $Lib 'msvcrt.lib')) { $Script:RET++ }
    if (-not (Test-FileInPaths $Lib 'oldnames.lib')) { $Script:RET++ }

    if ($Script:RET -gt 0) {
        Write-WarningMessage "Microsoft C runtime library not all found - $Name ($Arch) excluded"
        return $false
    }

    # Determine assembler name
    $Script:ASSEMBLER = if ($Arch -eq 'x64') { 'ml64.exe' } else { 'ml.exe' }

    # Check for assembler if required
    if ($Script:ML_REQUIRED) {
        if (-not (Test-FileInPaths $Path $Script:ASSEMBLER)) {
            Write-WarningMessage "Microsoft Assembler ($Script:ASSEMBLER) not found - $Name ($Arch)"
            return $false
        }
    }

    # Check for Manifest Tool if required
    if ($Script:MT_REQUIRED) {
        if (-not (Test-FileInPaths $Path 'mt.exe')) {
            Write-WarningMessage "Microsoft Manifest Tool not found - $Name ($Arch)"
            return $false
        }
    }

    return $true
}

function Format-Output {
    param(
        [string]$VarName,
        [string]$Value,
        [string]$Arch  # Can be 'always', 'x86', or 'x64'
    )

    # If arch matches ENV_ARCH, output empty value (no change needed)
    if ($Arch -eq $Script:ENV_ARCH) {
        $Value = ''
    }

    switch ($Script:OUTPUT_MODE) {
        0 {  # shell (PowerShell)
            $escapedValue = $Value -replace "'", "''"
            Write-Output "`$env:$VarName='$escapedValue'"
        }
        1 {  # make
            $escapedValue = $Value -replace '#', '\#' -replace '\$', '$$'
            Write-Output "$VarName=$escapedValue"
        }
        2 {  # data
            $prefix = switch ($VarName) {
                'MSVS_PATH' { 'bin' }
                'MSVS_INC'  { 'inc' }
                'MSVS_LIB'  { 'lib' }
                'MSVS_ML'   { 'asm' }
                default     { throw "Internal fault: $VarName" }
            }

            $entries = $Value -split ';' | Where-Object { $_ -ne '' }
            foreach ($entry in $entries) {
                Write-Output "$prefix*$entry"
            }
        }
    }
}

#endregion

#region Compiler Definitions

# Known compiler packages. Visual Studio .NET 2002 onwards.
$Script:COMPILERS = @{
    'VS7.0' = @{
        NAME = "Visual Studio .NET 2002"
        ENV = ""
        VERSION = "7.0"
        ARCH = @('x86')
    }
    'VS7.1' = @{
        NAME = "Visual Studio .NET 2003"
        ENV = "71"
        VERSION = "7.1"
        ARCH = @('x86')
    }
    'VS8.0' = @{
        NAME = "Visual Studio 2005"
        ENV = "80"
        VERSION = "8.0"
        EXPRESS = "VC"
        ARCH = @('x86', 'x64')
        EXPRESS_ARCH = @('x86')
    }
    'VS9.0' = @{
        NAME = "Visual Studio 2008"
        ENV = "90"
        VERSION = "9.0"
        EXPRESS = "VC"
        ARCH = @('x86', 'x64')
        EXPRESS_ARCH = @('x86')
    }
    'VS10.0' = @{
        NAME = "Visual Studio 2010"
        ENV = "100"
        VERSION = "10.0"
        EXPRESS = "VC"
        ARCH = @('x86', 'x64')
        EXPRESS_ARCH = @('x86')
    }
    'VS11.0' = @{
        NAME = "Visual Studio 2012"
        ENV = "110"
        VERSION = "11.0"
        EXPRESS = "WD"
        ARCH = @('x86', 'x64')
        EXPRESS_ARCH_SWITCHES = @{ 'x64' = 'x86_amd64' }
    }
    'VS12.0' = @{
        NAME = "Visual Studio 2013"
        ENV = "120"
        VERSION = "12.0"
        EXPRESS = "WD"
        ARCH = @('x86', 'x64')
        EXPRESS_ARCH_SWITCHES = @{ 'x64' = 'x86_amd64' }
    }
    'VS14.0' = @{
        NAME = "Visual Studio 2015"
        ENV = "140"
        VERSION = "14.0"
        ARCH = @('x86', 'x64')
    }
    'VS15.*' = @{
        NAME = "Visual Studio 2017"
        VSWHERE = $true
    }
    'VS16.*' = @{
        NAME = "Visual Studio 2019"
        VSWHERE = $true
    }
    'VS17.*' = @{
        NAME = "Visual Studio 2022"
        VSWHERE = $true
    }
    'VS18.*' = @{
        NAME = "Visual Studio 2026"
        VSWHERE = $true
    }
    'SDK5.2' = @{
        NAME = "Windows Server 2003 SP1 SDK"
        VC_VER = "8.0"
        VERSION = "5.2"
        REG_KEY = 'HKLM\SOFTWARE\Microsoft\MicrosoftSDK\InstalledSDKs\8F9E5EF3-A9A5-491B-A889-C58EFFECE8B3'
        REG_VALUE = "Install Dir"
        SETENV_RELEASE = "/RETAIL"
        ARCH = @('x64')
        ARCH_SWITCHES = @{ 'x64' = '/X64' }
    }
    'SDK' = @{
        NAME = "Generalised Windows SDK"
        SETENV_RELEASE = "/Release"
        ARCH = @('x86', 'x64')
        ARCH_SWITCHES = @{ 'x86' = '/x86'; 'x64' = '/x64' }
    }
    'SDK6.1' = @{
        NAME = "Windows Server 2008 with .NET 3.5 SDK"
        VC_VER = "9.0"
    }
    'SDK7.0' = @{
        NAME = "Windows 7 with .NET 3.5 SP1 SDK"
        VC_VER = "9.0"
    }
    'SDK7.1' = @{
        NAME = "Windows 7 with .NET 4 SDK"
        VC_VER = "10.0"
    }
}

#endregion

#region MSVS_PREFERENCE Handling

# Parse and validate MSVS_PREFERENCE
$Script:SCAN_ENV = $false
$Script:PREFERENCE_LIST = if ($MsvsPreference) {
    # Join array elements if passed as multiple parameters
    ($MsvsPreference -join ' ') -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
} elseif ($env:MSVS_PREFERENCE) {
    $env:MSVS_PREFERENCE -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
} else {
    # Default preference
    @('@', 'VS18.*', 'VS17.*', 'VS16.*', 'VS15.*', 'VS14.0', 'VS12.0', 'VS11.0', '10.0', '9.0', '8.0', '7.1', '7.0')
}

# Validate MSVS_PREFERENCE
$Script:PREFERENCE_VALIDATED = @()
$Script:SEEN = @{}
foreach ($pref in $Script:PREFERENCE_LIST) {
    if ($Script:SEEN.ContainsKey($pref)) {
        Write-Error "Corrupt MSVS_PREFERENCE: repeated '$pref'"
        exit 2
    }

    if ($pref -eq '@') {
        $Script:SCAN_ENV = $true
        $Script:PREFERENCE_VALIDATED += $pref
    }
    elseif ($Script:COMPILERS.ContainsKey($pref)) {
        $Script:PREFERENCE_VALIDATED += $pref
    }
    elseif ($Script:COMPILERS.ContainsKey("VS$pref")) {
        $Script:PREFERENCE_VALIDATED += "VS$pref"
    }
    elseif ($pref -match '.*\.\*$' -and $Script:COMPILERS.ContainsKey($pref)) {
        $Script:PREFERENCE_VALIDATED += $pref
    }
    elseif ($pref -match '^\d+\.\d+$') {
        # Version number - will match against SDKs or VS versions
        $Script:PREFERENCE_VALIDATED += $pref
    }
    else {
        Write-Error "Corrupt MSVS_PREFERENCE: unknown compiler '$pref'"
        exit 2
    }

    $Script:SEEN[$pref] = $true
}

# Options sanitizing
if ($Script:MODE -eq 1 -or $Script:MODE -eq 2) {  # --all or --installed
    if ($Script:TARGET_ARCH) {
        Write-Error "--all/--installed and --arch are mutually exclusive"
        exit 2
    }
    $Script:SCAN_ENV = $true
}
elseif ($Script:OUTPUT_MODE -eq 2 -and -not $Script:TARGET_ARCH) {
    Write-Error "--output=data requires --arch"
    exit 2
}

#endregion

#region Environment Compiler Detection

$Script:ENV_ARCH = $null
$Script:ENV_CL = $null
$Script:ENV_cl = $null

if ($Script:SCAN_ENV -or $Script:MODE -gt 0) {
    # Check if cl.exe is in PATH
    $clPath = Get-Command cl.exe -ErrorAction SilentlyContinue

    if ($clPath) {
        # Determine architecture from cl.exe banner
        $clOutput = & cl.exe 2>&1 | Select-Object -First 1
        $archMatch = $clOutput -match 'for (x64|AMD64|80x86|x86)'

        if ($archMatch) {
            $Script:ENV_ARCH = switch -Regex ($Matches[1]) {
                'x64|AMD64' { 'x64' }
                '80x86|x86' { 'x86' }
            }

            Write-DebugMessage "Environment compiler detected: $Script:ENV_ARCH" 1

            # Check INCLUDE and LIB environment variables
            $envInc = [Environment]::GetEnvironmentVariable('INCLUDE')
            $envLib = [Environment]::GetEnvironmentVariable('LIB')

            if (-not $envInc -or -not $envLib) {
                # Try alternate case
                if (-not $envInc) { $envInc = [Environment]::GetEnvironmentVariable('Include') }
                if (-not $envLib) { $envLib = [Environment]::GetEnvironmentVariable('Lib') }
            }

            if ($envInc -and $envLib) {
                # Validate environment compiler
                if (Test-Environment $env:PATH $envInc $envLib "Environment C compiler" $Script:ENV_ARCH) {
                    $Script:ENV_CL = $clPath.Source
                    $Script:ENV_cl = $Script:ENV_CL.ToLower() -replace 'bin\\[^\\]+_', 'bin\'
                    Write-DebugMessage "Environment appears to include a compiler at $Script:ENV_CL" 1

                    if ($Script:TARGET_ARCH -and $Script:TARGET_ARCH -ne $Script:ENV_ARCH) {
                        Write-DebugMessage "But architecture doesn't match required value" 1
                    }
                }
                else {
                    $Script:ENV_ARCH = $null
                }
            }
            else {
                Write-WarningMessage "Microsoft C Compiler Include and/or Lib not set - Environment C compiler ($Script:ENV_ARCH) excluded"
                $Script:ENV_ARCH = $null
            }
        }
        else {
            Write-Host "Unable to identify C compiler architecture from '$clOutput'" -ForegroundColor Yellow
            Write-Host "Environment C compiler discarded" -ForegroundColor Yellow
        }
    }
}

#endregion

#region Registry Scanning

$Script:FOUND = @{}

# Determine registry paths for WOW64 handling
if ([Environment]::Is64BitOperatingSystem) {
    Write-DebugMessage "WOW64 detected" 1
    $Script:MS_ROOT = 'HKLM:\SOFTWARE\Microsoft'
}
else {
    $Script:MS_ROOT = 'HKLM:\SOFTWARE\Wow6432Node\Microsoft'
}

# Scan for Visual Studio 2005-2015 (via environment variables)
foreach ($key in $Script:COMPILERS.Keys) {
    $compiler = $Script:COMPILERS[$key]

    # Skip SDK and vswhere-based entries for now
    if (-not $compiler.ENV -or $compiler.VSWHERE) {
        continue
    }

    $envVar = "VS$($compiler.ENV)COMNTOOLS"
    $envValue = [Environment]::GetEnvironmentVariable($envVar)

    if ($envValue) {
        Write-DebugMessage "$envVar is a candidate" 1

        $testPath = $envValue.TrimEnd('"').TrimStart('"')
        $vsvars32 = Join-Path $testPath 'vsvars32.bat'

        if (Test-Path $vsvars32) {
            Write-DebugMessage "Directory pointed to by $envVar contains vsvars32.bat" 1

            $isExpress = $false
            $regPath = "$Script:MS_ROOT\VisualStudio\$($compiler.VERSION)"
            $installDir = Get-RegistryString $regPath "InstallDir"

            if (-not $installDir -and $compiler.EXPRESS) {
                $expressKey = "$Script:MS_ROOT\$($compiler.EXPRESS)Express\$($compiler.VERSION)"
                $installDir = Get-RegistryString $expressKey "InstallDir"

                if ($installDir) {
                    $isExpress = $true
                }
                elseif ($compiler.VERSION -eq '8.0') {
                    # VS 2005 Express special case
                    $installDir = $testPath
                    $isExpress = $true
                }
            }

            if ($installDir) {
                # Determine script path
                $envValue = $envValue.TrimEnd('"').TrimStart('"')
                if ([int]$compiler.ENV -ge 80) {
                    $script = Join-Path (Split-Path (Split-Path $envValue)) "VC\vcvarsall.bat"
                }
                else {
                    $script = Join-Path $envValue "vsvars32.bat"
                }

                $display = $compiler.NAME
                if ($isExpress) {
                    $display += " Express"
                }

                $foundEntry = $compiler.Clone()
                $foundEntry.DISPLAY = $display
                $foundEntry.IS_EXPRESS = $isExpress
                $foundEntry.SETENV = $script

                $Script:FOUND[$key] = $foundEntry
                Write-DebugMessage "$($compiler.NAME) accepted for further detection" 1
            }
            else {
                Write-WarningMessage "vsvars32.bat found, but registry settings not found"
            }
        }
        else {
            Write-WarningMessage "$envVar set, but vsvars32.bat not found"
        }
    }
}

# Scan for Windows SDKs (6.0+)
$sdkRoot = 'HKLM:\SOFTWARE\Microsoft\Microsoft SDKs\Windows'
if (Test-Path $sdkRoot) {
    $sdkKeys = Get-ChildItem $sdkRoot -ErrorAction SilentlyContinue |
               Where-Object { $_.PSChildName -match '^v[\d.]+$' }

    foreach ($sdkKey in $sdkKeys) {
        $version = $sdkKey.PSChildName
        Write-DebugMessage "Analysing SDK key $version" 1

        $installDir = (Get-ItemProperty -Path $sdkKey.PSPath -Name 'InstallationFolder' -ErrorAction SilentlyContinue).InstallationFolder
        $productVersion = (Get-ItemProperty -Path $sdkKey.PSPath -Name 'ProductVersion' -ErrorAction SilentlyContinue).ProductVersion

        if ($installDir) {
            $setenvCmd = Join-Path $installDir 'Bin\SetEnv.cmd'

            if (Test-Path $setenvCmd) {
                $sdkVer = $version -replace '^v', ''
                $sdkKey = "SDK$sdkVer"

                $display = if ($Script:COMPILERS.ContainsKey($sdkKey)) {
                    $Script:COMPILERS[$sdkKey].NAME
                }
                else {
                    Write-WarningMessage "SDK $version is not known to this script - assuming compatibility"
                    "Windows SDK $version"
                }

                $foundEntry = $Script:COMPILERS['SDK'].Clone()
                $foundEntry.DISPLAY = $display
                $foundEntry.VERSION = $productVersion
                $foundEntry.SETENV = $setenvCmd

                $Script:FOUND["SDK$sdkVer"] = $foundEntry
            }
            else {
                if ($Script:COMPILERS.ContainsKey("SDK$sdkVer")) {
                    Write-WarningMessage "Registry set for Windows SDK $version, but SetEnv.cmd not found"
                }
            }
        }
        else {
            Write-WarningMessage "Registry key for Windows SDK $version doesn't contain expected InstallationFolder value"
        }
    }
}

# Scan for explicit SDK 5.2
if ($Script:COMPILERS.ContainsKey('SDK5.2')) {
    $sdk52 = $Script:COMPILERS['SDK5.2']
    $installDir = Get-RegistryString $sdk52.REG_KEY $sdk52.REG_VALUE -Force64bit

    if ($installDir) {
        $setenvCmd = Join-Path $installDir 'SetEnv.cmd'
        if (Test-Path $setenvCmd) {
            $foundEntry = $sdk52.Clone()
            $foundEntry.DISPLAY = $sdk52.NAME
            $foundEntry.SETENV = $setenvCmd

            $Script:FOUND['SDK5.2'] = $foundEntry
            Write-DebugMessage "$($sdk52.NAME) accepted for further detection" 1
        }
        else {
            Write-WarningMessage "Registry set for Windows Server 2003 SDK, but SetEnv.cmd not found"
        }
    }
}

#endregion

#region vswhere Enumeration for VS 2017+

# Look for vswhere.exe
$vswhereExe = Join-Path $PSScriptRoot 'vswhere.exe'
if (-not (Test-Path $vswhereExe)) {
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $vswhereExe = Join-Path $programFilesX86 'Microsoft Visual Studio\Installer\vswhere.exe'
}

if (Test-Path $vswhereExe) {
    Write-DebugMessage "$vswhereExe found" 1

    $vswhereOutput = & $vswhereExe -all -prerelease -products '*' -nologo 2>$null

    $instance = @{}
    foreach ($line in $vswhereOutput) {
        if ($line -match '^(\w+): (.*)$') {
            $key = $Matches[1]
            $value = $Matches[2]

            $instance[$key] = $value

            if ($key -eq 'displayName') {
                # Process this instance
                $instanceVer = $instance['installationVersion']
                $majorVer = ($instanceVer -split '\.')[0]
                $fullVer = ($instanceVer -split '\.')[0..1] -join '.'

                Write-DebugMessage "Looking at $($instance['instanceId']) in $($instance['installationPath']) ($instanceVer $value)" 1

                $vcvarsall = Join-Path $instance['installationPath'] 'VC\Auxiliary\Build\vcvarsall.bat'
                if (Test-Path $vcvarsall) {
                    Write-DebugMessage "vcvarsall.bat found" 1

                    if ($Script:MODE -eq 2) {
                        $key = "VS$fullVer-$($instance['instanceId'])"
                    }
                    else {
                        $key = "VS$fullVer"
                    }

                    $foundEntry = @{
                        DISPLAY = $value
                        VERSION = $instanceVer
                        ARCH = @('x86', 'x64')
                        SETENV = $vcvarsall
                        SETENV_RELEASE = ''
                    }

                    $Script:FOUND[$key] = $foundEntry
                }
                else {
                    Write-WarningMessage "vcvarsall.bat not found for $($instance['instanceId'])"
                }

                $instance = @{}
            }
        }
    }
}

#endregion

#region Display Installed/All Compilers

if ($Script:DebugLevelValue -gt 1 -or $Script:MODE -eq 2) {
    $sortedKeys = $Script:FOUND.Keys | Sort-Object
    foreach ($key in $sortedKeys) {
        if ($Script:MODE -eq 2) {
            $comp = $Script:FOUND[$key]
            Write-Host "  $key ($($comp.VERSION); $($comp.SETENV))"
        }
        else {
            Write-Host "Inspect $key" -ForegroundColor Gray
        }
    }
}

if ($Script:MODE -eq 2) {
    exit 0
}

#endregion

#region Batch Script Execution and Compiler Validation

function Invoke-CompilerSetup {
    <#
    .SYNOPSIS
    Executes a compiler setup script and extracts PATH, INCLUDE, LIB values
    #>
    param(
        [string]$Script,
        [string]$ArchSwitch,
        [string]$Arch
    )

    Write-DebugMessage "Scanning $(Split-Path -Leaf $Script) $ArchSwitch..." 4

    # Build the command to extract environment variables
    $command = '%EXEC_SCRIPT% && echo XMARKER && echo !PATH! && echo !LIB! && echo !INCLUDE! && echo !VCToolsVersion! && echo !VSCMD_VER! && echo !VisualStudioVersion!'

    # Prepare environment - unset variables that might interfere
    $envVars = @{}
    foreach ($var in @('ORIGINAL_PATH', 'ORIGINALPATH', 'TARGET_CPU', 'TARGET_PLATFORM',
                       'DevEnvDir', 'VSINSTALLDIR', 'VCToolsVersion', 'Framework35Version',
                       '__VSCMD_PREINIT_VCToolsVersion', 'INCLUDE', 'LIB')) {
        $envVars[$var] = [Environment]::GetEnvironmentVariable($var)
        [Environment]::SetEnvironmentVariable($var, $null)
    }

    # Save original PATH
    $originalPath = $env:PATH

    try {
        $scriptDir = Split-Path $Script
        $scriptName = Split-Path $Script -Leaf
        $execScript = "$scriptName $ArchSwitch"

        # Set PATH with marker to identify prepended paths
        # Use a fake path as marker that won't exist
        $env:PATH = "X:\MSVS-DETECT-MARKER;$scriptDir;$originalPath"

        # Set MSYS2_ARG_CONV_EXCL to prevent MSYS2 path mangling
        $env:MSYS2_ARG_CONV_EXCL = '*'
        $env:EXEC_SCRIPT = $execScript

        # Execute cmd.exe with the setup script
        $output = & cmd.exe /d /v:on /c "$command" 2>&1 |
                  Out-String -Stream |
                  Select-String -Pattern 'XMARKER' -Context 0,6

        if ($output) {
            $lines = $output.Context.PostContext
            if ($lines.Count -ge 6) {
                $fullPath = $lines[0].Trim()
                $fullLib = $lines[1].Trim()
                $fullInclude = $lines[2].Trim()

                # Extract only the prepended PATH (before the marker)
                # Split on the marker and take only the first part
                if ($fullPath -match '^(.+?);?X:\\MSVS-DETECT-MARKER') {
                    $msvsPath = $Matches[1]
                }
                elseif ($fullPath.Contains('X:\MSVS-DETECT-MARKER')) {
                    # Fallback: split and take first part
                    $pathParts = $fullPath -split 'X:\\MSVS-DETECT-MARKER'
                    $msvsPath = $pathParts[0].TrimEnd(';')
                }
                else {
                    # No marker found - this shouldn't happen but handle it
                    Write-DebugMessage "Warning: PATH marker not found in output" 2
                    $msvsPath = $fullPath
                }

                # Normalize paths - remove double backslashes
                $msvsPath = $msvsPath -replace '\\\\', '\'
                $fullLib = $fullLib -replace '\\\\', '\'
                $fullInclude = $fullInclude -replace '\\\\', '\'

                # Ensure trailing semicolon
                if ($msvsPath -and -not $msvsPath.EndsWith(';')) {
                    $msvsPath += ';'
                }
                if ($fullLib -and -not $fullLib.EndsWith(';')) {
                    $fullLib += ';'
                }
                if ($fullInclude -and -not $fullInclude.EndsWith(';')) {
                    $fullInclude += ';'
                }

                $result = @{
                    PATH = $msvsPath
                    LIB = $fullLib
                    INCLUDE = $fullInclude
                    VCToolsVersion = $lines[3].Trim()
                    VSCMD_VER = $lines[4].Trim()
                    VisualStudioVersion = $lines[5].Trim()
                }

                # Clean up unexpanded variables
                if ($result.VCToolsVersion -eq '!VCToolsVersion!' -and $result.VisualStudioVersion -ne '!VisualStudioVersion!') {
                    $result.VCToolsVersion = $result.VisualStudioVersion
                }
                if ($result.VCToolsVersion -eq '!VCToolsVersion!' -and $result.VCToolsVersion -eq '!VisualStudioVersion!') {
                    $result.VCToolsVersion = ''
                }
                if ($result.VSCMD_VER -eq '!VSCMD_VER!') {
                    $result.VSCMD_VER = ''
                }

                Write-DebugMessage "done" 4
                return $result
            }
        }
    }
    finally {
        # Restore PATH
        $env:PATH = $originalPath

        # Restore environment variables
        foreach ($var in $envVars.Keys) {
            if ($null -ne $envVars[$var]) {
                [Environment]::SetEnvironmentVariable($var, $envVars[$var])
            }
        }
        [Environment]::SetEnvironmentVariable('MSYS2_ARG_CONV_EXCL', $null)
        [Environment]::SetEnvironmentVariable('EXEC_SCRIPT', $null)
    }

    Write-DebugMessage "failed" 4
    return $null
}

# Now test each compiler package
$Script:ENV_COMPILER = $null
$Script:WEAK_ENV = $null
$Script:VALIDATED = @{}

foreach ($key in $Script:FOUND.Keys) {
    $compiler = $Script:FOUND[$key]

    # Get architecture switches
    $archInfo = @{}
    if ($compiler.IS_EXPRESS -and $compiler.EXPRESS_ARCH_SWITCHES) {
        $archInfo = $compiler.EXPRESS_ARCH_SWITCHES
    }
    elseif ($compiler.ARCH_SWITCHES) {
        $archInfo = $compiler.ARCH_SWITCHES
    }

    # Determine architectures to test
    $archs = if ($compiler.IS_EXPRESS -and $compiler.EXPRESS_ARCH) {
        $compiler.EXPRESS_ARCH
    }
    else {
        $compiler.ARCH
    }

    foreach ($arch in $archs) {
        # Determine architecture switch
        $archSwitch = if ($archInfo.ContainsKey($arch)) {
            $archInfo[$arch]
        }
        else {
            $arch
        }

        # Add any release switches
        if ($compiler.SETENV_RELEASE) {
            $archSwitch += " $($compiler.SETENV_RELEASE)"
        }

        # Execute the setup script
        $result = Invoke-CompilerSetup $compiler.SETENV $archSwitch $arch

        if ($result -and $result.PATH) {
            # Validate the environment
            if (Test-Environment $result.PATH $result.INCLUDE $result.LIB $key $arch) {
                # Store validated compiler
                $validatedKey = "$key-$arch"
                $validatedEntry = $compiler.Clone()
                $validatedEntry.MSVS_PATH = $result.PATH
                $validatedEntry.MSVS_INC = $result.INCLUDE
                $validatedEntry.MSVS_LIB = $result.LIB
                $validatedEntry.SETENV_SWITCHES = $archSwitch
                $validatedEntry.VC_VERSION = $result.VCToolsVersion
                $validatedEntry.VSCMD_VER = $result.VSCMD_VER
                $validatedEntry.ASSEMBLER = $Script:ASSEMBLER
                $validatedEntry.ARCH_NAME = $arch

                $Script:VALIDATED[$validatedKey] = $validatedEntry

                # Check if this matches the environment compiler
                if ($Script:ENV_ARCH) {
                    $testCl = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
                    if ($testCl) {
                        $testCl = $testCl.ToLower() -replace 'bin\\[^\\]+_', 'bin\'

                        if ($testCl -eq $Script:ENV_cl) {
                            # Check if INCLUDE and LIB match
                            $envInc = [Environment]::GetEnvironmentVariable('INCLUDE')
                            $envLib = [Environment]::GetEnvironmentVariable('LIB')

                            if (-not $envInc) { $envInc = [Environment]::GetEnvironmentVariable('Include') }
                            if (-not $envLib) { $envLib = [Environment]::GetEnvironmentVariable('Lib') }

                            $envInc = $envInc.TrimEnd(';') + ';'
                            $envLib = $envLib.TrimEnd(';') + ';'

                            if ($envInc.Contains($result.INCLUDE) -and $envLib.Contains($result.LIB)) {
                                Write-DebugMessage "$validatedKey is a strong candidate for the Environment C compiler" 1
                                if ($null -eq $Script:ENV_COMPILER) {
                                    $Script:ENV_COMPILER = $validatedKey
                                }
                                elseif ($Script:ENV_COMPILER -ne '') {
                                    # Multiple strong candidates - ambiguous
                                    $Script:ENV_COMPILER = ''
                                }
                            }
                            else {
                                Write-DebugMessage "$validatedKey is a weak candidate for the Environment C compiler" 1
                                if ($null -eq $Script:WEAK_ENV) {
                                    $Script:WEAK_ENV = $validatedKey
                                }
                                elseif ($Script:WEAK_ENV -ne '') {
                                    # Multiple weak candidates - ambiguous
                                    $Script:WEAK_ENV = ''
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

# Adopt weak match if that's the best we can do
if ($null -eq $Script:ENV_COMPILER -and $Script:WEAK_ENV) {
    Write-WarningMessage "Assuming Environment C compiler is $Script:WEAK_ENV"
    $Script:ENV_COMPILER = $Script:WEAK_ENV
}

#endregion

#region Compiler Selection

$Script:SOLUTION = $null

if ($Script:MODE -eq 1) {
    # --all mode: display all validated compilers
    Write-Host "Installed and usable packages:"
    $Script:VALIDATED.Keys | Sort-Object | ForEach-Object {
        $comp = $Script:VALIDATED[$_]
        $parts = $_ -split '-'
        $switches = $comp.SETENV_SWITCHES
        if ($switches -match ' ') {
            $switches = "`"$switches`""
        }
        Write-Host "- $($parts[0]) $($parts[1]) `"$($comp.SETENV)`" $switches"
    }

    if ($Script:ENV_COMPILER) {
        Write-Host ""
        Write-Host "Identified Environment C compiler as $Script:ENV_COMPILER"
    }

    exit 0
}

# Normal mode: find best match based on MSVS_PREFERENCE
# Build preference list with actual matches
$Script:TEST_ORDER = @()
$Script:PREFERENCE_FINAL = @()

foreach ($pref in $Script:PREFERENCE_VALIDATED) {
    if ($pref -eq '@') {
        if ($Script:ENV_COMPILER) {
            $Script:PREFERENCE_FINAL += '@'
        }
    }
    elseif ($pref -match '^\d+\.\d+$') {
        # Version number - match VS or SDK
        $matched = @()

        # First try VS
        if ($Script:VALIDATED.ContainsKey("VS$pref-$Script:LEFT_ARCH") -and
            $Script:VALIDATED.ContainsKey("VS$pref-$Script:RIGHT_ARCH")) {
            $matched += "VS$pref"
        }

        # Then try SDKs with this compiler version
        foreach ($sdkKey in $Script:COMPILERS.Keys) {
            if ($Script:COMPILERS[$sdkKey].VC_VER -eq $pref) {
                if ($Script:VALIDATED.ContainsKey("$sdkKey-$Script:LEFT_ARCH") -and
                    $Script:VALIDATED.ContainsKey("$sdkKey-$Script:RIGHT_ARCH")) {
                    $matched += $sdkKey
                }
            }
        }

        $Script:TEST_ORDER += $matched
        $Script:PREFERENCE_FINAL += $matched
    }
    elseif ($pref -match '\.\*$') {
        # Wildcard version - find all matches
        $prefix = $pref -replace '\.\*$', ''
        $matched = $Script:VALIDATED.Keys |
                   Where-Object { $_ -match "^$prefix\." } |
                   ForEach-Object { ($_ -split '-')[0] } |
                   Select-Object -Unique |
                   Sort-Object -Descending

        $Script:TEST_ORDER += $matched
        $Script:PREFERENCE_FINAL += $matched
    }
    else {
        # Exact match
        if ($Script:VALIDATED.ContainsKey("$pref-$Script:LEFT_ARCH") -and
            $Script:VALIDATED.ContainsKey("$pref-$Script:RIGHT_ARCH")) {
            $Script:TEST_ORDER += $pref
            $Script:PREFERENCE_FINAL += $pref
        }
    }
}

# Check for @ preference and environment compiler match
if ('@' -in $Script:PREFERENCE_FINAL -and $Script:ENV_COMPILER) {
    $envBase = $Script:ENV_COMPILER -replace '-[^-]+$', ''
    $Script:SOLUTION = $envBase
}

# If no solution yet, find first matching preference
if (-not $Script:SOLUTION) {
    foreach ($pref in $Script:PREFERENCE_FINAL) {
        if ($pref -ne '@') {
            if ($Script:VALIDATED.ContainsKey("$pref-$Script:LEFT_ARCH") -and
                $Script:VALIDATED.ContainsKey("$pref-$Script:RIGHT_ARCH")) {
                $Script:SOLUTION = $pref
                break
            }
        }
    }
}

Write-DebugMessage "Solution: $Script:SOLUTION" 1

#endregion

#region Output Generation

if ($Script:SOLUTION) {
    $leftComp = $Script:VALIDATED["$Script:SOLUTION-$Script:LEFT_ARCH"]

    if ($Script:OUTPUT_MODE -ne 2) {
        Format-Output 'MSVS_NAME' $leftComp.DISPLAY 'always'
        Format-Output 'MSVS_PATH' $leftComp.MSVS_PATH $Script:LEFT_ARCH
    }
    else {
        Write-Output "$($leftComp.DISPLAY) ($($leftComp.VERSION))"
        $cmd = $leftComp.SETENV
        if ($cmd -match ' ') {
            $cmd = "`"$cmd`""
        }
        Write-Output "cmd*$cmd $($leftComp.SETENV_SWITCHES)"
        Format-Output 'MSVS_PATH' $leftComp.MSVS_PATH $Script:LEFT_ARCH
    }

    Format-Output 'MSVS_INC' $leftComp.MSVS_INC $Script:LEFT_ARCH
    Format-Output 'MSVS_LIB' $leftComp.MSVS_LIB $Script:LEFT_ARCH

    if ($Script:ML_REQUIRED) {
        $asmName = $leftComp.ASSEMBLER -replace '\.exe$', ''
        Format-Output 'MSVS_ML' $asmName 'always'
    }

    if (-not $Script:TARGET_ARCH) {
        $rightComp = $Script:VALIDATED["$Script:SOLUTION-$Script:RIGHT_ARCH"]
        Format-Output 'MSVS64_PATH' $rightComp.MSVS_PATH $Script:RIGHT_ARCH
        Format-Output 'MSVS64_INC' $rightComp.MSVS_INC $Script:RIGHT_ARCH
        Format-Output 'MSVS64_LIB' $rightComp.MSVS_LIB $Script:RIGHT_ARCH

        if ($Script:ML_REQUIRED) {
            $asmName = $rightComp.ASSEMBLER -replace '\.exe$', ''
            Format-Output 'MSVS64_ML' $asmName 'always'
        }
    }

    exit 0
}
else {
    # No compiler found
    exit 1
}

#endregion
