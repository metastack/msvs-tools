<#
################################################################################################
David Allsopp Ltd.
################################################################################################
Microsoft C Compiler Environment Detection Script - opam Integration
################################################################################################
Copyright (c) 2021, 2022, 2023, 2024 David Allsopp Ltd.
Copyright (c) 2025 David Allsopp Ltd. (PowerShell conversion)
################################################################################################
Author: David Allsopp
24-Sep-2021 (bash version)
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

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('x86_32', 'x86_64')]
    [string]$Arch,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$PackageName,

    [Parameter(Mandatory=$true, Position=2)]
    [string]$MsvsDetectPath
)

$ErrorActionPreference = 'Stop'

function Get-MD5Hash {
    param([string]$FilePath)

    if (Test-Path $FilePath) {
        $md5 = [System.Security.Cryptography.MD5]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hash = $md5.ComputeHash($stream)
            return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
        }
        finally {
            $stream.Close()
        }
    }
    return ''
}

function Get-StringMD5 {
    param([string]$Text)

    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $md5.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

function Escape-OpamString {
    param([string]$Value)

    # Escape backslashes, percent signs, and quotes for opam format
    $result = $Value -replace '\\', '\\\\'
    $result = $result -replace '%', '%%'
    $result = $result -replace '"', '\"'
    return $result
}

function Generate-OpamFiles {
    param(
        [string]$Package,
        [string]$CacheFile
    )

    # Read cache file
    if (-not (Test-Path $CacheFile)) {
        Write-Error "Cache file not found: $CacheFile"
        return $false
    }

    $cacheLines = Get-Content $CacheFile

    # Initialize data structures
    $entries = @{
        'bin' = ''
        'inc' = ''
        'lib' = ''
    }
    $checksums = @{}

    $line = 0
    $packageName = ''
    $scriptPath = ''
    $mlName = ''

    foreach ($entry in $cacheLines) {
        if ($line -eq 0) {
            # First line is package name
            $packageName = Escape-OpamString $entry
        }
        elseif ($line -eq 1) {
            # Second line is script path (strip cmd* prefix if present)
            if ($entry -match '^cmd\*(.+)$') {
                $scriptPath = Escape-OpamString $Matches[1]
            }
            else {
                $scriptPath = Escape-OpamString $entry
            }
        }
        else {
            # Parse tagged entries (bin*, inc*, lib*, asm*)
            if ($entry -match '^([^*]+)\*(.+)$') {
                $tag = $Matches[1]
                $value = $Matches[2]
                $escapedValue = Escape-OpamString $value

                if ($tag -eq 'asm') {
                    $mlName = $escapedValue
                }
                else {
                    # Collect checksums for file-depends
                    switch ($tag) {
                        'bin' {
                            if (-not $checksums.ContainsKey('cl')) {
                                $clPath = Join-Path $value 'cl.exe'
                                if (Test-Path $clPath) {
                                    $checksums['cl'] = $clPath
                                }
                            }
                        }
                        'inc' {
                            if (-not $checksums.ContainsKey('crtversion')) {
                                $crtPath = Join-Path $value 'crtversion.h'
                                if (Test-Path $crtPath) {
                                    $checksums['crtversion'] = $crtPath
                                }
                            }
                            if (-not $checksums.ContainsKey('stdlib')) {
                                $stdlibPath = Join-Path $value 'stdlib.h'
                                if (Test-Path $stdlibPath) {
                                    $checksums['stdlib'] = $stdlibPath
                                }
                            }
                            if (-not $checksums.ContainsKey('windows')) {
                                $windowsPath = Join-Path $value 'windows.h'
                                if (Test-Path $windowsPath) {
                                    $checksums['windows'] = $windowsPath
                                }
                            }
                        }
                        'lib' {
                            if (-not $checksums.ContainsKey('msvcrt')) {
                                $msvcrtPath = Join-Path $value 'msvcrt.lib'
                                if (Test-Path $msvcrtPath) {
                                    $checksums['msvcrt'] = $msvcrtPath
                                }
                            }
                        }
                    }

                    # Build semicolon-separated list
                    $semicolonValue = $escapedValue -replace ';', '";\"'
                    if ($entries[$tag]) {
                        $entries[$tag] += ";$semicolonValue"
                    }
                    else {
                        $entries[$tag] = $semicolonValue
                    }
                }
            }
        }
        $line++
    }

    # If no cl.exe in msvs-bin, we're using an environment compiler
    if (-not $checksums.ContainsKey('cl')) {
        $envCl = Get-Command cl.exe -ErrorAction SilentlyContinue
        if (-not $envCl) {
            Write-Error 'The environment and msvs-detect appear to disagree?!'
            return $false
        }

        $checksums['cl'] = $envCl.Source

        # Query INCLUDE for header files
        $includeVar = [Environment]::GetEnvironmentVariable('INCLUDE')
        if (-not $includeVar) {
            $includeVar = [Environment]::GetEnvironmentVariable('Include')
        }

        if ($includeVar) {
            $includeDirs = $includeVar -split ';'
            foreach ($dir in $includeDirs) {
                if (-not $checksums.ContainsKey('crtversion')) {
                    $crtPath = Join-Path $dir 'crtversion.h'
                    if (Test-Path $crtPath) {
                        $checksums['crtversion'] = $crtPath
                    }
                }
                if (-not $checksums.ContainsKey('stdlib')) {
                    $stdlibPath = Join-Path $dir 'stdlib.h'
                    if (Test-Path $stdlibPath) {
                        $checksums['stdlib'] = $stdlibPath
                    }
                }
                if (-not $checksums.ContainsKey('windows')) {
                    $windowsPath = Join-Path $dir 'windows.h'
                    if (Test-Path $windowsPath) {
                        $checksums['windows'] = $windowsPath
                    }
                }
            }
        }

        # Query LIB for msvcrt.lib
        if (-not $checksums.ContainsKey('msvcrt')) {
            $libVar = [Environment]::GetEnvironmentVariable('LIB')
            if (-not $libVar) {
                $libVar = [Environment]::GetEnvironmentVariable('Lib')
            }

            if ($libVar) {
                $libDirs = $libVar -split ';'
                foreach ($dir in $libDirs) {
                    $msvcrtPath = Join-Path $dir 'msvcrt.lib'
                    if (Test-Path $msvcrtPath) {
                        $checksums['msvcrt'] = $msvcrtPath
                        break
                    }
                }
            }
        }
    }
    elseif ($checksums.ContainsKey('cl')) {
        # cl comes via msvs-bin, don't bind to file-depends
        $checksums.Remove('cl')
    }

    # If crtversion.h found, don't bind to stdlib.h
    if ($checksums.ContainsKey('crtversion')) {
        $checksums.Remove('stdlib')
    }

    # Generate .config file
    $configPath = "$Package.config"
    $config = @()
    $config += 'opam-version: "2.0"'
    $config += 'variables {'
    $config += "  package: `"$packageName`""
    $config += "  script: `"$scriptPath`""

    if ($mlName) {
        $config += "  ml: `"$mlName`""
    }

    foreach ($var in @('bin', 'inc', 'lib')) {
        $value = $entries[$var]
        $config += "  msvs-${var}: `"$value`""
    }

    $config += '}'

    # Add file-depends section
    if ($checksums.Count -gt 0) {
        $config += 'file-depends: ['

        foreach ($key in $checksums.Keys) {
            $file = $checksums[$key]
            $escaped = Escape-OpamString $file
            $hash = Get-MD5Hash $file
            if ($hash) {
                $config += "  [`"$escaped`" `"md5=$hash`"]"
            }
        }

        $config += ']'
    }

    # Write .config file
    $config | Out-File -FilePath $configPath -Encoding utf8

    # Generate .install file
    $installPath = "$Package.install"
    $install = @()
    $install += 'share: ['
    $install += "  `"$($CacheFile -replace '\\', '\\\\')`""
    $install += "  `"$($configPath -replace '\\', '\\\\')`""
    $install += ']'

    $install | Out-File -FilePath $installPath -Encoding utf8

    return $true
}

