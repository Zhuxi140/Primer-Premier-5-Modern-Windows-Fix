# 技术分析 —— xnmba458.dll / XVT 4.58 启动崩溃

> **语言 / Language:** **中文** · [**English → technical-analysis.md**](technical-analysis.md)
>
> 本文档的英文版位于 [`docs/technical-analysis.md`](technical-analysis.md)。
> 英文版为技术内容的原始记录，中文版为对应译文；两者章节编号与内容一一对应。

本文档完整记录了整个排查过程：运行环境、最初的故障、转储分析、反汇编、补丁设计与验证。

文中所有内容要么是直接观察到的证据，要么已明确标注为推断。**任何推测都不会被写成已经确认的事实。**

---

## 1. 运行环境

```text
目标软件   : Primer Premier 5.00
关键模块   : xnmba458.dll  (XVT Runtime 4.58.0.0)
模块架构   : x86
测试系统   : Windows, Build 26200, 64-bit
调试器     : WinDbg 10.0.29617.1000 X86
```

测试机器上的 Windows 产品字符串仍显示为旧版兼容值：

```text
Windows 10 Home China
WindowsVersion: 2009
```

而实际 Build 为 `26200`。这里要说明的重点只是：测试环境**远新于** Primer Premier 5
和 XVT 4.58 所设计的 Windows 98 时代环境。记录 Build 号是因为它关系到可复现性，
并不代表原厂的任何情况。

---

## 2. 最初的故障

启动 `Primer Premier 5.exe` 时出现 XVT Toolkit 错误：

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

有时还会伴随出现：

```text
Some of the required files have been missing or corrupted.
Please reinstall the application.
```

这条信息具有误导性。它暗示的各种假设——缺少运行库、缺少 DLL、安装包损坏、Windows 兼容性设置、
打印子系统、XVT 与现代 Windows 的整体不兼容——被逐一排查。其中两个被**证据排除**（见 §4、§5），
剩下两个最终证明是**两个相互独立的问题**（见 §6、§7）。

---

## 3. 安装目录调查

Primer Premier 5 安装目录中包含：

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

以及资源目录：

```text
data\
waves\
```

没有 MSI/CAB 安装结构。`Read Me.txt` 显示 `Primer Premier 5.00`，
且文档中仍然保留着 Windows 98 时代的安装说明。这确认了该软件及其运行库
来自非常早期的 Windows 软件环境。

---

## 4. 已排除：「缺少 MSVCIRT.dll」等假设

Process Monitor 显示程序尝试查找：

```text
MSVCIRT.dll
WINMM.dll
WINSPOOL.DRV
WINHTTP.dll
IppCommon.dll
...
```

其中一部分首先在程序目录中解析为 `NAME NOT FOUND`，但随后能够从以下位置成功加载：

```text
C:\Windows\SysWOW64\
```

例如 `C:\Windows\SysWOW64\MSVCIRT.dll` 确实存在并能成功加载。

**结论：** 缺少 `MSVCIRT.dll` **不是**本次崩溃的根本原因。

**给用户的实际建议：** 不要从第三方 DLL 下载站随机下载 DLL。它们不是问题所在，
而且会引入真实的安全风险。

---

## 5. 已排除：ERRCODES.TXT

Process Monitor 显示程序大量查找：

```text
...\Setup\ERRCODES.TXT   -> NAME NOT FOUND
```

创建一个空的 `ERRCODES.TXT` 后，程序会打印**更具体**的 XVT Toolkit 错误，
而不是笼统的提示信息。但这并没有让程序恢复正常。

**结论：** `ERRCODES.TXT` 影响的是错误信息的**显示方式**，不是根本故障。
实验用的空文件随后已删除。

---

## 6. 问题 A —— Print Spooler / XVT 打印初始化

错误信息直接指向 `wprnt.c`，同时 Process Monitor 显示程序启动过程中
`splwow64.exe` 被启动。

系统中已安装的打印机包括：

```text
Microsoft Print to PDF
Fax
Microsoft XPS Document Writer
OneNote
WPS PDF
```

并且默认打印机已经设置为 `Microsoft Print to PDF`。因此这**不是**简单的
「没有配置默认打印机」的情况。

### 实验

```powershell
Stop-Service Spooler -Force
```

然后启动 Primer Premier 5。

### 结果

`wprnt.c` / `xvt_vobj_get_attr` / Toolkit Error **消失**，程序能够继续进入下一阶段初始化。

**结论（已通过实验证明）：** Primer Premier 5 使用的旧 XVT Runtime 与现代 Windows
Print Spooler 初始化之间存在兼容性问题。

