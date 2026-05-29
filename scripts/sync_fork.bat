@echo off
setlocal enabledelayedexpansion

set TARGET_BRANCH=feat/external-control
set ORIGIN_REMOTE=origin
set MAIN_BRANCH=main
set UPSTREAM_REMOTE=upstream
set UPSTREAM_BRANCH=main
set UPSTREAM_REF=%UPSTREAM_REMOTE%/%UPSTREAM_BRANCH%

if not defined SYNC_FORK_RUNNING_COPY (
    set "SYNC_FORK_RUNNING_COPY=1"
    if "%~1"=="" (
        set "SYNC_FORK_REPO=%~dp0.."
    ) else (
        set "SYNC_FORK_REPO=%~1"
    )

    set "TEMP_SCRIPT=%TEMP%\sync_fork_%RANDOM%_%RANDOM%.bat"
    copy /y "%~f0" "!TEMP_SCRIPT!" >nul
    if errorlevel 1 (
        echo Failed to create temporary script copy
        exit /b 1
    )

    call "!TEMP_SCRIPT!" "!SYNC_FORK_REPO!"
    set "COPY_EXIT=!ERRORLEVEL!"
    del /q "!TEMP_SCRIPT!" >nul 2>&1
    exit /b !COPY_EXIT!
)

if "%~1"=="" (
    cd /d "%~dp0.."
) else (
    cd /d "%~1"
)
if errorlevel 1 (
    echo Failed to enter repository root
    exit /b 1
)

echo Fetching %UPSTREAM_REMOTE%...
git fetch %UPSTREAM_REMOTE%
if errorlevel 1 (
    echo Failed to fetch %UPSTREAM_REMOTE%
    exit /b 1
)

git fetch %UPSTREAM_REMOTE% --tags
if errorlevel 1 (
    echo Failed to fetch %UPSTREAM_REMOTE% tags
    exit /b 1
)

echo Checking for upstream updates...
git rev-parse %UPSTREAM_REF% >nul 2>&1
if errorlevel 1 (
    echo Cannot resolve %UPSTREAM_REF%
    exit /b 1
)

echo Ensuring %MAIN_BRANCH% tracks %UPSTREAM_REF%...
git show-ref --verify --quiet refs/heads/%MAIN_BRANCH%
if errorlevel 1 (
    git branch --track %MAIN_BRANCH% %UPSTREAM_REF%
) else (
    git branch --set-upstream-to=%UPSTREAM_REF% %MAIN_BRANCH%
)
if errorlevel 1 (
    echo Failed to set %MAIN_BRANCH% to track %UPSTREAM_REF%
    exit /b 1
)

git checkout %TARGET_BRANCH%
if errorlevel 1 (
    echo Failed to checkout %TARGET_BRANCH%
    exit /b 1
)

echo Updating %MAIN_BRANCH% to %UPSTREAM_REF%...
git branch -f %MAIN_BRANCH% %UPSTREAM_REF%
if errorlevel 1 (
    echo Failed to update %MAIN_BRANCH% to %UPSTREAM_REF%
    exit /b 1
)

echo Pushing %MAIN_BRANCH% to %ORIGIN_REMOTE%/%MAIN_BRANCH%...
git push %ORIGIN_REMOTE% %MAIN_BRANCH%:%MAIN_BRANCH% --force-with-lease
if errorlevel 1 (
    echo Failed to push %MAIN_BRANCH% to %ORIGIN_REMOTE%/%MAIN_BRANCH%
    exit /b 1
)

echo Rebasing onto %UPSTREAM_REF%...
git rebase --autostash %UPSTREAM_REF%
if errorlevel 1 (
    echo Rebase failed. Aborting...
    git rev-parse --verify REBASE_HEAD >nul 2>&1
    if not errorlevel 1 (
        git rebase --abort
    )
    exit /b 1
)

echo Pushing %TARGET_BRANCH% to %ORIGIN_REMOTE%...
git push %ORIGIN_REMOTE% %TARGET_BRANCH% --force-with-lease
if errorlevel 1 (
    echo Failed to push %TARGET_BRANCH% to %ORIGIN_REMOTE%
    exit /b 1
)

echo Sync completed successfully
