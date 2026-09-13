@echo off
setlocal enabledelayedexpansion

rem ==============================================================================
rem sgv.cmd - SuperGoodViewer (超好读) Windows Command Line Launcher
rem ==============================================================================

rem 1. Handle help flags
if "%~1"=="-h" goto help
if "%~1"=="--help" goto help
if "%~1"=="/?" goto help

rem 2. Resolve SuperGoodViewer.exe location
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

rem 3. Launch application or open files
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

:help
chcp 65001 >nul 2>&1
echo SuperGoodViewer (超好读) CLI Launcher
echo.
echo Usage:
echo   sgv [file.md ...]      Open markdown file(s) in SuperGoodViewer
echo   sgv                    Launch or focus SuperGoodViewer
echo   sgv -h, --help         Show this help message
exit /b 0
