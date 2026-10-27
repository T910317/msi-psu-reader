# msi-psu-reader

MSI Center を使わずに、USB 経由で MSI MEG Ai シリーズ電源のリアルタイム値（出力電力、効率、温度、各系統の電圧・電流）を読み取ります。

[English](README.md) | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | **日本語**

---

## 現在の状況

- **コマンドラインのみで、GUI はまだありません。** 1 回の実行で電源を 1 回読み取り、結果を出力します。継続的に監視する場合はタスクスケジューラなどで定期実行してください（下記「他のプログラムから呼び出す」を参照）。
- Windows 版：MSI MEG Ai1300P を搭載した 2 台の PC で動作確認済み。
- Linux 版：同じプロトコルで実装済みですが、**実機ではまだ未検証**です。
- **Home Assistant のセンサーとして組み込むことを検討中**です。壁側消費電力・出力電力・効率・温度を HA センサーにして、エネルギーダッシュボードで電源の実測値を使えるようにする計画です。まだ公開していませんが、下記の JSON 出力はそのまま HA で読み取れる形式です。

## 対応機種

| 機種 | USB ID | 状態 |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | 検証済み（Windows、2 台） |

他の Ai シリーズも製品 ID が違うだけで同じプロトコルの可能性があります（`-ProductId`／`--pid` で指定）が、**未検証**です。

## 使い方

### Windows

標準搭載の PowerShell 5.1 で動作。インストール不要、管理者権限不要。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

パラメーター `-ProductId`（既定 `0x56D4`）：電源の USB 製品 ID。出力は常に **JSON 1 行**です。読み取りに失敗すると `ok` が `false` になり、理由は `error` に入ります。スクリプト自体は正常終了するので、呼び出し側で `ok` を確認してください。

### Linux

Python 3、標準ライブラリのみ。**実機では未検証です。**

```sh
sudo python3 linux/msi_psu.py          # 人が読む表形式
sudo python3 linux/msi_psu.py --json   # JSON 1 行（Windows と同じ項目）
```

オプション：`--json` JSON で出力、`--pid` USB 製品 ID（既定 `0x56D4`）、`--device` hidraw デバイスのパス（既定は自動検出）。`/dev/hidrawN` へのアクセス権が必要です（root、または `0db0:56d4` を許可する udev ルール）。

### 他のプログラムから呼び出す

読み取りスクリプトを実行し、出力の最終行を JSON として解析します。Python の例は [英語版](README.md#calling-it-from-other-programs) を参照してください。1 分ごとの読み取りが目安です（タスクスケジューラ、cron、systemd timer など）。別の PC の電源を読む場合は、SSH でその PC 上で同じコマンドを実行します。

## 出力項目

詳細は [英語版の表](README.md#output-fields) を参照してください。要点：

- `watts_out` は電源が報告する**出力**電力です。
- `watts_in` は出力 ÷ 効率で**推定**した壁側入力電力で、実測値ではありません。
- `fan_rpm` が 0 のときは、セミパッシブモードでファンが停止しています。

## プロトコル

[英語版](README.md#protocol-notes) を参照してください。`FA 51` がハンドシェイク、`51 E0` で全項目を一括取得し、値はリトルエンディアンの PMBus Linear11 形式です。

## 謝辞

本プロジェクトはコードを一切コピーしない独自の再実装ですが、この電源のプロトコルを先に解明した方々の成果なしには成り立ちませんでした。感謝します：

- **Jack Doan**：[JackDoan/msi-psu](https://github.com/JackDoan/msi-psu)（このシリーズ用の Linux カーネルドライバー、[LKML のパッチ](https://patchew.org/linux/20240212174859.3321000-1-me@jackdoan.com)）。本プロジェクトの最初のきっかけです。
- [onlyjco/msi-psu-tool](https://github.com/onlyjco/msi-psu-tool)
- [boboom66/msi-psu-monitor](https://github.com/boboom66/msi-psu-monitor)
- [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)

## 免責事項

本プロジェクトは個人による独立した作品であり、**MSI の公式ソフトウェアではなく、MSI の承認やサポートも受けていません**。上記 2 つの読み取りコマンドのみを送信し、書き込みや設定変更のコマンドは一切送信しませんが、自己責任でご利用ください。ライセンスは [LICENSE](LICENSE)（MIT）を参照してください。
