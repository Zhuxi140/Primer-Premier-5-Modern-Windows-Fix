# Technical Analysis — xnmba458.dll / XVT 4.58 startup crash

This document records the full investigation: the environment, the original
failure, the dump analysis, the disassembly, the patch design, and the
verification that was performed.

Everything here is either directly observed evidence or clearly labelled as
inference. Nothing speculative is presented as confirmed fact.

---

## 1. Environment

```text
Target software : Primer Premier 5.00
Key module      : xnmba458.dll  (XVT Runtime 4.58.0.0)
Module arch     : x86
Test OS         : Windows, build 26200, 64-bit
Debugger        : WinDbg 10.0.29617.1000 X86
```

The Windows product string on the test machine still reports the legacy
compatibility values:

```text
Windows 10 Home China
WindowsVersion: 2009
```

while the actual build is `26200`. The point is simply that the test environment
is **far newer** than the Windows 98-era environment Primer Premier 5 and XVT
4.58 were designed for. Build numbers are recorded because they matter for
reproducibility, not because they indicate anything about the vendor.

---

## 2. Initial failure

Launching `Primer Premier 5.exe` produced an XVT Toolkit error:

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

Sometimes accompanied by:

```text
Some of the required files have been missing or corrupted.
Please reinstall the application.
```

This message is misleading. The initial hypotheses it suggests — missing runtime
libraries, missing DLLs, a corrupt installer, Windows compatibility settings, the
printing subsystem, or a general XVT/modern-Windows incompatibility — were
investigated one by one. Two of them were **ruled out** with evidence (§4, §5),
and the remaining two turned out to be **two separate problems** (§6, §7).

---

## 3. Installation directory survey

The Primer Premier 5 setup directory contains:

```text
Primer Premier 5.exe
Primer5.hlp

unmpr458.dll
xnmba458.dll
xnmhn458.dll
xnmr70mt.dll
xnmte458.dll

_ISREG32.DLL
_DEISREG.ISR
DeIsL1.isu
```

plus resource directories:

```text
data\
waves\
```

There is no MSI/CAB installation structure. `Read Me.txt` reports
`Primer Premier 5.00` and still contains Windows 98-era installation
instructions. This confirms the software and its runtime come from a very early
Windows software environment.

---

## 4. Ruled out: "missing MSVCIRT.dll" and friends

Process Monitor showed the application probing for:

```text
MSVCIRT.dll
WINMM.dll
WINSPOOL.DRV
WINHTTP.dll
IppCommon.dll
...
```

Some of these first resolve to `NAME NOT FOUND` in the application directory, but
then load successfully from:

```text
C:\Windows\SysWOW64\
```

For example `C:\Windows\SysWOW64\MSVCIRT.dll` exists and loads successfully.

**Conclusion:** a missing `MSVCIRT.dll` is *not* the root cause of this crash.

**Consequence for users:** do not download random DLLs from third-party DLL
websites. They are not the problem, and they introduce real risk.

---

## 5. Ruled out: ERRCODES.TXT

Process Monitor showed many lookups of:

```text
...\Setup\ERRCODES.TXT   -> NAME NOT FOUND
```

Creating an empty `ERRCODES.TXT` made the application print a *more specific*
XVT Toolkit error instead of the generic message. It did not make the
application work.

**Conclusion:** `ERRCODES.TXT` affects how errors are *displayed*. It is not the
root failure. The experimental file was deleted afterwards.

---

## 6. Problem A — Print Spooler / XVT print initialisation

The error text points directly at `wprnt.c`, and Process Monitor showed
`splwow64.exe` being started during application startup.

Installed printers included:

```text
Microsoft Print to PDF
Fax
Microsoft XPS Document Writer
OneNote
WPS PDF
```

with `Microsoft Print to PDF` already set as the default. So this is **not**
simply a "no default printer configured" situation.

### Experiment

```powershell
Stop-Service Spooler -Force
```

Then launch Primer Premier 5.

### Result

The `wprnt.c` / `xvt_vobj_get_attr` / Toolkit Error **disappeared**, and the
application proceeded to the next stage of initialisation.

**Conclusion (experimentally demonstrated):** the legacy XVT Runtime used by
Primer Premier 5 has a compatibility problem with modern Windows Print Spooler
initialisation.

