# Ultimate Macro exact-build repair helpers. Sourced by setup/Launch.ps1.
# No script downloaded from the internet is ever executed here.
$script:UMManifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
$script:UMReleaseTag = 'um-qa-v1.3.6-b2-hotfix3-logs'
$script:UMReleaseRepo = 'codebyaiden/ultmacro.xyz'
$script:UMReleaseAsset = 'Ultimate-Macro-v1.3.6-b2-hotfix3-logs.zip'

function Get-UMSHA256([string]$FilePath) {
    $inputStream = [System.IO.File]::OpenRead($FilePath)
    try {
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString($hasher.ComputeHash($inputStream)).Replace('-', '')
        } finally { $hasher.Dispose() }
    } finally { $inputStream.Dispose() }
}

function Get-UMManifest {
    if (-not (Test-Path -LiteralPath $script:UMManifestPath -PathType Leaf)) { return $null }
    $manifest = Get-Content -LiteralPath $script:UMManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.release_tag -ne $script:UMReleaseTag -or
        $manifest.official_repo -ne $script:UMReleaseRepo -or
        $manifest.release_asset -ne $script:UMReleaseAsset -or @($manifest.files).Count -lt 100) {
        throw 'The local repair manifest is invalid or does not match this build.'
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $manifest.files) {
        $path = [string]$file.path
        if ($path -notmatch '^[A-Za-z0-9_(). /+\-]+$' -or $path.StartsWith('/') -or
            $path.Contains('..') -or $path.Contains('//') -or
            -not $seen.Add($path) -or $file.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or
            [long]$file.bytes -lt 0 -or [long]$file.bytes -gt 100MB) {
            throw 'Repair manifest contains an invalid or duplicate file declaration.'
        }
    }
    return $manifest
}

function Test-UMFile([string]$Root, $Item) {
    $path = Join-Path $Root ($Item.path.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $path -Force).Length -ne [long]$Item.bytes) { return $false }
    return ((Get-UMSHA256 $path) -ieq [string]$Item.sha256)
}

function Find-UMProblems([string]$Root, $Manifest) {
    $problems = @()
    foreach ($item in $Manifest.files) {
        if (-not (Test-UMFile $Root $item)) { $problems += $item }
    }
    return $problems
}

function Find-UMArchives([string]$Root) {
    $dirs = @($Root, (Split-Path -Parent $Root),
        (Join-Path $env:USERPROFILE 'Downloads'))
    if ($env:OneDrive) { $dirs += (Join-Path $env:OneDrive 'Downloads') }
    $archives = @()
    foreach ($directory in ($dirs | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        # Avoid scanning a full drive or recursing into private user folders.
        $archives += @(Get-ChildItem -LiteralPath $directory -File -Filter '*.zip' -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge 1MB -and $_.Length -le 200MB } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 20)
    }
    return @($archives | Sort-Object FullName -Unique | Select-Object -First 50)
}

