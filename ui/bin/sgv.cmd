@echo off
setlocal enabledelayedexpansion

rem ==============================================================================
rem sgv.cmd - SuperGoodViewer (超好读) Windows Command Line Launcher
rem ==============================================================================

rem 1. Resolve sgv-cli.exe location
set "CLI_BIN="
if exist "%~dp0sgv-cli.exe" set "CLI_BIN=%~dp0sgv-cli.exe"
if not defined CLI_BIN (
    if exist "%~dp0..\sgv-cli.exe" set "CLI_BIN=%~dp0..\sgv-cli.exe"
)
if not defined CLI_BIN (
    if exist "%~dp0..\build\windows\x64\runner\Release\sgv-cli.exe" set "CLI_BIN=%~dp0..\build\windows\x64\runner\Release\sgv-cli.exe"
)
if not defined CLI_BIN (
    if exist "%LOCALAPPDATA%\SuperGoodViewer\sgv-cli.exe" set "CLI_BIN=%LOCALAPPDATA%\SuperGoodViewer\sgv-cli.exe"
)
if not defined CLI_BIN (
    if exist "%LOCALAPPDATA%\Programs\SuperGoodViewer\sgv-cli.exe" set "CLI_BIN=%LOCALAPPDATA%\Programs\SuperGoodViewer\sgv-cli.exe"
)
if not defined CLI_BIN (
    if exist "%~dp0..\..\core\target\release\sgv-cli.exe" set "CLI_BIN=%~dp0..\..\core\target\release\sgv-cli.exe"
)
if not defined CLI_BIN (
    if exist "%~dp0..\..\core\target\debug\sgv-cli.exe" set "CLI_BIN=%~dp0..\..\core\target\debug\sgv-cli.exe"
)
if not defined CLI_BIN (
    for %%X in (sgv-cli.exe) do (
        if not "%%~$PATH:X"=="" set "CLI_BIN=%%~$PATH:X"
    )
)

rem 2. Handle help and version flags
if "%~1"=="-h" goto help
if "%~1"=="--help" goto help
if "%~1"=="/?" goto help
if "%~1"=="-v" goto version
if "%~1"=="--version" goto version

rem 3. Check for export mode or flags
set "IS_EXPORT=0"
if /i "%~1"=="export" set "IS_EXPORT=1"
for %%A in (%*) do (
    if /i "%%~A"=="-o" set "IS_EXPORT=1"
    if /i "%%~A"=="--output" set "IS_EXPORT=1"
    if /i "%%~A"=="--export" set "IS_EXPORT=1"
    if /i "%%~A"=="-f" set "IS_EXPORT=1"
    if /i "%%~A"=="--format" set "IS_EXPORT=1"
    if /i "%%~A"=="--page-format" set "IS_EXPORT=1"
    if /i "%%~A"=="--fluid" set "IS_EXPORT=1"
    if /i "%%~A"=="-t" set "IS_EXPORT=1"
    if /i "%%~A"=="--theme" set "IS_EXPORT=1"
    if /i "%%~A"=="--dark" set "IS_EXPORT=1"
    if /i "%%~A"=="-s" set "IS_EXPORT=1"
    if /i "%%~A"=="--font-size" set "IS_EXPORT=1"
    if /i "%%~A"=="--title" set "IS_EXPORT=1"
    if /i "%%~A"=="-r" set "IS_EXPORT=1"
    if /i "%%~A"=="--recursive" set "IS_EXPORT=1"
    if /i "%%~A"=="--no-recursive" set "IS_EXPORT=1"
    if /i "%%~A"=="--image-cache-dir" set "IS_EXPORT=1"
)

if "!IS_EXPORT!"=="1" (
    if not defined CLI_BIN (
        echo sgv: error: headless export tool 'sgv-cli.exe' not found >&2
        exit /b 1
    )
    "!CLI_BIN!" %*
    exit /b !ERRORLEVEL!
)

