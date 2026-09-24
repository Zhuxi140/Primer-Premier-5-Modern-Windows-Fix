# 版本记录

> **语言 / Language:** **中文** · [**English → CHANGELOG.md**](CHANGELOG.md)
>
> 本文档的英文版位于 [`CHANGELOG.md`](CHANGELOG.md)。

本项目所有值得记录的变更都列在此处。

格式参考 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本](https://semver.org/spec/v2.0.0.html)。

`0.x` 系列版本号刻意反映了较窄的验证范围：本补丁仅在一个 `xnmba458.dll` 版本上得到确认。
在获得更广泛的验证之前，版本号不会提升到 `1.0.0`。

---

## [0.1.1] - 2026-09-24

正确性与文档修正。**补丁数据本身没有任何变化** —— 补丁的任何一个字节、
任何一个预期哈希都与 v0.1.0 完全相同。

### 修复

* `patch/patch-xnmba458.ps1` —— **`-DryRun` 不再创建备份文件。**
  该参数的文档描述是「不写入任何内容」，但备份步骤执行在 dry-run 判断之前，
  导致即使是 dry-run 模式也会生成 `xnmba458.dll.original`。
  现在 dry-run 判断移到所有写入动作之前，并且 dry-run 输出会说明
  「将会如何处理备份」以及「将会写入哪些字节区间」。
* `patch/patch-xnmba458.ps1` —— **写入后的失败会自动回滚。**
  此前如果在 DLL 已被写入之后校验失败，文件会被留在已修改的状态，
  脚本只是建议用户手动还原。现在脚本会自己用已验证的备份还原，
  并明确告知补丁并未生效。
* `patch/patch-xnmba458.ps1` / `patch/restore-xnmba458.ps1` —— 中止处理不再在
  **已经写入之后**仍然声称「未做任何修改」。那句话在这些路径下是错的，
  可能让用户误以为自己的 DLL 没有被改动过。
* `patch/patch-xnmba458.ps1` —— `Test-ByteRange` 现在也会拒绝负数偏移，
  而不再依赖调用方保证。

### 变更

* **所有文档中的字节数表述已修正。** 两个补丁区域的**跨度为 37 字节**（10 + 27），
  其中**实际发生值变化的是 33 字节**。`0x48EE8`、`0x48EE9`、`0x48EEB`、`0x48EF5`
  这 4 个字节在原文件中本来就是 `00`，补丁写入的也是 `00`，因此值没有变化。
  此前的表述（「仅修改 33 字节」）在算术上站得住，但会诱导读者把 10 + 27 相加，
  从而以为文档写错了。现在两个数字都明确写出，并附上解释。

  ```text
  区域跨度合计   ：10 + 27 = 37 字节
  实际变化合计   ：10 + 23 = 33 字节
  ```

* `README.md` / `README.zh-CN.md` —— 在最顶部新增 **快速开始** 章节，
  提供可直接复制的 SHA256 校验命令，让访问者一步判断补丁是否适用于自己的版本，
  随后给出打补丁命令。
* `README.md` / `README.zh-CN.md` —— 说明性引言移到显式的「项目概述」标题之下，
  使快速开始成为页面第一屏的内容。

### 未变更

```text
原始 SHA256    : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
补丁后 SHA256  : 77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

补丁区域、偏移与机器码与 v0.1.0 逐字节一致。
如果你已经用 v0.1.0 成功打过补丁，无需重做任何事。

---

## [0.1.0] - 2026-09-24

首次公开发布。

### 新增

* `patch/patch-xnmba458.ps1` —— 针对 `xnmba458.dll` 访问违例的补丁脚本。
  * 校验文件大小、SHA256、`0x154F5` 处的原始机器码，以及 `0x48EE0` 处的
    code cave 是否为未被占用的全零填充。
  * 在写入任何内容之前先创建 `xnmba458.dll.original`。
  * 写入后重新读取并校验两个补丁位置以及全文件 SHA256。
  * 能识别已打过补丁的 DLL 并正常退出。
  * 拒绝为未知版本打补丁——不存在「尽力而为」模式。
  * 支持 `-DryRun`、`-Force`、`-KeepReadOnly`。
* `patch/restore-xnmba458.ps1` —— 从已验证的备份还原原始 DLL。
* `docs/technical-analysis.md` —— 完整排查记录：运行环境、转储分析、调用栈、反汇编、
  PE 结构、code cave 选择、补丁设计与字节级差异。
* `docs/crash-analysis.md` —— 崩溃签名速查与转储抓取说明。
* `docs/troubleshooting.md` —— Print Spooler / `wprnt.c` 问题、未知版本的处理方式、
  以及撤销补丁的说明。
* 用于提交崩溃与兼容性报告的 Issue 模板。
* `LICENSE`，仅覆盖本仓库的原创脚本与文档。

### 修复

* `xnmba458.dll+0x154FB` 处、位于 `xvtwi_Init+0x4be` 的
  `0xC0000005` `INVALID_POINTER_READ`。

  `xvtk_vobj_get_attr(0, 0x12D)` 可能返回异常的小非零值（观察到 `0x4D8`、`0x9B0`）。
  旧版 XVT 代码只检查 `NULL`，随后将其解引用。补丁将小于 `0x10000` 的值引导至
  XVT 原有的 fallback 路径 `0x1559C`，而大于等于 `0x10000` 的对象地址保持原始执行路径。

### 发布时的已知限制

* 仅在一个 `xnmba458.dll` 版本上完成验证：

  ```text
  6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
  ```

* Print Spooler / `wprnt.c` 的 Toolkit 错误**未**修复，仅记录了绕过方案。
* 未在 Windows 11 23H2 / 24H2 / 25H2 上测试，也未在测试机器（Build 26200）之外的
  Windows 10 Build 上测试。
* `0x10000` 是本补丁引入的保守保护阈值，不是有文档记载的 XVT 语义边界。
* 不是官方补丁，与软件原厂无隶属或认可关系。

### 有意不包含的内容

* 不包含 `xnmba458.dll`、`Primer Premier 5.exe`、安装包或任何其他商业二进制文件。
* 不包含破解、注册机或授权绕过内容。

[0.1.1]: https://github.com/Zhuxi140/Primer-Premier-5-Modern-Windows-Fix/releases/tag/v0.1.1
[0.1.0]: https://github.com/Zhuxi140/Primer-Premier-5-Modern-Windows-Fix/releases/tag/v0.1.0
