[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('cpp', 'c')]
    [string]$Variant = 'cpp',

    [string]$Destination = (Join-Path -Path $env:ProgramFiles -ChildPath 'wtouch')
)

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (-not $identity) {
            return $false
        }
        $principal = [Security.Principal.WindowsPrincipal]$identity
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        Write-Verbose "Unable to determine elevation state: $_"
        return $false
    }
}

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

function Assert-PathIsSafeForUninstall {
    param([Parameter(Mandatory = $true)][string]$CandidatePath)

    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    if ($CandidatePath.IndexOfAny($invalidChars) -ge 0) {
        throw "Destination contains invalid path characters: '$CandidatePath'"
    }

    $normalized = Normalize-PathSegment -PathSegment $CandidatePath
    if (-not $normalized) {
        throw "Destination cannot be empty."
    }

    if (-not [System.IO.Path]::IsPathRooted($normalized)) {
        throw "Destination must be an absolute path. Provided: '$CandidatePath'"
    }

    return $normalized.TrimEnd('\\')
}

function Assert-ElevationIfRequired {
    param([string]$DestinationPath)

    if (-not $DestinationPath) {
        return
    }

    $normalizedDestination = Normalize-PathSegment -PathSegment $DestinationPath
    $programFiles = Normalize-PathSegment -PathSegment $env:ProgramFiles
    $programFilesX86 = Normalize-PathSegment -PathSegment ${env:ProgramFiles(x86)}

    $requiresElevation = $false
    if ($programFiles -and $normalizedDestination.StartsWith($programFiles, [System.StringComparison]::OrdinalIgnoreCase)) {
        $requiresElevation = $true
    } elseif ($programFilesX86 -and $normalizedDestination.StartsWith($programFilesX86, [System.StringComparison]::OrdinalIgnoreCase)) {
        $requiresElevation = $true
    }

    if ($requiresElevation -and -not (Test-IsAdministrator)) {
        Write-Error "Destination '$DestinationPath' resides under '%ProgramFiles%' and requires an elevated PowerShell session. Rerun this script as Administrator or provide -Destination pointing to a user-writable directory."
        exit 1
    }
}

function Remove-FileIfPresent {
    param([string]$PathToRemove)

    if (-not $PathToRemove) {
        return
    }

    if (Test-Path -LiteralPath $PathToRemove) {
        try {
            Remove-Item -LiteralPath $PathToRemove -Force -ErrorAction Stop
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
            Remove-Item -LiteralPath $DirectoryPath -Force -ErrorAction Stop
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

try {
    $validatedDestination = Assert-PathIsSafeForUninstall -CandidatePath $Destination
} catch {
    Write-Error $_
    exit 1
}

Write-Host "Validated uninstall destination: '$validatedDestination'"

Assert-ElevationIfRequired -DestinationPath $validatedDestination

foreach ($name in $binaryNames) {
    $binaryPath = Join-Path -Path $validatedDestination -ChildPath $name
    if ($PSCmdlet.ShouldProcess($binaryPath, 'Remove installed binary')) {
        Remove-FileIfPresent -PathToRemove $binaryPath
    } else {
        Write-Verbose "Removal of '$binaryPath' skipped by user confirmation settings."
    }
}
$directoryRemovedOrMissing = $false
if ($PSCmdlet.ShouldProcess($validatedDestination, 'Remove installation directory if empty')) {
    $directoryRemovedOrMissing = Remove-DirectoryIfEmpty -DirectoryPath $validatedDestination
} else {
    Write-Verbose 'Directory cleanup skipped by user confirmation settings.'
}
if ($directoryRemovedOrMissing) {
    if ($PSCmdlet.ShouldProcess('User PATH', "Remove '$validatedDestination'")) {
        Remove-FromUserPath -PathToRemove $validatedDestination
    } else {
        Write-Verbose 'User PATH cleanup skipped by user confirmation settings.'
    }
} else {
    Write-Verbose "Skipping PATH cleanup because '$validatedDestination' still contains files."
}

Write-Host 'uninstall-wtouch.ps1 completed successfully.'
