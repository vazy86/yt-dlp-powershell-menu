$ErrorActionPreference = 'Stop'

$script:AppRoot = $PSScriptRoot
$script:ConfigFilePath = Join-Path -Path $script:AppRoot -ChildPath 'settings.json'
$script:HistoryFilePath = Join-Path -Path $script:AppRoot -ChildPath 'history.json'
$script:MaxHistoryItems = 20
$script:Config = $null
$script:History = @()

function Get-DefaultConfig {
    return @{
        DownloadPath      = (Join-Path -Path $script:AppRoot -ChildPath 'downloads')
        YtDlpPath         = 'yt-dlp'
        FfmpegPath        = 'ffmpeg'
        PreferredVideoMode = 'best'
        PreferredAudioFormat = 'mp3'
    }
}

function Pause-App {
    Write-Host ''
    Read-Host 'Press Enter to continue'
}

function ConvertTo-Hashtable {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $result = @{}
    foreach ($property in $InputObject.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }

    return $result
}

function Save-JsonFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Data
    )

    $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Load-Config {
    $config = Get-DefaultConfig

    if (Test-Path -LiteralPath $script:ConfigFilePath) {
        try {
            $raw = Get-Content -LiteralPath $script:ConfigFilePath -Raw | ConvertFrom-Json
            $loadedConfig = ConvertTo-Hashtable -InputObject $raw
            foreach ($key in $loadedConfig.Keys) {
                if (-not [string]::IsNullOrWhiteSpace([string]$loadedConfig[$key])) {
                    $config[$key] = $loadedConfig[$key]
                }
            }
        }
        catch {
            Write-Host 'Warning: settings.json could not be read. Defaults were loaded.' -ForegroundColor Yellow
        }
    }

    $script:Config = $config
}

function Save-Config {
    Save-JsonFile -Path $script:ConfigFilePath -Data $script:Config
}

function Load-History {
    $script:History = @()

    if (-not (Test-Path -LiteralPath $script:HistoryFilePath)) {
        return
    }

    try {
        $raw = Get-Content -LiteralPath $script:HistoryFilePath -Raw | ConvertFrom-Json
        if ($raw -is [System.Collections.IEnumerable]) {
            $items = @($raw)
        }
        else {
            $items = @($raw)
        }

        $script:History = @(
            $items |
                Where-Object { $_ -and $_.Url } |
                Select-Object -First $script:MaxHistoryItems
        )
    }
    catch {
        Write-Host 'Warning: history.json could not be read. History was reset.' -ForegroundColor Yellow
    }
}

function Save-History {
    Save-JsonFile -Path $script:HistoryFilePath -Data @($script:History)
}

function Ensure-DownloadPath {
    if (-not (Test-Path -LiteralPath $script:Config.DownloadPath)) {
        New-Item -ItemType Directory -Path $script:Config.DownloadPath | Out-Null
    }
}

function Get-CommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Test-Dependencies {
    $ytDlp = Get-CommandPath -Name $script:Config.YtDlpPath
    $ffmpeg = Get-CommandPath -Name $script:Config.FfmpegPath

    [PSCustomObject]@{
        YtDlpFound  = [bool]$ytDlp
        YtDlpPath   = $ytDlp
        FfmpegFound = [bool]$ffmpeg
        FfmpegPath  = $ffmpeg
    }
}

function Show-Dependencies {
    Clear-Host
    $deps = Test-Dependencies

    Write-Host 'Dependency status' -ForegroundColor Cyan
    Write-Host '-----------------'
    Write-Host ("yt-dlp : {0}" -f ($(if ($deps.YtDlpFound) { $deps.YtDlpPath } else { 'not found' })))
    Write-Host ("ffmpeg : {0}" -f ($(if ($deps.FfmpegFound) { $deps.FfmpegPath } else { 'not found' })))
    Write-Host ''

    if (-not $deps.YtDlpFound) {
        Write-Host 'Install yt-dlp and add it to PATH.' -ForegroundColor Yellow
        Write-Host 'Example: winget install yt-dlp.yt-dlp'
    }

    if (-not $deps.FfmpegFound) {
        Write-Host 'ffmpeg is required for merge and conversion operations.' -ForegroundColor Yellow
        Write-Host 'Example: winget install Gyan.FFmpeg'
    }

    Pause-App
}

