#!/usr/bin/env pwsh

# Publishing script for OpenCage PowerShell Module
# Usage: ./publish.ps1 -ApiKey "your-api-key-here" [-WhatIf]

param(
    [Parameter(Mandatory = $true)]
    [string]$ApiKey,
    
    [switch]$WhatIf
)

$ModulePath = Join-Path $PSScriptRoot "OpenCage"

Write-Host "Publishing OpenCage PowerShell Module..." -ForegroundColor Green

# Validate the module manifest first
try {
    $manifest = Test-ModuleManifest -Path (Join-Path $ModulePath "OpenCage.psd1") -ErrorAction Stop
    Write-Host "✓ Module manifest is valid" -ForegroundColor Green
    Write-Host "  Version: $($manifest.Version)" -ForegroundColor Cyan
    Write-Host "  Author: $($manifest.Author)" -ForegroundColor Cyan
} catch {
    Write-Error "Module manifest validation failed: $_"
    exit 1
}

# Run tests
Write-Host "Running tests..." -ForegroundColor Yellow
try {
    $testResults = Invoke-Pester -Path "tests" -PassThru -ErrorAction Stop
    if ($testResults.FailedCount -gt 0) {
        Write-Error "Tests failed. Cannot publish with failing tests."
        exit 1
    }
    Write-Host "✓ All tests passed" -ForegroundColor Green
} catch {
    Write-Error "Failed to run tests: $_"
    exit 1
}

# Publish the module
$publishParams = @{
    Path        = $ModulePath
    NuGetApiKey = $ApiKey
    Repository  = 'PSGallery'
    Verbose     = $true
}

if ($WhatIf) {
    Write-Host "WhatIf: Would publish module with the following parameters:" -ForegroundColor Yellow
    $publishParams | Format-Table -AutoSize
} else {
    try {
        Write-Host "Publishing to PowerShell Gallery..." -ForegroundColor Yellow
        Publish-Module @publishParams
        Write-Host "✓ Module published successfully!" -ForegroundColor Green
        Write-Host "Your module should be available at: https://www.powershellgallery.com/packages/OpenCage" -ForegroundColor Cyan
    } catch {
        Write-Error "Failed to publish module: $_"
        exit 1
    }
}