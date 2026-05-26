# blue-merle v2 — GL-iNet Mudi 7 (GL-E5800)

A port of [SRLabs' blue-merle](https://github.com/srlabs/blue-merle) from the original Mudi (GL-E750) to the Mudi 7 (GL-E5800). The Mudi 7 ships with a completely different modem, a rewritten `gl_modem` wrapper, dual SIM + eSIM support, and no hardware switch — so this is a ground-up rewrite, not a patch.

---

## Features

| Feature | Description |
|---|---|
| **Dual IMEI rotation** | Randomize both modem IMEI slots independently on every SIM swap |
| **Three IMEI modes** | Per-slot: **Random** (Luhn-valid, band-matched TAC), **Deterministic** (stable hash of IMSI), or **Static** (fixed value) |
| **Wireless rotation** | Randomize BSSID/MAC, SSID, hostname, and Wi-Fi password |
| **SIM-swap protection** | Two-stage boot flow — throwaway IMEI written at shutdown, final IMEI written before first network attach on next boot |
| **Volatile MAC log** | `tmpfs` over GL-iNet's client MAC database — device history never hits flash |
| **Boot-time rotation** | Optional auto-rotate on every boot |
| **LuCI admin page** | Browser UI under Services → blue-merle |
| **GL-iNet UI sync** | Settings → About Device → IMEI updates automatically after rotation |

---

## Why this is a rewrite

| | Mudi v1 (GL-E750) | Mudi 7 (GL-E5800) |
|---|---|---|
| Modem | Quectel EP06 (LTE, USB) | Quectel **RG650V-NA** (5G, integrated MHI) |
| `gl_modem` syntax | `gl_modem AT <cmd>` | `gl_modem -B CPU -U <sub> AT <cmd>` |
| SIM support | Single SIM | Dual SIM + onboard eSIM (DSDS) |
| Trigger | 3-position hardware switch | LuCI / CLI (no switch on this hardware) |
| Modem power-off | `AT+QPOWD` | **`AT+QPOWD` bricks the modem** — replaced with `AT+CFUN` cycle |
| Wireless UCI | `@wifi-iface[N]` | Named interfaces (`wifi2g`, `wifi5g`, `wifi6g`, `sta`, `guest*g`) |
| Languages | sh + lua + Python | **sh + lua only** |

---

## Compatibility

- **Device:** GL-iNet GL-E5800 (Mudi 7)
- **Firmware:** GL.iNet 4.x (OpenWrt 23.05.4)
- **Tested modem firmware:** `RG650VNA01ACR02A04G8G`
- **Architecture:** `aarch64_cortex-a53`

---

## Prerequisites

LuCI must be enabled before installing. GL-iNet ships it bundled but off by default.

1. Open the GL-iNet web UI at `http://192.168.8.1`
2. Go to **System → Advanced Settings**
3. Click **Install Now** — this just starts the `uhttpd` web server, no internet needed
4. LuCI will be at `http://192.168.8.1/cgi-bin/luci`

---

## Installation

```sh
scp blue-merle_1.0.0-1_aarch64_cortex-a53.ipk root@192.168.8.1:/tmp/
ssh root@192.168.8.1 opkg install --force-reinstall /tmp/blue-merle_1.0.0-1_aarch64_cortex-a53.ipk
```

Expected output:

```
Installing blue-merle (1.0.0-1) to root...
Configuring blue-merle.
blue-merle: saving factory state...
  Factory IMEI slot1: 352000067890125
  Factory IMEI slot2: 352000067890133
  Factory SSID: GL-E5800-1A2B
  Factory hostname: GL-E5800
  Factory MAC (2.4 GHz): A8:22:42:1A:2B:3C
  Factory MAC (5 GHz): A8:22:42:1A:2B:3B
  ...
  STA MAC saved: 3A:47:9F:0C:11:82
blue-merle: factory state saved.
blue-merle: disabling GL-iNet BSSID randomization...
```

The admin page is available under **Services → blue-merle** in LuCI after install.

### Reinstalling / upgrading

Use the same command with `--force-reinstall`. Factory values are preserved on reinstall — the installer won't overwrite an existing factory record.

---

## Usage

### LuCI page

Navigate to **Services → blue-merle**. The page has four sections:

#### Current Identity

Live state read directly from the modem and UCI:

- **IMEI (Slot 1 / Slot 2)** — read via `AT+EGMR`
- **SSID / Guest SSID, MACs, Hostname**
- **Factory values** — saved at install time, shown for reference
- **Last rotate timestamps** — IMEI and wireless tracked separately

#### IMEI Rotation

Each slot has its own mode:

- **Random** — picks a TAC from the pool, appends random serial digits, computes Luhn check digit. The TAC pool is limited to 5G sub-6 devices whose band coverage overlaps the RG650V-NA, so the result looks like a real device on the same bands.
- **Deterministic** — hashes the SIM's IMSI to produce a stable IMEI. The same SIM always gets the same result. Useful if you want consistency without pinning to a static value. Falls back to random if no IMSI is readable.
- **Static** — write a specific IMEI. Validated for Luhn checksum before writing.

After clicking **Rotate IMEI**, the modem goes through an RF cycle (`AT+CFUN=4 → AT+CFUN=1`) and re-registers. Settings → About Device updates automatically.

#### Wireless Rotation

Rotates MACs (2.4/5/6 GHz, guest bands, repeater STA), SSID, hostname, and Wi-Fi password in one shot. Each option can be toggled independently.

#### Options

- **Rotate on boot** — auto-rotate on every boot via the `S10` init.d service
- Per-feature toggles for what counts as a "rotate"

#### Restore

Reverts everything to the factory values captured at install time.

---

### CLI

```sh
blue-merle rotate            # rotate IMEI (both slots, per configured mode)
blue-merle rotate-wireless   # rotate MACs / SSID / hostname / password
blue-merle restore           # restore all factory values
blue-merle sim-swap          # prep for SIM swap — writes throwaway IMEI then powers off
blue-merle status            # print current identity
blue-merle install           # re-run first-install setup (idempotent)
```

Example `rotate` output:

```
blue-merle: generating IMEIs...
  slot1 mode: random  →  new IMEI: 354491081234567
  slot2 mode: random  →  new IMEI: 860371059876543
blue-merle: writing IMEIs...
blue-merle: resetting modem for privacy...
blue-merle: done.
```

Example `sim-swap` output:

```
blue-merle: preparing for SIM swap...
blue-merle: writing throwaway IMEIs...
blue-merle: powering off. Swap your SIM and power back on.
```

Stage 2 runs automatically on the next boot and writes the final IMEIs before the modem first attaches.

---

## How It Works

### Boot sequence

```
S9  blue-merle-volatile-macs   Mounts tmpfs over /etc/oui-tertf. GL-iNet's
                                gl_clients binary writes MAC history to RAM
                                instead of flash. Cleared on every boot.

S10 blue-merle-wireless        If rotate_on_boot=1: rotates MACs/SSID/hostname/
                                password before the AP comes up.

S23 gl_cellular_manager        GL-iNet's modem init. First point where the AT
                                socket accepts commands.

S25 blue-merle-sim-swap        If /etc/blue-merle.sim-swap-pending exists:
                                  - Waits for AT socket ready
                                  - Disables RF (AT+CFUN=4)
                                  - Writes final IMEIs
                                  - Re-enables RF (AT+CFUN=1)
                                No reboot needed. gl_cellular_manager handles
                                registration from here with the correct identity.
```

The throwaway IMEI from Stage 1 is only live during the S23→S25 window, which is a few seconds at most.

### IMEI rotation

1. RF off (`AT+CFUN=4`) before any write
2. Both slots written via `AT+EGMR` (field 7 = Slot 1, field 11 = Slot 2)
3. RF on (`AT+CFUN=1`), re-register (`AT+COPS=0`)
4. `gl_cellular_manager` restarted to flush its IMEI cache (this is what updates Settings → About Device)

### Volatile MAC log

GL-iNet's `gl_clients` binary keeps a persistent MAC history at `/etc/oui-tertf/`. blue-merle mounts tmpfs over that path at S9, so the binary keeps writing there without knowing it's writing to RAM. The directory starts empty on every boot.

### SIM-swap flow

1. `blue-merle sim-swap` writes throwaway IMEIs, saves IMSI state to `/etc/blue-merle.sim-swap-pending`, calls `poweroff`
2. Swap SIMs, power back on
3. S25 reads the new IMSIs, generates final IMEIs, disables RF, writes, re-enables RF
4. Carrier sees the final IMEI — the throwaway never registered

---

## IMEI Modes

### Random

Picks a TAC from `tac_pool.json`, appends 6 random digits, computes the Luhn check digit. The pool is limited to 5G sub-6 handsets and hotspots that support the same bands as the RG650V-NA. A mismatched TAC (e.g. a 4G-only device on a 5G modem) is a fingerprint — the pool is specifically built to avoid that.

### Deterministic

DJB2 hash of the SIM's IMSI, mapped into the TAC pool:

```
IMEI = luhn_complete( tac_pool[hash(IMSI) % pool_size] + serial(hash(IMSI)) )
```

Same SIM always produces the same IMEI. Falls back to random if no IMSI is readable.

### Static

User-supplied 15-digit IMEI, validated for Luhn checksum before writing.

---

## Configuration

Settings live in `/etc/config/blue-merle` (standard UCI format).

```
config blue-merle 'factory'
    option slot1_imei        '352000067890125'   # captured at install
    option slot2_imei        '352000067890133'
    option wifi2g_ssid       'GL-E5800-1A2B'
    option guest_ssid        'GL-Guest-1A2B'
    option hostname          'GL-E5800'
    option wifi2g_mac        'A8:22:42:1A:2B:3C'
    option wifi5g_mac        'A8:22:42:1A:2B:3B'
    option wifi6g_mac        'A8:22:42:1A:2B:3A'
    option sta_mac           '3A:47:9F:0C:11:82'
    option guest2g_mac       'A8:22:42:1A:2B:3D'
    option wifi2g_key        '<original password>'

config blue-merle 'options'
    option randomize_mac        '1'   # 0 = skip in rotate-wireless
    option randomize_ssid       '1'
    option randomize_hostname   '1'
    option randomize_password   '1'
    option randomize_on_boot    '0'   # 1 = auto-rotate at every boot
    option imei_mode_slot1      'random'   # random | deterministic | static
    option imei_mode_slot2      'random'
    option static_imei_slot1    ''         # only used when mode = static
    option static_imei_slot2    ''
```

---

## Building from Source

### Without the SDK

```sh
git clone https://github.com/<your-org>/blue-merle-v2.git
cd blue-merle-v2
./build-ipk.sh
```

Packages the `files/` tree into a gzip-compressed IPK. No SDK needed — just `bash`, `tar`, and `gzip`. Output: `blue-merle_1.0.0-1_aarch64_cortex-a53.ipk`

### With the OpenWrt SDK

1. Set up the SDK for `qualcommax/ipq9574` (the GL-E5800 target)
2. Link this repo into the packages tree:
   ```sh
   ln -s /path/to/blue-merle-v2 package/blue-merle
   ```
3. Build:
   ```sh
   make package/blue-merle/compile V=s
   ```

Output lands in `bin/packages/aarch64_cortex-a53/base/`.

---

## Codebase

```
blue-merle-v2/
├── README.md
├── build-ipk.sh                     — standalone IPK builder (no SDK required)
├── Makefile                         — OpenWrt package Makefile for SDK builds
│
└── files/                           — package payload (mirrors the device filesystem)
    ├── usr/bin/blue-merle           — main CLI
    ├── usr/libexec/blue-merle       — rpcd exec backend called by LuCI
    │
    ├── usr/share/blue-merle/
    │   ├── tac_pool.json            — TAC list for IMEI generation
    │   └── oui_pool.json            — OUI list for MAC randomization
    │
    ├── lib/blue-merle/
    │   └── functions.sh             — AT helpers, IMEI/MAC generation, modem reset
    │
    ├── etc/init.d/
    │   ├── blue-merle-volatile-macs — S9: tmpfs over /etc/oui-tertf
    │   ├── blue-merle-wireless      — S10: boot-time wireless rotation
    │   └── blue-merle-sim-swap      — S25: SIM-swap Stage 2
    │
    └── www/luci-static/resources/view/
        └── blue_merle.js            — LuCI2 admin page
```

**`files/lib/blue-merle/functions.sh`** — all modem interaction:
- `_at <cmd>` — sends AT via `gl_modem -B CPU -U $SUB`
- `READ_IMEI` / `READ_IMEI_SLOT2` — `AT+EGMR=0,7` / `AT+EGMR=0,11`
- `SET_IMEIS <imei1> <imei2>` — disables RF, writes both slots, re-enables
- `READ_IMSI_SLOT1` / `READ_IMSI_SLOT2` — per-slot IMSI via `-U 1` / `-U 2`
- `MODEM_RESET_FOR_PRIVACY` — RF cycle + wait for `+CEREG` + restart `gl_cellular_manager`
- `_gen_imei <slot> <mode>` — dispatches to random/deterministic/static

**`files/usr/bin/blue-merle`** — parses subcommands and calls into `functions.sh`.

**`files/usr/libexec/blue-merle`** — rpcd backend for LuCI. Returns JSON on `status`, fires rotate/restore operations in the background (logged to `/tmp/blue-merle.log`), handles `set:<key>=<val>` for option persistence.

**`files/www/luci-static/resources/view/blue_merle.js`** — the LuCI page. Polls the rpcd backend on load, streams log output during operations.

---

## Uninstall

```sh
opkg remove blue-merle
```

The `postrm` script re-enables GL-iNet's BSSID randomization and removes the init.d services. Factory state in `/etc/config/blue-merle` is left in place — remove it manually if you want a clean slate:

```sh
uci delete blue-merle.factory
uci delete blue-merle.options
uci commit blue-merle
```

---

## AT Commands — What We Don't Use

A few commands look useful but cause serious problems on the RG650V-NA:

| Command | Problem |
|---|---|
| `AT+QPOWD` | Leaves the modem unresponsive until full device reboot |
| `AT+CFUN=1,1` | Reboots the whole device, not just an RF cycle |
| `AT+QPRTPARA=3` | Quectel internal factory reset — behavior on carrier-locked units is undefined |
| `AT+QUIMSUB` | Breaks the AT socket until reboot |
| RAWDATA MMC partition | Where the factory MAC lives — writes risk unrecoverable corruption |
| Default eSIM profile | Can't be restored without a factory reset |
| `ubus call cellular.cm cm_stop_dial` | Writes `allow_dial=0` to flash, persists across reboots |

---

## Work in Progress

### Touchscreen (Phase 4)

The GL-E5800's touchscreen runs a closed-source `gl_screen` binary. The framebuffer approach works — stop `gl_screen`, write to `/dev/fb0`, restart — but we haven't verified behavior when a passcode is set. Deferred until that can be tested on a live device.

### Live SIM validation

Still need to run these with a real connected SIM:
- Modem re-registration (confirm `+CEREG` stat 1 or 5 after rotate)
- Deterministic mode end-to-end (IMSI → IMEI → carrier attach)
- Full sim-swap two-stage flow with physical SIM change
- Throwaway IMEI timing (`logread | grep "sim-swap throwaway"`)

---

## Acknowledgements

- **[SRLabs](https://www.srlabs.de) / `srlabs/blue-merle`** — original design and threat model. This port tries to preserve the spirit of the original while adapting to completely different hardware.
- **[GL.iNet `glinet-tac-fix`](https://github.com/gl-inet/glinet-tac-fix)** — the only public GL.iNet code that uses `AT+EGMR`, which confirmed the quoting format and `AT+QPRTPARA=1` persistence pattern.
- **[`zhaojh329/oui`](https://github.com/zhaojh329/oui)** — upstream framework GL.iNet's web UI is built on.

---

## License

GPL-2.0-only, same as the original SRLabs blue-merle.
