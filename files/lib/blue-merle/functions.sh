#!/usr/bin/env ash
# blue-merle v2 — helper functions
# Device: GL-iNet GL-E5800 (Mudi 7), Quectel RG650V-NA, OpenWrt 23.05.4
# Sourced by /usr/bin/blue-merle and the init.d services.

BUS=CPU
SUB=1  # logical subscription for _at() — slot 1 (-U 1); -U 0 alternates and must not be used

# ── Messaging ────────────────────────────────────────────────────────────────
# Writes to syslog and stdout. During boot stdout goes to the system console;
# during SSH sessions it appears inline.
_screen_msg() {
    logger -p notice -t blue-merle "$1"
    echo "blue-merle: $1"
}

_SCREENS_DIR=/usr/share/blue-merle/screens

# Stop gl_screen (if running) and write a pre-rendered RGB565 frame to fb0.
# Safe to call at any boot stage — stop is a no-op if gl_screen isn't running.
# Uses procd ubus delete before stop to prevent automatic respawn (gl_screen
# has procd_set_param respawn which would otherwise restart it within seconds).
# $1 = frame name (rotating|done|simswap|restoring|error|warning)
_screen_splash() {
    local frame="${_SCREENS_DIR}/${1}.rgb565"
    [ -f "$frame" ] || return 0
    ubus call service delete '{"name": "gl_screen"}' 2>/dev/null
    /etc/init.d/gl_screen stop >/dev/null 2>&1
    pkill -9 gl_screen 2>/dev/null
    local _i=0
    while pidof gl_screen >/dev/null 2>&1 && [ "$_i" -lt 5 ]; do
        sleep 1
        _i=$((_i + 1))
    done
    cat "$frame" > /dev/fb0 2>/dev/null
}

# Restart gl_screen so the normal touchscreen UI returns.
# Only call from user-triggered operations (rotate, restore) — boot scripts
# should not call this; S80 starts gl_screen automatically.
_screen_restore_display() {
    /etc/init.d/gl_screen start >/dev/null 2>&1
}

# Show the error frame on failure, then return to the normal UI.
# For interactive (user-triggered) operations only. RF is intentionally left
# disabled on failure — a privacy tool must never transmit a half-rotated
# identity — so this only surfaces the failure, it does not re-enable RF.
_screen_fail() {
    _screen_splash error
    sleep 3
    _screen_restore_display
}

# Print how to recover after a failure that left RF disabled (CFUN=4).
_recovery_hint() {
    echo "blue-merle: RF is OFF (CFUN=4) — the device will not connect until recovered." >&2
    echo "blue-merle: recover by re-running the operation, or 'blue-merle restore'," >&2
    echo "blue-merle: or force RF on manually: gl_modem -B ${BUS} -U 1 AT 'AT+CFUN=1'" >&2
}

# ── Modem AT helpers ─────────────────────────────────────────────────────────

# Send one AT command via the active subscription channel.
_at() {
    gl_modem -B "$BUS" -U "$SUB" AT "$1"
}

# True unless the option is explicitly set to 0 (unset = enabled).
# Shared by the boot service and the CLI: _opt_enabled <option-name>
_opt_enabled() {
    [ "$(uci -q get "blue-merle.options.$1" 2>/dev/null)" != "0" ]
}

# Return the active data SIM slot (1 or 2) without touching the AT interface.
# Reads dds_id from UCI network config (updated by cellular_manager on DDS changes).
READ_ACTIVE_SLOT() {
    local slot
    slot=$(uci -q get network.modem_cpu.dds_id 2>/dev/null)
    case "$slot" in
        1|2) echo "$slot" ;;
        *)   echo "1" ;;   # safe default
    esac
}

# ── IMEI read/write ──────────────────────────────────────────────────────────
#
# Dual-IMEI mapping on the RG650V-NA (DSDS device):
#   AT+EGMR field 7  = SIM Slot 1 IMEI  — broadcast to the network by subscription 0
#   AT+EGMR field 11 = SIM Slot 2 / eSIM IMEI — broadcast by subscription 1
#   SIM Slot 2 and eSIM are mutually exclusive (same physical slot, different card types).
#   Both fields must be rotated independently on every rotation.

# SIM Slot 1 IMEI — AT+EGMR field 7
READ_IMEI() {
    _at "AT+EGMR=0,7" | tr -d '\r' | grep -oE '[0-9]{15}'
}