# Validate architecture
if ($Arch -notin @('x86_32', 'x86_64')) {
    Write-Error "Unsupported or unrecognised architecture: $Arch"
    exit 2
}

# Build cache key
$keyComponents = @()
$keyComponents += "$Arch-$env:MSVS_PREFERENCE"

# Add cl.exe location if in PATH
$clCmd = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($clCmd) {
    $keyComponents += $clCmd.Source
}

# Add msvs-detect content
if (Test-Path $MsvsDetectPath) {
    $keyComponents += (Get-Content $MsvsDetectPath -Raw)
}

# Add this script's content
$keyComponents += (Get-Content $PSCommandPath -Raw)

# Add --installed output (sorted)
try {
    $installed = & pwsh -NoProfile -Command "& '$MsvsDetectPath' -Installed" 2>&1 | Sort-Object
    $keyComponents += ($installed -join "`n")
}
catch {
    # If PowerShell version fails, try with the script directly
    $installed = & $MsvsDetectPath -Installed 2>&1 | Sort-Object
    $keyComponents += ($installed -join "`n")
}

# Calculate cache key
$key = Get-StringMD5 ($keyComponents -join "`n")

# Search for cached result
$cachedResult = ''
if (-not $env:OPAMVAR_msvs_detect_nocache) {
    # Try to find opam command
    $opamCmd = Get-Command opam -ErrorAction SilentlyContinue

    if ($opamCmd) {
        # Search global and local switches
        $switches = & opam switch list --short 2>$null
        foreach ($switch in $switches) {
            $switch = $switch.Trim()

            # Try local switch
            $localCache = Join-Path $switch "_opam\share\$PackageName\$key.cache"
            if (Test-Path $localCache) {
                $cachedResult = $localCache
                break
            }

            # Try global switch
            if ($env:OPAMROOT) {
                $globalCache = Join-Path $env:OPAMROOT "$switch\share\$PackageName\$key.cache"
                if (Test-Path $globalCache) {
                    $cachedResult = $globalCache
                    break
                }
            }
        }
    }
    elseif ($env:OPAMROOT) {
        # opam not available, search global switches
        $switches = Get-ChildItem $env:OPAMROOT -Directory
        foreach ($switch in $switches) {
            $cacheFile = Join-Path $switch.FullName "share\$PackageName\$key.cache"
            if (Test-Path $cacheFile) {
                $cachedResult = $cacheFile
                break
            }
        }
    }
}

$runMsvsDetect = $true

if ($cachedResult) {
    # Copy cached result
    Copy-Item $cachedResult "$key.cache"

    # Try to generate from cache
    if (Generate-OpamFiles $PackageName "$key.cache") {
        $runMsvsDetect = $false
    }
    else {
        Write-Host 'The cached result failed - re-running with msvs-detect' -ForegroundColor Yellow
        $runMsvsDetect = $true
    }
}

if ($runMsvsDetect) {
    # Run msvs-detect
    try {
        & $MsvsDetectPath -Arch $Arch -WithAssembler -WithMt -Output data | Out-File -FilePath "$key.cache" -Encoding utf8

        if ($LASTEXITCODE -ne 0) {
            throw "msvs-detect failed with exit code $LASTEXITCODE"
        }

        if (-not (Generate-OpamFiles $PackageName "$key.cache")) {
            exit 1
        }
    }
    catch {
        Write-Host 'No compatible Visual Studio installation was found!' -ForegroundColor Red
        Write-Host 'Please install Visual Studio with at least the x64/x86 build tools' -ForegroundColor Red
        Write-Host 'and Windows SDK packages. See https://visualstudio.microsoft.com/downloads/' -ForegroundColor Red
        exit 1
    }
}
