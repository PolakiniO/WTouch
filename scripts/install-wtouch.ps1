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
            $candidate = Join-Path -Path $scriptRoot -ChildPath '..\build\Release\wtouch.exe'
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).ProviderPath
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

    $targetName = if ($Variant -eq 'cpp') { 'wtouch-cpp.exe' } else { 'wtouch-c.exe' }
    $destinationPath = Join-Path -Path $Destination -ChildPath $targetName

    try {
        Copy-Item -LiteralPath $resolvedBinary -Destination $destinationPath -Force:$Force.IsPresent
        Write-Host "Copied '$resolvedBinary' to '$destinationPath'."
    } catch {
        Write-Error "Failed to copy '$resolvedBinary' to '$destinationPath': $_"
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
    }

    $segments = @($current -split ';' | Where-Object { $_ -ne '' })
    if ($segments -contains $PathToAdd) {
        Write-Host "Destination already present in the user PATH."
        return
    }

    $segments += $PathToAdd
    $newValue = ($segments -join ';')
    [Environment]::SetEnvironmentVariable('Path', $newValue, 'User')

    $processPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    if (-not $processPath) {
        $processPath = ''
    }
    $processSegments = @($processPath -split ';' | Where-Object { $_ -ne '' })
    if ($processSegments -notcontains $PathToAdd) {
        $processSegments += $PathToAdd
        [Environment]::SetEnvironmentVariable('Path', ($processSegments -join ';'), 'Process')
    }

    Write-Host "Added '$PathToAdd' to the user PATH. Open a new shell to use it everywhere."
}

if ($SkipPathUpdate) {
    Write-Verbose "Skipping PATH update step because -SkipPathUpdate was provided."
} else {
    Add-ToUserPath -PathToAdd $Destination
}

Write-Host "install-wtouch.ps1 completed successfully."