# SIM Slot 2 / eSIM IMEI — AT+EGMR field 11
READ_IMEI_SLOT2() {
    _at "AT+EGMR=0,11" | tr -d '\r' | grep -oE '[0-9]{15}'
}

# Read IMSI via gl_modem subscription $1, retrying up to 3× (the SIM can be
# slow to answer right after modem init). Returns non-zero if no SIM answers.
_read_imsi() {
    local sub="$1" i=0 imsi
    while [ "$i" -lt 3 ]; do
        imsi=$(gl_modem -B "$BUS" -U "$sub" AT AT+CIMI | tr -d '\r' | grep -E '^[0-9]{6,15}$')
        [ -n "$imsi" ] && { echo "$imsi"; return 0; }
        i=$((i + 1))
        sleep 2
    done
    return 1
}

READ_IMSI_SLOT1() { _read_imsi 1; }
READ_IMSI_SLOT2() { _read_imsi 2; }

# Read ICCID via gl_modem subscription $1 — try AT+QCCID, fall back to AT+CCID.
_read_iccid() {
    local sub="$1" out
    out=$(gl_modem -B "$BUS" -U "$sub" AT AT+QCCID | tr -d '\r')
    if echo "$out" | grep -q '+QCCID:'; then
        echo "$out" | grep -o '+QCCID:.*' | sed 's/+QCCID: //' | tr -d 'F'
        return
    fi
    gl_modem -B "$BUS" -U "$sub" AT AT+CCID | tr -d '\r' | grep -o '+CCID:.*' | sed 's/+CCID: //' | tr -d 'F'
}

READ_ICCID_SLOT1() { _read_iccid 1; }
READ_ICCID_SLOT2() { _read_iccid 2; }