function Read-RequiredInput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-UrlWithHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    if ($script:History.Count -gt 0) {
        Write-Host ''
        Write-Host 'Recent URLs:' -ForegroundColor Cyan
        $previewItems = @($script:History | Select-Object -First 5)
        for ($index = 0; $index -lt $previewItems.Count; $index++) {
            $entry = $previewItems[$index]
            Write-Host ("{0}. {1} [{2}]" -f ($index + 1), $entry.Url, $entry.Type)
        }
        Write-Host 'Type a URL or enter r<number> to reuse one of these.'
        Write-Host ''
    }

    while ($true) {
        $value = Read-RequiredInput -Prompt $Prompt
        if ($value -match '^[Rr](\d+)$') {
            $requestedIndex = [int]$Matches[1] - 1
            if ($requestedIndex -ge 0 -and $requestedIndex -lt $script:History.Count) {
                return $script:History[$requestedIndex].Url
            }

            Write-Host 'History item not found.' -ForegroundColor Yellow
            continue
        }

        return $value
    }
}

function Add-HistoryEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    $trimmedUrl = $Url.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedUrl)) {
        return
    }

    $remaining = @(
        $script:History |
            Where-Object { $_.Url -ne $trimmedUrl }
    )

    $entry = [PSCustomObject]@{
        Url        = $trimmedUrl
        Type       = $Type
        Timestamp  = (Get-Date).ToString('s')
    }

    $script:History = @($entry) + $remaining
    if ($script:History.Count -gt $script:MaxHistoryItems) {
        $script:History = @($script:History | Select-Object -First $script:MaxHistoryItems)
    }

    Save-History
}

function Show-History {
    Clear-Host
    Write-Host 'URL history' -ForegroundColor Cyan
    Write-Host '-----------'

    if ($script:History.Count -eq 0) {
        Write-Host 'History is empty.'
        Pause-App
        return
    }

    for ($index = 0; $index -lt $script:History.Count; $index++) {
        $entry = $script:History[$index]
        Write-Host ("{0}. {1}" -f ($index + 1), $entry.Url)
        Write-Host ("   type: {0} | saved: {1}" -f $entry.Type, $entry.Timestamp) -ForegroundColor DarkGray
    }

    Write-Host ''
    $choice = Read-Host 'Type c to clear history or press Enter to return'
    if ($choice -eq 'c') {
        $script:History = @()
        Save-History
        Write-Host 'History cleared.' -ForegroundColor Green
        Pause-App
    }
}

function Select-DownloadPath {
    Clear-Host
    Write-Host 'Current download folder:' -ForegroundColor Cyan
    Write-Host $script:Config.DownloadPath
    Write-Host ''
    $newPath = Read-Host 'Enter a new folder path or leave blank to cancel'

    if ([string]::IsNullOrWhiteSpace($newPath)) {
        return
    }

    $resolved = [Environment]::ExpandEnvironmentVariables($newPath.Trim())
    if (-not (Test-Path -LiteralPath $resolved)) {
        New-Item -ItemType Directory -Path $resolved | Out-Null
    }

    $script:Config.DownloadPath = (Resolve-Path -LiteralPath $resolved).Path
    Save-Config
    Write-Host ''
    Write-Host "Download folder updated: $($script:Config.DownloadPath)" -ForegroundColor Green
    Pause-App
}

function Open-DownloadFolder {
    Ensure-DownloadPath
    Start-Process explorer.exe -ArgumentList $script:Config.DownloadPath
}

function Get-OutputTemplate {
    Ensure-DownloadPath
    return (Join-Path -Path $script:Config.DownloadPath -ChildPath '%(title)s [%(id)s].%(ext)s')
}

function Invoke-YtDlp {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [string]$HistoryUrl,
        [string]$HistoryType = 'download'
    )

    $deps = Test-Dependencies
    if (-not $deps.YtDlpFound) {
        Write-Host 'yt-dlp was not found. Install it first.' -ForegroundColor Red
        Pause-App
        return
    }

    Ensure-DownloadPath

    Write-Host ''
    Write-Host 'Command:' -ForegroundColor DarkGray
    Write-Host ("yt-dlp {0}" -f ($Arguments -join ' ')) -ForegroundColor DarkGray
    Write-Host ''

    & $script:Config.YtDlpPath @Arguments
    $exitCode = $LASTEXITCODE

    Write-Host ''
    if ($exitCode -eq 0) {
        if ($HistoryUrl) {
            Add-HistoryEntry -Url $HistoryUrl -Type $HistoryType
        }

        Write-Host 'Done.' -ForegroundColor Green
    }
    else {
        Write-Host "yt-dlp exited with code $exitCode" -ForegroundColor Red
    }

    Pause-App
}

