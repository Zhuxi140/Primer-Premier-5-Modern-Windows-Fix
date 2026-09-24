<#
.SYNOPSIS
    Restores the original xnmba458.dll from the backup created by patch-xnmba458.ps1.

.DESCRIPTION
    Reads <Path>.original, verifies that it is the supported original build by
    SHA256, copies it over the patched DLL and verifies the restored file again.

    Nothing is written unless the backup hash matches exactly.

.PARAMETER Path
    Path to the xnmba458.dll that should be restored. Defaults to .\xnmba458.dll

.PARAMETER BackupPath
    Backup to restore from. Defaults to <Path>.original

.PARAMETER DryRun
    Verify everything but do not write.

.PARAMETER KeepReadOnly
    Re-apply the read-only attribute after restoring if the source file had it.

.EXAMPLE
    .\restore-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
#>

[CmdletBinding()]
param(
    [string]$Path = '.\xnmba458.dll',
    [string]$BackupPath,
    [switch]$DryRun,
    [switch]$KeepReadOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ExpectedSize   = 360960
$OriginalSha256 = '6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9'
$PatchedSha256  = '77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0'

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$FilePath)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        try   { $hash = $sha.ComputeHash($stream) }
        finally { $stream.Dispose() }
    }
    finally { $sha.Dispose() }
    return ([BitConverter]::ToString($hash) -replace '-', '')
}

function Fail {
    param(
        [string]$Message,
        [switch]$AfterWrite
    )
    Write-Host ''
    Write-Host "  ABORTED: $Message" -ForegroundColor Red
    if ($AfterWrite) {
        Write-Host '  The target file was already overwritten before this failure.' -ForegroundColor Red
        Write-Host "  Copy your own backup over it manually, then verify the SHA256." -ForegroundColor Red
    }
    else {
        Write-Host '  No changes were made.' -ForegroundColor Red
    }
    Write-Host ''
    exit 1
}

Write-Host ''
Write-Host 'Primer Premier 5 / XVT 4.58 - xnmba458.dll restore' -ForegroundColor Cyan
Write-Host '========================================================================'
Write-Host ''

if (-not $BackupPath) {
    if (Test-Path -LiteralPath $Path) {
        $BackupPath = "$((Resolve-Path -LiteralPath $Path).ProviderPath).original"
    }
    else {
        $BackupPath = "$Path.original"
    }
}
$backupFull = [System.IO.Path]::GetFullPath($BackupPath)

if (-not (Test-Path -LiteralPath $backupFull -PathType Leaf)) {
    Fail "Backup file not found: $backupFull"
}

Write-Host "  Backup : $backupFull"

$backupInfo = Get-Item -LiteralPath $backupFull
if ($backupInfo.Length -ne $ExpectedSize) {
    Fail ("Backup has an unexpected size. Expected $ExpectedSize bytes, found " +
          "$($backupInfo.Length) bytes. Refusing to restore an unknown file.")
}

$backupSha = Get-Sha256Hex -FilePath $backupFull
Write-Host "  [..] sha256  $backupSha"

if ($backupSha -ne $OriginalSha256) {
    Write-Host ''
    Write-Host '  The backup does not match the supported original build.' -ForegroundColor Red
    Write-Host "    expected : $OriginalSha256"
    Write-Host "    actual   : $backupSha"
    Write-Host ''
    Write-Host '  Refusing to restore. Verify that this really is your untouched DLL.' -ForegroundColor Red
    Write-Host ''
    exit 2
}
Write-Host '  [OK] backup is the supported original build' -ForegroundColor Green
Write-Host ''

$targetFull = [System.IO.Path]::GetFullPath($Path)
$isReadOnly = $false

if (Test-Path -LiteralPath $targetFull -PathType Leaf) {
    $targetInfo = Get-Item -LiteralPath $targetFull
    $isReadOnly = ($targetInfo.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0
    $targetSha = Get-Sha256Hex -FilePath $targetFull

    if ($targetSha -eq $OriginalSha256) {
        Write-Host '  The target file is already the original build. Nothing to do.' -ForegroundColor Yellow
        Write-Host ''
        exit 0
    }

    if ($targetSha -ne $PatchedSha256) {
        Write-Host "  [!!] target sha256 $targetSha" -ForegroundColor Yellow
        Write-Host '  The target is neither the original nor the known patched build.' -ForegroundColor Yellow
        Write-Host '  It will still be replaced by the verified backup.' -ForegroundColor Yellow
        Write-Host ''
    }
}
else {
    Write-Host "  [!!] target does not exist, it will be created: $targetFull" -ForegroundColor Yellow
    Write-Host ''
}

if ($DryRun) {
    Write-Host '  [--] dry run  all checks passed, no bytes written' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

if ($isReadOnly) {
    Write-Host '  [..] attributes  clearing read-only so the file can be written'
    Set-ItemProperty -LiteralPath $targetFull -Name IsReadOnly -Value $false
}

Copy-Item -LiteralPath $backupFull -Destination $targetFull -Force
Write-Host '  [OK] restored' -ForegroundColor Green

if ($KeepReadOnly -and $isReadOnly) {
    Set-ItemProperty -LiteralPath $targetFull -Name IsReadOnly -Value $true
    Write-Host '  [OK] attributes  read-only restored'
}

$finalSha = Get-Sha256Hex -FilePath $targetFull
Write-Host "  [..] sha256  $finalSha"

if ($finalSha -ne $OriginalSha256) {
    Fail 'Verification after restore failed. The file does not match the original build.' -AfterWrite
}

Write-Host '  [OK] verification passed' -ForegroundColor Green
Write-Host ''
Write-Host 'Restore complete.' -ForegroundColor Green
Write-Host "  original sha256 : $OriginalSha256"
Write-Host ''
