# Ultimate Macro: first-run launcher only. No game automation runs here.
# No automatic downloads or installations without the user's explicit Yes.
param([switch]$InstallAutoHotkey, [switch]$NoPrompt, [switch]$PreflightOnly,
      [switch]$RepairOnly, [switch]$VerifyOnly, [switch]$NoNetwork,
      [switch]$NoHide, [switch]$WindowsStartupLaunch)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$main = Join-Path $root 'Main.ahk'
$bundledName = if ([Environment]::Is64BitOperatingSystem) { 'AutoHotkey64.exe' } else { 'AutoHotkey32.exe' }
$bundled = Join-Path $root ('submacros\' + $bundledName)
$repairScript = Join-Path $PSScriptRoot 'Repair.ps1'
if (Test-Path -LiteralPath $repairScript -PathType Leaf) { . $repairScript }
$preferences = Join-Path $env:APPDATA 'Ultimate_Macro\Options\Launcher.ini'

function Display-Message([string]$text, [string]$title, [string]$type = 'Information') {
    if ($NoPrompt -or $VerifyOnly -or $PreflightOnly -or $RepairOnly) {
        Write-Host ($title + ": " + $text)
        return
    }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($text, $title, 'OK', $type)
    } catch { Write-Host "$title : $text" }
}

function Check-CompletePackage {
    # Repair only from independently validated matching ZIP content. A healthy
    # installation does not download anything, re-install AHK, or change scripts.
    $required = @(
        'Main.ahk', 'lib\OCR.ahk', 'lib\JSON.ahk', 'lib\Gdip_All.ahk',
        'lib\ImageSearch\ImageSearch.ahk', 'lib\ImageSearch\image_search.dll',
        'Resources\ready_gs.png', 'submacros\safe_update.ps1',
        'submacros\AutoHotkey64.exe', 'submacros\AutoHotkey32.exe',
        'lib\ImageSearch\msvcp140.dll', 'lib\ImageSearch\opencv_world500.dll',
        'lib\ImageSearch\vcruntime140.dll', 'StrategyLab.exe',
        'discord-gateway\worker.mjs'
    )
    if (-not (Test-Path -LiteralPath $repairScript -PathType Leaf)) {
        Display-Message 'Repair helper is missing. Extract the entire original ZIP first.' 'Ultimate Macro Setup' 'Warning'
        return $false
    }
    try {
        $manifest = Get-UMManifest
        if ($null -ne $manifest) {
            $problems = @(Find-UMProblems $root $manifest)
            if ($problems.Count -gt 0) {
                Write-Host ("Found $($problems.Count) missing or damaged application files.")
                if ($PreflightOnly -or $VerifyOnly) {
                    Write-Host ('Problem files: ' + (($problems | Select-Object -First 12 -ExpandProperty path) -join ', '))
                    return $false
                }
                Repair-UMFiles $root $manifest $problems (-not $NoNetwork) | Out-Null
                $remaining = @(Find-UMProblems $root $manifest)
                if ($remaining.Count -gt 0) { throw 'Integrity check still fails after repair.' }
                Write-Host 'Exact-build file repair completed successfully.'
            }
        }
        else {
            # An older official release may lack this package-specific manifest.
            # Don't preserve an OLD manifest across an update to a NEW version.
            Write-Host 'No matching build manifest (legacy update). Basic package checks only; repair unavailable.'
        }
    }
    catch {
        Display-Message ("Could not repair this installation:`n" + $_.Exception.Message +
            "`n`nRight-click the original ZIP, choose Extract All, and try Ultimate Macro.cmd again.") 'Ultimate Macro Repair' 'Warning'
        return $false
    }
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) })
    if ($missing.Count -gt 0) {
        Display-Message ("Missing application files: " + ($missing -join ', ') +
            "`n`nExtract the original ZIP completely and run Ultimate Macro.cmd from the new folder.") 'Extract Ultimate Macro First' 'Warning'
        return $false
    }
    return $true
}