function Get-VideoFormatPreset {
    Write-Host ''
    Write-Host 'Choose video format mode:' -ForegroundColor Cyan
    Write-Host '1. Best available'
    Write-Host '2. 1080p or lower'
    Write-Host '3. 720p or lower'
    Write-Host '4. 480p or lower'
    Write-Host '5. Audio compatible single file'
    Write-Host '6. Enter yt-dlp format string manually'
    Write-Host ''

    $choice = Read-RequiredInput -Prompt 'Option'

    switch ($choice) {
        '1' {
            return @{
                Format = 'bv*+ba/b'
                Label  = 'best-video'
            }
        }
        '2' {
            return @{
                Format = 'bv*[height<=1080]+ba/b[height<=1080]'
                Label  = '1080p'
            }
        }
        '3' {
            return @{
                Format = 'bv*[height<=720]+ba/b[height<=720]'
                Label  = '720p'
            }
        }
        '4' {
            return @{
                Format = 'bv*[height<=480]+ba/b[height<=480]'
                Label  = '480p'
            }
        }
        '5' {
            return @{
                Format = 'b'
                Label  = 'single-file'
            }
        }
        '6' {
            $customFormat = Read-RequiredInput -Prompt 'Enter yt-dlp format selector'
            return @{
                Format = $customFormat
                Label  = 'custom-format'
            }
        }
        default {
            return $null
        }
    }
}

function Download-BestVideo {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Video URL'

    $arguments = @(
        '--newline'
        '--ignore-errors'
        '-f', 'bv*+ba/b'
        '-o', (Get-OutputTemplate)
        $url
    )

    $script:Config.PreferredVideoMode = 'best'
    Save-Config
    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType 'video-best'
}

function Download-WithFormatMenu {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Video URL'
    $selection = Get-VideoFormatPreset

    if ($null -eq $selection) {
        Write-Host 'Unknown option.' -ForegroundColor Yellow
        Pause-App
        return
    }

    $arguments = @(
        '--newline'
        '--ignore-errors'
        '-f', $selection.Format
        '-o', (Get-OutputTemplate)
        $url
    )

    $script:Config.PreferredVideoMode = $selection.Label
    Save-Config
    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType "video-$($selection.Label)"
}

function Download-Audio {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Video or playlist URL'

    Write-Host ''
    Write-Host 'Audio format:' -ForegroundColor Cyan
    Write-Host '1. mp3'
    Write-Host '2. m4a'
    Write-Host '3. opus'
    Write-Host ''

    $choice = Read-RequiredInput -Prompt 'Option'
    $format = switch ($choice) {
        '1' { 'mp3' }
        '2' { 'm4a' }
        '3' { 'opus' }
        default { $null }
    }

    if (-not $format) {
        Write-Host 'Unknown option.' -ForegroundColor Yellow
        Pause-App
        return
    }

    $arguments = @(
        '--newline'
        '--ignore-errors'
        '-x'
        '--audio-format', $format
        '-o', (Get-OutputTemplate)
        $url
    )

    $script:Config.PreferredAudioFormat = $format
    Save-Config
    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType "audio-$format"
}

function Download-Playlist {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Playlist URL'

    Write-Host ''
    $startIndex = Read-Host 'Start from item number (Enter = first)'
    $endIndex = Read-Host 'End at item number (Enter = last)'
    $selection = Get-VideoFormatPreset

    if ($null -eq $selection) {
        Write-Host 'Unknown option.' -ForegroundColor Yellow
        Pause-App
        return
    }

    $arguments = @(
        '--newline'
        '--yes-playlist'
        '--ignore-errors'
        '-f', $selection.Format
        '-o', (Get-OutputTemplate)
    )

    if ($startIndex) {
        $arguments += @('--playlist-start', $startIndex)
    }

    if ($endIndex) {
        $arguments += @('--playlist-end', $endIndex)
    }

    $arguments += $url
    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType "playlist-$($selection.Label)"
}

