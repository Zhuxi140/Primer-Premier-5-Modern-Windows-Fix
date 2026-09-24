# Troubleshooting

> **Language / 语言:** **English** · [**中文版 → troubleshooting.zh-CN.md**](troubleshooting.zh-CN.md)
>
> 本文档的中文版位于 [`docs/troubleshooting.zh-CN.md`](troubleshooting.zh-CN.md)。
> 英文版为技术内容的原始记录，中文版为对应译文；两者内容一一对应。

Common startup problems with Primer Premier 5 on modern Windows, and what is
known about each of them.

---

## 1. "Primer Premier 5 crashes immediately after launch" (C0000005)

Check the Windows Event Log. If you see:

```text
Faulting module name: xnmba458.dll
Exception code:       0xc0000005
Fault offset:         0x000154fb
```

then this is **Problem B**, and the patch in this repository targets it.

First verify your DLL:

```powershell
Get-FileHash .\xnmba458.dll -Algorithm SHA256
(Get-Item .\xnmba458.dll).Length
```

Expected for the supported build:

```text
Length : 360960
SHA256 : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
```

If it matches, run `patch-xnmba458.ps1`. If it does not match, **do not patch** —
open an issue with your size, version and hash instead.

---

## 2. "XVT Toolkit Error / wprnt.c line 763" (Problem A)

Full message:

```text
ERROR: MSG 0x0073c35f [CAT 7/3 STD 50015]

Category:
Underlying system generated error [Toolkit error]

Function:
xvt_vobj_get_attr
xvt_app_create

File:
wprnt.c

Line:
763
```

### Status

**Not fixed by this patch.** This is a separate compatibility problem between the
legacy XVT Runtime's print initialisation and the modern Windows Print Spooler.

### Workaround

Stop the Print Spooler before launching Primer Premier 5:

```powershell
Stop-Service Spooler -Force
```

Then start the application. The Toolkit error should not appear and the
application should proceed to the next stage of initialisation.

Restart the service afterwards if you need to print from other applications:

```powershell
Start-Service Spooler
```

You need an elevated PowerShell session to control the service.

### Things that were checked and are *not* the cause

* The default printer is configured (`Microsoft Print to PDF` was set on the test
  machine).
* Multiple printers exist.
* `ERRCODES.TXT` is missing. Creating it only makes the error message *more
  specific*; it does not fix the failure.
* Missing `MSVCIRT.dll` / `WINMM.dll` / `WINSPOOL.DRV` / `WINHTTP.dll` /
  `IppCommon.dll`. These resolve to `NAME NOT FOUND` in the application folder but
  load correctly from `C:\Windows\SysWOW64\`.

### ⚠ Do not download DLLs from third-party "DLL fix" websites

Those sites are not a solution here and installing random DLLs into your system
directory is a genuine security risk. The required system libraries are already
present.

---

## 3. "Some of the required files have been missing or corrupted. Please reinstall the application."

This message can appear alongside the Toolkit error above and is **misleading**.
It is not evidence that your installation is damaged. See
[`technical-analysis.md` §4](technical-analysis.md#4-ruled-out-missing-msvcirtdll-and-friends).

Reinstalling the application does not fix either Problem A or Problem B.

---

## 4. The patcher refuses to run

```text
Unsupported xnmba458.dll version. Patch aborted.
```

This is intentional. The patch verifies:

1. file size is exactly `360960` bytes,
2. SHA256 is exactly `6FF40C2B…4BBF9`,
3. the original machine code at `0x154F5` is `8B 95 7C FF FF FF 83 7A 54 00`,
4. the code cave region at `0x48EE0` is untouched zero padding.

If any check fails, the script stops without writing anything. There is no
"best effort" mode and there will not be one — patching an unknown build at a
fixed offset risks corrupting a file that may have an unrelated layout.

**What to do instead:** open an issue with:

```text
xnmba458.dll size
xnmba458.dll version
xnmba458.dll SHA256
Faulting module / exception code / fault offset from the Event Log
```

A separate patch profile can then be developed for that build.

---

## 5. "This DLL is already patched"

The file's SHA256 already equals:

```text
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

Nothing to do. If the application still crashes, the cause is something else —
check the Event Log again.

---

## 6. I want to undo the patch

```powershell
.\restore-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

The script verifies `xnmba458.dll.original` against the known original SHA256
before copying anything back, then verifies the restored file.

If the backup is missing or has the wrong hash, the script refuses to act. In that
case, restore the DLL from your own installation media or backup.

---

## 7. The application starts but behaves oddly

This patch changes 33 bytes (across two regions spanning 37 bytes) in one runtime
module and nothing else. It does not
alter Primer's own code, data files, licence handling or configuration.

If you observe unrelated instability:

* confirm the patched DLL hash matches the expected patched SHA256,
* confirm you did not also replace other DLLs in the folder,
* check whether the Print Spooler is running (Problem A may still apply),
* open an issue describing the behaviour.

---

## 8. Antivirus or SmartScreen flags the scripts

The scripts are plain, readable PowerShell text. They:

* compute a SHA256 hash,
* compare bytes at two fixed file offsets,
* copy a file,
* write bytes to two regions of a file.

They do not download anything, do not contact the network, do not modify the
registry, and do not touch any file other than the DLL you point them at.

You are encouraged to read them before running them:
[`patch/patch-xnmba458.ps1`](../patch/patch-xnmba458.ps1),
[`patch/restore-xnmba458.ps1`](../patch/restore-xnmba458.ps1).

If your execution policy blocks scripts, run once with:

```powershell
powershell -ExecutionPolicy Bypass -File .\patch-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

---

## 9. Known issue: patched DLL but still crashes

Verify the patch actually applied:

```powershell
Get-FileHash "C:\Primer Premier 5\xnmba458.dll" -Algorithm SHA256
```

Expected:

```text
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

If that matches and the application still crashes, the fault is somewhere else.
Capture a dump (see [`crash-analysis.md`](crash-analysis.md)) and open an issue.
Include the new fault offset — a different offset means a different problem, and
this patch deliberately does not touch code paths that have not been proven to
fault.
