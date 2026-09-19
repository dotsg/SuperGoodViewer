# Local Release Workflow Test Script (Simulates GitHub Actions release.yml)
param(
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path "$PSScriptRoot\.."

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   SuperGoodViewer Local Release Rehearsal Test       " -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# 1. Version Detection & Verification
$cargoToml = Get-Content "$root\core\Cargo.toml" -Raw
$cargoVersion = ($cargoToml | Select-String 'version\s*=\s*"([^"]+)"').Matches.Groups[1].Value

$pubspecYaml = Get-Content "$root\ui\pubspec.yaml" -Raw
$pubspecVersion = ($pubspecYaml | Select-String 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)').Matches.Groups[1].Value

if ($cargoVersion -ne $pubspecVersion) {
    Write-Error "Version mismatch: core/Cargo.toml ($cargoVersion) != ui/pubspec.yaml ($pubspecVersion)"
}

if (-not $Version) {
    $Version = "v$cargoVersion"
}
Write-Host "[1/4] Version Verified: $Version (Cargo.toml=$cargoVersion, pubspec.yaml=$pubspecVersion)" -ForegroundColor Green

# Prepare dist directory
$distDir = "$root\dist"
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Force -Path $distDir | Out-Null
}

# 2. Windows x64 Build & Packaging
Write-Host "`n[2/4] Simulating Windows x64 Release Build..." -ForegroundColor Yellow
$swWin = [System.Diagnostics.Stopwatch]::StartNew()

# Build Rust core (use --lib --bin sgv-cli)
Write-Host "  -> Building Rust sogood_core & sgv-cli (Release)..."
Set-Location "$root\core"
cargo build --release --lib --bin sgv-cli
if ($LASTEXITCODE -ne 0) { throw "Cargo build failed" }

# Build Flutter Desktop Windows
Write-Host "  -> Building Flutter Desktop Windows (Release)..."
Set-Location "$root\ui"
flutter pub get
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw "Flutter windows build failed" }

# Package Windows Portable ZIP
Write-Host "  -> Injecting artifacts & packaging ZIP..."
$winBuildDir = "$root\ui\build\windows\x64\runner\Release"
Copy-Item "$root\core\target\release\sogood_core.dll" -Destination $winBuildDir -Force
Copy-Item "$root\core\target\release\sgv-cli.exe" -Destination $winBuildDir -Force
Copy-Item "$root\ui\bin\sgv.cmd" -Destination $winBuildDir -Force
Copy-Item "$root\ui\bin\sgv.ps1" -Destination $winBuildDir -Force

$winZip = "$distDir\SuperGoodViewer-$Version-windows-x64.zip"
if (Test-Path $winZip) { Remove-Item $winZip -Force }
Compress-Archive -Path "$winBuildDir\*" -DestinationPath $winZip

# Verification
if (-not (Test-Path "$winBuildDir\SuperGoodViewer.exe")) { throw "Missing SuperGoodViewer.exe" }
if (-not (Test-Path "$winBuildDir\sogood_core.dll")) { throw "Missing sogood_core.dll" }
if (-not (Test-Path "$winBuildDir\sgv-cli.exe")) { throw "Missing sgv-cli.exe" }
if (-not (Test-Path "$winBuildDir\sgv.cmd")) { throw "Missing sgv.cmd" }
$swWin.Stop()
$winSize = (Get-Item $winZip).Length / 1MB
Write-Host ("  ✓ Windows x64 Package Created: {0:N2} MB ({1}s)" -f $winSize, $swWin.Elapsed.TotalSeconds.ToString("F1")) -ForegroundColor Green

# 3. Linux x64 Build & Packaging in WSL
Write-Host "`n[3/4] Simulating Linux x64 Release Build in WSL..." -ForegroundColor Yellow
$swLinux = [System.Diagnostics.Stopwatch]::StartNew()

$wslRoot = (wsl wslpath -u ($root.ToString().Replace('\', '/'))).Trim()

$wslCmd = @"
set -e
cd "$wslRoot"
export PATH="/usr/local/bin:/opt/flutter/bin:`$PATH"
echo "  -> [WSL] Building Rust sogood_core & sgv-cli..."
cd core && cargo build --release --lib --bin sgv-cli
echo "  -> [WSL] Resolving Linux pub packages..."
cd ../ui && flutter pub get
echo "  -> [WSL] Building Flutter Linux..."
flutter build linux --release
echo "  -> [WSL] Injecting sgv-cli into Linux bundle..."
mkdir -p "$wslRoot/ui/build/linux/x64/release/bundle/bin"
cp "$wslRoot/core/target/release/sgv-cli" "$wslRoot/ui/build/linux/x64/release/bundle/bin/"
chmod +x "$wslRoot/ui/build/linux/x64/release/bundle/bin/sgv-cli"
echo "  -> [WSL] Packaging tar.gz..."
cd "$wslRoot"
test -f ui/build/linux/x64/release/bundle/supergoodviewer || { echo "Missing supergoodviewer binary"; exit 1; }
test -f ui/build/linux/x64/release/bundle/bin/sgv-cli || { echo "Missing sgv-cli binary"; exit 1; }
mkdir -p dist
tar -czvf "dist/SuperGoodViewer-$Version-linux-x64.tar.gz" -C ui/build/linux/x64/release/bundle .
"@

wsl -e bash -c $wslCmd
if ($LASTEXITCODE -ne 0) { throw "WSL Linux build failed" }

$linuxTar = "$distDir\SuperGoodViewer-$Version-linux-x64.tar.gz"
$swLinux.Stop()
$linuxSize = (Get-Item $linuxTar).Length / 1MB
Write-Host ("  ✓ Linux x64 Package Created: {0:N2} MB ({1}s)" -f $linuxSize, $swLinux.Elapsed.TotalSeconds.ToString("F1")) -ForegroundColor Green

# Restore Windows Flutter package config
Write-Host "  -> Restoring Windows host package config..."
Set-Location "$root\ui"
flutter pub get | Out-Null

# 4. Final Summary & Verification
Write-Host "`n[4/4] Release Rehearsal Verification Summary:" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
Get-ChildItem -Path "$distDir\SuperGoodViewer-$Version-*" | ForEach-Object {
    $mb = $_.Length / 1MB
    Write-Host ("  [Artifact] {0,-48} {1,8:N2} MB" -f $_.Name, $mb) -ForegroundColor White
}
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "SUCCESS: Both Windows x64 & Linux x64 release artifacts built & verified locally!" -ForegroundColor Green
Set-Location $root
