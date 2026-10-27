#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Read live telemetry from an MSI MEG Ai1300P power supply over Linux hidraw.

*** NOT TESTED ON REAL HARDWARE (Linux). ***
*** 未在實機測試（Linux 版）。解析邏輯有單元測試，USB 讀寫部分沒有實機驗證。***

Standard library only. Sends only two READ commands (handshake FA 51, read-all 51 E0);
never sends write commands, so it cannot change PSU settings.

Usage:
    sudo python3 msi_psu.py [--json] [--pid 0x56D4] [--device /dev/hidrawN]

You need read/write access to the /dev/hidrawN node (run as root or add a udev rule).
"""
import argparse
import glob
import json
import os
import select
import sys
import time

VENDOR_ID = 0x0DB0
DEFAULT_PRODUCT_ID = 0x56D4
REPORT_LEN = 64
CMD_HANDSHAKE = bytes([0xFA, 0x51])
CMD_READ_ALL = bytes([0x51, 0xE0])
REJECT = 0xFE


def linear11(lo, hi):
    """Decode a PMBus Linear11 value: top 5 bits signed exponent, low 11 bits signed mantissa."""
    v = lo | (hi << 8)
    exp = v >> 11
    if exp >= 16:
        exp -= 32
    mant = v & 0x7FF
    if mant >= 1024:
        mant -= 2048
    return round(mant * (2.0 ** exp), 3)


def find_echo(reply, cmd):
    """Return the index where the command echo starts (0 or 1, the latter if a report ID precedes it), or -1."""
    for k in (0, 1):
        if k + 1 < len(reply) and reply[k] == cmd[0] and reply[k + 1] == cmd[1]:
            return k
    return -1


def parse_read_all(reply):
    """Parse a reply to 51 E0 into a dict. Raises ValueError on rejection or malformed data."""
    reply = bytes(reply)
    base = find_echo(reply, CMD_READ_ALL)
    if base < 0:
        if (len(reply) > 1 and reply[1] == REJECT) or (len(reply) > 2 and reply[2] == REJECT):
            raise ValueError("PSU rejected the read command")
        raise ValueError("reply does not start with 51 E0: " + reply[:8].hex(" ").upper())
    d = base + 2  # start of data area, right after the echo
    if len(reply) < d + 40:
        raise ValueError("reply too short")

    def val(off):
        return linear11(reply[d + off], reply[d + off + 1])

    rails = [{"v": val(n * 4), "a": val(n * 4 + 2)} for n in range(5)]
    watts = val(32)
    eff = val(34)
    if 0 < eff <= 1:  # some firmware may report 0..1
        eff = round(eff * 100, 2)
    return {
        "watts_out": watts,
        "efficiency": eff,
        # Input (wall) power is an estimate: output / efficiency.
        "watts_in": round(watts / (eff / 100), 1) if eff > 0 else None,
        "temp_c": val(36),
        "fan_rpm": val(38),
        "v12_total": {"v": val(20), "a": val(22)},
        "v12_rails": rails,
        "v5": {"v": val(24), "a": val(26)},
        "v3_3": {"v": val(28), "a": val(30)},
        "raw": reply[:48].hex().upper(),
    }


def find_hidraw(vid, pid):
    """Find /dev/hidrawN whose uevent HID_ID matches vid:pid."""
    for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            with open(os.path.join(path, "device", "uevent")) as f:
                for line in f:
                    if line.startswith("HID_ID="):
                        # format: HID_ID=0003:00000DB0:000056D4
                        parts = line.strip().split("=", 1)[1].split(":")
                        if len(parts) == 3 and int(parts[1], 16) == vid and int(parts[2], 16) == pid:
                            return "/dev/" + os.path.basename(path)
        except OSError:
            continue
    return None


def ask(fd, cmd, timeout):
    """Write one command (report ID 0 + 64 bytes) and read back the report that echoes it."""
    out = bytes([0]) + cmd + bytes(REPORT_LEN - len(cmd))
    os.write(fd, out)
    until = time.monotonic() + timeout
    for _ in range(6):  # other software may be polling too; skip replies to other commands
        left = until - time.monotonic()
        if left <= 0:
            break
        ready, _, _ = select.select([fd], [], [], left)
        if not ready:
            break
        r = os.read(fd, REPORT_LEN + 1)
        for k in (0, 1):
            if k + 1 < len(r) and r[k] == cmd[0] and r[k + 1] in (cmd[1], REJECT):
                return r
    raise TimeoutError("PSU did not respond")


def query(device, timeout=2.0):
    fd = os.open(device, os.O_RDWR)
    try:
        ask(fd, CMD_HANDSHAKE, timeout)
        return ask(fd, CMD_READ_ALL, timeout)
    finally:
        os.close(fd)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Read MSI MEG Ai1300P PSU telemetry (read-only).")
    ap.add_argument("--json", action="store_true", help="print one line of JSON")
    ap.add_argument("--pid", type=lambda s: int(s, 0), default=DEFAULT_PRODUCT_ID, help="USB product ID (default 0x56D4)")
    ap.add_argument("--device", help="hidraw device path (default: auto-detect)")
    args = ap.parse_args(argv)

    out = {"ok": False, "pid": "%04X" % args.pid,
           "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    try:
        dev = args.device or find_hidraw(VENDOR_ID, args.pid)
        if not dev:
            raise OSError("MSI PSU hidraw device not found")
        out.update(parse_read_all(query(dev)))
        out["ok"] = True
    except Exception as e:  # report any failure in the output instead of a traceback
        out["error"] = str(e)

    if args.json:
        print(json.dumps(out, separators=(",", ":")))
    elif out["ok"]:
        print("Output  : %s W" % out["watts_out"])
        print("Input   : %s W (estimated)" % out["watts_in"])
        print("Eff.    : %s %%" % out["efficiency"])
        print("Temp    : %s C   Fan: %s RPM" % (out["temp_c"], out["fan_rpm"]))
        print("12V     : %s V / %s A" % (out["v12_total"]["v"], out["v12_total"]["a"]))
        print("5V      : %s V / %s A" % (out["v5"]["v"], out["v5"]["a"]))
        print("3.3V    : %s V / %s A" % (out["v3_3"]["v"], out["v3_3"]["a"]))
    else:
        print("error: " + out["error"], file=sys.stderr)
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
