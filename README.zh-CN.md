# msi-psu-reader

不开 MSI Center，直接通过 USB 读取 MSI MEG Ai 系列电源的实时数据：输出功率、效率、温度、各路电压电流。

[English](README.md) | [繁體中文](README.zh-TW.md) | **简体中文** | [日本語](README.ja.md)

---

## 当前状态

- **只有命令行，还没有图形界面（GUI）。** 每运行一次读取一次电源并打印结果；如需持续监控，请用计划任务定时运行（见下方「从其他程序调用」）。
- Windows 版：已在两台装有 MSI MEG Ai1300P 的电脑上实测。
- Linux 版：按同一协议编写，**尚未在实机上测试**。
- **正在考虑接入 Home Assistant 作为传感器**：把墙上功耗、输出功率、效率、温度做成 HA 传感器，供能源面板使用电源的实际读数。尚未发布；下面的 JSON 输出已经是 HA 可直接读取的格式。

## 支持机型

| 机型 | USB ID | 状态 |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | 已实测（Windows，两台电脑） |

其他 Ai 系列可能使用同一协议、只是产品编号不同（用 `-ProductId`／`--pid` 指定），但**未测试**。

## 用法

### Windows

系统自带 PowerShell 5.1，无需安装、无需管理员权限。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

参数 `-ProductId`（默认 `0x56D4`）：电源的 USB 产品编号。始终只输出**一行 JSON**；读取失败时 `ok` 为 `false`，原因在 `error`，程序仍正常退出，调用方需自行检查 `ok`。

### Linux

Python 3，仅用标准库。**尚未在实机上测试。**

```sh
sudo python3 linux/msi_psu.py          # 便于阅读的表格
sudo python3 linux/msi_psu.py --json   # 一行 JSON（字段同 Windows）
```

选项：`--json` 输出 JSON；`--pid` USB 产品编号（默认 `0x56D4`）；`--device` hidraw 设备路径（默认自动查找）。需要能读写 `/dev/hidrawN`（root，或添加 udev 规则开放 `0db0:56d4`）。

### 从其他程序调用

运行读取程序，取输出的最后一行，按 JSON 解析。Python 示例见 [英文说明](README.md#calling-it-from-other-programs)。每分钟读取一次即可（Windows 任务计划程序、cron、systemd timer 均可）；读取其他电脑上的电源，用 SSH 在那台电脑上执行同一条命令即可。

## 输出字段

字段说明见 [英文表格](README.md#output-fields)。要点：

- `watts_out` 是电源上报的**输出**功率。
- `watts_in` 是**推算**的墙上输入功率＝输出 ÷ 效率，并非实测。
- `fan_rpm` 为 0 表示风扇在半被动模式下停转。

## 协议说明

见 [英文说明](README.md#protocol-notes)：`FA 51` 握手，`51 E0` 一次读取全部数值，数值为小端序 PMBus Linear11 格式。

## 致谢

本项目为独立重写、未复制任何代码，但离不开先行者对该电源协议的研究。感谢：

- **Jack Doan**：[JackDoan/msi-psu](https://github.com/JackDoan/msi-psu)，该系列电源的 Linux 内核驱动（[LKML 补丁](https://patchew.org/linux/20240212174859.3321000-1-me@jackdoan.com)），也是本项目最初的灵感来源。
- [onlyjco/msi-psu-tool](https://github.com/onlyjco/msi-psu-tool)
- [boboom66/msi-psu-monitor](https://github.com/boboom66/msi-psu-monitor)
- [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)

## 免责声明

本项目为个人独立作品，**并非 MSI 官方程序，也未经 MSI 认可或支持**。程序只发送上述两条读取命令，不发送任何写入或设置命令；使用风险自负。许可证见 [LICENSE](LICENSE)（MIT）。