function Hide-UMInternals {
    # Preserve the directory tree exactly: many AHK paths depend on A_ScriptDir.
    # Hidden = cosmetic, NOT a security or access-control boundary.
    foreach ($name in @('Main.ahk', 'Resources', 'lib', 'submacros', '_app',
                        'discord-gateway', 'setup', 'icon.ico', 'StrategyLab.exe')) {
        $target = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $target)) { continue }
        try {
            $item = Get-Item -LiteralPath $target -Force
            if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                $item.Attributes = $item.Attributes -bor [IO.FileAttributes]::Hidden
            }
        } catch { Write-Host ("Could not hide optional internal item: " + $name) }
    }
}

function Find-SystemAHKv2 {
    # Ignore v1 installations; v1 and v2 can coexist.
    $candidates = @()
    foreach ($basePath in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ([string]::IsNullOrWhiteSpace($basePath)) { continue }
        $candidates += (Join-Path $basePath 'AutoHotkey\v2\AutoHotkey64.exe')
        $candidates += (Join-Path $basePath 'AutoHotkey\v2\AutoHotkey.exe')
        $candidates += (Join-Path $basePath 'Programs\AutoHotkey\v2\AutoHotkey64.exe')
        $candidates += (Join-Path $basePath 'Programs\AutoHotkey\v2\AutoHotkey.exe')
    }
    foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $registry -ErrorAction SilentlyContinue)) {
            if ($entry.DisplayName -match '^AutoHotkey v?2(?:\.|\s|$)' -and $entry.InstallLocation) {
                $candidates += (Join-Path $entry.InstallLocation 'v2\AutoHotkey64.exe')
                $candidates += (Join-Path $entry.InstallLocation 'AutoHotkey64.exe')
            }
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        try {
            $version = [string](Get-Item -LiteralPath $candidate).VersionInfo.ProductVersion
            if ($version -match '^2\.\d+(?:\.\d+){1,2}') { return $candidate }
        } catch {}
    }
    return $null
}

function Install-LatestOfficialAHK {
    # Only the official versioned v2.0 distribution directory is trusted.
    # Both setup and the published SHA-256 are checked before execution.
    $baseUri = 'https://www.autohotkey.com/download/2.0/'
    $response = Invoke-WebRequest -Uri $baseUri -UseBasicParsing -TimeoutSec 20
    if ($response.BaseResponse.ResponseUri.Host -ne 'www.autohotkey.com') {
        throw 'The official release directory redirected to an unexpected site.'
    }
    $versions = @([regex]::Matches([string]$response.Content,
        'AutoHotkey_(2\.0\.\d+)_setup\.exe(?:\.sha256)?') |
        ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Unique -Descending)
    if ($versions.Count -eq 0) { throw 'No verified stable AutoHotkey v2 installer was listed.' }
    $version = $versions[0].ToString(3)
    $file = "AutoHotkey_${version}_setup.exe"
    $shaUri = $baseUri + $file + '.sha256'
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) ('ultimate-macro-ahk-' + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -Path $tempDir -ItemType Directory -Force)
    $destination = Join-Path $tempDir $file
    $shaFile = Join-Path $tempDir ($file + '.sha256')
    try {
        # The official checksum endpoint may be served as binary content, so
        # read the downloaded bytes as ASCII instead of casting the HTTP response.
        Invoke-WebRequest -Uri $shaUri -OutFile $shaFile -UseBasicParsing -TimeoutSec 20
        $expected = [IO.File]::ReadAllText($shaFile, [Text.Encoding]::ASCII).Trim()
        if ($expected -notmatch '^[A-Fa-f0-9]{64}$') {
            throw 'Official installer checksum was missing or invalid.'
        }
        Write-Host "Downloading AutoHotkey $version from the official website..."
        Invoke-WebRequest -Uri ($baseUri + $file) -OutFile $destination -UseBasicParsing -TimeoutSec 90
        $actual = (Get-UMSHA256 $destination)
        if ($actual -ine $expected) {
            throw 'Installer SHA-256 verification FAILED. No installer was launched.'
        }
        $signature = Get-AuthenticodeSignature -LiteralPath $destination
        if ($signature.Status -ne 'Valid') {
            throw ('Windows could not verify the official installer signature: ' + $signature.Status)
        }
        Write-Host "Verified official AutoHotkey $version installer. Opening setup..."
        # Explicit interactive setup, NOT silent/elevated on the user's behalf.
        $process = Start-Process -FilePath $destination -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "AutoHotkey setup exited with status $($process.ExitCode)."
        }
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


