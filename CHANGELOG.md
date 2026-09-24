# Changelog

> **Language / 语言:** **English** · [**中文版 → CHANGELOG.zh-CN.md**](CHANGELOG.zh-CN.md)
>
> 本文档的中文版位于 [`CHANGELOG.zh-CN.md`](CHANGELOG.zh-CN.md)。

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `0.x` version series reflects the deliberately narrow verification scope:
the patch is confirmed against exactly one `xnmba458.dll` build. The version will
not advance to `1.0.0` until broader verification exists.

---

## [0.1.1] - 2026-09-24

Correctness and documentation fixes. **The patch data itself is unchanged** — no
byte of the patch, and no expected hash, differs from v0.1.0.

### Fixed

* `patch/patch-xnmba458.ps1` — **`-DryRun` no longer creates a backup file.**
  The switch is documented as "write nothing", but the backup step ran before the
  dry-run check, so a `xnmba458.dll.original` file was created even in dry-run
  mode. The dry-run check now happens before any write, and dry-run output
  reports what *would* happen to the backup and which byte ranges *would* be
  written.
* `patch/patch-xnmba458.ps1` — **post-write failures now roll back
  automatically.** If verification failed after the DLL had already been
  written, the original file was previously left in a modified state and the user
  was only advised to restore it manually. The script now restores the verified
  backup itself and reports clearly that the patch did not apply.
* `patch/patch-xnmba458.ps1` / `patch/restore-xnmba458.ps1` — the abort handler
  no longer claims "No changes were made" when it is invoked *after* the target
  file has been written. That message was false in those paths and could mislead
  a user into thinking their DLL was untouched.
* `patch/patch-xnmba458.ps1` — `Test-ByteRange` now also rejects a negative
  offset instead of relying on the caller.

### Changed

* **Byte-count wording corrected in all documents.** The two patched regions
  **span 37 bytes** (10 + 27), of which **33 bytes actually change value**. The
  four bytes at `0x48EE8`, `0x48EE9`, `0x48EEB` and `0x48EF5` already contained
  `00` in the original file, and the patch writes `00` there as well, so their
  value does not change. The previous wording ("only 33 bytes are modified") was
  arithmetically defensible but invited the reader to add 10 + 27 and conclude the
  document was wrong. Both numbers are now stated explicitly, with the
  explanation.

  ```text
  region span    : 10 + 27 = 37 bytes
  actual changes : 10 + 23 = 33 bytes
  ```

* `README.md` / `README.zh-CN.md` — added a **Quick Start** section at the very
  top, with a copy-pasteable SHA256 check so a visitor can tell in one step
  whether the patch applies to their build, followed by the patch command.
* `README.md` / `README.zh-CN.md` — the descriptive introduction moved under an
  explicit `Overview` heading so that Quick Start is the first thing on the page.

### Unchanged

```text
original sha256 : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
patched  sha256 : 77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

Patch regions, offsets and machine code are byte-for-byte identical to v0.1.0.
If you already patched successfully with v0.1.0, there is nothing to redo.

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

[0.1.1]: https://github.com/Zhuxi140/Primer-Premier-5-Modern-Windows-Fix/releases/tag/v0.1.1
[0.1.0]: https://github.com/Zhuxi140/Primer-Premier-5-Modern-Windows-Fix/releases/tag/v0.1.0