rem 4. Resolve SuperGoodViewer.exe location
set "EXE_PATH="

rem Check if EXE_PATH was configured by the installer
if defined SGV_EXE_OVERRIDE (
    if exist "!SGV_EXE_OVERRIDE!" set "EXE_PATH=!SGV_EXE_OVERRIDE!"
)

rem Check current directory and script directory
if not defined EXE_PATH (
    if exist "%~dp0SuperGoodViewer.exe" set "EXE_PATH=%~dp0SuperGoodViewer.exe"
)
if not defined EXE_PATH (
    if exist "%~dp0..\SuperGoodViewer.exe" set "EXE_PATH=%~dp0..\SuperGoodViewer.exe"
)
if not defined EXE_PATH (
    if exist "%~dp0..\build\windows\x64\runner\Release\SuperGoodViewer.exe" set "EXE_PATH=%~dp0..\build\windows\x64\runner\Release\SuperGoodViewer.exe"
)
rem Check AppData location if installed
if not defined EXE_PATH (
    if exist "%LOCALAPPDATA%\SuperGoodViewer\SuperGoodViewer.exe" set "EXE_PATH=%LOCALAPPDATA%\SuperGoodViewer\SuperGoodViewer.exe"
)
if not defined EXE_PATH (
    if exist "%LOCALAPPDATA%\Programs\SuperGoodViewer\SuperGoodViewer.exe" set "EXE_PATH=%LOCALAPPDATA%\Programs\SuperGoodViewer\SuperGoodViewer.exe"
)

rem Fallback to PATH search
if not defined EXE_PATH (
    for %%X in (SuperGoodViewer.exe) do (
        if not "%%~$PATH:X"=="" set "EXE_PATH=%%~$PATH:X"
    )
)

if not defined EXE_PATH (
    set "EXE_PATH=SuperGoodViewer.exe"
)

rem 5. Launch application or open files
if "%~1"=="" (
    start "" "!EXE_PATH!"
    exit /b 0
)

:loop
if "%~1"=="" goto done

set "TARGET_FILE=%~f1"
if not exist "!TARGET_FILE!" (
    echo sgv: error: file not found: %~1 >&2
    exit /b 1
)

start "" "!EXE_PATH!" "!TARGET_FILE!"
shift
goto loop

:done
exit /b 0

:version
if defined CLI_BIN (
    "!CLI_BIN!" --version
    exit /b !ERRORLEVEL!
)
echo SuperGoodViewer CLI Launcher
exit /b 0

:help
chcp 65001 >nul 2>&1
echo SuperGoodViewer (超好读) CLI Launcher & Tool
echo.
echo Usage:
echo   sgv [file.md ...]               Open markdown file(s) in SuperGoodViewer GUI
echo   sgv export ^<path^>... [options]  Export markdown file(s) or directory to PDF
echo   sgv ^<file.md^> -o ^<output.pdf^>   Export single markdown file to PDF
echo   sgv                             Launch or focus SuperGoodViewer GUI
echo   sgv -h, --help                  Show this help message
echo.
echo Export Options:
echo   -o, --output ^<path^>             Output PDF path or destination directory
echo   -f, --format ^<format^>           Page layout format: a4, a4-landscape, fluid, slide, slide-4-3
echo       --fluid                     Shorthand for --format fluid
echo   -t, --theme ^<theme^>             Theme: light, dark (default: light)
echo       --dark                      Shorthand for --theme dark
echo   -s, --font-size ^<pt^>            Font size in points (default: 10.5)
echo   -r, --recursive                 Recursively scan subdirectories (default: enabled)
echo       --no-recursive              Do not scan subdirectories
echo.
echo Examples:
echo   sgv README.md                             # View in GUI
echo   sgv export README.md                      # Export to README.pdf
echo   sgv export .\docs -o .\dist               # Batch export .\docs to .\dist
echo   cat draft.md ^| sgv export - -o draft.pdf  # Export from stdin
exit /b 0
