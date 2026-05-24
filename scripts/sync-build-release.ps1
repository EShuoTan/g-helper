# Sync upstream, build and release script
# Checks for upstream updates, builds exe, and publishes to GitHub release

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("win-x64", "win-x86", "win-arm64")]
    [string]$Runtime = "win-x64",

    [Parameter(Mandatory=$false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "`n>>> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Skip {
    param([string]$Message)
    Write-Host "- $Message" -ForegroundColor Yellow
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

try {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    Push-Location $repoRoot

    $remoteUrl = git remote get-url origin
    if ($remoteUrl -match "github\.com[:/](.+?)(?:\.git)?$") {
        $repoName = $Matches[1]
    } else {
        Write-ErrorAndExit "Cannot determine GitHub repository from origin remote"
    }

    Write-Step "Syncing with upstream (calling sync_fork.bat)"
    $syncScript = Join-Path $PSScriptRoot "sync_fork.bat"
    & cmd /c $syncScript
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Sync failed"
    }
    Write-Success "Sync completed"

    Write-Step "Getting latest upstream tag"
    $latestTag = git describe --tags --abbrev=0 upstream/main 2>$null
    if (-not $latestTag) {
        Write-ErrorAndExit "No tag found on upstream/main"
    }
    Write-Success "Latest upstream tag: $latestTag"

    $releaseTag = "$latestTag-custom"
    Write-Step "Checking if release $releaseTag already exists"
    $existingRelease = $null
    try {
        $existingRelease = gh release view $releaseTag --repo $repoName --json tagName 2>$null
    } catch {
        $existingRelease = $null
    }
    if ($existingRelease) {
        Write-Host "Release $releaseTag already exists. Will be overwritten." -ForegroundColor Yellow
    }

    Write-Step "Building GHelper.exe"
    $publishDir = Join-Path $env:TEMP "ghelper-publish-$(Get-Date -Format 'yyyyMMddHHmmss')"
    $buildScript = Join-Path $PSScriptRoot "build.ps1"

    & $buildScript -Configuration Release -Runtime $Runtime -OutputDir $publishDir
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Build failed"
    }
    Write-Success "Build completed"

    $exePath = Join-Path $publishDir "GHelper.exe"
    if (-not (Test-Path $exePath)) {
        Write-ErrorAndExit "GHelper.exe not found at $exePath"
    }

    $fileSize = [math]::Round((Get-Item $exePath).Length / 1MB, 2)
    Write-Host "Executable size: $fileSize MB" -ForegroundColor Gray

    Write-Step "Creating release $releaseTag"
    if ($existingRelease) {
        Write-Host "Deleting existing release $releaseTag" -ForegroundColor Yellow
        gh release delete $releaseTag --repo $repoName --yes
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorAndExit "Failed to delete existing release"
        }
    }

    $releaseNotes = @"
## $releaseTag

Synced with upstream $latestTag. Custom build from feat/external-control branch.

### Changes
Based on upstream release: [$latestTag](https://github.com/seerge/g-helper/releases/tag/$latestTag)
"@

    gh release create $releaseTag `
        --repo $repoName `
        --title "GHelper $releaseTag" `
        --notes $releaseNotes `
        $exePath

    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Failed to create release"
    }
    Write-Success "Release $releaseTag created and exe uploaded"

    Write-Step "Cleaning up temporary files"
    if (Test-Path $publishDir) {
        Remove-Item $publishDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Success "Cleanup done"

    Write-Host "`nDone! Release: $releaseTag" -ForegroundColor Green
    gh release view $releaseTag --repo $repoName --web
}
catch {
    Write-Host "`nFailed: $_" -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}
