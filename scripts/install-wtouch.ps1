[CmdletBinding()]
param(
    [ValidateSet('cpp', 'c')]
    [string]$Variant = 'cpp',

    [string]$BinaryPath,

    [string]$Destination = (Join-Path -Path $env:ProgramFiles -ChildPath 'wtouch'),

    [switch]$Force,

    [switch]$SkipCopy,

    [switch]$SkipPathUpdate
)

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

if (-not $SkipCopy) {
    try {
        $resolvedBinary = Resolve-BinaryPath -Variant $Variant -BinaryPath $BinaryPath
    } catch {
        Write-Error $_
        exit 1
    }

    if (-not (Test-Path -LiteralPath $Destination)) {
        Write-Verbose "Creating destination directory '$Destination'."
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }

    $primaryName = 'wtouch.exe'
    $variantName = if ($Variant -eq 'cpp') { 'wtouch-cpp.exe' } else { 'wtouch-c.exe' }

    $primaryDestination = Join-Path -Path $Destination -ChildPath $primaryName
    $variantDestination = Join-Path -Path $Destination -ChildPath $variantName

    try {
        Copy-Item -LiteralPath $resolvedBinary -Destination $primaryDestination -Force:$Force.IsPresent
        Write-Host "Copied '$resolvedBinary' to '$primaryDestination'."

        if (-not [StringComparer]::OrdinalIgnoreCase.Equals($primaryDestination, $variantDestination)) {
            Copy-Item -LiteralPath $primaryDestination -Destination $variantDestination -Force:$Force.IsPresent
            Write-Host "Created variant-specific copy at '$variantDestination'."
        }
    } catch {
        Write-Error "Failed to copy '$resolvedBinary' to the destination: $_"
        exit 1
    }
} else {
    Write-Verbose "Skipping binary copy step because -SkipCopy was provided."
}

function Add-ToUserPath {
    param([string]$PathToAdd)

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

    if ($segments -contains $PathToAdd) {
        Write-Host "Destination already present in the user PATH."
        return
    }

    $segments += $PathToAdd
    $newValue = ($segments -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newValue, 'User')

    Write-Host "Updated user PATH will contain $($segments.Count) entries."
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
    if ($processSegments -notcontains $PathToAdd) {
        $processSegments += $PathToAdd
        [Environment]::SetEnvironmentVariable('Path', ($processSegments -join ';'), 'Process')
        Write-Host 'Appended destination to the process PATH for the current session.'
    } else {
        Write-Host 'Destination already present in the process PATH for the current session.'
    }

    Write-Host "Added '$PathToAdd' to the user PATH. Open a new shell to use it everywhere."
}

if ($SkipPathUpdate) {
    Write-Verbose "Skipping PATH update step because -SkipPathUpdate was provided."
} else {
    Add-ToUserPath -PathToAdd $Destination
}

Write-Host "install-wtouch.ps1 completed successfully."