function Remove-OnboardingMarkers {
    # These files communicate instructions through their names, not through their contents.
    # Delete only the two known markers, and only after the macro starts successfully.
    foreach ($marker in @('00 - EXTRACT THE ZIP FILE.txt',
                         '01 - RUN THE ULTIMATE MACRO CMD.txt')) {
        $path = Join-Path $root $marker
        try {
            $item = Get-Item -LiteralPath $path -ErrorAction Stop
            if (-not $item.PSIsContainer -and
                -not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            }
        } catch {
            # Launch succeeded: lack of deletion permission is not fatal.
            Write-Host "Onboarding marker was kept: $marker"
        }
    }
}

function Has-SkippedInstaller {
    if (-not (Test-Path -LiteralPath $preferences -PathType Leaf)) { return $false }
    return ([IO.File]::ReadAllText($preferences) -match '(?m)^UsePortable=1\s*$')
}

function Save-PortablePreference {
    $directory = Split-Path -Parent $preferences
    if (-not (Test-Path -LiteralPath $directory)) {
        [void](New-Item -Path $directory -ItemType Directory -Force)
    }
    # This file never contains credentials.
    [IO.File]::WriteAllText($preferences, "[Launcher]`r`nUsePortable=1`r`n")
}

if (-not (Check-CompletePackage)) { exit 2 }