**状态：这一层目前没有 DLL 级的永久补丁。** 当前的绕过方案是在启动 Primer 前停止
Print Spooler。未来可以考虑的思路是：

```text
停止 Spooler
  -> 启动 Primer
  -> 等待 XVT 初始化完成
  -> 恢复 Spooler
```

或者继续逆向 `wprnt.c` 对应逻辑，寻找真正的兼容性修复。这两条路目前都还没有做。

---

## 7. 问题 B —— xnmba458.dll C0000005

绕过 Print Spooler 问题之后，Primer 仍然会闪退。

Windows 事件日志：

```text
Faulting module : xnmba458.dll
Version         : 4.58.0.0
Exception       : 0xc0000005
Offset          : 0x000154fb
```

配置 Windows LocalDumps 后，得到：

```text
Primer Premier 5.exe.<PID>.dmp
```

大小约为 `164 MB`。

---

## 8. WinDbg 转储分析

```text
AV.Type        : Read
Failure bucket : INVALID_POINTER_READ_c0000005_xnmba458.dll!Unknown
Fault location : xnmba458.dll + 0x154FB
Module base    : 0x1C000000
```

崩溃指令：

```asm
xnmba458!xvtwi_Init+0x4be

1c0154fb  837a5400    cmp dword ptr [edx+54h], 0
```

崩溃发生时：

```text
EDX = 0x000009B0
```

因此 CPU 实际尝试读取：

```text
0x000009B0 + 0x54 = 0x00000A04
```

该地址在进程中未被映射，于是产生：

```text
0xC0000005  INVALID_POINTER_READ
```

---

## 9. 调用栈

转储中的重要调用栈：

```text
xnmba458!xvtwi_Init+0x4be
xnmba458!xvtwi_xvt_system+0x28c
unmpr458!CFactoryElement::CFactoryElement+0xac
unmpr458!CFactoryElement::CFactoryElement+0x107af
unmpr458!PWR_CApplication::Go+0x53
Primer_Premier_5+0xdf27c
...
```

崩溃发生在 **XVT Runtime 初始化阶段**，而不是 Primer 自身的生物信息学计算逻辑中。
这一点很重要：缺陷位于旧运行库与现代操作系统之间的兼容层，而不是应用自身的领域代码里。

---

## 10. 关键反汇编

崩溃前的代码：

```asm
1c0154d3  682d010000          push 12Dh
1c0154d8  6a00                push 0
1c0154da  e8e1b30000          call xnmba458!xvtk_vobj_get_attr
1c0154df  83c408              add  esp, 8
1c0154e2  89857cffffff        mov  [ebp-84h], eax
1c0154e8  83bd7cffffff00      cmp  [ebp-84h], 0
1c0154ef  0f84a7000000        je   1c01559c
1c0154f5  8b957cffffff        mov  edx, [ebp-84h]
1c0154fb  837a5400            cmp  dword ptr [edx+54h], 0     <-- 崩溃点
```

简化成类 C 伪代码：

```c
obj = xvtk_vobj_get_attr(0, 0x12D);

if (obj == NULL)
    goto fallback;          /* 0x1559C */

if (*(obj + 0x54) == 0)     /* <-- 在这里崩溃 */
    ...
```

问题在于：在现代系统环境下，`xvtk_vobj_get_attr()` 有时会返回一个
**非零但无法安全解引用的对象地址**。

---

## 11. 实机调试验证

使用 WinDbg 实机调试，在一次正常运行中观察到：

```text
[ebp-84] = 00E1BCF8
```

这是一个正常的用户态地址，`[ptr+0x54]` 可以正常读取。

之后的运行中捕获到：

```text
[ebp-84] = 000004D8
```

而某个转储中出现了：

```text
000009B0
```

可见异常值**并不固定**：

```text
0x4D8
0x9B0
...
```

所有观察到的异常值都是**很小的非零值**。旧版 XVT 代码只检查 `pointer != NULL`，
因此 `0x4D8 != 0` 通过检查，该值随后被当作指针使用，访问 `0x4D8 + 0x54` 时触发访问违例。

> 这些很小的值在 XVT 内部**究竟代表什么**，目前**尚未**完全逆向清楚。
> 已经确认的是：在观察到的崩溃中，它们不是可解引用的对象指针。

---

## 12. 修复思路的动态验证

在 WinDbg 中做了一个实验：如果返回值是明显异常的低地址，则跳转到 XVT 中
**原本就存在**的 fallback 路径：

