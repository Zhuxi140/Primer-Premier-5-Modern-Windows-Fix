# Primer Premier 5 / XVT 4.58 现代 Windows 兼容性修复

本项目提供一个**可复现、可验证**的兼容性补丁，用于修复 **Primer Premier 5.00**
在现代 64 位 Windows 上因旧版 **XVT Runtime 4.58**（`xnmba458.dll`）导致的启动崩溃。

本仓库**只发布原创补丁脚本、补丁数据和技术文档**，不包含、不托管、不重新分发
`xnmba458.dll`、`Primer Premier 5.exe`、Primer Premier 安装包或任何其他商业二进制文件。
你需要自行提供来自自己合法安装副本的 DLL。

> **适用范围：** 本补丁目前**仅在一个特定版本的 `xnmba458.dll` 上完成验证**，其 SHA256 见下文。
> 这不是官方补丁，未获得原厂认可，也不是 Windows 10/11 的通用修复方案。详见[已知限制](#已知限制)。

---

## 两个互相独立的问题

Primer Premier 5 在现代 Windows 上存在**两个相互独立**的兼容性问题，请勿混为一谈。

| | 问题 A — Print Spooler | 问题 B — 访问违例 |
|---|---|---|
| 现象 | 启动时出现 XVT Toolkit 错误 | 程序立即闪退 |
| 模块 | XVT Runtime 打印相关代码 | `xnmba458.dll` |
| 位置 | `wprnt.c` 第 763 行 | `xnmba458.dll+0x154FB` |
| 函数 | `xvt_vobj_get_attr` / `xvt_app_create` | `xvtwi_Init` |
| 异常 | Toolkit 错误 `MSG 0x0073c35f [CAT 7/3 STD 50015]` | `0xC0000005` `INVALID_POINTER_READ` |
| 状态 | **仅有绕过方案**（停止 Print Spooler） | **本补丁已修复** |

本仓库**只修复问题 B**。问题 A 记录在 [`docs/troubleshooting.md`](docs/troubleshooting.md)。

---

## 崩溃原因（问题 B）

绕过 Print Spooler 问题后，Primer Premier 5 仍会立即崩溃。Windows 事件日志显示：

```text
Faulting module:  xnmba458.dll
Version:          4.58.0.0
Exception code:   0xc0000005
Fault offset:     0x000154fb
```

对 LocalDump 的 WinDbg 分析显示，非法指针读取发生在 `xnmba458!xvtwi_Init+0x4be`：

```asm
1c0154f5  mov  edx, [ebp-84h]        ; xvtk_vobj_get_attr(0, 0x12D) 的返回值
1c0154fb  cmp  dword ptr [edx+54h], 0   <-- 崩溃点
```

`xvtk_vobj_get_attr(0, 0x12D)` 在某些情况下会返回一个**很小的非零值**，而它并不是有效的对象指针。
在实机调试和崩溃转储中观察到的值：

```text
0x4D8
0x9B0
```

旧版 XVT 代码只检查 `NULL`。由于 `0x4D8 != 0`，检查通过，该值被当作指针使用，
随后解引用 `[edx+0x54]` 触发访问违例。

---

## 修复方式

将执行流从 `0x154F5` 重定向到位于 `0x48EE0` 的代码洞（原文件中的全零填充区）。
代码洞中重新实现原有两条指令，并加入一个保守的低地址保护：

```asm
mov  edx, [ebp-84h]
cmp  edx, 10000h            ; 本补丁使用的兼容性保护阈值
jb   0x1559C                ; 跳转到 XVT 原有的 fallback 路径
cmp  dword ptr [edx+54h], 0
jmp  0x154FF
```

* 对象地址 `>= 0x10000` 时，保持 **XVT 原始执行路径**不变。
* 明显非法的低地址被引导到 **XVT 中原本就存在的 fallback 路径**——不新增任何行为，
  也没有删除 XVT 的初始化过程。

### 关于 `0x10000` 的准确表述

`0x10000` 是**本补丁引入的保守低地址保护阈值**，用于在解引用之前拒绝明显非法的低地址。

它**不是** XVT 官方定义的语义边界。目前没有证据表明 XVT 官方规定小于 `0x10000`
的指针就是无效的。请不要把本补丁描述为实现了某项 XVT 官方规则。

### 字节级补丁数据

全文件仅修改 **33 字节**，分布在两个区域。

```text
文件偏移 0x154F5  （10 字节）
  原始：8B 95 7C FF FF FF 83 7A 54 00
  修改：E9 E6 39 03 00 90 90 90 90 90

文件偏移 0x48EE0  （27 字节，原文件为零填充）
  原始：00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  修改：8B 95 7C FF FF FF 81 FA 00 00 01 00 0F 82 AA C6 FC FF 83 7A 54 00 E9 04 C6 FC FF
```

---

## 支持的 DLL

```text
文件名    : xnmba458.dll
大小      : 360960 字节
版本      : 4.58.0.0
时间戳    : 1998-05-13
架构      : x86 (i386)
ImageBase : 0x1C000000
```

| | SHA256 |
|---|---|
| **原始文件（必需输入）** | `6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9` |
| **补丁后（预期输出）** | `77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0` |

如果你的 DLL 与上述原始 SHA256 不完全一致，补丁脚本**会拒绝执行**。

---

## 使用方法

1. 找到你的 Primer Premier 5 安装目录。
2. 在该目录中找到 `xnmba458.dll`。
3. 下载 [`patch/patch-xnmba458.ps1`](patch/patch-xnmba458.ps1)。
4. 关闭 Primer Premier 5。
5. 对 DLL 运行补丁脚本：

   ```powershell
   .\patch-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
   ```

6. 脚本会在做任何修改之前校验文件大小、SHA256 和原始机器码。
7. 自动创建备份 `xnmba458.dll.original`。
8. 脚本会再次校验结果是否匹配预期的补丁后 SHA256。
9. 启动 Primer Premier 5。

可选参数：

```powershell
-DryRun         # 执行全部检查，但不写入任何字节
-Force          # 覆盖已存在的备份文件
-KeepReadOnly   # 补丁完成后恢复只读属性
```

### 还原

```powershell
.\restore-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

还原脚本会先校验备份的 SHA256，确认无误后才覆盖，并在还原后再次校验。

---

## 补丁脚本的安全机制

以下任何一项检查失败，脚本都会**立即中止**，绝不会采用「尽力而为」的方式继续：

1. 文件存在。
2. 文件大小恰好为 `360960` 字节。
3. SHA256 匹配受支持的原始版本。
4. `0x154F5` 处的原始机器码匹配 `8B 95 7C FF FF FF 83 7A 54 00`。
5. `0x48EE0` 处的代码洞区域是未被占用的全零填充。
6. 在写入之前存在有效备份（或已成功创建）。
7. 补丁后重新读取两个位置的字节并逐字节比对。
8. 补丁后全文件 SHA256 匹配 `77C7C009…62BE0`。

如果 DLL 已经是打过补丁的状态，脚本会提示并正常退出。如果 DLL 是未知版本：

```text
Unsupported xnmba458.dll version. Patch aborted.
```

未知版本**不会**按固定 RVA 强行修改。请
[提交 Issue](../../issues/new/choose)，附上 DLL 大小、版本、SHA256 和崩溃签名。

---

## 本补丁未覆盖的已知问题

在 Print Spooler 服务运行的情况下，部分系统仍会出现 XVT 错误：

```text
ERROR: MSG 0x0073c35f [CAT 7/3 STD 50015]
Category: Underlying system generated error [Toolkit error]
Function: xvt_vobj_get_attr / xvt_app_create
File:     wprnt.c
Line:     763
```

这与 `xnmba458.dll` 访问违例是**两个不同的问题**。启动 Primer Premier 5 之前停止
Print Spooler 可以绕过该问题：

```powershell
Stop-Service Spooler -Force
```

这一层目前尚未完成真正的永久修复。详见
[`docs/troubleshooting.md`](docs/troubleshooting.md)。

---

## 已知限制

* 仅在一个 `xnmba458.dll` 版本（上述 SHA256）上完成验证。
* 尚未在所有 Windows 10/11 Build 上测试，测试矩阵见
  [`docs/technical-analysis.md`](docs/technical-analysis.md)。
* 不是官方补丁，与软件原厂无隶属或认可关系。
* 不修复 Print Spooler / `wprnt.c` 问题。
* 不涉及、不替换、不绕过任何授权、激活或保护机制。本仓库不包含破解、注册机或授权绕过内容，
  也不接受此类提交。
* `0x10000` 是一个务实的保护阈值，不是有文档记载的 XVT 常量。

---

## 文档

| 文档 | 内容 |
|---|---|
| [`docs/technical-analysis.md`](docs/technical-analysis.md) | 完整分析：转储、WinDbg、反汇编、PE 结构、补丁设计与验证 |
| [`docs/crash-analysis.md`](docs/crash-analysis.md) | 崩溃签名速查，以及如何自行抓取转储 |
| [`docs/troubleshooting.md`](docs/troubleshooting.md) | Print Spooler / `wprnt.c` 问题及其他启动问题 |

---

## 法律说明

`xnmba458.dll` 是 Primer Premier 附带的原始 XVT Runtime 组件。本项目在**用户自己的机器上**、
对**用户自己已拥有的文件**修改了少量字节，不重新分发任何商业二进制文件。

[LICENSE](LICENSE) 仅覆盖本仓库中的原创脚本与文档，不对 Primer Premier、XVT 及其任何组件或
商标主张任何权利。所有商标归各自所有者所有。

---

## 关键词

`Primer Premier 5` · `Primer Premier 5.0` · `xnmba458.dll` · `XVT 4.58` ·
`0xc0000005` · `xvtwi_Init` · `xvt_vobj_get_attr` · `wprnt.c` · `Windows 10` ·
`Windows 11` · `闪退修复` · `兼容性补丁`
