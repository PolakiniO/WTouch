[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateSet('cpp', 'c')]
    [string]$Variant = 'cpp',

    [string]$BinaryPath,

    [string]$Destination = (Join-Path -Path $env:ProgramFiles -ChildPath 'wtouch'),

    [switch]$Force,

    [switch]$SkipCopy,

    [switch]$SkipPathUpdate
)

function Get-NormalizedPath {
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

function Assert-PathIsSafeForInstall {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [switch]$RequireExisting
    )

    $invalidChars = [System.IO.Path]::GetInvalidPathChars()
    if ($CandidatePath.IndexOfAny($invalidChars) -ge 0) {
        throw "Destination contains invalid path characters: '$CandidatePath'"
    }

    $normalized = Get-NormalizedPath -PathSegment $CandidatePath
    if (-not $normalized) {
        throw "Destination cannot be empty."
    }

    if (-not [System.IO.Path]::IsPathRooted($normalized)) {
        throw "Destination must be an absolute path. Provided: '$CandidatePath'"
    }

    if ($RequireExisting.IsPresent) {
        if (-not (Test-Path -LiteralPath $normalized -PathType Container)) {
            throw "Destination '$normalized' must exist and be a directory before updating PATH."
        }
    }

    return $normalized.TrimEnd('\\')
}

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

function Assert-ElevationIfRequired {
    param([string]$DestinationPath)

    if (-not $DestinationPath) {
        return
    }

    $normalizedDestination = Get-NormalizedPath -PathSegment $DestinationPath
    $programFiles = Get-NormalizedPath -PathSegment $env:ProgramFiles
    $programFilesX86 = Get-NormalizedPath -PathSegment ${env:ProgramFiles(x86)}

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

function Resolve-BinaryPath {
    param(
        [string]$Variant,
        [string]$BinaryPath
    )

    if ($BinaryPath) {
        return (Resolve-Path -LiteralPath $BinaryPath).ProviderPath
    }

    $scriptRoot = Split-Path -Parent $PSCommandPath
    switch ($Variant) {
        'cpp' {
            $candidates = @(
                '..\build\Release\wtouch.exe',
                '..\build\windows-release\Release\wtouch.exe',
                '..\build\ninja-release\wtouch.exe',
                '..\build\ninja-release\wtouch'
            ) | ForEach-Object { Join-Path -Path $scriptRoot -ChildPath $_ }

            foreach ($candidate in $candidates) {
                if (Test-Path -LiteralPath $candidate) {
                    return (Resolve-Path -LiteralPath $candidate).ProviderPath
                }
            }

            throw "Unable to locate the native C++ binary. Provide -BinaryPath explicitly."
        }
        'c' {
            $cDir = Join-Path -Path $scriptRoot -ChildPath '..\c'
            $candidates = @(
                (Join-Path -Path $cDir -ChildPath 'wtouch_c.exe'),
                (Join-Path -Path $cDir -ChildPath 'wtouch_c')
            )
            foreach ($candidate in $candidates) {
                if (Test-Path -LiteralPath $candidate) {
                    return (Resolve-Path -LiteralPath $candidate).ProviderPath
                }
            }
            throw "Unable to locate the portable C binary. Provide -BinaryPath explicitly."
        }
    }
}

try {
    $validatedDestination = Assert-PathIsSafeForInstall -CandidatePath $Destination
} catch {
    Write-Error $_
    exit 1
}

Write-Host "Validated installation destination: '$validatedDestination'"

Assert-ElevationIfRequired -DestinationPath $validatedDestination

$shouldCopy = -not $SkipCopy
$pathUpdateBlocked = $false
if ($shouldCopy) {
    try {
        $resolvedBinary = Resolve-BinaryPath -Variant $Variant -BinaryPath $BinaryPath
    } catch {
        Write-Error $_
        exit 1
    }

    $primaryName = 'wtouch.exe'
    $variantName = if ($Variant -eq 'cpp') { 'wtouch-cpp.exe' } else { 'wtouch-c.exe' }

    $primaryDestination = Join-Path -Path $validatedDestination -ChildPath $primaryName
    $variantDestination = Join-Path -Path $validatedDestination -ChildPath $variantName

    $primaryExists = Test-Path -LiteralPath $primaryDestination
    $variantExists = $true
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($primaryDestination, $variantDestination)) {
        $variantExists = Test-Path -LiteralPath $variantDestination
    }

    if ($primaryExists -and $variantExists -and -not $Force.IsPresent) {
        Write-Host "Detected existing installation at '$Destination'. Use -Force to overwrite or -SkipCopy to refresh PATH entries only."
        $shouldCopy = $false
    }

    if ($shouldCopy -and -not (Test-Path -LiteralPath $validatedDestination)) {
        Write-Verbose "Creating destination directory '$validatedDestination'."
        try {
            if ($PSCmdlet.ShouldProcess($validatedDestination, 'Create installation directory')) {
                New-Item -ItemType Directory -Path $validatedDestination -Force -ErrorAction Stop | Out-Null
            } else {
                Write-Verbose 'Directory creation skipped by user confirmation settings.'
                $shouldCopy = $false
                $pathUpdateBlocked = $true
            }
        } catch {
            Write-Error "Failed to create destination directory '$validatedDestination': $_"
            exit 1
        }
    }

    if ($shouldCopy) {
        try {
            if ($PSCmdlet.ShouldProcess($primaryDestination, "Copy '$resolvedBinary'")) {
                Copy-Item -LiteralPath $resolvedBinary -Destination $primaryDestination -Force:$Force.IsPresent -ErrorAction Stop
                Write-Host "Copied '$resolvedBinary' to '$primaryDestination'."

                if (-not [StringComparer]::OrdinalIgnoreCase.Equals($primaryDestination, $variantDestination)) {
                    if ($PSCmdlet.ShouldProcess($variantDestination, "Create variant copy from '$primaryDestination'")) {
                        Copy-Item -LiteralPath $primaryDestination -Destination $variantDestination -Force:$Force.IsPresent -ErrorAction Stop
                        Write-Host "Created variant-specific copy at '$variantDestination'."
                    } else {
                        Write-Verbose "Variant copy for '$variantDestination' skipped by user confirmation settings."
                    }
                }
            } else {
                Write-Verbose 'Binary copy skipped by user confirmation settings.'
            }
        } catch {
            Write-Error "Failed to copy '$resolvedBinary' to the destination: $_"
            exit 1
        }
    }
} else {
    Write-Verbose "Skipping binary copy step because -SkipCopy was provided."
}

