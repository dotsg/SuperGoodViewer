<#
.SYNOPSIS
    SuperGoodViewer (超好读) PowerShell Command Line Launcher
.DESCRIPTION
    Launches SuperGoodViewer or opens markdown files in the running instance.
.EXAMPLE
    sgv README.md
    sgv C:\docs\notes.md
    sgv
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files,

    [Alias("h")]
    [switch]$Help
)

if ($Help) {
    Write-Host "SuperGoodViewer (超好读) CLI Launcher"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  sgv [file.md ...]      Open markdown file(s) in SuperGoodViewer"
    Write-Host "  sgv                    Launch or focus SuperGoodViewer"
    Write-Host "  sgv -h, -Help          Show this help message"
    exit 0
}

# 1. Locate executable
$exePath = $null

$candidates = @(
    "$PSScriptRoot\SuperGoodViewer.exe",
    "$PSScriptRoot\..\SuperGoodViewer.exe",
    "$PSScriptRoot\..\build\windows\x64\runner\Release\SuperGoodViewer.exe",
    "$env:LOCALAPPDATA\SuperGoodViewer\SuperGoodViewer.exe",
    "$env:LOCALAPPDATA\Programs\SuperGoodViewer\SuperGoodViewer.exe"
)

foreach ($c in $candidates) {
    if (Test-Path $c) {
        $exePath = (Resolve-Path $c).Path
        break
    }
}

if (-not $exePath) {
    $cmd = Get-Command "SuperGoodViewer.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        $exePath = $cmd.Source
    }
}

if (-not $exePath) {
    $exePath = "SuperGoodViewer.exe"
}

# 2. Launch
if (-not $Files -or $Files.Count -eq 0) {
    Start-Process -FilePath $exePath
    exit 0
}

foreach ($f in $Files) {
    if (Test-Path $f) {
        $absPath = (Resolve-Path $f).Path
        Start-Process -FilePath $exePath -ArgumentList "`"$absPath`""
    } else {
        Write-Error "sgv: error: file not found: $f"
        exit 1
    }
}
