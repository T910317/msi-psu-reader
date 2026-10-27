# msi-psu-reader

Read live power telemetry (output watts, efficiency, temperature, rail voltages/currents) from an MSI MEG Ai-series power supply over its USB HID link — without MSI Center.

[English](#english) | [繁體中文](#繁體中文)

---

## English

### Supported hardware

| Model | USB ID | Status |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | Tested (Windows, two machines) |

Other MSI Ai-series units may use the same protocol with a different product ID (`-ProductId` / `--pid`), but they have **not** been tested.

### Usage

**Windows** (PowerShell 5.1, built in; no install, no admin rights):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

**Linux** (Python 3, standard library only; **not yet tested on real hardware**):

```sh
sudo python3 linux/msi_psu.py          # human-readable
sudo python3 linux/msi_psu.py --json   # one line of JSON
```

Access to `/dev/hidrawN` is needed (root, or a udev rule granting your user access to `0db0:56d4`).

Run the parser unit tests (no hardware needed):

```sh
python3 -m unittest discover -s linux/tests
```

### Output fields

| Field | Meaning |
|---|---|
| `ok` | `true` if the read succeeded; otherwise see `error` |
| `pid` | USB product ID queried |
| `at` | UTC timestamp |
| `watts_out` | DC output power reported by the PSU (W) |
| `efficiency` | Efficiency reported by the PSU (%) |
| `watts_in` | **Estimated** AC input power = `watts_out / (efficiency / 100)` |
| `temp_c` | PSU temperature (°C) |
| `fan_rpm` | Fan speed (0 when the fan is stopped in semi-passive mode) |
| `v12_total` | 12 V total: `v` volts, `a` amps |
| `v12_rails` | 12 V rails 1–5, each `{v, a}` |
| `v5`, `v3_3` | 5 V and 3.3 V rails, each `{v, a}` |
| `raw` | First 48 bytes of the raw reply, hex |

**Important:** the PSU reports its *output* power. Wall (input) power is *not measured*; it is calculated from output and the PSU's own efficiency figure, so treat it as an estimate.

### Protocol notes

Written from observation; not an official specification.

- The PSU appears as a USB HID device using 64-byte reports. On both Windows and Linux hidraw, a report ID byte `0x00` is prepended when writing, so each write is 65 bytes.
- Every command is two bytes. The reply begins by echoing those two bytes. If the second byte of the reply is `0xFE`, the PSU rejected the command.
- `FA 51` is a handshake, sent once before reading.
- `51 E0` returns all readings at once. After the 2-byte echo, the data area is a sequence of 16-bit little-endian values in PMBus **Linear11** format (top 5 bits: signed exponent; low 11 bits: signed mantissa; value = mantissa × 2^exponent):

| Data offset (bytes) | Value |
|---|---|
| 0–19 | 12 V rails 1–5, each as voltage then current |
| 20 / 22 | 12 V total voltage / current |
| 24 / 26 | 5 V voltage / current |
| 28 / 30 | 3.3 V voltage / current |
| 32 | Output power (W) |
| 34 | Efficiency (%) |
| 36 | Temperature (°C) |
| 38 | Fan speed (RPM) |

- Other software (e.g. MSI Center) may poll the PSU at the same time, so a read can return a reply meant for someone else. The tools discard replies whose echo does not match and read again.

### Disclaimer

This is an independent project. It is **not affiliated with, endorsed by, or supported by MSI**. The tools only send the two read commands above and never send write/configuration commands, but you use them at your own risk. See [LICENSE](LICENSE).

---

## 繁體中文

### 這是什麼

不開 MSI Center，直接從 USB 讀 MSI MEG Ai 系列電源的即時數據：輸出瓦數、效率、溫度、各路電壓電流。

### 支援機型

| 機型 | USB ID | 狀態 |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | 已實測（Windows，兩台電腦） |

其他 Ai 系列可能用同一套協定、只是產品編號不同（用 `-ProductId`／`--pid` 指定），但**沒測過**。

### 用法

**Windows**（內建 PowerShell 5.1，不用安裝、不用系統管理員）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

**Linux**（Python 3，只用標準函式庫；**還沒在實機測過**）：

```sh
sudo python3 linux/msi_psu.py --json
```

需要能讀寫 `/dev/hidrawN`（用 root，或加 udev 規則開放 `0db0:56d4`）。

### 輸出欄位

欄位說明見上方英文表格。重點：

- `watts_out` 是電源回報的**輸出**瓦數。
- `watts_in` 是**推算**的牆上輸入瓦數＝輸出 ÷ 效率，不是實際量到的。
- `fan_rpm` 為 0 表示風扇在半被動模式停轉。

### 協定說明

依實際觀察整理，不是官方規格。

- 電源是 USB HID 裝置，報告長度 64 位元組；Windows 和 Linux hidraw 寫入時都要在前面補一個報告編號 `0x00`，共 65 位元組。
- 每個指令兩個位元組，回覆開頭會照抄這兩個位元組；回覆第 2 個位元組是 `0xFE` 表示電源拒絕。
- `FA 51` 是握手，讀之前先送一次。
- `51 E0` 一次讀回全部數值。照抄的兩位元組之後是資料區，每 2 位元組一個小端序 Linear11 數值（高 5 位元是有號指數、低 11 位元是有號尾數，值＝尾數 × 2^指數），位置見上方英文表格。
- MSI Center 等軟體可能同時在問電源，讀到不是自己指令的回覆會丟掉重讀。

### 免責聲明

本專案是個人獨立作品，**不是 MSI 官方程式，也未經 MSI 認可或支援**。程式只送上述兩個讀取指令，不送任何寫入或設定指令；使用風險自負。授權見 [LICENSE](LICENSE)（MIT）。
