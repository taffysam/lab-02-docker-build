param(
    [Parameter(Mandatory = $true)]
    [string]$Image,

    [Parameter(Mandatory = $false)]
    [ValidateSet("development", "production")]
    [string]$Environment = "development",

    [switch]$SimulateFailure
)

$ErrorActionPreference = "Stop"

$environmentSuffix = if ($Environment -eq "production") {
    "prod"
}
else {
    "dev"
}

$containerName = "shipping-$environmentSuffix"
$previousName = "$containerName-previous"
$envFile = Join-Path $PSScriptRoot "..\.env.$environmentSuffix"

Write-Host "========================================"
Write-Host "Deployment environment : $Environment"
Write-Host "Container name         : $containerName"
Write-Host "Previous container     : $previousName"
Write-Host "Environment file       : $envFile"
Write-Host "Image                  : $Image"
Write-Host "========================================"

function Invoke-Docker {
    param([string[]]$Arguments)

    & docker @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "Docker command failed: docker $($Arguments -join ' ')"
    }
}

function Test-ContainerExists {
    param([string]$Name)

    $names = @(docker ps -a --format '{{.Names}}')

    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list Docker containers."
    }

    return ($names -contains $Name)
}

$previousPreserved = $false
$newContainerCreated = $false

try {
    if (-not (Test-Path $envFile)) {
        throw "Environment file not found: $envFile"
    }

    Write-Host "Pulling deployment image: $Image"

    # Pull before touching the existing deployment.
    Invoke-Docker -Arguments @("pull", $Image)

    # Remove the stale backup only after the candidate image
    # has been pulled successfully.
    if (Test-ContainerExists $previousName) {
        Write-Host "Removing stale backup container: $previousName"

        Invoke-Docker -Arguments @(
            "rm", "-f", $previousName
        )
    }

    # Preserve the current deployment.
    if (Test-ContainerExists $containerName) {
        Invoke-Docker -Arguments @(
            "stop", $containerName
        )

        Invoke-Docker -Arguments @(
            "rename", $containerName, $previousName
        )

        $previousPreserved = $true
    }

    # Build the docker run arguments.
    $runArgs = @(
        "run", "-d",
        "--name", $containerName,
        "--env-file", $envFile
    )

    if ($SimulateFailure) {
        $runArgs += @(
            "--entrypoint", "sh",
            $Image,
            "-c",
            "echo 'Starting faulty deployment'; sleep infinity"
        )
    }
    else {
        $runArgs += @(
            $Image,
            "sh", "-c",
            "python app.py && sleep infinity"
        )
    }

    # Start the candidate deployment.
    Invoke-Docker -Arguments $runArgs
    $newContainerCreated = $true

    # Verify that the container is running.
    $running = docker inspect $containerName `
        --format '{{.State.Running}}'

    if ($LASTEXITCODE -ne 0 -or $running -ne "true") {
        throw "Container is not running."
    }

    # Allow a short period for the application to produce
    # its startup output.
    $startupVerified = $false

    for ($attempt = 1; $attempt -le 10; $attempt++) {
        $logs = docker logs $containerName 2>&1
        $logsExitCode = $LASTEXITCODE
        $logText = $logs -join "`n"

        if ($logsExitCode -ne 0) {
            throw "Unable to read container logs. Docker exit code: $logsExitCode"
        }

        if ($logText -match "Shipping Calculator") {
            $startupVerified = $true
            Write-Host "Startup verified on attempt $attempt"
            break
        }

        Write-Host "Waiting for startup output ($attempt/10)..."
        Start-Sleep -Seconds 1
    }

    if (-not $startupVerified) {
        Write-Host "Container logs collected during verification:"
        Write-Host $logText

        throw "Startup verification failed after 10 attempts."
    }

    # Perform a functional application test.
    & docker exec $containerName python -c `
        "from app import calculate_shipping; assert calculate_shipping(7) == 100"

    if ($LASTEXITCODE -ne 0) {
        throw "Functional verification failed."
    }

    Write-Host "DEPLOYMENT SUCCESSFUL" -ForegroundColor Green
}
catch {
    Write-Host "DEPLOYMENT FAILED: $_" -ForegroundColor Red

    # Only attempt rollback if the existing deployment
    # was successfully preserved.
    if ($previousPreserved) {
        Write-Host "Starting rollback..."

        try {
            # Remove the failed candidate deployment.
            if (Test-ContainerExists $containerName) {
                Invoke-Docker -Arguments @(
                    "rm", "-f", $containerName
                )
            }

            # Restore the previous deployment.
            Invoke-Docker -Arguments @(
                "rename", $previousName, $containerName
            )

            Invoke-Docker -Arguments @(
                "start", $containerName
            )

            # Verify that the restored container is running.
            $restored = docker inspect $containerName `
                --format '{{.State.Running}}'

            if ($LASTEXITCODE -ne 0 -or $restored -ne "true") {
                throw "Restored container is not running."
            }

            Write-Host "ROLLBACK COMPLETED" -ForegroundColor Yellow
        }
        catch {
            Write-Host "ROLLBACK FAILED: $_" -ForegroundColor Red
        }
    }
    elseif (
        $newContainerCreated -and
        (Test-ContainerExists $containerName)
    ) {
        Write-Host "No previous deployment to restore."

        Invoke-Docker -Arguments @(
            "rm", "-f", $containerName
        )
    }

    exit 1
}