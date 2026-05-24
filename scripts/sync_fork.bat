@echo off
setlocal enabledelayedexpansion

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

git checkout feat/external-control
if errorlevel 1 (
    echo Failed to checkout feat/external-control
    exit /b 1
)

echo Rebasing onto upstream/main...
git rebase upstream/main
if errorlevel 1 (
    echo Rebase failed. Aborting...
    git rebase --abort
    exit /b 1
)

echo Pushing to origin...
git push origin --force-with-lease
if errorlevel 1 (
    echo Failed to push to origin
    exit /b 1
)

echo Sync completed successfully