**Status: no permanent DLL-level patch exists for this layer.** The current
workaround is to stop the Print Spooler before launching Primer. A possible
future approach is:

```text
stop Spooler
  -> launch Primer
  -> wait for XVT initialisation to complete
  -> restart Spooler
```

or reverse-engineering the `wprnt.c` logic to find the real fix. Neither has been
done yet.

---

## 7. Problem B — xnmba458.dll C0000005

With the Print Spooler issue bypassed, Primer still crashed to the desktop.

Windows Event Log:

```text
Faulting module : xnmba458.dll
Version         : 4.58.0.0
Exception       : 0xc0000005
Offset          : 0x000154fb
```

Windows LocalDumps was configured, producing:

```text
Primer Premier 5.exe.<PID>.dmp
```

approximately `164 MB` in size.

---

## 8. WinDbg dump analysis

```text
AV.Type        : Read
Failure bucket : INVALID_POINTER_READ_c0000005_xnmba458.dll!Unknown
Fault location : xnmba458.dll + 0x154FB
Module base    : 0x1C000000
```

The faulting instruction:

```asm
xnmba458!xvtwi_Init+0x4be

1c0154fb  837a5400    cmp dword ptr [edx+54h], 0
```

At the time of the fault:

```text
EDX = 0x000009B0
```

so the CPU attempted to read:

```text
0x000009B0 + 0x54 = 0x00000A04
```

which is not mapped in the process, producing:

```text
0xC0000005  INVALID_POINTER_READ
```

---

## 9. Call stack

The relevant frames from the dump:

```text
xnmba458!xvtwi_Init+0x4be
xnmba458!xvtwi_xvt_system+0x28c
unmpr458!CFactoryElement::CFactoryElement+0xac
unmpr458!CFactoryElement::CFactoryElement+0x107af
unmpr458!PWR_CApplication::Go+0x53
Primer_Premier_5+0xdf27c
...
```

The crash occurs during **XVT Runtime initialisation**, not inside Primer's own
bioinformatics logic. This matters: the defect is in the compatibility layer
between the legacy runtime and the modern OS, not in the application's
domain code.

---

## 10. Key disassembly

Code leading up to the crash:

```asm
1c0154d3  682d010000          push 12Dh
1c0154d8  6a00                push 0
1c0154da  e8e1b30000          call xnmba458!xvtk_vobj_get_attr
1c0154df  83c408              add  esp, 8
1c0154e2  89857cffffff        mov  [ebp-84h], eax
1c0154e8  83bd7cffffff00      cmp  [ebp-84h], 0
1c0154ef  0f84a7000000        je   1c01559c
1c0154f5  8b957cffffff        mov  edx, [ebp-84h]
1c0154fb  837a5400            cmp  dword ptr [edx+54h], 0     <-- fault
```

Simplified to C-like pseudocode:

```c
obj = xvtk_vobj_get_attr(0, 0x12D);

if (obj == NULL)
    goto fallback;          /* 0x1559C */

if (*(obj + 0x54) == 0)     /* <-- crashes here */
    ...
```

The problem: on modern systems, `xvtk_vobj_get_attr()` sometimes returns a value
that is **non-zero but not a safely dereferenceable object address**.

---

## 11. Live debug confirmation

Using WinDbg live debugging, a normal run was observed to produce:

```text
[ebp-84] = 00E1BCF8
```

a normal user-mode address, for which `[ptr+0x54]` is readable.

Later runs captured:

```text
[ebp-84] = 000004D8
```

and a dump showed:

```text
000009B0
```

So the bad value is **not constant**:

```text
0x4D8
0x9B0
...
```

All observed bad values are **small non-zero values**. The legacy XVT code only
checks `pointer != NULL`, so `0x4D8 != 0` passes the check, and the value is then
used as a pointer. Accessing `0x4D8 + 0x54` faults.

> The exact meaning of these small values inside XVT has **not** been fully
> reverse-engineered. What is established is that they are not dereferenceable
> object pointers in the observed crashes.

---

## 12. Dynamic verification of the fix

In WinDbg, an experiment was performed: if the return value is an obviously
invalid low address, branch to the fallback path that **already exists** in XVT
at:

```text
xnmba458.dll + 0x1559C
```

The dynamic rule:

```text
if (EDX < 0x10000)
    branch to 0x1559C
else
    keep the original execution path
```

With this applied automatically:

* Primer Premier 5 **successfully reached the main window**.
* Menus, buttons and the UI were **operable**.

**Conclusion:** treating an anomalous low value as an invalid object and taking
XVT's existing fallback path is sufficient to bypass this compatibility crash.

Note: `0x10000` is a **conservative low-address threshold chosen for this patch**.
There is no evidence that `0x10000` is an XVT-defined semantic boundary. See §16.

---

## 13. Original DLL information

```text
File     : xnmba458.dll
Size     : 360960 bytes
Version  : 4.58.0.0
SHA256   : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
```

The patch script **must** check this SHA256 first. On mismatch it stops
immediately. Patching an unknown version by fixed RVA is not acceptable.

---

## 14. PE information

```text
Module       : xnmba458.dll
Architecture : i386
ImageBase    : 0x1C000000
EntryPoint   : 0x48DD0
SizeOfImage  : 0x5D000
Headers      : 0x400
```

Key `.text` section:

```text
VirtualAddress : 0x1000
VirtualSize    : 0x47EDE

RawOffset      : 0x1000
RawSize        : 0x48000

Flags          : Execute, Read
```

Because `.text` has `RVA == RawOffset == 0x1000`, all `.text` addresses relevant
to this patch map **directly** to file offsets. No RVA-to-file-offset conversion
is needed for the two patched locations.

---

## 15. Code cave selection

File offset `0x48EE0` was inspected:

```text
00048EE0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048EF0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048F00: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048F10: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

This is zero padding and is executable (it lies inside `.text`). It was selected
as the patch code cave at:

```text
0x48EE0
```

The patch consumes exactly **27 bytes** there. The region from `0x48EE0` to
`0x49000` was verified to be entirely zero in the original file, so there is no
collision with existing code or data.

---

## 16. Patch design

Original code:

```asm
154F5:  mov edx, [ebp-84h]
154FB:  cmp dword ptr [edx+54h], 0
```

Patched flow:

```asm
154F5:  jmp 48EE0
        nop x5

48EE0:  mov edx, [ebp-84h]
        cmp edx, 10000h
        jb  1559C
        cmp dword ptr [edx+54h], 0
        jmp 154FF
```

Control flow:

```text
xvtk_vobj_get_attr()
        |
        v
  return value in [ebp-84h]
        |
        v
   value < 0x10000 ?
       /       \
     YES        NO
      |          |
      |          +--> original [EDX+0x54] logic, then resume at 0x154FF
      |
      +--> XVT's existing fallback path at 0x1559C
```

Properties of this design:

* Normal object addresses still execute the original XVT logic.
* Anomalous low values (`0x4D8`, `0x9B0`, ...) are no longer dereferenced.
* The XVT initialisation sequence is **not** removed.
* The behavioural change is limited to the single ambiguous case.
* The fallback target is pre-existing XVT code, not new logic.

### Note on the resume address

The patched jump at the code cave is encoded as `E9 04 C6 FC FF`, whose target is
`0x154FC`. That address lies inside the five NOP bytes that replace the original
instructions, so execution flows through NOP padding and resumes at `0x154FF`,
which is the intended continuation point. The observable behaviour is identical
to jumping to `0x154FF` directly. The byte sequence is kept exactly as verified
because the expected patched SHA256 depends on it.

---

## 17. Patch bytes — patch site

Offset:

```text
0x154F5
```

After patching:

```hex
E9 E6 39 03 00
90 90 90 90 90
```

i.e. `JMP code_cave` followed by five `NOP` bytes.

Verification result:

```text
E9 E6 39 03 00 90 90 90 90 90
```

---

## 18. Patch bytes — code cave

Offset:

```text
0x48EE0
```

Written:

```hex
8B 95 7C FF FF FF
81 FA 00 00 01 00
0F 82 AA C6 FC FF
83 7A 54 00
E9 04 C6 FC FF
```

Verification result:

```text
8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00 E9 04 C6 FC FF
```

---

## 19. Byte-level diff summary

A full byte comparison of the original and patched files yields **exactly 33
differing bytes**, in two contiguous regions:

```text
offset 0x154F5 - 0x154FE  (10 bytes)
  original : 8B 95 7C FF FF FF 83 7A 54 00
  patched  : E9 E6 39 03 00 90 90 90 90 90

