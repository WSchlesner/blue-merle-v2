# blue-merle v2 — GL-iNet Mudi 7 (GL-E5800)

A port of [SRLabs' blue-merle](https://github.com/srlabs/blue-merle) from the original Mudi (GL-E750) to the Mudi 7 (GL-E5800). The Mudi 7 ships with a completely different modem, a rewritten `gl_modem` wrapper, dual SIM + eSIM support, and no hardware switch — so this is a ground-up rewrite, not a patch.

---

## Features

| Feature | Description |
|---|---|
| **Dual IMEI rotation** | Randomize both modem IMEI slots independently on every SIM swap |
| **Three IMEI modes** | Per-slot: **Random** (Luhn-valid, band-matched TAC), **Deterministic** (stable hash of IMSI), or **Static** (fixed value) |
| **Wireless rotation** | Randomize BSSID/MAC, SSID, hostname, and Wi-Fi password |
| **SIM-Swap** | Two-stage boot flow — throwaway IMEI written at shutdown, final IMEI written before first network attach on next boot |
| **Volatile Client MACs** | `tmpfs` over GL-iNet's client MAC database — device history never hits flash |
| **Boot-time rotation** | Optional auto-rotate on every boot |
| **Touchscreen trigger** | 2-second hold on the screen clock initiates SIM swap without SSH |
| **LuCI admin page** | Browser UI under Services → blue-merle |
| **GL-iNet UI sync** | Settings → About Device → IMEI updates automatically after rotation |

---

## Compatibility

- **Device:** GL-iNet GL-E5800 (Mudi 7)
- **Firmware:** GL.iNet 4.8.3 (OpenWrt 23.05.4)
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

Navigate to **Services → blue-merle**. The page has five sections:

#### IMEI

Live IMEI state for both modem slots:

- **IMEI (Slot 1 / Slot 2)** — current values read via `AT+EGMR`; factory values shown alongside for reference
- **IMSI (Slot 1 / Slot 2)** — read from the modem; shows "No SIM Detected" when empty

Per-slot IMEI mode selectors (Radio buttons: Random / Deterministic / Static). Static mode reveals a text field for a specific IMEI, validated for Luhn checksum before writing.

#### Wireless/System Identity

Live MAC/SSID/hostname state:

- **SSID / Guest SSID, MACs, Hostname** — current values from UCI
- **Factory values** — saved at install time, shown for reference

#### Rotation Options

Three sub-sections, each with its own inline **Saved ✓** indicator:

**Wireless / System Rotation**
- "Randomize identity on boot" master toggle (auto-rotate every boot via the S10 init.d service)
- Independent checkboxes: BSSIDs/MACs, SSID, Wi-Fi password, Hostname

**IMEI Rotation**
- Mode radios per slot (Random / Deterministic / Static)

**Touchscreen Trigger**
- Enable/disable the clock long-press SIM swap trigger (persisted via init.d enable/disable)

#### Actions

- **Rotate IMEIs** — generates new IMEIs per configured mode, writes via `AT+EGMR`, cycles RF (`AT+CFUN=4 → AT+CFUN=1`), restarts `gl_cellular_manager`. Settings → About Device updates automatically.
- **Rotate Wireless/System** — randomizes MACs/SSID/hostname/password immediately via `wifi reload`
- **Restore Factory** — reverts everything to the factory values captured at install time
- Last IMEI rotate and last wireless rotate timestamps (shows "Never" until first use)

#### Last Command Log

Streams the tail of `/tmp/blue-merle.log` — live output from the last operation.

<!-- SCREENSHOT: Replace the lines below with actual screenshots once captured -->
<!-- Upload to assets/screenshots/ and update the image paths -->

> **Photos needed:**
> - `assets/screenshots/luci-overview.png` — Full LuCI page overview (Services → blue-merle)
> - `assets/screenshots/luci-imei.png` — IMEI section showing both slots + IMSI
> - `assets/screenshots/luci-rotation-options.png` — Rotation Options with all sub-sections visible
> - `assets/screenshots/luci-actions.png` — Actions section with rotate/restore buttons + timestamps

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

### Touchscreen trigger

Hold the **clock in the top-left corner** of the home screen for **2 seconds** to initiate a SIM swap — identical to running `blue-merle sim-swap` from SSH.

The `blue-merle-touch` daemon starts at S81, reads `/dev/input/event0` without grabbing the device (so `gl_screen` continues operating normally), and watches for a 2-second hold in the clock region (`X: 0–80, Y: 0–30`).

**Guards preventing accidental triggers:**
- 2-second hold required (quick taps are logged and ignored)
- 10-second cooldown between consecutive triggers
- Blocked if a sim-swap stage file is already present

**Toggle (persists across reboots):**  
LuCI → Services → Blue Merle → Rotation Options → **Touchscreen Trigger** checkbox.  
Or via SSH: `/etc/init.d/blue-merle-touch disable && /etc/init.d/blue-merle-touch stop`

---

## How It Works

### Boot sequence

| Priority | Service | What it does |
|---|---|---|
| S9 | `blue-merle-volatile-macs` | Mounts a `tmpfs` over `/etc/oui-tertf` — the directory GL-iNet's `gl_clients` binary uses to store its persistent MAC history database. All client history is written to RAM and discarded on every reboot. |
| S10 | `blue-merle-wireless` | If `randomize_on_boot=1`: rotates MACs, SSID, hostname, and Wi-Fi password before the AP comes up. |
| S23 | `gl_cellular_manager` | GL-iNet's modem init daemon. This is the first point in the boot sequence where the AT socket accepts commands. |
| S25 | `blue-merle-sim-swap` | If `/etc/blue-merle.sim-swap-pending` exists (left by Stage 1): waits for the AT socket, disables RF (`AT+CFUN=4`), writes the final IMEIs, re-enables RF (`AT+CFUN=1`). No reboot needed — `gl_cellular_manager` handles carrier registration from here with the correct identity. |
| S80 | `gl_screen` | GL-iNet's touchscreen UI daemon. |
| S81 | `blue-merle-touch` | Procd respawn-managed daemon. Reads `/dev/input/event0` and watches for a 2-second hold on the clock area (X:0–80, Y:0–30). Forks `blue-merle sim-swap` when triggered. Can be toggled on/off via LuCI or `init.d disable`. |

The throwaway IMEI written in Stage 1 is only live during the S23→S25 window, which is a few seconds at most.

### IMEI rotation

1. RF off (`AT+CFUN=4`) before any write
2. Both slots written via `AT+EGMR` (field 7 = Slot 1, field 11 = Slot 2)
3. RF on (`AT+CFUN=1`), re-register (`AT+COPS=0`)
4. `gl_cellular_manager` restarted to flush its IMEI cache (this is what updates Settings → About Device)

### Volatile MAC log

GL-iNet's `gl_clients` binary keeps a persistent MAC history at `/etc/oui-tertf/`. blue-merle mounts tmpfs over that path at S9, so the binary keeps writing there without knowing it's writing to RAM. The directory starts empty on every boot.

### MAC randomization

All MAC addresses are generated from a curated OUI pool (`oui_pool.json`) with two categories:

**Router OUIs** — used for the Mudi 7's own AP interfaces (`wifi2g`, `wifi5g`, `wifi6g`, and the guest variants). These are OUIs from common home routers and mobile hotspots (ASUS, Netgear, TP-Link, etc.) so the device's BSSIDs look like a normal home network to anyone scanning nearby.

**Client OUIs** — used for the STA (repeater/upstream) interface only. When the Mudi 7 connects to an upstream Wi-Fi network in repeater mode, its upstream MAC should look like a laptop or phone, not a router. These OUIs come from Apple, Intel, and similar NIC vendors.

All generated MACs have the **locally-administered (LA) bit** forced on (`0x02` mask on the first octet). This is required by the Qualcomm `ath11k` driver: LA-bit MACs allow the driver to change channels on AP interfaces at runtime, which is how GL-iNet's channel co-location works when the repeater STA is connected. Universally-administered (UA) MACs — what you would get by just randomizing bytes — break this and can prevent the Wi-Fi radios from coming up correctly.

GL-iNet ships with its own BSSID randomization (`random_bssid=1` per radio). blue-merle disables this on install and takes over MAC rotation entirely, because GL-iNet's randomization generates UA MACs and runs on a different schedule.

**SSID** is randomized to a name matching common home routers (e.g. `NETGEAR-A3F1`, `TP-Link-7B2C`, `eero-9D4A`) — the same brands whose OUIs are in the router pool, so the SSID and BSSID stay consistent-looking as a set.

**Hostname** is randomized to `router-XXXX` (4 random hex chars).

**Wi-Fi password** — the main and guest networks each get a separate 12-character random hex password.

### SIM-Swap flow

1. `blue-merle sim-swap` writes throwaway IMEIs, saves IMSI state to `/etc/blue-merle.sim-swap-pending`, calls `poweroff`
2. Swap SIMs, power back on
3. S25 reads the new IMSIs, generates final IMEIs, disables RF, writes, re-enables RF
4. Carrier sees the final IMEI — the throwaway never registered

---

## IMEI Modes

### Random

Picks a TAC from `tac_pool.json`, appends 6 random digits, computes the Luhn check digit. The pool is curated to contain only 5G sub-6 mobile hotspots and handsets whose band sets overlap the RG650V-NA's supported bands (n2/n5/n12/n25/n41/n66/n70/n71/n77/n78).

**Why the TAC pool matters:** A carrier can fingerprint a device by comparing its reported IMEI against the capabilities of the cell it is connecting on. An IMEI with a 4G-only TAC connecting via a 5G NR cell is a contradiction — some carriers flag this and throttle the connection to ~10 Mbps. Using an LTE-only TAC in the pool was confirmed to trigger this on real hardware. The pool is intentionally restricted to avoid it.

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

There are three ways to produce an IPK, depending on your workflow.

### 1. `build-ipk.sh` — offline, no SDK required

```sh
git clone https://github.com/<your-org>/blue-merle-v2.git
cd blue-merle-v2
./build-ipk.sh
```

Requires only `bash`, `tar`, and `gzip`. Manually assembles the IPK from the `files/` tree and the `preinst`/`postinst`/`postrm` scripts inlined in the script itself. The pre-compiled `files/usr/bin/blue-merle-touch` binary (cross-compiled via Docker; see below) is bundled as-is.

Output: `blue-merle_1.0.0-1_aarch64_cortex-a53.ipk`

**When to use:** day-to-day development, testing on device without CI, building offline.

### 2. OpenWrt SDK — `Makefile`

The `Makefile` is a standard OpenWrt package recipe. The SDK cross-compiles `src/blue-merle-touch.c` for `aarch64` automatically — no pre-built binary required.

1. Download and set up the OpenWrt SDK for target `qualcommax/ipq9574` (the GL-E5800 target).
2. Symlink this repo into the SDK packages tree:
   ```sh
   ln -s /path/to/blue-merle-v2 package/blue-merle
   ```
3. Build:
   ```sh
   make package/blue-merle/compile V=s
   ```

Output lands in `bin/packages/aarch64_cortex-a53/base/`.

**When to use:** producing a reproducible build from source without a committed binary, or submitting to an opkg feed.

> **Note:** The `Makefile` currently does not install `blue-merle-touch` or its init.d service — those entries need to be added to `Package/blue-merle/install` if you want a fully SDK-built package.

### 3. GitHub Actions — automated CI / release

The workflow at `.github/workflows/build.yml` runs `./build-ipk.sh` automatically:

- **On every push to `main`** — builds the IPK and uploads it as a workflow artifact (retained 30 days).
- **On every `v*.*.*` tag** — builds the IPK and publishes it as a GitHub Release with auto-generated release notes.
- **Manually** — trigger via the **Run workflow** button in the Actions tab (`workflow_dispatch`).

To cut a release:

```sh
git tag v1.1.0
git push origin v1.1.0
```

The IPK appears under **Releases** once the workflow completes.

### Cross-compiling `blue-merle-touch`

The `blue-merle-touch` C daemon must be compiled for `aarch64` (musl, statically linked). If you change `src/blue-merle-touch.c`, rebuild with:

```sh
docker run --rm --platform linux/arm64 \
  -v $(pwd)/src:/src -v $(pwd)/files/usr/bin:/out \
  alpine:3.20 \
  sh -c 'apk add --no-cache gcc musl-dev linux-headers && \
         gcc -O2 -static -o /out/blue-merle-touch /src/blue-merle-touch.c'
```

Requires Docker with QEMU binfmt support (`multiarch/qemu-user-static`). Commit the resulting `files/usr/bin/blue-merle-touch` binary so `build-ipk.sh` and GitHub Actions can bundle it without a local toolchain.

### Development deploy (`deploy.sh`)

For iterating without rebuilding the IPK each time:

```sh
./deploy.sh                    # deploys to root@192.168.8.1
./deploy.sh root@192.168.8.2   # custom host
```

Copies all source files directly to the device over SCP and re-enables the init.d services. Uses `scp -O` (legacy SCP protocol) required by OpenWrt's busybox SSH server. Does **not** run `blue-merle install` — if you need to re-capture factory state, run that manually over SSH.

---

## Codebase

```
blue-merle-v2/
├── README.md
├── build-ipk.sh                     — standalone IPK builder (no SDK required)
├── deploy.sh                        — scp + install shortcut for dev workflow
├── Makefile                         — OpenWrt package Makefile for SDK builds
│
├── src/
│   └── blue-merle-touch.c           — touchscreen daemon C source
│                                      (cross-compiled for aarch64 via Docker + QEMU)
│
├── screens/
│   ├── generate.py                  — RGB565 frame generator (Python 3 + Pillow)
│   ├── previews/                    — PNG previews (committed; embedded in README)
│   └── extras/                      — error.rgb565 / warning.rgb565 (not bundled)
│
└── files/                           — package payload (mirrors the device filesystem)
    ├── usr/bin/blue-merle           — main CLI
    ├── usr/bin/blue-merle-touch     — compiled aarch64 static binary (~347 KB)
    ├── usr/libexec/blue-merle       — rpcd exec backend called by LuCI
    │
    ├── usr/share/blue-merle/
    │   ├── tac_pool.json            — TAC list for IMEI generation
    │   ├── oui_pool.json            — OUI list for MAC randomization
    │   └── screens/                 — pre-rendered 240×320 RGB565 splash frames
    │       ├── rotating.rgb565
    │       ├── done.rgb565
    │       ├── simswap.rgb565
    │       └── restoring.rgb565
    │
    ├── lib/blue-merle/
    │   └── functions.sh             — AT helpers, IMEI/MAC generation, modem reset,
    │                                  splash screen functions
    │
    ├── etc/init.d/
    │   ├── blue-merle-volatile-macs — S9: tmpfs over /etc/oui-tertf
    │   ├── blue-merle-wireless      — S10: boot-time wireless rotation
    │   ├── blue-merle-sim-swap      — S25: SIM-swap Stage 2
    │   └── blue-merle-touch         — S81: touchscreen long-press daemon
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

**`src/blue-merle-touch.c`** — statically-linked aarch64 daemon. Opens `/dev/input/event0` read-only (no EVIOCGRAB), tracks `ABS_MT_POSITION_X/Y` and `BTN_TOUCH` events, measures hold duration using kernel event timestamps. Cross-compile command:

```sh
docker run --rm --platform linux/arm64 \
  -v $(pwd)/src:/src -v $(pwd)/files/usr/bin:/out \
  alpine:3.20 \
  sh -c 'apk add --no-cache gcc musl-dev linux-headers && gcc -O2 -static -o /out/blue-merle-touch /src/blue-merle-touch.c'
```

**`files/usr/bin/blue-merle`** — parses subcommands and calls into `functions.sh`.

**`files/usr/libexec/blue-merle`** — rpcd backend for LuCI. Returns JSON on `status`, fires rotate/restore operations in the background (logged to `/tmp/blue-merle.log`), handles `set:<key>=<val>` for option persistence.

**`files/www/luci-static/resources/view/blue_merle.js`** — the LuCI page. Polls the rpcd backend on load, streams log output during operations.

---

## Splash Screens

During operations the daemon writes a pre-rendered frame to `/dev/fb0`. Four frames ship with the IPK:

| Frame | Shown when |
|---|---|
| `rotating.rgb565` | IMEI rotation or SIM-swap Stage 2 in progress |
| `done.rgb565` | Rotation complete |
| `simswap.rgb565` | Stage 1: device powering off for SIM swap |
| `restoring.rgb565` | Factory restore in progress |

**Format:** 240×320 portrait, 16-bit RGB565 little-endian, 153,600 bytes each.

| Rotating | Done | SIM Swap | Restoring |
|:---:|:---:|:---:|:---:|
| ![Rotating](screens/previews/rotating.png) | ![Done](screens/previews/done.png) | ![SIM Swap](screens/previews/simswap.png) | ![Restoring](screens/previews/restoring.png) |

### How they are displayed

`_screen_splash <name>` in `lib/blue-merle/functions.sh`:

1. `ubus call service delete '{"name":"gl_screen"}'` — removes `gl_screen` from procd's watch list. This is required because `gl_screen` uses `procd_set_param respawn` with no arguments, meaning a plain `stop` triggers an immediate restart that overwrites the framebuffer.
2. `/etc/init.d/gl_screen stop` + `pkill -9 gl_screen`
3. Polls `pidof gl_screen` up to 5 seconds until the process is gone.
4. `cat <name>.rgb565 > /dev/fb0`

`_screen_restore_display` restarts `gl_screen` after user-triggered operations. Boot scripts do **not** call this — `gl_screen` restarts at S80 automatically.

### How to rebuild frames

Requires Python 3 and Pillow (`pip install Pillow`), plus DejaVu fonts installed at `/usr/share/fonts/truetype/dejavu/`.

```sh
cd screens
python3 generate.py
```

Output: `files/usr/share/blue-merle/screens/*.rgb565` (committed — device has no Python) and `screens/previews/*.png` (also committed; embedded in the README below).

### How to modify frames

Edit the `FRAMES` list in `screens/generate.py`. Each entry:

```python
("name", "Main Text", COLOR, [
    ("sub line text",  font_size, COLOR, gap_before_px),
    ...
])
```

Run `python3 generate.py` after any change. Commit the resulting `.rgb565` files.

### Testing a frame on device

```sh
# Preview a frame immediately (stops gl_screen):
ssh root@192.168.8.1 'cat /usr/share/blue-merle/screens/rotating.rgb565 > /dev/fb0'

# Restore normal UI:
ssh root@192.168.8.1 '/etc/init.d/gl_screen start'
```

<!-- PHOTOS: Replace with actual device photos once captured -->
<!-- Upload to assets/screenshots/ and update the image paths -->

> **Device photos needed:**
> - `assets/screenshots/device-rotating.jpg` — Mudi 7 screen showing "Rotating..." splash
> - `assets/screenshots/device-done.jpg` — Mudi 7 screen showing "Done" splash
> - `assets/screenshots/device-simswap.jpg` — Mudi 7 screen showing "SIM Swap" splash

### Extra frames (not bundled)

`screens/extras/` contains `error.rgb565` and `warning.rgb565` for future error/warning states. They are not included in the IPK and not wired to any call site yet.

### Note on GL-iNet boot animation

During a boot-time SIM swap (Stage 2 at S25), a separate GL-iNet proprietary process writes a horizontal progress bar to `/dev/fb0` at a fixed vertical position regardless of `gl_screen`'s state. The `rotating` and `done` frames have 28 px of extra spacing at the lines that would otherwise overlap this bar (`Writing to Modem...` and `Re-registered with Carrier`).

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

### Live SIM validation

Still need to run these with a real connected SIM:
- Modem re-registration (confirm `+CEREG` stat 1 or 5 after rotate)
- Deterministic mode end-to-end (IMSI → IMEI → carrier attach)
- Full sim-swap two-stage flow with physical SIM change
- Throwaway IMEI timing (`logread | grep "sim-swap throwaway"`)

---

## Acknowledgements

- **[SRLabs](https://www.srlabs.de) / [`srlabs/blue-merle`](https://github.com/srlabs/blue-merle)** — original design, threat model, and the v1 implementation this port is based on.
- **[GL.iNet `glinet-tac-fix`](https://github.com/gl-inet/glinet-tac-fix)** — the only public GL.iNet code that calls `AT+EGMR`, which confirmed the correct quoting format and the `AT+QPRTPARA=1` NV persistence pattern needed for the Quectel RG650V-NA.

---

## License

GPL-2.0-only, same as the original SRLabs blue-merle.