function Stage-UMFromArchive([string]$ZipPath, [string]$Stage, $Missing) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        if ($zip.Entries.Count -gt 5000) { return $false }
        $unpacked = [long]0
        $index = @{}
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName.Replace('\', '/')
            if ($name.StartsWith('/') -or $name.Contains(':') -or
                ($name -split '/') -contains '..') { return $false }
            if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { return $false }
            $unpacked += $entry.Length
            if ($unpacked -gt 512MB) { return $false }
            $index[$name] = $entry
        }
        # A complete release may contain one enclosing folder; reject ambiguous roots.
        $prefix = ''
        if (-not $index.ContainsKey('Main.ahk')) {
            $mainPaths = @($index.Keys | Where-Object { $_ -match '^[^/]+/Main\.ahk$' })
            if ($mainPaths.Count -ne 1) { return $false }
            $prefix = $mainPaths[0].Substring(0, $mainPaths[0].LastIndexOf('/') + 1)
        }
        foreach ($item in $Missing) {
            $key = $prefix + [string]$item.path
            if (-not $index.ContainsKey($key)) { return $false }
            $entry = $index[$key]
            if ($entry.Length -ne [long]$item.bytes) { return $false }
            $dest = Join-Path $Stage ($item.path.Replace('/', '\'))
            $folder = Split-Path -Parent $dest
            [void](New-Item -ItemType Directory -Path $folder -Force)
            $input = $entry.Open()
            try {
                $output = [IO.File]::Open($dest, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
                try { $input.CopyTo($output) } finally { $output.Dispose() }
            } finally { $input.Dispose() }
            if (-not (Test-UMFile $Stage $item)) { return $false }
        }
        return $true
    }
    catch { return $false }
    finally { $zip.Dispose() }
}

function Get-UMOfficialExactRelease([string]$TempDir, $Manifest) {
    # Never use /releases/latest here: it can be a DIFFERENT version from the installed RC.
    $tag = [Uri]::EscapeDataString([string]$Manifest.release_tag)
    $api = 'https://api.github.com/repos/' + $script:UMReleaseRepo + '/releases/tags/' + $tag
    $release = Invoke-RestMethod -Uri $api -TimeoutSec 15 -Headers @{
        Accept = 'application/vnd.github+json'; 'User-Agent' = 'Ultimate-Macro-Repair/1.3.6-b2'
    }
    if ($release.tag_name -ne $Manifest.release_tag -or $release.draft) {
        throw 'No official release matches the exact version of this private build.'
    }
    $assets = @($release.assets | Where-Object {
        $_.name -eq $Manifest.release_asset -and
        $_.browser_download_url -match '^https://github\.com/codebyaiden/ultmacro\.xyz/releases/download/' -and
        $_.digest -match '^sha256:[a-fA-F0-9]{64}$' -and
        [long]$_.size -gt 1MB -and [long]$_.size -le 200MB
    })
    if ($assets.Count -ne 1) { throw 'This exact version has no verifiable official ZIP asset.' }
    $path = Join-Path $TempDir 'official-release.zip'
    Invoke-WebRequest -Uri $assets[0].browser_download_url -UseBasicParsing -OutFile $path -TimeoutSec 100
    $actual = (Get-UMSHA256 $path)
    $expected = $assets[0].digest.Substring(7)
    if ($actual -ine $expected) { throw 'Official release archive SHA-256 mismatch.' }
    return $path
}

function Assert-UMSafeDestination([string]$Root, [string]$Path) {
    $parent = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
    $target = [IO.Path]::GetFullPath((Join-Path $Root $Path.Replace('/', '\')))
    if (-not $target.StartsWith(($parent + [IO.Path]::DirectorySeparatorChar),
            [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing a repair destination outside UM.' }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Refusing to replace a symbolic link or junction.'
        }
    }
    $walk = Split-Path -Parent $target
    while ($walk.StartsWith($parent, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $walk) {
            if ((Get-Item -LiteralPath $walk -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'A symbolic link or junction was found in a repair destination.'
            }
        }
        if ($walk -eq $parent) { break }
        $walk = Split-Path -Parent $walk
    }
    return $target
}

function Repair-UMFiles([string]$Root, $Manifest, $Missing, [bool]$AllowDownload = $true) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('UltimateMacro-repair-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $tmp -Force)
    try {
        $stage = Join-Path $tmp 'stage'
        $restored = $false
        foreach ($archive in (Find-UMArchives $Root)) {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            [void](New-Item -ItemType Directory -Path $stage)
            if (Stage-UMFromArchive $archive.FullName $stage $Missing) {
                Write-Host ('Validated original local ZIP: ' + $archive.Name)
                $restored = $true
                break
            }
        }
        if (-not $restored -and $AllowDownload) {
            if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
            [void](New-Item -ItemType Directory -Path $stage)
            try {
                $official = Get-UMOfficialExactRelease $tmp $Manifest
                $restored = Stage-UMFromArchive $official $stage $Missing
            }
            catch { Write-Host ('No verified exact-build online repair: ' + $_.Exception.Message) }
        }
        if (-not $restored) {
            throw 'Could not locate an exact matching source. Re-extract the same v1.3.6-b2-hotfix2 ZIP, or download a complete matching release. Nothing was replaced.'
        }
        # Do not partially replace files if source validation failed. Copy verified
        # files only after all staged items are verified; roll back if replacement fails.
        # Keep a persistent copy of any pre-existing modified files. A repair
        # should not silently erase a user's intentional source changes.
        $backup = Join-Path $env:APPDATA ('Ultimate_Macro\RepairBackups\' +
            (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N'))
        $backupsWritten = 0
        $done = @()
        try {
            foreach ($item in $Missing) {
                $dest = Assert-UMSafeDestination $Root $item.path
                $src = Join-Path $stage ($item.path.Replace('/', '\'))
                if (-not (Test-UMFile $stage $item)) { throw 'A staged file failed integrity verification.' }
                $prior = Test-Path -LiteralPath $dest -PathType Leaf
                if ($prior) {
                    $bak = Join-Path $backup ($item.path.Replace('/', '\'))
                    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $bak) -Force)
                    Copy-Item -LiteralPath $dest -Destination $bak -Force
                    $backupsWritten++
                }
                $done += [PSCustomObject]@{ Destination = $dest; Original = $prior; Relative = $item.path }
                [void](New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force)
                Copy-Item -LiteralPath $src -Destination $dest -Force
                if (-not (Test-UMFile $Root $item)) { throw 'Repair verification failed after copying.' }
            }
        }
        catch {
            $failure = $_.Exception.Message
            for ($i = $done.Count-1; $i -ge 0; $i--) {
                $item = $done[$i]
                if ($item.Original) {
                    $old = Join-Path $backup ($item.Relative.Replace('/', '\'))
                    Copy-Item -LiteralPath $old -Destination $item.Destination -Force
                } else {
                    Remove-Item -LiteralPath $item.Destination -Force -ErrorAction SilentlyContinue
                }
            }
            throw ('Repair failed and attempted rollback: ' + $failure)
        }
        if ($backupsWritten -gt 0) {
            Write-Host ('Previous modified files retained at: ' + $backup)
        }
        return $true
    }
    finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