function Show-Formats {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Video URL'

    $arguments = @(
        '--list-formats'
        $url
    )

    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType 'list-formats'
}

function Download-Custom {
    Clear-Host
    $url = Read-UrlWithHistory -Prompt 'Video or playlist URL'
    $customArgs = Read-Host 'Extra yt-dlp arguments'

    $arguments = @('--newline')

    if (-not [string]::IsNullOrWhiteSpace($customArgs)) {
        $parseErrors = $null
        $parsedArgs = [System.Management.Automation.PSParser]::Tokenize($customArgs, [ref]$parseErrors) |
            Where-Object { $_.Type -in @('CommandArgument', 'String') } |
            ForEach-Object { $_.Content }
        $arguments += $parsedArgs
    }

    $arguments += @('-o', (Get-OutputTemplate), $url)
    Invoke-YtDlp -Arguments $arguments -HistoryUrl $url -HistoryType 'custom'
}

function Update-YtDlp {
    Clear-Host
    $deps = Test-Dependencies

    if (-not $deps.YtDlpFound) {
        Write-Host 'yt-dlp was not found. Install it first.' -ForegroundColor Red
        Pause-App
        return
    }

    Write-Host 'Updating yt-dlp...' -ForegroundColor Cyan
    Write-Host ''
    & $script:Config.YtDlpPath -U
    $exitCode = $LASTEXITCODE
    Write-Host ''

    if ($exitCode -eq 0) {
        Write-Host 'yt-dlp update finished.' -ForegroundColor Green
    }
    else {
        Write-Host "yt-dlp update failed with code $exitCode" -ForegroundColor Red
    }

    Pause-App
}

function Show-Settings {
    Clear-Host
    Write-Host 'Current settings' -ForegroundColor Cyan
    Write-Host '----------------'
    Write-Host ("Download folder        : {0}" -f $script:Config.DownloadPath)
    Write-Host ("yt-dlp command         : {0}" -f $script:Config.YtDlpPath)
    Write-Host ("ffmpeg command         : {0}" -f $script:Config.FfmpegPath)
    Write-Host ("Preferred video mode   : {0}" -f $script:Config.PreferredVideoMode)
    Write-Host ("Preferred audio format : {0}" -f $script:Config.PreferredAudioFormat)
    Write-Host ("Config file            : {0}" -f $script:ConfigFilePath)
    Write-Host ("History file           : {0}" -f $script:HistoryFilePath)
    Pause-App
}

function Show-Header {
    Clear-Host
    Write-Host 'YT-DLP PowerShell Menu' -ForegroundColor Cyan
    Write-Host '----------------------'
    Write-Host ("Download folder: {0}" -f $script:Config.DownloadPath)
    Write-Host ("Recent URLs: {0}" -f $script:History.Count)
    Write-Host ''
}

function Show-Menu {
    Show-Header
    Write-Host '1. Download best quality video'
    Write-Host '2. Download video with format menu'
    Write-Host '3. Download audio only'
    Write-Host '4. Download playlist'
    Write-Host '5. Show available formats'
    Write-Host '6. Custom yt-dlp command'
    Write-Host '7. Change download folder'
    Write-Host '8. Open download folder'
    Write-Host '9. Show URL history'
    Write-Host '10. Check yt-dlp and ffmpeg'
    Write-Host '11. Update yt-dlp'
    Write-Host '12. Show current settings'
    Write-Host '13. Exit'
    Write-Host ''
}

Load-Config
Load-History
Ensure-DownloadPath
Save-Config

while ($true) {
    Show-Menu
    $selection = Read-Host 'Select menu item'

    switch ($selection) {
        '1' { Download-BestVideo }
        '2' { Download-WithFormatMenu }
        '3' { Download-Audio }
        '4' { Download-Playlist }
        '5' { Show-Formats }
        '6' { Download-Custom }
        '7' { Select-DownloadPath }
        '8' { Open-DownloadFolder }
        '9' { Show-History }
        '10' { Show-Dependencies }
        '11' { Update-YtDlp }
        '12' { Show-Settings }
        '13' { break }
        default {
            Write-Host ''
            Write-Host 'Unknown menu item.' -ForegroundColor Yellow
            Pause-App
        }
    }
}
