# 崩溃分析速查

> **语言 / Language:** **中文** · [**English → crash-analysis.md**](crash-analysis.md)
>
> 本文档的英文版位于 [`docs/crash-analysis.md`](crash-analysis.md)。
> 英文版为技术内容的原始记录，中文版为对应译文；两者内容一一对应。

本文是相关崩溃签名的速查表，同时说明如何自行抓取转储，以便与
[`technical-analysis.zh-CN.md`](technical-analysis.zh-CN.md) 中的分析进行比对。

---

## 问题 B —— 本补丁修复的崩溃

### 事件日志签名

```text
Faulting application name: Primer Premier 5.exe
Faulting module name:     xnmba458.dll
Faulting module version:  4.58.0.0
Exception code:           0xc0000005
Fault offset:             0x000154fb
```

### 调试器签名

```text
AV.Type        : Read
Failure bucket : INVALID_POINTER_READ_c0000005_xnmba458.dll!Unknown
Module base    : 0x1C000000
Fault address  : xnmba458.dll + 0x154FB
Function       : xnmba458!xvtwi_Init+0x4be
Instruction    : cmp dword ptr [edx+54h],0
```

### 调用栈形态

```text
xnmba458!xvtwi_Init+0x4be
xnmba458!xvtwi_xvt_system+0x28c
unmpr458!CFactoryElement::CFactoryElement+0xac
unmpr458!CFactoryElement::CFactoryElement+0x107af
unmpr458!PWR_CApplication::Go+0x53
Primer_Premier_5+0xdf27c
```

### 根本行为

```text
xvtk_vobj_get_attr(0, 0x12D)
        -> 返回一个异常的小非零值（观察到 0x4D8、0x9B0）
        -> 旧代码只判断 != NULL
        -> 该值被当作指针解引用 [value + 0x54]
        -> 0xC0000005 INVALID_POINTER_READ
```

当需要把新的崩溃报告与本文分析比对时，要重点核对两件事：崩溃偏移 `0x154FB`，
以及上述「小非零值」行为。

---

## 问题 A —— XVT Toolkit 错误（本补丁未修复）

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

有时还会看到相关现象：

```text
Some of the required files have been missing or corrupted.
Please reinstall the application.
```

这条信息具有误导性——被排查并排除的各种假设，见
[`technical-analysis.zh-CN.md` §4 与 §5](technical-analysis.zh-CN.md#4-已排除缺少-msvcirtdll等假设)。

---

## 如何抓取崩溃转储

要生成一份可与本文分析比对的转储：

1. 打开 `regedit`，定位到：

   ```text
   HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps
   ```

2. 如果该键不存在则新建，然后添加：

   ```text
   DumpFolder      REG_EXPAND_SZ   C:\CrashDumps
   DumpCount       REG_DWORD       10
   DumpType        REG_DWORD       1        （1 = 迷你，2 = 完整）
   ```

   若要得到与本文分析相当的转储，请使用 `DumpType = 2`。

3. 复现崩溃。`C:\CrashDumps` 中会出现名为 `Primer Premier 5.exe.<PID>.dmp` 的文件。

4. 用 WinDbg（x86）分析。常用起始命令：

   ```text
   .symfix
   .reload
   !analyze -v
   kb
   u xnmba458!xvtwi_Init+0x4be L1
   ```

5. 分析完成后删除 `LocalDumps` 键。

该程序的完整转储约为 164 MB。请**不要**把大体积转储直接附加到 GitHub Issue 上——
放到别处托管并提供链接。

---

## Bug 报告中需要包含的内容

```text
Windows 版本：
Windows Build：

Primer Premier 版本：

xnmba458.dll 大小：
xnmba458.dll SHA256：
xnmba458.dll 版本：
xnmba458.dll 时间戳：

Faulting module：
Exception code：
Fault offset：
函数名（如已知）：

停止 Print Spooler 后行为是否改变？  是 / 否

是否有崩溃转储：  有 / 无  （链接）
```

其中 SHA256 是最重要的一项。如果它与受支持的版本不一致，补丁会拒绝运行；
此时正确的下一步是**单独分析该版本**，而不是强行打补丁。
