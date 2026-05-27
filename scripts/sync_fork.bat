@echo off
setlocal enabledelayedexpansion

set TARGET_BRANCH=feat/external-control

if "%~1"=="" (
    cd /d "%~dp0.."
) else (
    cd /d "%~1"
)
if errorlevel 1 (
    echo Failed to enter repository root
    exit /b 1
)

echo Fetching upstream...
git fetch upstream
git fetch upstream --tags
if errorlevel 1 (
    echo Failed to fetch upstream
    exit /b 1
)

echo Checking for upstream updates...
git rev-parse upstream/main >nul 2>&1
if errorlevel 1 (
    echo Cannot resolve upstream/main
    exit /b 1
)

git checkout %TARGET_BRANCH%
if errorlevel 1 (
    echo Failed to checkout %TARGET_BRANCH%
    exit /b 1
)

echo Rebasing onto upstream/main...
git rebase --autostash upstream/main
if errorlevel 1 (
    echo Rebase failed. Aborting...
    git rebase --abort
    exit /b 1
)

echo Pushing to origin...
git push origin %TARGET_BRANCH% --force-with-lease
if errorlevel 1 (
    echo Failed to push to origin
    exit /b 1
)

echo Sync completed successfully