# Write one IMEI via AT+EGMR after validating it is exactly 15 digits.
# _set_imei <egmr-field> <imei> <label>
_set_imei() {
    local field="$1" imei="$2" label="$3"
    case "$imei" in *[!0-9]*|'')
        echo "blue-merle: ${label}: IMEI must contain only digits" >&2
        return 1 ;;
    esac
    if [ ${#imei} -ne 15 ]; then
        echo "blue-merle: ${label}: expected 15-digit IMEI, got ${#imei} digits" >&2
        return 1
    fi
    local out
    out=$(_at "AT+EGMR=1,${field},\"${imei}\"" 2>&1)
    if ! echo "$out" | grep -q "OK"; then
        echo "blue-merle: EGMR field ${field} (${label}) write failed" >&2
        return 1
    fi
    sleep 1
}

# SIM Slot 1 IMEI — AT+EGMR field 7.
SET_IMEI_SLOT1() {
    _set_imei 7 "$1" "slot 1"
}

# SIM Slot 2 / eSIM IMEI — AT+EGMR field 11.
# Also updates /root/esim/imei so the eSIM LPA uses this IMEI for RSP identity.
SET_IMEI_SLOT2() {
    _set_imei 11 "$1" "slot 2/eSIM" || return 1
    if [ -f /root/esim/imei ]; then
        printf '%s\n' "$1" > /root/esim/imei
    fi
    return 0
}

# Write both IMEIs, persist all NV changes to flash, and refresh WebUI.
# $1 = Slot 1 IMEI (field 7), $2 = Slot 2/eSIM IMEI (field 11)
SET_IMEIS() {
    local imei1="$1" imei2="$2" _slot
    SET_IMEI_SLOT1 "$imei1" || return 1
    SET_IMEI_SLOT2 "$imei2" || return 1
    _at AT+QPRTPARA=1 >/dev/null 2>&1
    # Refresh WebUI for both slots.
    for _slot in 1 2; do
        ubus call cellular.network update_status \
            "{\"bus\":\"CPU\",\"slot\":${_slot}}" >/dev/null 2>&1
        ubus call cellular.network update_info \
            "{\"bus\":\"CPU\",\"slot\":${_slot}}" >/dev/null 2>&1
    done
}

GENERATE_IMEI() {
    lua /lib/blue-merle/imei_generate.lua random
}

# Generate an IMEI for a given slot using the specified mode.
# Falls back to random if deterministic/static fails (no IMSI or no static value set).
# $1 = slot (1 or 2), $2 = mode (random|deterministic|static)
_gen_imei() {
    local slot="$1" mode="$2"
    if [ "$mode" = "deterministic" ]; then
        local imsi
        if [ "$slot" = "1" ]; then
            imsi=$(READ_IMSI_SLOT1 2>/dev/null)
        else
            imsi=$(READ_IMSI_SLOT2 2>/dev/null)
        fi
        if [ -z "$imsi" ]; then
            echo "blue-merle: slot ${slot} IMSI not available — using random IMEI" >&2
            GENERATE_IMEI
        else
            lua /lib/blue-merle/imei_generate.lua deterministic "$imsi"
        fi
    elif [ "$mode" = "static" ]; then
        local static_imei
        if [ "$slot" = "1" ]; then
            static_imei=$(uci -q get blue-merle.options.static_imei_slot1 2>/dev/null)
        else
            static_imei=$(uci -q get blue-merle.options.static_imei_slot2 2>/dev/null)
        fi
        case "$static_imei" in
            '')
                echo "blue-merle: slot ${slot} static IMEI not configured — using random IMEI" >&2
                GENERATE_IMEI
                ;;
            *[!0-9]*)
                echo "blue-merle: slot ${slot} static IMEI invalid — using random IMEI" >&2
                GENERATE_IMEI
                ;;
            *)
                if [ ${#static_imei} -eq 15 ]; then
                    printf '%s\n' "$static_imei"
                else
                    echo "blue-merle: slot ${slot} static IMEI is not 15 digits — using random IMEI" >&2
                    GENERATE_IMEI
                fi
                ;;
        esac
    else
        GENERATE_IMEI
    fi
}

# ── Modem RF helpers ─────────────────────────────────────────────────────────
# AT+CFUN=1,1 causes a FULL device reboot (~3-4 min) — do NOT use.
# AT+QPOWD bricks the modem until device reboot — do NOT use.
# AT+QPRTPARA=3 is Quectel internal only — do NOT use.

# Disable RF (SIM stays powered). Use before writing IMEI to prevent any
# transmission of the old IMEI after the write begins.
MODEM_RF_DISABLE() {
    _at AT+CFUN=4 >/dev/null 2>&1
    sleep 2
}

# Re-enable RF and wait for network re-attachment, then restart
# gl_cellular_manager so its cached IMEI matches the modem.
# Blocks until re-attach or timeout: $1 seconds if given, else
# blue-merle.options.register_timeout, else 120. A timeout is non-fatal —
# RF stays on and the modem keeps retrying registration in the background.
MODEM_RESET_FOR_PRIVACY() {
    local timeout="${1:-$(uci -q get blue-merle.options.register_timeout 2>/dev/null)}"
    case "$timeout" in ''|*[!0-9]*) timeout=120 ;; esac

    # Do NOT use cm_stop_dial — it writes allow_dial=0 to UCI flash and persists
    # across reboots, making cellular_manager skip SIM detection on next boot.
    _at AT+CFUN=4 >/dev/null 2>&1    # RF off
    sleep 3
    _at AT+CFUN=1 >/dev/null 2>&1    # RF on
    sleep 2
    _at AT+COPS=0 >/dev/null 2>&1    # auto re-attach
    sleep 2

    local elapsed=0 _result=1
    while [ "$elapsed" -lt "$timeout" ]; do
        local reg
        reg=$(_at 'AT+CEREG?')
        if echo "$reg" | grep -qE '\+CEREG: [0-9],[15]'; then
            _result=0
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Restart GL-iNet cellular manager so its IMEI cache reflects the new values.
    # This keeps Settings → About Device in sync with the actual modem state.
    /etc/init.d/gl_cellular_manager restart >/dev/null 2>&1

    return $_result
}

# ── Network status (read-only) ──────────────────────────────────────────────

# Decode a +CEREG <stat> digit into a human-readable string.
_decode_reg_stat() {
    case "$1" in
        0) echo "not registered (idle)" ;;
        1) echo "registered (home)" ;;
        2) echo "searching..." ;;
        3) echo "registration denied" ;;
        4) echo "unknown" ;;
        5) echo "registered (roaming)" ;;
        *) echo "unavailable" ;;
    esac
}

