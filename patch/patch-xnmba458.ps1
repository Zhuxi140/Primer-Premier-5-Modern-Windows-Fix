<#
.SYNOPSIS
    Applies the Primer Premier 5 / XVT 4.58 compatibility patch to xnmba458.dll.

.DESCRIPTION
    This script patches a *local copy* of xnmba458.dll that the user already owns.

    It does NOT download, bundle or redistribute any commercial binary. The only
    input is the DLL found on the user's own machine.

    What the patch does:
        At file offset 0x154F5 the original code is

            8B 95 7C FF FF FF    mov edx, [ebp-84h]
            83 7A 54 00          cmp dword ptr [edx+54h], 0

        xvtk_vobj_get_attr(0, 0x12D) can return a small non-zero value
        (observed: 0x4D8, 0x9B0) that is not a valid object pointer. The legacy
        XVT code only tests for NULL and then dereferences it, which raises
        0xC0000005 INVALID_POINTER_READ at xnmba458.dll+0x154FB.

        The patch redirects execution to a code cave at file offset 0x48EE0
        (a region of zero padding) and adds a conservative low-address guard:

            mov edx, [ebp-84h]
            cmp edx, 10000h          ; compatibility guard, NOT an XVT rule
            jb  0x1559C              ; route to the existing XVT fallback path
            cmp dword ptr [edx+54h], 0
            jmp 0x154FF

        Addresses >= 0x10000 keep the original XVT code path.

    Safety:
        * The exact SHA256 of the supported original DLL is verified first.
        * File size is verified.
        * The original machine code at the patch site is verified byte by byte.
        * The code cave region is verified to be untouched zero padding.
        * A backup (xnmba458.dll.original) is created before any write.
        * The result is re-read and verified against the expected patched SHA256.
        * Any mismatch aborts the script. There is no "best effort" mode.

.PARAMETER Path
    Path to the xnmba458.dll to patch. Defaults to .\xnmba458.dll

.PARAMETER BackupPath
    Where to store the untouched backup. Defaults to <Path>.original

.PARAMETER Force
    Overwrite an existing backup file. Without this switch, an existing backup
    that does not match the supported original SHA256 causes an abort.

.PARAMETER DryRun
    Perform every verification but do not write anything.

.PARAMETER KeepReadOnly
    Re-apply the read-only attribute after patching if the source file had it.

.EXAMPLE
    .\patch-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"

.EXAMPLE
    .\patch-xnmba458.ps1 -DryRun

.NOTES
    Verified only against one specific xnmba458.dll build (see the SHA256 below).
    This is not an official patch and not a universal fix.
#>

