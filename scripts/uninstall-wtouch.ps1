[CmdletBinding()]
param(
    [ValidateSet('cpp', 'c')]
    [string]$Variant = 'cpp',

    [string]$Destination = (Join-Path -Path $env:ProgramFiles -ChildPath 'wtouch')
)

function Get-BinaryNames {
    param([string]$Variant)

    $names = @('wtouch.exe')

    switch ($Variant) {
        'cpp' { $names += 'wtouch-cpp.exe' }
        'c'   { $names += 'wtouch-c.exe' }
    }

    return $names | Select-Object -Unique
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
        Write-Verbose "Directory '$DirectoryPath' does not exist."
        return $true
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
            return $true
        } catch {
            Write-Warning "Failed to remove directory '$DirectoryPath': $_"
            return $false
        }
    }

    Write-Verbose "Directory '$DirectoryPath' is not empty; leaving it in place."
    return $false
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

$binaryNames = Get-BinaryNames -Variant $Variant

foreach ($name in $binaryNames) {
    $binaryPath = Join-Path -Path $Destination -ChildPath $name
    Remove-FileIfPresent -PathToRemove $binaryPath
}
$directoryRemovedOrMissing = Remove-DirectoryIfEmpty -DirectoryPath $Destination
if ($directoryRemovedOrMissing) {
    Remove-FromUserPath -PathToRemove $Destination
} else {
    Write-Verbose "Skipping PATH cleanup because '$Destination' still contains files."
}

Write-Host 'uninstall-wtouch.ps1 completed successfully.'