# Validate every live AHK entry point using the exact bundled interpreter.
# /Validate loads and parses scripts/includes, then exits without running them.
function Test-UMScriptSyntax {
    $entrypoints = @('Main.ahk', 'submacros\watchdog.ahk',
                     'submacros\official_remote.ahk',
                     '_app\StrategyEditorHost.ahk', '_app\calibration\sandbox_replay.ahk')
    foreach ($entry in $entrypoints) {
        $scriptPath = Join-Path $root $entry
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { continue }
        $errPath = Join-Path ([IO.Path]::GetTempPath()) ('um-ahk-check-' + [Guid]::NewGuid().ToString('N') + '.log')
        try {
            $cmdArgs = '/Validate /ErrorStdOut=UTF-8 "' + $scriptPath + '"'
            $process = Start-Process -FilePath $bundled -ArgumentList $cmdArgs -WorkingDirectory $root -PassThru -RedirectStandardError $errPath -ErrorAction Stop
            if (-not $process.WaitForExit(20000)) {
                try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
                Write-Host ('AHK validation timed out: ' + $entry)
                return $false
            }
            $details = ''
            if (Test-Path -LiteralPath $errPath) {
                $details = [string](Get-Content -LiteralPath $errPath -Raw -Encoding UTF8)
            }
            # Windows PowerShell 5 can return a blank ExitCode for a completed GUI process.
            # A captured parser error, timeout, or known nonzero result is still a hard failure.
            $exitText = [string]$process.ExitCode
            $exitKnown = -not [string]::IsNullOrWhiteSpace($exitText)
            $errorPresent = -not [string]::IsNullOrWhiteSpace($details)
            if (($exitKnown -and [int]$exitText -ne 0) -or $errorPresent) {
                Write-Host ('AHK validation failed: ' + $entry + ' | exit=' + $exitText + ' | ' + $details)
                return $false
            }
        } catch {
            Write-Host ('AHK validation failed: ' + $entry + ' | ' + $_.Exception.Message)
            return $false
        } finally { Remove-Item -LiteralPath $errPath -Force -ErrorAction SilentlyContinue }
    }
    return $true
}
if (-not (Test-UMScriptSyntax)) {
    Display-Message 'A bundled script failed startup validation. Please send the error from the console to the development team.' 'Ultimate Macro QA' 'Error'
    exit 3
}
if ($PreflightOnly -or $VerifyOnly -or $RepairOnly) {
    Write-Host 'Ultimate Macro file verification + AHK syntax: OK'
    exit 0
}
$installed = Find-SystemAHKv2
if ($InstallAutoHotkey -or (-not $installed -and -not $NoPrompt -and -not (Has-SkippedInstaller))) {
    if (-not $InstallAutoHotkey) {
        Add-Type -AssemblyName System.Windows.Forms
        $message = "AutoHotkey v2 isn't installed on this PC.`n`n" +
            "YES: Download and open the latest official AutoHotkey v2 installer (recommended if you want to open .ahk files directly).`n`n" +
            "NO: Run Ultimate Macro with its INCLUDED AutoHotkey v2, without installing anything.`n`n" +
            'CANCEL: Close without starting.'
        $choice = [System.Windows.Forms.MessageBox]::Show($message, 'Ultimate Macro | AutoHotkey Setup',
            [System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
            [System.Windows.Forms.MessageBoxIcon]::Question,
            [System.Windows.Forms.MessageBoxDefaultButton]::Button2)
        if ($choice -eq [System.Windows.Forms.DialogResult]::Cancel) { exit 0 }
        if ($choice -eq [System.Windows.Forms.DialogResult]::No) {
            Save-PortablePreference
        } else { $InstallAutoHotkey = $true }
    }
    if ($InstallAutoHotkey) {
        try {
            Install-LatestOfficialAHK
            $installed = Find-SystemAHKv2
            if (-not $installed) {
                Display-Message 'Installation did not register AutoHotkey v2. Ultimate Macro will use its included portable version.' 'AutoHotkey Setup' 'Warning'
            }
        } catch {
            Display-Message ("Could not install AutoHotkey v2:`n" + $_.Exception.Message +
                "`n`nUltimate Macro will use its included portable version. You can try installing from https://www.autohotkey.com/ later.") 'AutoHotkey Setup' 'Warning'
        }
    }
}

# Always use the packaged compatible interpreter. The optional system install
# exists for easier .ahk file associations, not to mutate UM's proven runtime.
Write-Host 'Starting Ultimate Macro using packaged AutoHotkey v2 runtime...'
try {
    $macroArguments = '"' + $main + '"'
    if ($WindowsStartupLaunch) { $macroArguments += ' --windows-startup' }
    elseif ($NoPrompt) { $macroArguments += ' --noninteractive' }
    $macroProcess = Start-Process -FilePath $bundled -ArgumentList $macroArguments -WorkingDirectory $root -PassThru -ErrorAction Stop
    # Ensure it hasn't immediately failed during AHK parsing/startup. No game automation here.
    Start-Sleep -Milliseconds 1250
    $macroProcess.Refresh()
    if ($macroProcess.HasExited) {
        throw ('Ultimate Macro exited during startup (code ' + $macroProcess.ExitCode + '). The extraction instructions were kept.')
    }
    Remove-OnboardingMarkers
    if (-not $NoHide) { Hide-UMInternals }
    Write-Host 'Ultimate Macro started. Internal folders organized in Explorer.'
} catch {
    Display-Message ("Could not launch Ultimate Macro:`n" + $_.Exception.Message +
        "`n`nThe extraction instructions remain in the folder so you can retry.") 'Ultimate Macro Launch Failed' 'Error'
    exit 1
}
