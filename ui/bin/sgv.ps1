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

# 1. Locate sgv-cli executable
$cliBin = $null
$cliCandidates = @(
    "$PSScriptRoot\sgv-cli.exe",
    "$PSScriptRoot\..\sgv-cli.exe",
    "$PSScriptRoot\..\build\windows\x64\runner\Release\sgv-cli.exe",
    "$env:LOCALAPPDATA\SuperGoodViewer\sgv-cli.exe",
    "$env:LOCALAPPDATA\Programs\SuperGoodViewer\sgv-cli.exe",
    "$PSScriptRoot\..\..\core\target\release\sgv-cli.exe",
    "$PSScriptRoot\..\..\core\target\debug\sgv-cli.exe"
)

foreach ($c in $cliCandidates) {
    if (Test-Path $c) {
        $cliBin = (Resolve-Path $c).Path
        break
    }
}

if (-not $cliBin) {
    $cmd = Get-Command "sgv-cli.exe" -ErrorAction SilentlyContinue
    if ($cmd) {
        $cliBin = $cmd.Source
    }
}

if ($args.Count -eq 1 -and ($args[0] -in @('-v', '--version', '-version', '/v'))) {
    if ($cliBin) {
        & $cliBin --version
        exit $LASTEXITCODE
    }
    Write-Host "SuperGoodViewer CLI Launcher"
    exit 0
}

if ($args.Count -eq 1 -and ($args[0] -in @('-h', '--help', '-help', '-?', '/?'))) {
    Write-Host "SuperGoodViewer (超好读) CLI Launcher & Tool"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  sgv [file.md ...]               Open markdown file(s) in SuperGoodViewer GUI"
    Write-Host "  sgv export <path>... [options]  Export markdown file(s) or directory to PDF"
    Write-Host "  sgv <file.md> -o <output.pdf>   Export single markdown file to PDF"
    Write-Host "  sgv                             Launch or focus SuperGoodViewer GUI"
    Write-Host "  sgv -h, --help                  Show this help message"
    Write-Host ""
    Write-Host "Export Options:"
    Write-Host "  -o, --output <path>             Output PDF path or destination directory"
    Write-Host "  -f, --format <format>           Page layout format: a4, a4-landscape, fluid, slide, slide-4-3"
    Write-Host "      --fluid                     Shorthand for --format fluid"
    Write-Host "  -t, --theme <theme>             Theme: light, dark (default: light)"
    Write-Host "      --dark                      Shorthand for --theme dark"
    Write-Host "  -s, --font-size <pt>            Font size in points (default: 10.5)"
    Write-Host "  -r, --recursive                 Recursively scan subdirectories (default: enabled)"
    Write-Host "      --no-recursive              Do not scan subdirectories"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  sgv README.md                             # View in GUI"
    Write-Host "  sgv export README.md                      # Export to README.pdf"
    Write-Host "  sgv export .\docs -o .\dist               # Batch export .\docs to .\dist"
    Write-Host "  cat draft.md | sgv export - -o draft.pdf  # Export from stdin"
    exit 0
}

# 2. Check for export mode
$isExport = $false
if ($args.Count -gt 0 -and $args[0] -eq 'export') {
    $isExport = $true
} else {
    foreach ($f in $args) {
        if ($f -in @('-o', '--output', '--export', '-f', '--format', '--page-format', '--fluid', '-t', '--theme', '--dark', '-s', '--font-size', '--title', '-r', '--recursive', '--no-recursive', '--image-cache-dir')) {
            $isExport = $true
            break
        }
    }
}

if ($isExport) {
    if (-not $cliBin -or -not (Test-Path $cliBin)) {
        Write-Error "sgv: error: headless export tool 'sgv-cli.exe' not found"
        exit 1
    }
    & $cliBin @args
    exit $LASTEXITCODE
}

# 3. Locate GUI executable
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

# 4. Launch GUI
if ($args.Count -eq 0) {
    Start-Process -FilePath $exePath
    exit 0
}

foreach ($f in $args) {
    if (Test-Path -LiteralPath $f) {
        $absPath = (Resolve-Path -LiteralPath $f).Path
        Start-Process -FilePath $exePath -ArgumentList "`"$absPath`""
    } else {
        Write-Error "sgv: error: file not found: $f"
        exit 1
    }
}