[CmdletBinding()]
param(
    [string]$Path = '.\xnmba458.dll',
    [string]$BackupPath,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$KeepReadOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Known-good constants for the supported build
# ---------------------------------------------------------------------------

$ExpectedSize   = 360960
$OriginalSha256 = '6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9'
$PatchedSha256  = '77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0'

# Patch site: 0x154F5, 10 bytes
$EntryOffset        = 0x154F5
$EntryOriginalBytes = '8B957CFFFFFF837A5400'
$EntryPatchedBytes  = 'E9E63903009090909090'

# Code cave: 0x48EE0, 27 bytes of zero padding in the original file
$CaveOffset        = 0x48EE0
$CaveOriginalBytes = ('00' * 27)
$CavePatchedBytes  = '8B957CFFFFFF81FA000001000F82AAC6FCFF837A5400E904C6FCFF'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Convert-HexToBytes {
    param([Parameter(Mandatory)][string]$Hex)
    $clean = $Hex -replace '[^0-9A-Fa-f]', ''
    if ($clean.Length % 2 -ne 0) { throw "Malformed hex string: $Hex" }
    $out = New-Object 'byte[]' ($clean.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) {
        $out[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
    }
    return $out
}

function Format-Hex {
    param([byte[]]$Bytes)
    return (($Bytes | ForEach-Object { $_.ToString('X2') }) -join ' ')
}

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

function Test-ByteRange {
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][byte[]]$Expected
    )
    if ($Offset + $Expected.Length -gt $Data.Length) { return $false }
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Data[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

function Write-BytesAt {
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [Parameter(Mandatory)][int]$Offset,
        [Parameter(Mandatory)][byte[]]$Value
    )
    [Array]::Copy($Value, 0, $Data, $Offset, $Value.Length)
}

function Fail {
    param([string]$Message)
    Write-Host ''
    Write-Host "  ABORTED: $Message" -ForegroundColor Red
    Write-Host '  No changes were made.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Primer Premier 5 / XVT 4.58 - xnmba458.dll compatibility patcher' -ForegroundColor Cyan
Write-Host '========================================================================'
Write-Host ''

# ---------------------------------------------------------------------------
# 1. Resolve the target file
# ---------------------------------------------------------------------------

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Fail "File not found: $Path"
}

$dll = (Resolve-Path -LiteralPath $Path).ProviderPath
if (-not $BackupPath) { $BackupPath = "$dll.original" }
$backupFull = [System.IO.Path]::GetFullPath($BackupPath)

Write-Host "  Target : $dll"
Write-Host "  Backup : $backupFull"
Write-Host ''

# ---------------------------------------------------------------------------
# 2. File size
# ---------------------------------------------------------------------------

$info = Get-Item -LiteralPath $dll
$size = $info.Length

if ($size -ne $ExpectedSize) {
    Fail ("Unexpected file size. Expected $ExpectedSize bytes, found $size bytes. " +
          'Unsupported xnmba458.dll version.')
}
Write-Host ("  [OK] size            {0} bytes" -f $size) -ForegroundColor Green

# ---------------------------------------------------------------------------
# 3. SHA256
# ---------------------------------------------------------------------------

$sha = Get-Sha256Hex -FilePath $dll
Write-Host "  [..] sha256          $sha"

if ($sha -eq $PatchedSha256) {
    Write-Host ''
    Write-Host '  This DLL is already patched. Nothing to do.' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

if ($sha -ne $OriginalSha256) {
    Write-Host ''
    Write-Host '  SHA256 mismatch.' -ForegroundColor Red
    Write-Host "    expected : $OriginalSha256"
    Write-Host "    actual   : $sha"
    Write-Host ''
    Write-Host '  Unsupported xnmba458.dll version. Patch aborted.' -ForegroundColor Red
    Write-Host '  The patch only supports the exact build identified by the SHA256 above.' -ForegroundColor Red
    Write-Host '  Please open an issue and attach your DLL version, size and SHA256.' -ForegroundColor Red
    Write-Host '  Do NOT force the patch onto an unknown build.' -ForegroundColor Red
    Write-Host ''
    exit 2
}
Write-Host '  [OK] sha256          matches the supported original build' -ForegroundColor Green

# ---------------------------------------------------------------------------
# 4. Read the file and verify the original machine code
# ---------------------------------------------------------------------------

$data = [System.IO.File]::ReadAllBytes($dll)

$entryOriginal = Convert-HexToBytes $EntryOriginalBytes
if (-not (Test-ByteRange -Data $data -Offset $EntryOffset -Expected $entryOriginal)) {
    $actual = $data[$EntryOffset..($EntryOffset + $entryOriginal.Length - 1)]
    $msg = "Machine code at 0x{0:X} does not match the expected original bytes.`n" -f $EntryOffset
    $msg += "         expected : {0}`n" -f (Format-Hex $entryOriginal)
    $msg += "         actual   : {0}" -f (Format-Hex $actual)
    Fail $msg
}
Write-Host ("  [OK] code @ 0x{0:X}  {1}" -f $EntryOffset, (Format-Hex $entryOriginal)) -ForegroundColor Green

$caveOriginal = Convert-HexToBytes $CaveOriginalBytes
if (-not (Test-ByteRange -Data $data -Offset $CaveOffset -Expected $caveOriginal)) {
    $actual = $data[$CaveOffset..($CaveOffset + $caveOriginal.Length - 1)]
    $msg = "Code cave region at 0x{0:X} is not the expected zero padding.`n" -f $CaveOffset
    $msg += "         actual   : {0}" -f (Format-Hex $actual)
    Fail $msg
}
Write-Host ("  [OK] cave @ 0x{0:X}  {1} zero bytes free" -f $CaveOffset, $caveOriginal.Length) -ForegroundColor Green
Write-Host ''

# ---------------------------------------------------------------------------
# 5. Backup
# ---------------------------------------------------------------------------

$isReadOnly = ($info.Attributes -band [System.IO.FileAttributes]::ReadOnly) -ne 0

if (Test-Path -LiteralPath $backupFull -PathType Leaf) {
    $backupSha = Get-Sha256Hex -FilePath $backupFull
    if ($backupSha -eq $OriginalSha256) {
        Write-Host '  [OK] backup          existing backup already matches the original build' -ForegroundColor Green
    }
    elseif ($Force) {
        Write-Host '  [!!] backup          overwriting existing backup because -Force was used' -ForegroundColor Yellow
        [System.IO.File]::WriteAllBytes($backupFull, $data)
        Write-Host '  [OK] backup          written' -ForegroundColor Green
    }
    else {
        $msg = "A backup already exists at $backupFull but its SHA256 does not match the`n"
        $msg += '         supported original build. Refusing to overwrite it. Inspect it, or`n'
        $msg += '         re-run with -Force if you are certain it is disposable.'
        Fail $msg
    }
}
else {
    [System.IO.File]::WriteAllBytes($backupFull, $data)
    $backupSha = Get-Sha256Hex -FilePath $backupFull
    if ($backupSha -ne $OriginalSha256) {
        Fail 'Backup verification failed immediately after writing. Aborting.'
    }
    Write-Host "  [OK] backup          created -> $backupFull" -ForegroundColor Green
}
Write-Host ''

# ---------------------------------------------------------------------------
# 6. Apply the patch
# ---------------------------------------------------------------------------

if ($DryRun) {
    Write-Host '  [--] dry run         all checks passed, no bytes written' -ForegroundColor Yellow
    Write-Host ''
    exit 0
}

if ($isReadOnly) {
    Write-Host '  [..] attributes      clearing read-only so the file can be written'
    Set-ItemProperty -LiteralPath $dll -Name IsReadOnly -Value $false
}

$entryPatched = Convert-HexToBytes $EntryPatchedBytes
$cavePatched  = Convert-HexToBytes $CavePatchedBytes

Write-BytesAt -Data $data -Offset $EntryOffset -Value $entryPatched
Write-BytesAt -Data $data -Offset $CaveOffset  -Value $cavePatched

[System.IO.File]::WriteAllBytes($dll, $data)
Write-Host '  [OK] patch           bytes written' -ForegroundColor Green

if ($KeepReadOnly -and $isReadOnly) {
    Set-ItemProperty -LiteralPath $dll -Name IsReadOnly -Value $true
    Write-Host '  [OK] attributes      read-only restored'
}
Write-Host ''

# ---------------------------------------------------------------------------
# 7. Re-verify the patched file
# ---------------------------------------------------------------------------

$verify = [System.IO.File]::ReadAllBytes($dll)

if (-not (Test-ByteRange -Data $verify -Offset $EntryOffset -Expected $entryPatched)) {
    Fail 'Post-patch verification failed at the patch site.'
}
Write-Host ("  [OK] verify @ 0x{0:X}  {1}" -f $EntryOffset, (Format-Hex $entryPatched)) -ForegroundColor Green

if (-not (Test-ByteRange -Data $verify -Offset $CaveOffset -Expected $cavePatched)) {
    Fail 'Post-patch verification failed inside the code cave.'
}
Write-Host ("  [OK] verify @ 0x{0:X}  {1}" -f $CaveOffset, (Format-Hex $cavePatched)) -ForegroundColor Green

$finalSha = Get-Sha256Hex -FilePath $dll
Write-Host "  [..] sha256          $finalSha"

if ($finalSha -ne $PatchedSha256) {
    Write-Host ''
    Write-Host '  Final SHA256 does not match the expected patched build.' -ForegroundColor Red
    Write-Host "    expected : $PatchedSha256"
    Write-Host "    actual   : $finalSha"
    Write-Host ''
    Write-Host '  The byte-level checks passed but the whole-file hash differs, which' -ForegroundColor Red
    Write-Host '  should be impossible for this build. Restore from the backup and' -ForegroundColor Red
    Write-Host '  report this as an issue.' -ForegroundColor Red
    Write-Host ''
    exit 3
}
Write-Host '  [OK] sha256          matches the expected patched build' -ForegroundColor Green
Write-Host ''

# ---------------------------------------------------------------------------
# 8. Summary
# ---------------------------------------------------------------------------

Write-Host 'Patch applied successfully.' -ForegroundColor Green
Write-Host ''
Write-Host "  original sha256 : $OriginalSha256"
Write-Host "  patched  sha256 : $PatchedSha256"
Write-Host "  backup          : $backupFull"
Write-Host ''
Write-Host '  Reminder: this patch only addresses the xnmba458.dll access violation.' -ForegroundColor Yellow
Write-Host '  A separate XVT wprnt.c / Print Spooler error may still occur on some' -ForegroundColor Yellow
Write-Host '  systems. See docs/troubleshooting.md.' -ForegroundColor Yellow
Write-Host ''
Write-Host "  To undo:  .\restore-xnmba458.ps1 -Path `"$dll`"" -ForegroundColor Cyan
Write-Host ''
