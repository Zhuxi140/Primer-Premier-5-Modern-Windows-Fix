# Primer Premier 5 / XVT 4.58 — Modern Windows Compatibility Fix

A reproducible, verifiable compatibility patch that fixes a startup crash in
**Primer Premier 5.00** on modern 64-bit Windows, caused by the legacy **XVT
Runtime 4.58** shipped as `xnmba458.dll`.

This repository distributes **only original patch scripts, patch data and
technical documentation**. It does **not** contain, host or redistribute
`xnmba458.dll`, `Primer Premier 5.exe`, the Primer Premier installer, or any
other commercial binary. You supply the DLL from your own licensed copy.

> **Scope:** this patch has currently been verified only against the specific
> `xnmba458.dll` build identified by the SHA256 listed below. It is not an
> official patch, it is not endorsed by the vendor, and it is not a universal
> Windows 10/11 fix. See [Limitations](#limitations).

---

## The two problems

Primer Premier 5 on modern Windows suffers from **two independent** compatibility
problems. They are unrelated and must not be confused.

| | Problem A — Print Spooler | Problem B — Access Violation |
|---|---|---|
| Symptom | XVT Toolkit error at startup | Immediate crash to desktop |
| Module | XVT runtime print code | `xnmba458.dll` |
| Location | `wprnt.c` line 763 | `xnmba458.dll+0x154FB` |
| Function | `xvt_vobj_get_attr` / `xvt_app_create` | `xvtwi_Init` |
| Exception | Toolkit error `MSG 0x0073c35f [CAT 7/3 STD 50015]` | `0xC0000005` `INVALID_POINTER_READ` |
| Status | **Workaround only** (stop the Print Spooler) | **Fixed by this patch** |

This repository patches **Problem B only**. Problem A is documented in
[`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## The crash (Problem B)

After the Print Spooler issue is bypassed, Primer Premier 5 still crashes
immediately. Windows Event Log reports:

```text
Faulting module:  xnmba458.dll
Version:          4.58.0.0
Exception code:   0xc0000005
Fault offset:     0x000154fb
```

WinDbg analysis of a LocalDump shows an invalid pointer read at
`xnmba458!xvtwi_Init+0x4be`:

```asm
1c0154f5  mov  edx, [ebp-84h]        ; return value of xvtk_vobj_get_attr(0, 0x12D)
1c0154fb  cmp  dword ptr [edx+54h], 0   <-- fault
```

`xvtk_vobj_get_attr(0, 0x12D)` can return a **small non-zero value** that is not
a valid object pointer. Values observed during live debugging and in crash dumps:

```text
0x4D8
0x9B0
```

The legacy XVT code only tests for `NULL`. Since `0x4D8 != 0`, the check passes,
the value is treated as a pointer, and the dereference of `[edx+0x54]` faults.

---

## The fix

Execution is redirected from `0x154F5` into a code cave at `0x48EE0` (a region of
zero padding present in the original binary). The cave re-implements the original
two instructions and adds a conservative low-address guard:

```asm
mov  edx, [ebp-84h]
cmp  edx, 10000h            ; compatibility guard used by this patch
jb   0x1559C                ; route to the existing XVT fallback path
cmp  dword ptr [edx+54h], 0
jmp  0x154FF
```

* Object addresses `>= 0x10000` keep the **original XVT code path**.
* Obviously invalid low addresses are routed to the **fallback path that already
  exists in XVT** — no new behaviour is invented and the XVT initialisation
  sequence is not removed.

### What `0x10000` is — and is not

`0x10000` is a **conservative low-address guard used by this patch**. It rejects
obviously invalid low addresses before the pointer dereference.

It is **not** an XVT-defined semantic boundary. There is currently no evidence
that XVT officially defines pointers below `0x10000` as invalid. Do not describe
this patch as implementing an official XVT rule.

### Byte-level patch data

Only **33 bytes** are modified, in exactly two regions.

```text
File offset 0x154F5  (10 bytes)
  original : 8B 95 7C FF FF FF 83 7A 54 00
  patched  : E9 E6 39 03 00 90 90 90 90 90

File offset 0x48EE0  (27 bytes, zero padding in the original)
  original : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  patched  : 8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00 E9 04 C6 FC FF
```

---

## Supported DLL

```text
File name : xnmba458.dll
Size      : 360960 bytes
Version   : 4.58.0.0
Timestamp : 1998-05-13
Arch     : x86 (i386)
ImageBase : 0x1C000000
```

| | SHA256 |
|---|---|
| **Original (required input)** | `6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9` |
| **Patched (expected output)** | `77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0` |

The patch script **refuses to run** if your DLL does not match the original
SHA256 exactly.

---

## Usage

1. Locate your Primer Premier 5 installation directory.
2. Find `xnmba458.dll` in it.
3. Download [`patch/patch-xnmba458.ps1`](patch/patch-xnmba458.ps1).
4. Close Primer Premier 5.
5. Run the patcher against your DLL:

   ```powershell
   .\patch-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
   ```

6. The script verifies size, SHA256 and the original machine code before making
   any change.
7. A backup is created automatically as `xnmba458.dll.original`.
8. The result is re-verified against the expected patched SHA256.
9. Start Primer Premier 5.

Useful switches:

```powershell
-DryRun         # run every check, write nothing
-Force          # overwrite an existing backup file
-KeepReadOnly   # restore the read-only attribute after patching
```

### Undo

```powershell
.\restore-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

The restore script verifies the backup hash before copying anything back, then
verifies the restored file.

---

## Safety properties of the patcher

The script aborts — never proceeds on a best-effort basis — when any of these
checks fail:

1. File exists.
2. File size is exactly `360960` bytes.
3. SHA256 matches the supported original build.
4. Original machine code at `0x154F5` matches `8B 95 7C FF FF FF 83 7A 54 00`.
5. Code cave region at `0x48EE0` is untouched zero padding.
6. A valid backup exists (or is created) before any write.
7. After patching, the bytes at both sites are re-read and compared.
8. After patching, the whole-file SHA256 matches `77C7C009…62BE0`.

If the DLL is already patched, the script reports that and exits cleanly. If the
DLL is an unknown build:

```text
Unsupported xnmba458.dll version. Patch aborted.
```

Unknown builds are **not** patched by RVA. Please
[open an issue](../../issues/new/choose) with your DLL size, version, SHA256 and
crash signature instead.

---

## Known issue not covered by this patch

Some systems still encounter an XVT error while the Windows Print Spooler service
is running:

```text
ERROR: MSG 0x0073c35f [CAT 7/3 STD 50015]
Category: Underlying system generated error [Toolkit error]
Function: xvt_vobj_get_attr / xvt_app_create
File:     wprnt.c
Line:     763
```

This is a **separate issue** from the `xnmba458.dll` access violation. Stopping
the Print Spooler before launching Primer Premier 5 bypasses it:

```powershell
Stop-Service Spooler -Force
```

A permanent fix for this layer has not been developed. See
[`docs/troubleshooting.md`](docs/troubleshooting.md).

---

## Limitations

* Verified against **one** `xnmba458.dll` build only (SHA256 above).
* Not tested across all Windows 10/11 builds. See
  [`docs/technical-analysis.md`](docs/technical-analysis.md) for the test matrix.
* Not an official patch. Not affiliated with or endorsed by the vendor.
* Does not fix the Print Spooler / `wprnt.c` issue.
* Does not remove, replace or bypass any licensing, activation or protection
  mechanism. This project contains no crack, keygen or licence-bypass material
  and none will be accepted.
* The `0x10000` threshold is a pragmatic guard, not a documented XVT constant.

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/technical-analysis.md`](docs/technical-analysis.md) | Full analysis: dump, WinDbg, disassembly, PE layout, patch design, verification |
| [`docs/crash-analysis.md`](docs/crash-analysis.md) | Crash signature reference and how to capture your own dump |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Print Spooler / `wprnt.c` issue and other startup problems |

---

## Legal

`xnmba458.dll` is a component of the original XVT Runtime shipped with Primer
Premier. This project modifies a few bytes of a file **the user already owns**,
on the user's own machine. No commercial binary is redistributed here.

The [LICENSE](LICENSE) covers only the original scripts and documentation in this
repository. It makes no claim over Primer Premier, XVT, or any of their
components or trademarks. All trademarks belong to their respective owners.

---

## Keywords

`Primer Premier 5` · `Primer Premier 5.0` · `xnmba458.dll` · `XVT 4.58` ·
`0xc0000005` · `xvtwi_Init` · `xvt_vobj_get_attr` · `wprnt.c` · `Windows 10` ·
`Windows 11` · `crash fix` · `compatibility patch`
