# msi-psu-reader

不開 MSI Center，直接從 USB 讀 MSI MEG Ai 系列電源的即時數據：輸出瓦數、效率、溫度、各路電壓電流。

[English](README.md) | **繁體中文** | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

---

## 目前狀態

v0.1.1 修正 Windows 回覆驗證與逾時處理，詳見[更新紀錄](CHANGELOG.md)。下方兩台電腦的實測紀錄屬於 v0.1.0；v0.1.1 修正已通過離線回歸測試，尚未重新接電源實測。此版維持單次讀取，沒有新增高頻常駐模式，也未宣稱硬體更新頻率。

Windows 不接硬體即可執行的測試：

```powershell
powershell -NoProfile -File windows\tests\test_transport.ps1
powershell -NoProfile -File windows\tests\test_parser.ps1
```

- **只有命令列，還沒有圖形介面（GUI）。** 每跑一次讀一次電源、印出結果；要持續監看就用排程定時跑（見下方〈從其他程式呼叫〉）。
- Windows 版：已在兩台裝 MSI MEG Ai1300P 的電腦實測。
- Linux 版：照同一套協定寫成，**還沒在實機測過**。
- **正在考慮接進 Home Assistant 當感測器**：把牆上耗電、輸出瓦數、效率、溫度做成 HA 感測器，讓能源儀表板用電源的實際讀數。還沒釋出；下面的 JSON 輸出已經是 HA 能直接讀的格式。

## 支援機型

| 機型 | USB ID | 狀態 |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | 已實測（Windows，兩台電腦） |

其他 Ai 系列可能用同一套協定、只是產品編號不同（用 `-ProductId`／`--pid` 指定），但**沒測過**。

## 用法

### Windows

內建 PowerShell 5.1，不用安裝、不用系統管理員。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

| 參數 | 預設 | 說明 |
|---|---|---|
| `-ProductId` | `0x56D4` | 電源的 USB 產品編號 |

一定只印**一行 JSON**，例如（節錄）：

```json
{"ok":true,"pid":"56D4","at":"2026-10-28T05:26:02Z","watts_out":122.0,"efficiency":83.6,"watts_in":145.9,"temp_c":42.0,"fan_rpm":0, ...}
```

讀不到時 `ok` 是 `false`，原因寫在 `error`；程式照樣正常結束，呼叫的一方要自己看 `ok`。

### Linux

Python 3，只用標準函式庫。**還沒在實機測過。**

```sh
sudo python3 linux/msi_psu.py          # 給人看的表格
sudo python3 linux/msi_psu.py --json   # 一行 JSON（欄位同 Windows）
```

| 選項 | 預設 | 說明 |
|---|---|---|
| `--json` | 關 | 改印一行 JSON |
| `--pid` | `0x56D4` | 電源的 USB 產品編號 |
| `--device` | 自動尋找 | hidraw 裝置路徑，例如 `/dev/hidraw3` |

需要能讀寫 `/dev/hidrawN`（用 root，或加 udev 規則開放 `0db0:56d4`）。

不接電源也能跑的解析測試：

```sh
python3 -m unittest discover -s linux/tests
```

### 從其他程式呼叫

執行讀取程式、取輸出的最後一行、當 JSON 解析。Python 範例（Windows）：

```python
import json, subprocess

out = subprocess.run(
    ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
     "-File", r"windows\read_msi_psu.ps1"],
    capture_output=True, text=True, timeout=30).stdout
r = json.loads(out.strip().splitlines()[-1])
if r["ok"]:
    print(f"牆上約 {r['watts_in']} W，輸出 {r['watts_out']} W，效率 {r['efficiency']} %")
else:
    print("讀取失敗：", r["error"])
```

- 每分鐘讀一次很合適（Windows 工作排程器、cron、systemd timer 都行）；一次讀取最多幾秒，大部分是 Windows 那邊 PowerShell 在編譯輔助程式。
- 要讀別台電腦的電源，用 SSH 在那台執行同一行指令，輸出照樣解析。
- MSI Center 可以同時開著。

## 輸出欄位

| 欄位 | 說明 |
|---|---|
| `ok` | 讀取成功為 `true`；失敗看 `error` |
| `pid` | 查詢的 USB 產品編號 |
| `at` | UTC 時間 |
| `watts_out` | 電源回報的直流**輸出**瓦數 |
| `efficiency` | 電源回報的效率（%） |
| `watts_in` | **推算**的牆上輸入瓦數＝輸出 ÷（效率 ÷ 100） |
| `temp_c` | 電源溫度（°C） |
| `fan_rpm` | 風扇轉速（半被動模式停轉時為 0） |
| `v12_total` | 12V 合計：`v` 電壓、`a` 電流 |
| `v12_rails` | 12V 第 1～5 路，各為 `{v, a}` |
| `v5`、`v3_3` | 5V、3.3V，各為 `{v, a}` |
| `raw` | 原始回覆前 48 位元組（十六進位） |

**注意：** 電源回報的是**輸出**瓦數；牆上輸入瓦數**不是量到的**，是用輸出和電源自己報的效率推算，請當估計值。

## 協定說明

依實際觀察和公開資料整理，不是官方規格。

- 電源是 USB HID 裝置，報告長度 64 位元組；Windows 和 Linux hidraw 寫入時都要在前面補一個報告編號 `0x00`，共 65 位元組。
- 每個指令兩個位元組，回覆開頭會照抄這兩個位元組；回覆第 2 個位元組是 `0xFE` 表示電源拒絕。
- `FA 51` 是握手，讀之前先送一次。
- `51 E0` 一次讀回全部數值。照抄的兩位元組之後是資料區，每 2 位元組一個小端序 PMBus **Linear11** 數值（高 5 位元是有號指數、低 11 位元是有號尾數，值＝尾數 × 2^指數）：

| 資料位移（位元組） | 內容 |
|---|---|
| 0–19 | 12V 第 1～5 路，各為電壓、電流 |
| 20 / 22 | 12V 合計電壓／電流 |
| 24 / 26 | 5V 電壓／電流 |
| 28 / 30 | 3.3V 電壓／電流 |
| 32 | 輸出瓦數 |
| 34 | 效率（%） |
| 36 | 溫度（°C） |
| 38 | 風扇轉速（RPM） |

- MSI Center 等軟體可能同時在問電源，讀到不是自己指令的回覆會丟掉重讀。

## 致謝

本專案是獨立重寫、沒有複製任何程式碼，但如果沒有前人先把這顆電源的協定摸清楚，就不會有它。感謝：

- **Jack Doan**：[JackDoan/msi-psu](https://github.com/JackDoan/msi-psu)，這系列電源的 Linux 核心驅動（[LKML 上的修補](https://patchew.org/linux/20240212174859.3321000-1-me@jackdoan.com)），也是本專案最初的靈感來源。
- [onlyjco/msi-psu-tool](https://github.com/onlyjco/msi-psu-tool)：跨平台的 Python 讀取工具。
- [boboom66/msi-psu-monitor](https://github.com/boboom66/msi-psu-monitor)：Linux 監看工具。
- [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)：已支援這系列電源。

各專案的授權請以它們自己的說明為準。

## 免責聲明

本專案是個人獨立作品，**不是 MSI 官方程式，也未經 MSI 認可或支援**。程式只送上述兩個讀取指令，不送任何寫入或設定指令；使用風險自負。授權見 [LICENSE](LICENSE)（MIT）。