```text
xnmba458.dll + 0x1559C
```

动态规则：

```text
if (EDX < 0x10000)
    跳转 0x1559C
else
    保持原始执行路径
```

自动应用该规则后：

* Primer Premier 5 **成功进入主界面**。
* 菜单、按钮及 UI **可以正常操作**。

**结论：** 把异常低值视为无效对象、并走 XVT 原有的 fallback 路径，足以绕过该兼容性崩溃。

注意：`0x10000` 是**本补丁选择的保守低地址阈值**。没有证据表明 `0x10000` 是
XVT 官方定义的语义边界。见 §16。

---

## 13. 原始 DLL 信息

```text
文件      : xnmba458.dll
大小      : 360960 字节
版本      : 4.58.0.0
SHA256    : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
```

补丁脚本**必须**首先检查这个 SHA256。一旦不一致就立即停止。
绝对不能按照固定 RVA 修改未知版本。

---

## 14. PE 信息

```text
模块         : xnmba458.dll
架构         : i386
ImageBase    : 0x1C000000
EntryPoint   : 0x48DD0
SizeOfImage  : 0x5D000
Headers      : 0x400
```

关键 `.text` 段：

```text
VirtualAddress : 0x1000
VirtualSize    : 0x47EDE

RawOffset      : 0x1000
RawSize        : 0x48000

Flags          : Execute, Read
```

由于 `.text` 满足 `RVA == RawOffset == 0x1000`，本次补丁涉及的所有 `.text` 地址
**可以直接**对应到文件偏移。两个被打补丁的位置都不需要做 RVA 到文件偏移的换算。

---

## 15. Code Cave 选择

检查文件偏移 `0x48EE0`：

```text
00048EE0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048EF0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048F00: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00048F10: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

这是零填充，且位于 `.text` 内，因此是可执行的。选择它作为补丁 code cave：

```text
0x48EE0
```

补丁恰好占用其中 **27 字节**。已核实原文件中 `0x48EE0` 到 `0x49000` 区域全为零，
因此不会与任何已有代码或数据冲突。

---

## 16. 补丁设计

原始代码：

```asm
154F5:  mov edx, [ebp-84h]
154FB:  cmp dword ptr [edx+54h], 0
```

修改后的执行流：

```asm
154F5:  jmp 48EE0
        nop x5

48EE0:  mov edx, [ebp-84h]
        cmp edx, 10000h
        jb  1559C
        cmp dword ptr [edx+54h], 0
        jmp 154FF
```

控制流：

```text
xvtk_vobj_get_attr()
        |
        v
  返回值存入 [ebp-84h]
        |
        v
   值 < 0x10000 ?
       /       \
     是         否
      |          |
      |          +--> 执行原始 [EDX+0x54] 逻辑，随后在 0x154FF 继续
      |
      +--> XVT 原有的 fallback 路径 0x1559C
```

该设计的性质：

* 正常对象地址仍然执行原始的 XVT 逻辑。
* 异常低值（`0x4D8`、`0x9B0` 等）不再被解引用。
* **没有**删除 XVT 的初始化过程。
* 行为改动仅限这一个有歧义的分支。
* 跳转目标是 XVT 中已有的代码，不是新增逻辑。

### 关于跳回地址的说明

code cave 末尾的跳转编码为 `E9 04 C6 FC FF`，其目标是 `0x154FC`。
该地址落在替换原指令的那 5 个 NOP 字节内部，因此执行流会穿过 NOP 填充，
最终在 `0x154FF` 继续——这正是预期的续接点。其可观察行为与直接跳转到 `0x154FF` 完全相同。
字节序列保持与已验证结果完全一致，因为预期的 patched SHA256 依赖于它。

---

## 17. 补丁字节 —— 补丁位置

偏移：

```text
0x154F5
```

打补丁后：

```hex
E9 E6 39 03 00
90 90 90 90 90
```

即 `JMP code_cave` 后接五个 `NOP`。

验证结果：

```text
E9 E6 39 03 00 90 90 90 90 90
```

---

## 18. 补丁字节 —— Code Cave

偏移：

```text
0x48EE0
```

写入：

```hex
8B 95 7C FF FF FF
81 FA 00 00 01 00
0F 82 AA C6 FC FF
83 7A 54 00
E9 04 C6 FC FF
```

验证结果：

```text
8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00 E9 04 C6 FC FF
```

---

## 19. 字节级差异汇总

对原始文件与补丁文件做全文件字节比对，**恰好 33 个字节**不同，分布在两个连续区域：

```text
偏移 0x154F5 - 0x154FE  （10 字节）
  原始 : 8B 95 7C FF FF FF 83 7A 54 00
  补丁 : E9 E6 39 03 00 90 90 90 90 90