# Raw +CEREG <stat> digit via gl_modem subscription $1 (covers LTE/5G NSA).
_read_reg_stat() {
    gl_modem -B "$BUS" -U "$1" AT 'AT+CEREG?' 2>/dev/null | tr -d '\r' \
        | grep -o '+CEREG: [0-9],[0-9]*' | cut -d, -f2
}

# Operator name (long alphanumeric form) — empty when not registered.
READ_OPERATOR() {
    _at 'AT+COPS?' | tr -d '\r' | sed -n 's/.*+COPS: [0-9],[0-9],"\([^"]*\)".*/\1/p'
}

# Signal strength: +CSQ 0-31 mapped to dBm (-113 + 2×csq); 99 = unknown.
READ_SIGNAL() {
    local csq
    csq=$(_at 'AT+CSQ' | tr -d '\r' | grep -o '+CSQ: [0-9]*' | grep -o '[0-9]*$')
    case "$csq" in
        ''|99) echo "unknown" ;;
        *)     echo "$(( -113 + 2 * csq )) dBm" ;;
    esac
}

# ── MAC generation ───────────────────────────────────────────────────────────
# Generates a locally-administered (LA) MAC styled after a real OUI prefix.
# LA bit (0x02) is forced on the first octet so the Qualcomm ath11k driver
# accepts runtime channel changes on AP interfaces (required for GL-iNet's
# channel co-location when the repeater STA connects).
# OUI source: /usr/share/blue-merle/oui_pool.json

_OUI_POOL_PATH=/usr/share/blue-merle/oui_pool.json

_load_ouis() {
    local category="$1"
    awk "
        /\"${category}\"/{in_section=1; next}
        in_section && /\]/{in_section=0}
        in_section && /\"oui\"/{
            match(\$0, /[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}/)
            if (RLENGTH > 0) print substr(\$0, RSTART, RLENGTH)
        }
    " "$_OUI_POOL_PATH" 2>/dev/null
}

_pick_oui() {
    local ouis="$1"
    local count
    count=$(echo "$ouis" | grep -c '.')
    if [ "$count" -eq 0 ]; then
        echo "EC:08:6B"
        return
    fi
    local idx=$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % count + 1 ))
    echo "$ouis" | sed -n "${idx}p"
}

