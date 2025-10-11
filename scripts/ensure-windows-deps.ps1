# Ensures that the Visual Studio Build Tools, CMake, and Ninja required by the
# Windows build preset are installed. The script relies on winget for
# unattended installation and can skip individual packages with the
# -SkipVisualStudio, -SkipCMake, or -SkipNinja switches.

[CmdletBinding()]
param(
    [switch]$SkipVisualStudio,
    [switch]$SkipCMake,
    [switch]$SkipNinja
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[+] $Message" -ForegroundColor Cyan
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Warning $Message
}

function Test-CommandExists {
    param([string]$Name)
    try {
        Get-Command -Name $Name -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Test-VisualStudioBuildTools {
    $vsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\\Installer\\vswhere.exe'
    if (-not (Test-Path -Path $vsWhere)) {
        return $false
    }

    $installationPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    return [string]::IsNullOrWhiteSpace($installationPath) -eq $false
}

function Ensure-WingetAvailable {
    if (Test-CommandExists -Name 'winget') {
        return
    }

    throw 'winget is not available on this system. Install winget from the Microsoft Store and rerun the script.'
}

function Ensure-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-WarningMessage 'winget installs may require elevation. If prompted, approve the elevation request or rerun this script from an elevated PowerShell session.'
    }
}

function Install-WithWinget {
    param(
        [Parameter(Mandatory)]
        [string]$Id,
        [string]$Override,
        [string]$DisplayName,
        [switch]$Force
    )

    Ensure-WingetAvailable
    Ensure-Admin

    $arguments = @('install', '--id', $Id, '--source', 'winget', '--accept-package-agreements', '--accept-source-agreements')
    if ($Force) {
        $arguments += '--force'
    }
    if ($Override) {
        $arguments += @('--override', $Override)
    }

    Write-Info "Installing $DisplayName via winget..."
    winget @arguments
}

if (-not $SkipVisualStudio) {
    if (Test-VisualStudioBuildTools) {
        Write-Info 'Visual Studio Build Tools with the C++ workload are already installed.'
    }
    else {
        Install-WithWinget -Id 'Microsoft.VisualStudio.2022.BuildTools' -Override '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart' -DisplayName 'Visual Studio Build Tools 2022 (Desktop development with C++)'
        if (-not (Test-VisualStudioBuildTools)) {
            Write-WarningMessage 'Required C++ components were not detected after the initial install attempt. Retrying with winget --force...'
            Install-WithWinget -Id 'Microsoft.VisualStudio.2022.BuildTools' -Override '--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --quiet --wait --norestart' -DisplayName 'Visual Studio Build Tools 2022 (Desktop development with C++)' -Force
        }

        if (-not (Test-VisualStudioBuildTools)) {
            throw 'Visual Studio Build Tools installation did not complete successfully. Please rerun the script or install the tools manually.'
        }
    }
}
else {
    Write-Info 'Skipping Visual Studio Build Tools check as requested.'
}

if (-not $SkipCMake) {
    if (Test-CommandExists -Name 'cmake') {
        Write-Info 'CMake is already available in PATH.'
    }
    else {
        Install-WithWinget -Id 'Kitware.CMake' -DisplayName 'CMake'
        if (-not (Test-CommandExists -Name 'cmake')) {
            throw 'CMake installation did not complete successfully. Please rerun the script or install CMake manually.'
        }
    }
}
else {
    Write-Info 'Skipping CMake check as requested.'
}

if (-not $SkipNinja) {
    if (Test-CommandExists -Name 'ninja') {
        Write-Info 'Ninja is already available in PATH.'
    }
    else {
        Install-WithWinget -Id 'Ninja-build.Ninja' -DisplayName 'Ninja build tool'
        if (-not (Test-CommandExists -Name 'ninja')) {
            throw 'Ninja installation did not complete successfully. Please rerun the script or install Ninja manually.'
        }
    }
}
else {
    Write-Info 'Skipping Ninja check as requested.'
}

Write-Info 'All requested dependencies are present.'
