param(
    [Parameter(Mandatory = $true)]
    [string]$Executable
)

$ErrorActionPreference = 'Stop'

function Invoke-Touch {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    & $Executable @Arguments
    $exitCode = $LASTEXITCODE
    return $exitCode
}

$testRoot = Join-Path -Path $PSScriptRoot -ChildPath 'tmp'
if (Test-Path $testRoot) {
    Remove-Item -Path $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $testRoot | Out-Null

# Test 1: Create a missing file
$createPath = Join-Path $testRoot 'created.txt'
$code = Invoke-Touch @($createPath)
if ($code -ne 0) {
    throw "Creation command failed with exit code $code"
}
if (-not (Test-Path $createPath)) {
    throw 'Creation test failed: file was not created.'
}

# Test 2: Update only access time
$accessPath = Join-Path $testRoot 'access.txt'
Set-Content -Path $accessPath -Value 'sample'
$initialInfo = Get-Item $accessPath
Start-Sleep -Milliseconds 1100
$code = Invoke-Touch @('-a', $accessPath)
if ($code -ne 0) {
    throw "Access update command failed with exit code $code"
}
$updatedInfo = Get-Item $accessPath
if ($updatedInfo.LastAccessTime -le $initialInfo.LastAccessTime) {
    throw 'Access time was not updated.'
}
if ($updatedInfo.LastWriteTime -ne $initialInfo.LastWriteTime) {
    throw 'Write time changed unexpectedly when using -a.'
}

# Test 3: Specific date via -d
$specificPath = Join-Path $testRoot 'specific.txt'
$code = Invoke-Touch @('-d', '2023-02-01 03:04:05', $specificPath)
if ($code -ne 0) {
    throw "Specific date command failed with exit code $code"
}
$specificInfo = Get-Item $specificPath
if ($specificInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss') -ne '2023-02-01 03:04:05') {
    throw 'Write time did not match expected value for -d.'
}
if ($specificInfo.LastAccessTime.ToString('yyyy-MM-dd HH:mm:ss') -ne '2023-02-01 03:04:05') {
    throw 'Access time did not match expected value for -d.'
}

# Test 4: --no-create should fail for missing file
$missingPath = Join-Path $testRoot 'missing.txt'
$code = Invoke-Touch @('--no-create', $missingPath)
if ($code -eq 0) {
    throw '--no-create did not fail for missing file.'
}
if (Test-Path $missingPath) {
    throw 'Missing file was unexpectedly created with --no-create.'
}

# Test 5: Copy timestamps from reference file
$referencePath = Join-Path $testRoot 'reference.txt'
Set-Content -Path $referencePath -Value 'ref'
$refAccess = Get-Date '2022-01-02T03:04:05'
$refWrite = Get-Date '2022-06-07T08:09:10'
[System.IO.File]::SetLastAccessTime($referencePath, $refAccess) | Out-Null
[System.IO.File]::SetLastWriteTime($referencePath, $refWrite) | Out-Null
$targetPath = Join-Path $testRoot 'target.txt'
Set-Content -Path $targetPath -Value 'target'
$code = Invoke-Touch @('-r', $referencePath, $targetPath)
if ($code -ne 0) {
    throw "Reference command failed with exit code $code"
}
$targetInfo = Get-Item $targetPath
if ($targetInfo.LastAccessTime -ne $refAccess) {
    throw 'Reference access time mismatch.'
}
if ($targetInfo.LastWriteTime -ne $refWrite) {
    throw 'Reference write time mismatch.'
}

# Test 6: Touch a directory
$directoryPath = Join-Path $testRoot 'dir'
New-Item -ItemType Directory -Path $directoryPath | Out-Null
$dirInfoBefore = Get-Item $directoryPath
Start-Sleep -Milliseconds 1100
$code = Invoke-Touch @($directoryPath)
if ($code -ne 0) {
    throw "Directory command failed with exit code $code"
}
$dirInfoAfter = Get-Item $directoryPath
if ($dirInfoAfter.LastWriteTime -le $dirInfoBefore.LastWriteTime) {
    throw 'Directory write time was not updated.'
}

Exit 0
