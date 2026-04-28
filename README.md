# YT-DLP PowerShell Menu

Simple PowerShell menu for downloading videos and audio with `yt-dlp`.

## Features

- download the best quality video
- choose video quality
- extract audio to `mp3`, `m4a`, or `opus`
- download playlists
- show available formats
- run custom `yt-dlp` arguments
- change the download folder
- open the current download folder in Explorer
- check `yt-dlp` and `ffmpeg`

## Files

- `yt-dlp-menu.ps1` - main interactive menu
- `Run YT-DLP Menu.bat` - launcher for double click start from Explorer

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- `yt-dlp`
- `ffmpeg`

Install tools with:

```powershell
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg
```

## Run

Double click:

- `Run YT-DLP Menu.bat`

Or run manually:

```powershell
powershell -ExecutionPolicy Bypass -File ".\yt-dlp-menu.ps1"
```
