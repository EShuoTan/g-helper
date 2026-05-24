@echo off
setlocal

set "PS_SCRIPT=%~dp0ghelper-ipc.ps1"

if "%~1"=="" goto :usage
if /i "%~1"=="--set" goto :set_mode
if /i "%~1"=="--get" goto :get_mode
if /i "%~1"=="--list" goto :get_modes
goto :usage

:set_mode
if "%~2"=="" (
    echo Error: Mode number required
    echo Usage: %~nx0 --set ^<0^|1^|2^|...^>
    exit /b 1
)
set "CURRENT_MODE="
for /f "tokens=2 delims=()" %%a in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Command get_mode 2^>nul') do set "INDEX_PART=%%a"
if defined INDEX_PART (
    for /f "tokens=2 delims=: " %%b in ("%INDEX_PART%") do set "CURRENT_MODE=%%b"
)
if defined CURRENT_MODE (
    if "%CURRENT_MODE%"=="%~2" (
        echo Already in mode %~2, skipping.
        goto :eof
    )
)
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Command set_mode -Mode %~2
goto :eof

:get_mode
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Command get_mode
goto :eof

:get_modes
powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Command get_modes
goto :eof

:usage
echo Usage: %~nx0 [option] [mode]
echo.
echo Options:
echo   --set ^<mode^>  Switch to specified mode (0, 1, 2, ...)
echo   --get         Get current mode
echo   --list        List all available modes
echo.
echo Examples:
echo   %~nx0 --set 0    (switch to mode 0)
echo   %~nx0 --set 1    (switch to mode 1)
echo   %~nx0 --get      (show current mode)
echo   %~nx0 --list     (show all modes)
exit /b 0
