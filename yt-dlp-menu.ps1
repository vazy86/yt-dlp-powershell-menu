$ErrorActionPreference = 'Stop'

$script:Config = @{
    DownloadPath = Join-Path -Path $PSScriptRoot -ChildPath 'downloads'
    YtDlpPath    = 'yt-dlp'
    FfmpegPath   = 'ffmpeg'
}

function Pause-App {
    Write-Host ''
    Read-Host 'Press Enter to continue'
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
        [string[]]$Arguments
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
        Write-Host 'Done.' -ForegroundColor Green
    }
    else {
        Write-Host "yt-dlp exited with code $exitCode" -ForegroundColor Red
    }

    Pause-App
}

function Download-BestVideo {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Video URL'

    $arguments = @(
        '--newline'
        '--ignore-errors'
        '-f', 'bv*+ba/b'
        '-o', (Get-OutputTemplate)
        $url
    )

    Invoke-YtDlp -Arguments $arguments
}

function Download-WithQualityChoice {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Video URL'

    Write-Host ''
    Write-Host 'Choose quality:' -ForegroundColor Cyan
    Write-Host '1. Best available'
    Write-Host '2. 1080p or lower'
    Write-Host '3. 720p or lower'
    Write-Host '4. 480p or lower'
    Write-Host ''

    $choice = Read-RequiredInput -Prompt 'Option'
    $format = switch ($choice) {
        '1' { 'bv*+ba/b' }
        '2' { 'bv*[height<=1080]+ba/b[height<=1080]' }
        '3' { 'bv*[height<=720]+ba/b[height<=720]' }
        '4' { 'bv*[height<=480]+ba/b[height<=480]' }
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
        '-f', $format
        '-o', (Get-OutputTemplate)
        $url
    )

    Invoke-YtDlp -Arguments $arguments
}

function Download-Audio {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Video or playlist URL'

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

    Invoke-YtDlp -Arguments $arguments
}

function Download-Playlist {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Playlist URL'

    Write-Host ''
    $startIndex = Read-Host 'Start from item number (Enter = first)'
    $endIndex = Read-Host 'End at item number (Enter = last)'

    $arguments = @(
        '--newline'
        '--yes-playlist'
        '--ignore-errors'
        '-f', 'bv*+ba/b'
        '-o', (Get-OutputTemplate)
    )

    if ($startIndex) {
        $arguments += @('--playlist-start', $startIndex)
    }

    if ($endIndex) {
        $arguments += @('--playlist-end', $endIndex)
    }

    $arguments += $url
    Invoke-YtDlp -Arguments $arguments
}

function Show-Formats {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Video URL'

    $arguments = @(
        '--list-formats'
        $url
    )

    Invoke-YtDlp -Arguments $arguments
}

function Download-Custom {
    Clear-Host
    $url = Read-RequiredInput -Prompt 'Video or playlist URL'
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
    Invoke-YtDlp -Arguments $arguments
}

function Show-Header {
    Clear-Host
    Write-Host 'YT-DLP PowerShell Menu' -ForegroundColor Cyan
    Write-Host '----------------------'
    Write-Host ("Download folder: {0}" -f $script:Config.DownloadPath)
    Write-Host ''
}

function Show-Menu {
    Show-Header
    Write-Host '1. Download best quality video'
    Write-Host '2. Download video with quality choice'
    Write-Host '3. Download audio only'
    Write-Host '4. Download playlist'
    Write-Host '5. Show available formats'
    Write-Host '6. Custom yt-dlp command'
    Write-Host '7. Change download folder'
    Write-Host '8. Open download folder'
    Write-Host '9. Check yt-dlp and ffmpeg'
    Write-Host '10. Exit'
    Write-Host ''
}

Ensure-DownloadPath

while ($true) {
    Show-Menu
    $selection = Read-Host 'Select menu item'

    switch ($selection) {
        '1' { Download-BestVideo }
        '2' { Download-WithQualityChoice }
        '3' { Download-Audio }
        '4' { Download-Playlist }
        '5' { Show-Formats }
        '6' { Download-Custom }
        '7' { Select-DownloadPath }
        '8' { Open-DownloadFolder }
        '9' { Show-Dependencies }
        '10' { break }
        default {
            Write-Host ''
            Write-Host 'Unknown menu item.' -ForegroundColor Yellow
            Pause-App
        }
    }
}
