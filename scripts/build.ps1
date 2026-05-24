# G-Helper Build Script
# Builds the application and copies the executable to the target directory

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Release")]
    [string]$Configuration = "Release",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("win-x64", "win-x86", "win-arm64")]
    [string]$Runtime = "win-x64",
    
    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "D:\app\g-helper",
    
    [Parameter(Mandatory=$false)]
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectDir = Join-Path $scriptDir "..\app"

function Write-Step {
    param([string]$Message)
    Write-Host "`n>>> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-ErrorAndExit {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

try {
    # Validate project directory
    if (-not (Test-Path $projectDir)) {
        Write-ErrorAndExit "Project directory not found: $projectDir"
    }
    
    $csprojPath = Join-Path $projectDir "GHelper.csproj"
    if (-not (Test-Path $csprojPath)) {
        Write-ErrorAndExit "Project file not found: $csprojPath"
    }
    
    # Clean if requested
    if ($Clean) {
        Write-Step "Cleaning previous builds"
        $binDir = Join-Path $projectDir "bin"
        $objDir = Join-Path $projectDir "obj"
        if (Test-Path $binDir) { Remove-Item $binDir -Recurse -Force }
        if (Test-Path $objDir) { Remove-Item $objDir -Recurse -Force }
        Write-Success "Cleaned build directories"
    }
    
    # Restore NuGet packages
    Write-Step "Restoring NuGet packages"
    Push-Location $projectDir
    dotnet restore
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Failed to restore NuGet packages"
    }
    Pop-Location
    Write-Success "NuGet packages restored"
    
    # Publish as single file
    Write-Step "Publishing $Configuration configuration for $Runtime"
    $publishArgs = @(
        "publish"
        "$projectDir\GHelper.sln"
        "-c", $Configuration
        "-r", $Runtime
        "-p:PublishSingleFile=true"
        "--no-self-contained"
        "-o", $OutputDir
    )
    
    Push-Location $projectDir
    dotnet @publishArgs
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorAndExit "Failed to publish application"
    }
    Pop-Location
    Write-Success "Application published"
    
    $exeDestination = Join-Path $OutputDir "GHelper.exe"
    if (-not (Test-Path $exeDestination)) {
        Write-ErrorAndExit "Published executable not found: $exeDestination"
    }
    
    # Stop GHelper process if running
    Write-Step "Stopping GHelper process if running"
    $process = Get-Process -Name GHelper -ErrorAction SilentlyContinue
    if ($process) {
        $process | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Success "GHelper process stopped"
    } else {
        Write-Host "GHelper process not running" -ForegroundColor Gray
    }
    
    # Get file size for information
    $fileSize = (Get-Item $exeDestination).Length
    $fileSizeMB = [math]::Round($fileSize / 1MB, 2)
    Write-Host "Executable size: $fileSizeMB MB" -ForegroundColor Gray
    
    Write-Host "`nBuild completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`nBuild failed: $_" -ForegroundColor Red
    exit 1
}