offset 0x48EE0 - 0x48EFA  (23 bytes, all zero padding in the original)
  original : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  patched  : 8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00
             E9 04 C6 FC FF  (extends to 0x48EFB)
```

No other byte in the 360960-byte file is modified.

---

## 20. Patched DLL information

```text
Generated : xnmba458.dll.patched
Size      : 360960 bytes (unchanged)

Patched SHA256 :
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

Final deployment on the test machine:

```text
xnmba458.dll           SHA256 77C7C009…62BE0   (patched, in use)
xnmba458.dll.patched   SHA256 77C7C009…62BE0
xnmba458.dll.original  SHA256 6FF40C2B…4BBF9   (untouched backup)
```

---

## 21. Final on-machine verification

Test conditions:

```text
patched xnmba458.dll in place
Print Spooler temporarily stopped
WinDbg NOT attached
Primer Premier 5.exe launched directly
```

Result:

```text
Primer Premier 5 started successfully.
```

Specifically:

```text
main window displayed normally
menus clickable
buttons clickable
no immediate C0000005 crash
```

**Conclusion:** for the tested build, the `xnmba458.dll` compatibility patch
resolves the identified `xvtwi_Init` low-address invalid dereference **without a
debugger attached**.

---

## 22. Summary of the two problems

### Problem A

```text
wprnt.c / xvt_vobj_get_attr / Toolkit Error / Print Spooler
```

Symptom: XVT Toolkit Error during startup.
Workaround: `Stop-Service Spooler -Force`.
Permanent patch: **not implemented**.

### Problem B

```text
xnmba458.dll / xvtwi_Init / 0x154FB / C0000005
```

Symptom: crash to desktop.
Root behaviour:

```text
xvtk_vobj_get_attr(0, 0x12D) returns an anomalous small non-zero value
legacy code tests only != NULL
the value is then dereferenced as [value+0x54]
```

Status: **resolved on the test machine by this DLL patch.**

---

## 23. One location deliberately left unmodified

Nearby, at:

```asm
1554f:  call xnmba458!xvtk_vobj_get_attr
15557:  mov  eax, [eax+54h]
```

there is a similar direct dereference.

However:

> current testing has **not** demonstrated that this location ever crashes.

Therefore this patch **does not modify it**.

Principle: only modify locations where a problem has been proven by dump +
live debug + an actual crash. Do not widen a patch because something "looks
like it might be a problem".

If a future crash dump from another user demonstrates a fault at this location,
it should be analysed separately as its own patch profile.

---

## 24. Test matrix

| Item | Status |
|---|---|
| Windows build 26200 (test machine) | Patched, verified working |
| Other Windows 10 builds | Not tested |
| Windows 11 23H2 | Not tested |
| Windows 11 24H2 | Not tested |
| Windows 11 25H2 and later | Not tested |
| Other `xnmba458.dll` hashes | Not collected |
| Existence of multiple PP5/XVT builds | Unknown |

---

## 25. Open questions

* What do the anomalous small return values from `xvtk_vobj_get_attr` represent
  inside XVT?
* What is the actual root cause of the `wprnt.c` / Print Spooler failure?
* Do other Primer Premier 5 / XVT builds contain the same code shape at the same
  or a different offset?
* Can the low-address guard be replaced by a more precise validity test?

---

## 26. Most important technical conclusion

This failure is **not** simply:

```text
missing DLL
missing VC++ runtime
corrupt installer
```

Dump plus live debug show:

```text
xvtk_vobj_get_attr(0, 0x12D)
        |
        v
returns a small non-zero value
        |
        v
legacy XVT code only checks for NULL
        |
        v
treats the small value as an object pointer
        |
        v
dereferences [EDX+0x54]
        |
        v
0xC0000005
```

The patch adds a low-address guard:

```text
value < 0x10000  ->  take XVT's existing fallback path
```

while normal object addresses keep the original XVT execution path. On the test
machine this resolves the crash.