function Add-ToUserPath {
    param([string]$PathToAdd)

    try {
        $normalizedTarget = Assert-PathIsSafeForInstall -CandidatePath $PathToAdd -RequireExisting
    } catch {
        Write-Error "Refusing to update PATH: $_"
        exit 1
    }

    Write-Host "Validated installation path for PATH update: '$normalizedTarget'"

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $current) {
        $current = ''
        Write-Host 'Current user PATH is empty.'
    } else {
        Write-Host "Current user PATH raw value: '$current'"
    }

    $segments = @($current -split ';' | Where-Object { $_ -ne '' })
    if ($segments.Count -gt 0) {
        $segmentList = $segments | ForEach-Object { "  - $_" }
        Write-Host "Parsed user PATH entries:`n$($segmentList -join "`n")"
    } else {
        Write-Host 'No non-empty user PATH entries found after parsing.'
    }

    $outputSegments = @()
    $alreadyPresent = $false
    foreach ($segment in $segments) {
        $outputSegments += $segment
        $candidate = Get-NormalizedPath -PathSegment $segment
        if ($candidate -and [StringComparer]::OrdinalIgnoreCase.Equals($candidate, $normalizedTarget)) {
            $alreadyPresent = $true
        }
    }

    if ($alreadyPresent) {
        Write-Host "Destination already present in the user PATH."
        return
    }

    if (-not $PSCmdlet.ShouldProcess('User PATH', "Append '$normalizedTarget'")) {
        Write-Verbose 'User PATH update skipped by user confirmation settings.'
        return
    }

    $outputSegments += $normalizedTarget
    $newValue = ($outputSegments -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newValue, 'User')

    Write-Host "Updated user PATH will contain $($outputSegments.Count) entries."
    Write-Host "New user PATH raw value: '$newValue'"

    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    if (-not $processPath) {
        $processPath = ''
        Write-Host 'Current process PATH is empty.'
    } else {
        Write-Host "Current process PATH raw value: '$processPath'"
    }
    $processSegments = @($processPath -split ';' | Where-Object { $_ -ne '' })
    if ($processSegments.Count -gt 0) {
        $processSegmentList = $processSegments | ForEach-Object { "  - $_" }
        Write-Host "Parsed process PATH entries:`n$($processSegmentList -join "`n")"
    } else {
        Write-Host 'No non-empty process PATH entries found after parsing.'
    }
    $processOutputSegments = @()
    $processAlreadyPresent = $false
    foreach ($segment in $processSegments) {
        $processOutputSegments += $segment
        $candidate = Get-NormalizedPath -PathSegment $segment
        if ($candidate -and [StringComparer]::OrdinalIgnoreCase.Equals($candidate, $normalizedTarget)) {
            $processAlreadyPresent = $true
        }
    }
    if (-not $processAlreadyPresent) {
        if ($PSCmdlet.ShouldProcess('Process PATH', "Append '$normalizedTarget' for current session")) {
            $processOutputSegments += $normalizedTarget
            [Environment]::SetEnvironmentVariable('Path', ($processOutputSegments -join ';'), 'Process')
            Write-Host 'Appended destination to the process PATH for the current session.'
        } else {
            Write-Verbose 'Process PATH update skipped by user confirmation settings.'
        }
    } else {
        Write-Host 'Destination already present in the process PATH for the current session.'
    }

    Write-Host "Added '$normalizedTarget' to the user PATH. Open a new shell to use it everywhere."
}

if ($SkipPathUpdate) {
    Write-Verbose "Skipping PATH update step because -SkipPathUpdate was provided."
} elseif ($pathUpdateBlocked) {
    Write-Verbose "Skipping PATH update because installation directory creation was declined."
} else {
    Add-ToUserPath -PathToAdd $validatedDestination
}

Write-Host "install-wtouch.ps1 completed successfully."
