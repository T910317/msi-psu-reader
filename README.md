# msi-psu-reader

Read live power telemetry (output watts, efficiency, temperature, rail voltages/currents) from an MSI MEG Ai-series power supply over its USB HID link — without MSI Center.

**English** | [繁體中文](README.zh-TW.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

---

## Project status

v0.1.1 fixes Windows reply validation and timeout handling; see [CHANGELOG](CHANGELOG.md). The two-machine hardware checks below apply to v0.1.0. The v0.1.1 changes have offline regression coverage but have not been re-tested on a physical PSU. This release keeps the one-shot CLI; it does not add a high-frequency collector or claim a hardware update rate.

Offline Windows tests (no PSU access):

```powershell
powershell -NoProfile -File windows\tests\test_transport.ps1
powershell -NoProfile -File windows\tests\test_parser.ps1
```

- **Command-line only — there is no GUI yet.** Each run reads the PSU once and prints the result. To monitor continuously, run it on a schedule (see [Calling it from other programs](#calling-it-from-other-programs)).
- Windows version: tested on two machines with an MSI MEG Ai1300P.
- Linux version: written to the same protocol, **not yet tested on real hardware**.
- **Being considered: a Home Assistant sensor.** The plan is to expose wall power, output power, efficiency and temperature as HA sensors so energy dashboards can use real PSU readings. Nothing is published for this yet; the JSON output below is already in a shape HA can consume.

## Supported hardware

| Model | USB ID | Status |
|---|---|---|
| MSI MEG Ai1300P | `0DB0:56D4` | Tested (Windows, two machines) |

Other MSI Ai-series units may use the same protocol with a different product ID (`-ProductId` / `--pid`), but they have **not** been tested.

## Usage

### Windows

PowerShell 5.1 (built in). No install, no admin rights.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File windows\read_msi_psu.ps1
```

| Parameter | Default | Meaning |
|---|---|---|
| `-ProductId` | `0x56D4` | USB product ID of the PSU |

It always prints exactly **one line of JSON**, for example (shortened):

```json
{"ok":true,"pid":"56D4","at":"2026-10-28T05:26:02Z","watts_out":122.0,"efficiency":83.6,"watts_in":145.9,"temp_c":42.0,"fan_rpm":0, ...}
```

If the PSU cannot be read, `ok` is `false` and `error` explains why. The script still exits normally, so callers should check `ok`.

### Linux

Python 3, standard library only. **Not yet tested on real hardware.**

```sh
sudo python3 linux/msi_psu.py          # human-readable
sudo python3 linux/msi_psu.py --json   # one line of JSON (same fields as Windows)
```

| Option | Default | Meaning |
|---|---|---|
| `--json` | off | Print one line of JSON instead of a table |
| `--pid` | `0x56D4` | USB product ID of the PSU |
| `--device` | auto-detect | hidraw device path, e.g. `/dev/hidraw3` |

Access to `/dev/hidrawN` is needed (root, or a udev rule granting your user access to `0db0:56d4`).

Run the parser unit tests (no hardware needed):

```sh
python3 -m unittest discover -s linux/tests
```

### Calling it from other programs

Run the reader, take the last line of output, and parse it as JSON. Python example (Windows):

```python
import json, subprocess

out = subprocess.run(
    ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
     "-File", r"windows\read_msi_psu.ps1"],
    capture_output=True, text=True, timeout=30).stdout
r = json.loads(out.strip().splitlines()[-1])
if r["ok"]:
    print(f"wall ≈ {r['watts_in']} W, output {r['watts_out']} W, efficiency {r['efficiency']} %")
else:
    print("read failed:", r["error"])
```

- Polling once a minute (e.g. Windows Task Scheduler, cron, systemd timer) works well. A single read takes a few seconds at most (most of it is PowerShell compiling the helper on the Windows side).
- To read a PSU on another machine, run the same command over SSH and parse its output the same way.
- MSI Center may keep running at the same time.

## Output fields

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

## Protocol notes

Written from observation and public sources; not an official specification.

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

## Acknowledgements

This project is an independent rewrite — no code was copied — but it would not exist without the people who worked out this PSU's protocol first. Thank you:

- **Jack Doan** — [JackDoan/msi-psu](https://github.com/JackDoan/msi-psu), a Linux kernel driver for these PSUs ([patch on LKML](https://patchew.org/linux/20240212174859.3321000-1-me@jackdoan.com)). The original inspiration for this project.
- [onlyjco/msi-psu-tool](https://github.com/onlyjco/msi-psu-tool) — cross-platform Python reader.
- [boboom66/msi-psu-monitor](https://github.com/boboom66/msi-psu-monitor) — Linux monitor.
- [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor) — includes support for these PSUs.

Please check each project for its own license.

## Disclaimer

This is an independent project. It is **not affiliated with, endorsed by, or supported by MSI**. The tools only send the two read commands above and never send write/configuration commands, but you use them at your own risk. See [LICENSE](LICENSE) (MIT).
