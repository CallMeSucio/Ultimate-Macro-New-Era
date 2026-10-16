# Ultimate Macro Automated Logs API uploader. No Discord webhook in this package.
# This process runs separately from gameplay, so upload errors cannot stop the macro.
param([Parameter(Mandatory = $true)][ValidatePattern('^[a-f0-9]{32}$')][string]$RunId)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$api = 'https://ultmacro.xyz/api/automated-logs/v1/reports'
# Local loopback override exists only for automated Windows QA tests. Never accepts remote hosts.
if ($env:UM_QA_LOGS_TEST_API -match '^http://127\.0\.0\.1:[0-9]{2,5}/api/automated-logs/v1/reports$') {
    $api = $env:UM_QA_LOGS_TEST_API
}
$directory = Join-Path $env:APPDATA 'Ultimate_Macro\AutomatedLogs'
$settings = Join-Path $env:APPDATA 'Ultimate_Macro\Options\Settings.tds'
$privateAccess = Join-Path $env:APPDATA 'Ultimate_Macro\Options\AutomatedLogs-Access.ini'
$packagedAccess = Join-Path $PSScriptRoot 'AutomatedLogs-Access.ini'

function Write-UMStatus([string]$id, [string]$text) {
    # Fixed status values, no exception traces, credentials or URLs.
    try { [IO.File]::WriteAllText((Join-Path $directory ($id + '.status')),
        $text, [Text.Encoding]::ASCII) } catch {}
}
function Read-UMToken {
    $path = if (Test-Path -LiteralPath $privateAccess -PathType Leaf) { $privateAccess }
            elseif (Test-Path -LiteralPath $packagedAccess -PathType Leaf) { $packagedAccess }
            else { return $null }
    $data = [IO.File]::ReadAllText($path)
    $section = [regex]::Match($data, '(?ms)^\[Access\][ \t]*\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
    $match = [regex]::Match($section, '(?im)^UploadToken=([a-zA-Z0-9_-]{40,128})[ \t]*$')
    if ($match.Success) { return $match.Groups[1].Value }
    return $null
}
function Allowed-ToUpload {
    if (-not (Test-Path -LiteralPath $settings -PathType Leaf)) { return $false }
    $all = [IO.File]::ReadAllText($settings)
    $section = [regex]::Match($all, '(?ms)^\[AutomatedLogs\][ \t]*\r?\n(.*?)(?=^\[|\z)').Groups[1].Value
    return ($section -match '(?im)^Consent=yes\s*$' -and
            $section -match '(?im)^ConsentVersion=api-v2\s*$')
}
function Validate-UMReport([string]$path, [string]$id) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($item.Length -lt 70 -or $item.Length -gt 140000) { return $false }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if (-not $text.StartsWith('ULTIMATE MACRO - AUTOMATED LOGS v1')) { return $false }
    if ($text -notmatch '(?m)^run_id=' + [regex]::Escape($id) + '\s*$') { return $false }
    if ($text -notmatch '(?m)^consent=yes\s*$' -or $text -notmatch '(?m)^finished_at=') { return $false }
    # No passwords, email addresses, URLs or user folder paths in uploads.
    if ($text -match '(?i)https?://|\b(?:token|password|secret|authorization|api[_-]?key)\s*[:=]|[a-z0-9_.+\-]+@[a-z0-9.\-]+\.[a-z]{2,}|[a-z]:\\users\\') { return $false }
    return $true
}

try {
    if (-not (Allowed-ToUpload)) { exit 0 }
    $token = Read-UMToken
    if (-not $token) {
        Write-UMStatus $RunId 'awaiting_tester_access'
        exit 0
    }
    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(12)
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('UltimateMacroAutomatedLogs/1.0')
    $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
    try {
        # Send the latest run first, then up to nine pending reports from offline sessions.
        $pending = @($RunId)
        $history = @(Get-ChildItem -LiteralPath $directory -File -Filter '*.txt' -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^[a-f0-9]{32}\.txt$' } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 12)
        foreach ($item in $history) {
            $id = [IO.Path]::GetFileNameWithoutExtension($item.Name)
            if ($id -ne $RunId -and $pending.Count -lt 10) { $pending += $id }
        }
        foreach ($id in $pending) {
            if (-not (Allowed-ToUpload)) { break }
            $report = Join-Path $directory ($id + '.txt')
            if (-not (Validate-UMReport $report $id)) {
                Write-UMStatus $id 'report_not_sent'
                continue
            }
            try {
                $data = [IO.File]::ReadAllBytes($report)
                $content = [System.Net.Http.ByteArrayContent]::new($data)
                $content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('text/plain; charset=utf-8')
                $req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $api)
                try {
                    $req.Headers.Add('X-UM-Run-ID', $id)
                    $req.Content = $content
                    $resp = $client.SendAsync($req).GetAwaiter().GetResult()
                    try {
                        $code = [int]$resp.StatusCode
                        if ($code -eq 202 -or $code -eq 200) {
                            Move-Item -LiteralPath $report -Destination (Join-Path $directory ($id + '.sent.txt')) -Force
                            Write-UMStatus $id 'uploaded'
                        } elseif ($code -eq 401 -or $code -eq 403) {
                            Write-UMStatus $id 'access_not_authorized'
                            break
                        } elseif ($code -eq 422) {
                            Write-UMStatus $id 'report_not_accepted'
                        } else {
                            Write-UMStatus $id 'will_retry_later'
                            break
                        }
                    } finally { $resp.Dispose() }
                } finally { $req.Dispose() }
            } catch { Write-UMStatus $id 'will_retry_later'; break }
        }
    } finally { $client.Dispose(); $handler.Dispose() }
} catch { Write-UMStatus $RunId 'will_retry_later' }
