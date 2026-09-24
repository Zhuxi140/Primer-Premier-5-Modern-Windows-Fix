# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `0.x` version series reflects the deliberately narrow verification scope:
the patch is confirmed against exactly one `xnmba458.dll` build. The version will
not advance to `1.0.0` until broader verification exists.

---

## [0.1.0] - 2026-09-24

First public release.

### Added

* `patch/patch-xnmba458.ps1` — patcher for the `xnmba458.dll` access violation.
  * Verifies file size, SHA256, the original machine code at `0x154F5`, and that
    the code cave at `0x48EE0` is untouched zero padding.
  * Creates `xnmba458.dll.original` before writing anything.
  * Re-reads and verifies both patch sites and the whole-file SHA256 afterwards.
  * Detects an already-patched DLL and exits cleanly.
  * Refuses to patch unknown builds — no best-effort mode.
  * Supports `-DryRun`, `-Force`, `-KeepReadOnly`.
* `patch/restore-xnmba458.ps1` — restores the original DLL from the verified
  backup.
* `docs/technical-analysis.md` — full investigation record: environment, dump
  analysis, call stack, disassembly, PE layout, code cave selection, patch design
  and the byte-level diff.
* `docs/crash-analysis.md` — crash signature reference and dump-capture
  instructions.
* `docs/troubleshooting.md` — the Print Spooler / `wprnt.c` issue, unsupported-DLL
  behaviour, and undo instructions.
* Issue template for crash and compatibility reports.
* `LICENSE` covering only the original scripts and documentation.

### Fixed

* `xnmba458.dll+0x154FB` `0xC0000005` `INVALID_POINTER_READ` in
  `xvtwi_Init+0x4be`.

  `xvtk_vobj_get_attr(0, 0x12D)` can return an anomalous small non-zero value
  (`0x4D8`, `0x9B0` observed). The legacy XVT code only tests for `NULL` and then
  dereferences it. The patch routes values below `0x10000` to XVT's pre-existing
  fallback path at `0x1559C`, while object addresses `>= 0x10000` keep the
  original execution path.

### Known limitations at release

* Verified against one `xnmba458.dll` build only:

  ```text
  6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
  ```

* The Print Spooler / `wprnt.c` Toolkit error is **not** fixed. Only a workaround
  is documented.
* Not tested on Windows 11 23H2 / 24H2 / 25H2 or on Windows 10 builds other than
  the test machine.
* `0x10000` is a conservative guard introduced by this patch, not a documented
  XVT semantic boundary.
* Not an official patch and not affiliated with the vendor.

### Not included, by design

* No `xnmba458.dll`, `Primer Premier 5.exe`, installer, or any other commercial
  binary.
* No crack, keygen, or licence-bypass material.

[0.1.0]: https://github.com/Zhuxi140/Primer-Premier-5-Modern-Windows-Fix/releases/tag/v0.1.0