# List "OUI BRAND" pairs from the routers section of the pool.
_load_router_identities() {
    awk '
        /"routers"/{in_section=1; next}
        in_section && /\]/{in_section=0}
        in_section && /"oui"/{
            oui=""; brand=""
            if (match($0, /[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}/))
                oui = substr($0, RSTART, RLENGTH)
            if (match($0, /"brand"[^"]*"[^"]*"/)) {
                b = substr($0, RSTART, RLENGTH)
                sub(/^"brand"[^"]*"/, "", b); sub(/"$/, "", b)
                brand = b
            }
            if (oui != "" && brand != "") print oui " " brand
        }
    ' "$_OUI_POOL_PATH" 2>/dev/null
}

# Pick ONE router OUI+brand for this rotation. A real consumer router uses the
# same vendor OUI on every band, and its default SSID matches that vendor —
# mixing vendors across bands (or vs. the SSID) is a fingerprinting flag.
# Sets _BM_ROUTER_OUI and _BM_ROUTER_BRAND; TP-Link fallback if the pool is missing.
_pick_router_identity() {
    local ids count idx line
    ids=$(_load_router_identities)
    count=$(echo "$ids" | grep -c '.')
    if [ "$count" -eq 0 ]; then
        _BM_ROUTER_OUI="EC:08:6B"
        _BM_ROUTER_BRAND="TP-Link"
        return
    fi
    idx=$(( $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % count + 1 ))
    line=$(echo "$ids" | sed -n "${idx}p")
    _BM_ROUTER_OUI="${line%% *}"
    _BM_ROUTER_BRAND="${line#* }"
}

# Generate one MAC: random OUI from $1 category, or a forced OUI via $2.
MAC_GEN() {
    local category="${1:-routers}" oui="$2"
    if [ -z "$oui" ]; then
        local ouis
        ouis=$(_load_ouis "$category")
        oui=$(_pick_oui "$ouis")
    fi
    # Force LA bit on first octet (0x02 mask) — keeps channel co-location intact.
    local _first _rest
    _first=$(printf '%02x' $(( 0x${oui%%:*} | 0x02 )))
    _rest=${oui#*:}
    local nic
    nic=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n' | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
    echo "${_first}:${_rest}:${nic}" | tr '[:upper:]' '[:lower:]'
}

MAC_GEN_ROUTER()  { MAC_GEN routers "$1"; }
MAC_GEN_CLIENT()  { MAC_GEN clients; }

# ── Wireless UCI randomization ────────────────────────────────────────────────
# Mudi 7 uses named interfaces (wifi2g / wifi5g / wifi6g / sta / guest*g).

# Session brand handoff: RANDOMIZE_MACADDR records the chosen router brand
# here (RAM) so RANDOMIZE_SSID can broadcast a matching SSID prefix.
_SESSION_BRAND_FILE=/tmp/blue-merle.session_brand

RANDOMIZE_MACADDR() {
    local _radio _iface
    # Disable GL-iNet's BSSID randomization — we own MAC rotation from here.
    # LA bit is forced in MAC_GEN so Qualcomm's channel co-location still works.
    for _radio in wifi0 wifi1 wifi2; do
        uci -q set "wireless.${_radio}.random_bssid=0" 2>/dev/null
    done
    # One router identity per rotation: every AP BSSID shares the same vendor
    # OUI (only the NIC bytes differ), like a real consumer router.
    _pick_router_identity
    printf '%s' "$_BM_ROUTER_BRAND" > "$_SESSION_BRAND_FILE"
    for _iface in wifi2g wifi5g wifi6g guest2g guest5g guest6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.macaddr=$(MAC_GEN_ROUTER "$_BM_ROUTER_OUI")"
    done
    # STA (repeater upstream): client-class OUI MAC; keep repeater config in sync.
    # repeater.@network[0].macaddr uses GL-iNet's r, prefix format.
    # repeater.@main[0].macaddr is a device-management field — do not touch.
    if uci get wireless.sta >/dev/null 2>&1; then
        local _sta_mac
        _sta_mac=$(MAC_GEN_CLIENT)
        uci set "wireless.sta.macaddr=${_sta_mac}"
        uci -q set "repeater.@network[0].macaddr=r,${_sta_mac}" 2>/dev/null
        uci commit repeater 2>/dev/null
    fi
    uci commit wireless
}

# Re-enable GL-iNet's BSSID randomization (called by blue-merle restore).
RESTORE_RANDOM_BSSID() {
    local _radio
    for _radio in wifi0 wifi1 wifi2; do
        uci -q set "wireless.${_radio}.random_bssid=1" 2>/dev/null
    done
    uci commit wireless
}

RANDOMIZE_SSID() {
    local _suffix _new_ssid _iface _brand
    # Use the brand recorded by RANDOMIZE_MACADDR so the SSID matches the
    # BSSID vendor; pick a fresh identity only if MAC rotation didn't run.
    _brand=$(cat "$_SESSION_BRAND_FILE" 2>/dev/null)
    if [ -z "$_brand" ]; then
        _pick_router_identity
        _brand="$_BM_ROUTER_BRAND"
    fi
    _suffix=$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    _new_ssid="${_brand}-${_suffix}"
    for _iface in wifi2g wifi5g wifi6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.ssid=${_new_ssid}"
    done
    for _iface in guest2g guest5g guest6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.ssid=${_new_ssid}-Guest"
    done
    uci commit wireless
}

RANDOMIZE_PASSWORD() {
    # Main (wifi2g/5g/6g) and guest (guest2g/5g/6g) get separate passwords.
    local _main_pass _guest_pass _iface
    _main_pass=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    _guest_pass=$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    for _iface in wifi2g wifi5g wifi6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.key=${_main_pass}"
    done
    for _iface in guest2g guest5g guest6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.key=${_guest_pass}"
    done
    uci commit wireless
}

RANDOMIZE_HOSTNAME() {
    local _suffix _new_hostname
    _suffix=$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    _new_hostname="router-${_suffix}"
    printf '%s' "$_new_hostname" > /proc/sys/kernel/hostname
    uci set system.@system[0].hostname="$_new_hostname"
    uci commit system
    /etc/init.d/log restart 2>/dev/null
}

WIFI_RELOAD() {
    uci commit wireless
    sleep 1
    wifi reload
    /etc/init.d/dnsmasq restart 2>/dev/null
}
