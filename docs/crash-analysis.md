# Crash Analysis Reference

A quick reference for the crash signatures involved, plus instructions for
capturing your own dump so it can be compared against the analysis in
[`technical-analysis.md`](technical-analysis.md).

---

## Problem B — the crash this patch fixes

### Event Log signature

```text
Faulting application name: Primer Premier 5.exe
Faulting module name:     xnmba458.dll
Faulting module version:  4.58.0.0
Exception code:           0xc0000005
Fault offset:             0x000154fb
```

### Debugger signature

```text
AV.Type        : Read
Failure bucket : INVALID_POINTER_READ_c0000005_xnmba458.dll!Unknown
Module base    : 0x1C000000
Fault address  : xnmba458.dll + 0x154FB
Function       : xnmba458!xvtwi_Init+0x4be
Instruction    : cmp dword ptr [edx+54h],0
```

### Call stack shape

```text
xnmba458!xvtwi_Init+0x4be
xnmba458!xvtwi_xvt_system+0x28c
unmpr458!CFactoryElement::CFactoryElement+0xac
unmpr458!CFactoryElement::CFactoryElement+0x107af
unmpr458!PWR_CApplication::Go+0x53
Primer_Premier_5+0xdf27c
```

### Root behaviour

```text
xvtk_vobj_get_attr(0, 0x12D)
        -> returns an anomalous small non-zero value (observed 0x4D8, 0x9B0)
        -> legacy code only tests != NULL
        -> value is dereferenced as [value + 0x54]
        -> 0xC0000005 INVALID_POINTER_READ
```

The faulting offset `0x154FB` and the small-value behaviour are the two things to
check when comparing a new crash report against this analysis.

---

## Problem A — the XVT Toolkit error (not fixed by this patch)

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

Related symptom sometimes seen:

```text
Some of the required files have been missing or corrupted.
Please reinstall the application.
```

This message is misleading — see
[`technical-analysis.md` §4 and §5](technical-analysis.md#4-ruled-out-missing-msvcirtdll-and-friends)
for the hypotheses that were investigated and ruled out.

---

## Capturing a crash dump

To produce a dump that can be compared with the one analysed here:

1. Open `regedit` and navigate to:

   ```text
   HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps
   ```

2. Create the key if it does not exist, then add:

   ```text
   DumpFolder      REG_EXPAND_SZ   C:\CrashDumps
   DumpCount       REG_DWORD       10
   DumpType        REG_DWORD       1        (1 = mini, 2 = full)
   ```

   For a dump comparable to the one in this analysis, use `DumpType = 2`.

3. Reproduce the crash. A file named `Primer Premier 5.exe.<PID>.dmp` appears in
   `C:\CrashDumps`.

4. Analyse it with WinDbg (x86). Useful starting commands:

   ```text
   .symfix
   .reload
   !analyze -v
   kb
   u xnmba458!xvtwi_Init+0x4be L1
   ```

5. Remove the `LocalDumps` key when you are finished.

A full dump of this application is roughly 164 MB. Please do **not** attach large
dumps directly to a GitHub issue — host them elsewhere and link them.

---

## What to include in a bug report

```text
Windows version:
Windows build:

Primer Premier version:

xnmba458.dll size:
xnmba458.dll SHA256:
xnmba458.dll version:
xnmba458.dll timestamp:

Faulting module:
Exception code:
Fault offset:
Function (if known):

Does stopping the Print Spooler change the behaviour?  yes / no

Crash dump available:  yes / no  (link)
```

The SHA256 is the single most important field. If it differs from the supported
build, the patch will refuse to run, and the correct next step is to analyse that
build separately — not to force the patch.
