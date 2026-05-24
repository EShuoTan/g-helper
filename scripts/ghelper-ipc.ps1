# G-Helper IPC Client Script
# Usage: .\ghelper-ipc.ps1 -Command <command> [-Mode <mode>]

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("set_mode", "get_mode", "get_modes")]
    [string]$Command,
    
    [Parameter(Mandatory=$false)]
    [string]$Mode
)

$PipeName = "GHelper_IPC"

function Send-IPCCommand {
    param(
        [string]$Request,
        [int]$Retries = 1
    )
    
    for ($attempt = 0; $attempt -le $Retries; $attempt++) {
        try {
            $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $PipeName, [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect(5000)
            
            $writer = New-Object System.IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $reader = New-Object System.IO.StreamReader($pipe)
            
            $writer.WriteLine($Request)
            
            $response = $reader.ReadLine()
            
            $pipe.Dispose()
            
            if (-not [string]::IsNullOrEmpty($response)) {
                return $response | ConvertFrom-Json
            }
        }
        catch {
            try { $pipe.Dispose() } catch {}
        }
    }
    return $null
}

$request = @{
    command = $Command
}

if ($Mode) {
    if ($Mode -match "^\d+$") {
        $request.mode = [int]$Mode
    }
    else {
        $request.mode = $Mode
    }
}

$jsonRequest = $request | ConvertTo-Json -Compress
$response = Send-IPCCommand -Request $jsonRequest

if ($response) {
    if ($response.success) {
        switch ($Command) {
            "set_mode" {
                Write-Host "Mode switched to: $($response.data.name) (index: $($response.data.mode))" -ForegroundColor Green
            }
            "get_mode" {
                Write-Host "Current mode: $($response.data.name) (index: $($response.data.mode))" -ForegroundColor Cyan
            }
            "get_modes" {
                Write-Host "Available modes:" -ForegroundColor Yellow
                foreach ($mode in $response.data.modes) {
                    $current = if ($mode.isCurrent) { " *" } else { "" }
                    Write-Host "  [$($mode.index)] $($mode.name)$current"
                }
            }
        }
    }
    else {
        Write-Error "Error: $($response.error)"
    }
}
