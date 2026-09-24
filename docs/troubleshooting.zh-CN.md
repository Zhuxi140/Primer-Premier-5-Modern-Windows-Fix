# 故障排查

> **语言 / Language:** **中文** · [**English → troubleshooting.md**](troubleshooting.md)
>
> 本文档的英文版位于 [`docs/troubleshooting.md`](troubleshooting.md)。
> 英文版为技术内容的原始记录，中文版为对应译文；两者内容一一对应。

Primer Premier 5 在现代 Windows 上的常见启动问题，以及目前对每个问题的已知情况。

---

## 1. 「Primer Premier 5 启动后立即崩溃」（C0000005）

查看 Windows 事件日志。如果看到：

```text
Faulting module name: xnmba458.dll
Exception code:       0xc0000005
Fault offset:         0x000154fb
```

那么这就是**问题 B**，本仓库的补丁针对的正是它。

先核验你的 DLL：

```powershell
Get-FileHash .\xnmba458.dll -Algorithm SHA256
(Get-Item .\xnmba458.dll).Length
```

受支持版本的预期值：

```text
Length : 360960
SHA256 : 6FF40C2B8A9C63C403F529106C154E72BF5B818E112F4204F05D66394CF4BBF9
```

如果一致，运行 `patch-xnmba458.ps1`。如果不一致，**不要打补丁**——
请提交 Issue 并附上你的大小、版本和哈希。

---

## 2. 「XVT Toolkit Error / wprnt.c 第 763 行」（问题 A）

完整信息：

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

### 状态

**本补丁未修复此问题。** 这是旧 XVT Runtime 的打印初始化与现代 Windows Print Spooler
之间**另一个独立**的兼容性问题。

### 绕过方案

在启动 Primer Premier 5 之前停止 Print Spooler：

```powershell
Stop-Service Spooler -Force
```

然后启动程序。Toolkit 错误应当不再出现，程序会继续进入下一阶段初始化。

如果之后需要用其他程序打印，可以重新启动该服务：

```powershell
Start-Service Spooler
```

控制该服务需要以管理员权限运行 PowerShell。

### 已排查过、**不是**原因的事项

* 默认打印机已配置（测试机器上设置为 `Microsoft Print to PDF`）。
* 系统中存在多台打印机。
* `ERRCODES.TXT` 缺失。创建它只会让错误信息**更具体**，并不能修复故障。
* 缺少 `MSVCIRT.dll` / `WINMM.dll` / `WINSPOOL.DRV` / `WINHTTP.dll` / `IppCommon.dll`。
  这些在程序目录中解析为 `NAME NOT FOUND`，但能从 `C:\Windows\SysWOW64\` 正常加载。

### ⚠ 不要从第三方「DLL 修复」网站下载 DLL

那些站点在这里不是解决方案，而且往系统目录里塞来路不明的 DLL 是实实在在的安全风险。
所需的系统库本来就已经存在。

---

## 3. 「Some of the required files have been missing or corrupted. Please reinstall the application.」

这条信息可能与上面的 Toolkit 错误同时出现，而且具有**误导性**。
它并不能证明你的安装已损坏。见
[`technical-analysis.zh-CN.md` §4](technical-analysis.zh-CN.md#4-已排除缺少-msvcirtdll等假设)。

重装程序既不能修复问题 A，也不能修复问题 B。

---

## 4. 补丁脚本拒绝运行

```text
Unsupported xnmba458.dll version. Patch aborted.
```

这是**有意为之**。补丁会校验：

1. 文件大小恰好为 `360960` 字节；
2. SHA256 恰好为 `6FF40C2B…4BBF9`；
3. `0x154F5` 处的原始机器码为 `8B 95 7C FF FF FF 83 7A 54 00`；
4. `0x48EE0` 处的 code cave 区域是未被占用的全零填充。

任何一项不通过，脚本都会在**不写入任何字节**的情况下停止。
不存在「尽力而为」模式，将来也不会有——按固定偏移去改未知版本，
有可能破坏一个布局完全无关的文件。

**正确的做法：** 提交 Issue 并附上：

```text
xnmba458.dll 大小
xnmba458.dll 版本
xnmba458.dll SHA256
事件日志中的 Faulting module / Exception code / Fault offset
```

之后可以针对该版本单独开发一个 patch profile。

---

## 5. 「This DLL is already patched」

该文件的 SHA256 已经等于：

```text
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

无需再做任何事。如果程序仍然崩溃，说明原因在别处——请重新查看事件日志。

---

## 6. 我想撤销补丁

```powershell
.\restore-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

脚本会先校验 `xnmba458.dll.original` 是否匹配已知的原始 SHA256，确认无误后才覆盖，
并在还原后再次校验。

如果备份缺失或哈希不对，脚本会拒绝执行。这种情况下，请从你自己的安装介质或备份中
恢复该 DLL。

---

## 7. 程序能启动但行为异常

本补丁只修改了一个运行库模块中的 33 个字节，除此之外什么都没动。
它不会改动 Primer 自身的代码、数据文件、授权处理或配置。

如果你观察到与之无关的不稳定现象：

* 确认补丁后 DLL 的哈希与预期的 patched SHA256 一致；
* 确认你没有同时替换该目录下的其他 DLL；
* 检查 Print Spooler 是否在运行（问题 A 可能仍然存在）；
* 提交 Issue 描述该现象。

---

## 8. 杀毒软件或 SmartScreen 对脚本报警

脚本是纯文本、可读的 PowerShell。它们只会：

* 计算 SHA256 哈希；
* 在两个固定文件偏移处比对字节；
* 复制一个文件；
* 向文件的两个区域写入字节。

它们不下载任何内容、不访问网络、不修改注册表，也不会碰你指定 DLL 之外的任何文件。

建议在运行前先自行阅读：
[`patch/patch-xnmba458.ps1`](../patch/patch-xnmba458.ps1)、
[`patch/restore-xnmba458.ps1`](../patch/restore-xnmba458.ps1)。

如果执行策略阻止脚本运行，可以这样执行一次：

```powershell
powershell -ExecutionPolicy Bypass -File .\patch-xnmba458.ps1 -Path "C:\Primer Premier 5\xnmba458.dll"
```

---

## 9. 已知问题：已打补丁但仍然崩溃

确认补丁确实生效：

```powershell
Get-FileHash "C:\Primer Premier 5\xnmba458.dll" -Algorithm SHA256
```

预期值：

```text
77C7C00971B2E72A5364BE27533E5FE21B9DE5FFC38C1986776BE38D1E362BE0
```

如果哈希一致但程序仍然崩溃，说明故障在别处。
请抓取转储（见 [`crash-analysis.zh-CN.md`](crash-analysis.zh-CN.md)）并提交 Issue。
请附上新的崩溃偏移——**不同的偏移意味着不同的问题**，而本补丁有意不去改动
那些尚未被证明会发生故障的代码路径。