偏移 0x48EE0 - 0x48EFA  （23 字节，原文件全部为零填充）
  原始 : 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  补丁 : 8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00
         E9 04 C6 FC FF  （延伸至 0x48EFB）
```

整个 360960 字节的文件中，没有其他任何字节被修改。

---

## 20. 补丁后 DLL 信息

```text
生成文件 : xnmba458.dll.patched
大小     : 360960 字节（未变化）

补丁后 SHA256 :
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

测试机器上的最终部署状态：

```text
xnmba458.dll           SHA256 77C7C009…62BE0   （已打补丁，实际使用）
xnmba458.dll.patched   SHA256 77C7C009…62BE0
xnmba458.dll.original  SHA256 6FF40C2B…4BBF9   （未改动的备份）
```

---

## 21. 最终实机验证

测试条件：

```text
使用已打补丁的 xnmba458.dll
Print Spooler 暂时停止
不附加 WinDbg
直接运行 Primer Premier 5.exe
```

结果：

```text
Primer Premier 5 成功启动。
```

具体表现为：

```text
主界面正常显示
菜单可以点击
按钮可以点击
程序不再立即 C0000005 闪退
```

**结论：** 对于本次测试版本，`xnmba458.dll` 兼容性补丁能够在**不附加调试器**的情况下
解决已经定位的 `xvtwi_Init` 低地址非法解引用崩溃。

---

## 22. 两个问题的汇总

### 问题 A

```text
wprnt.c / xvt_vobj_get_attr / Toolkit Error / Print Spooler
```

现象：启动阶段出现 XVT Toolkit Error。
绕过方案：`Stop-Service Spooler -Force`。
永久补丁：**尚未实现**。

### 问题 B

```text
xnmba458.dll / xvtwi_Init / 0x154FB / C0000005
```

现象：程序闪退。
根本行为：

```text
xvtk_vobj_get_attr(0, 0x12D) 返回异常的小非零值
旧代码只判断 != NULL
该值随后被当作指针解引用 [value+0x54]
```

状态：**本 DLL 补丁已在测试机器上解决该问题。**

---

## 23. 一处故意未修改的位置

附近还有：

```asm
1554f:  call xnmba458!xvtk_vobj_get_attr
15557:  mov  eax, [eax+54h]
```

这里同样存在直接解引用。

但是：

> 当前测试**没有**证明该位置会发生相同崩溃。

因此本次补丁**不修改这里**。

原则：只修改已经通过转储 + 实机调试 + 实际崩溃证明存在问题的位置。
不因为「看起来可能有问题」就扩大补丁范围。

如果未来其他用户的崩溃转储证明该位置也会发生异常，应作为独立的 patch profile 单独研究。

---

## 24. 测试矩阵

| 项目 | 状态 |
|---|---|
| Windows Build 26200（测试机器） | 已打补丁，验证可用 |
| 其他 Windows 10 Build | 未测试 |
| Windows 11 23H2 | 未测试 |
| Windows 11 24H2 | 未测试 |
| Windows 11 25H2 及后续版本 | 未测试 |
| 其他 `xnmba458.dll` 哈希 | 尚未收集 |
| 是否存在多个 PP5/XVT build | 未知 |

---

## 25. 待解问题

* `xvtk_vobj_get_attr` 返回的异常小值在 XVT 内部究竟代表什么？
* `wprnt.c` / Print Spooler 故障的真正根因是什么？
* 其他 Primer Premier 5 / XVT build 是否在相同或不同偏移处存在相同的代码形态？
* 能否用更精确的有效性判定替代这个低地址保护阈值？

---

## 26. 最重要的技术结论

本次故障**不是**简单的：

```text
缺 DLL
缺 VC++ 运行库
安装包损坏
```

转储 + 实机调试表明：

```text
xvtk_vobj_get_attr(0, 0x12D)
        |
        v
返回一个很小的非零值
        |
        v
旧 XVT 代码只检查 NULL
        |
        v
把该小值当成对象指针
        |
        v
解引用 [EDX+0x54]
        |
        v
0xC0000005
```

补丁增加了低地址保护：

```text
值 < 0x10000  ->  走 XVT 原有的 fallback 路径
```

而正常的对象地址仍保持 XVT 原始执行路径。在测试机器上，该补丁解决了此崩溃。
