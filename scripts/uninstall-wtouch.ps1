[CmdletBinding()]
param(
    [ValidateSet('cpp', 'c')]
    [string]$Variant = 'cpp',

    [string]$Destination = (Join-Path -Path $env:ProgramFiles -ChildPath 'wtouch')
)

function Get-BinaryName {
    param([string]$Variant)
    switch ($Variant) {
        'cpp' { return 'wtouch-cpp.exe' }
        'c'   { return 'wtouch-c.exe' }
    }
}

function Normalize-PathSegment {
    param([string]$PathSegment)

    if (-not $PathSegment) {
        return $null
    }

    try {
        return [System.IO.Path]::GetFullPath($PathSegment)
    } catch {
        return $PathSegment.TrimEnd('\\')
    }
}

function Remove-FileIfPresent {
    param([string]$PathToRemove)

    if (-not $PathToRemove) {
        return
    }

    if (Test-Path -LiteralPath $PathToRemove) {
        try {
            Remove-Item -LiteralPath $PathToRemove -Force
            Write-Host "Removed '$PathToRemove'."
        } catch {
            Write-Error "Failed to remove '$PathToRemove': $_"
            exit 1
        }
    } else {
        Write-Verbose "File '$PathToRemove' does not exist. Nothing to remove."
    }
}

function Remove-DirectoryIfEmpty {
    param([string]$DirectoryPath)

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return
    }

    try {
        $remaining = @(Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction Stop)
    } catch {
        Write-Error "Unable to inspect directory '$DirectoryPath': $_"
        exit 1
    }

    if ($remaining.Count -eq 0) {
        try {
            Remove-Item -LiteralPath $DirectoryPath -Force
            Write-Host "Removed empty directory '$DirectoryPath'."
        } catch {
            Write-Warning "Failed to remove directory '$DirectoryPath': $_"
        }
    } else {
        Write-Verbose "Directory '$DirectoryPath' is not empty; leaving it in place."
    }
}

function Remove-FromUserPath {
    param([string]$PathToRemove)

    $normalizedTarget = Normalize-PathSegment -PathSegment $PathToRemove
    if (-not $normalizedTarget) {
        return
    }

    $currentUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $currentUserPath) {
        Write-Verbose 'User PATH is empty; nothing to update.'
        return
    }

    $segments = @()
    $removed = $false
    foreach ($segment in ($currentUserPath -split ';')) {
        if (-not $segment) { continue }
        $normalized = Normalize-PathSegment -PathSegment $segment
        if ([String]::IsNullOrWhiteSpace($normalized)) { continue }
        if ([StringComparer]::OrdinalIgnoreCase.Equals($normalized, $normalizedTarget)) {
            $removed = $true
            continue
        }
        $segments += $segment
    }

    if (-not $removed) {
        Write-Verbose "Destination '$PathToRemove' was not present on the user PATH."
    }

    $updatedUserPath = ($segments -join ';')
    [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')

    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    if ($processPath) {
        $processSegments = @()
        foreach ($segment in ($processPath -split ';')) {
            if (-not $segment) { continue }
            $normalized = Normalize-PathSegment -PathSegment $segment
            if ([String]::IsNullOrWhiteSpace($normalized)) { continue }
            if ([StringComparer]::OrdinalIgnoreCase.Equals($normalized, $normalizedTarget)) {
                $removed = $true
                continue
            }
            $processSegments += $segment
        }
        [Environment]::SetEnvironmentVariable('Path', ($processSegments -join ';'), 'Process')
    }

    if ($removed) {
        Write-Host "Removed '$PathToRemove' from the user PATH. Open a new shell to refresh the environment."
    } else {
        Write-Host "No PATH entries referencing '$PathToRemove' were found."
    }
}

$binaryName = Get-BinaryName -Variant $Variant
$binaryPath = Join-Path -Path $Destination -ChildPath $binaryName

Remove-FileIfPresent -PathToRemove $binaryPath
Remove-DirectoryIfEmpty -DirectoryPath $Destination
Remove-FromUserPath -PathToRemove $Destination

Write-Host 'uninstall-wtouch.ps1 completed successfully.'
