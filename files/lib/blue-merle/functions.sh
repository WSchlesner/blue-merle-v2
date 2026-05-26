#!/usr/bin/env ash
# blue-merle v2 — helper functions
# Device: GL-iNet GL-E5800 (Mudi 7), Quectel RG650V-NA, OpenWrt 23.05.4
# Sourced by /usr/bin/blue-merle and the init.d services.

BUS=CPU
SUB=1  # logical subscription for _at() — slot 1 (-U 1); -U 0 alternates and must not be used

# ── Messaging ────────────────────────────────────────────────────────────────
# Writes to syslog and stdout. During boot stdout goes to the system console;
# during SSH sessions it appears inline.
# Phase 4: add gl_screen/mcu ubus notification here when the display API is confirmed.
_screen_msg() {
    logger -p notice -t blue-merle "$1"
    echo "blue-merle: $1"
}

# ── Modem AT helpers ─────────────────────────────────────────────────────────

# Send one AT command via the active subscription channel.
_at() {
    gl_modem -B "$BUS" -U "$SUB" AT "$1"
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

# SIM Slot 1 IMSI — reads via subscription 1 (-U 1), retries up to 3×.
READ_IMSI_SLOT1() {
    local i=0 imsi
    while [ "$i" -lt 3 ]; do
        imsi=$(gl_modem -B "$BUS" -U 1 AT AT+CIMI | tr -d '\r' | grep -E '^[0-9]{6,15}$')
        [ -n "$imsi" ] && { echo "$imsi"; return 0; }
        i=$((i + 1))
        sleep 2
    done
    return 1
}

# SIM Slot 2 IMSI — reads via subscription 2 (-U 2), retries up to 3×.
# Returns non-zero if no SIM2 is present or SIM is inactive/dead.
READ_IMSI_SLOT2() {
    local i=0 imsi
    while [ "$i" -lt 3 ]; do
        imsi=$(gl_modem -B "$BUS" -U 2 AT AT+CIMI | tr -d '\r' | grep -E '^[0-9]{6,15}$')
        [ -n "$imsi" ] && { echo "$imsi"; return 0; }
        i=$((i + 1))
        sleep 2
    done
    return 1
}

# Generic READ_IMSI — slot 1 (backward-compat alias).
READ_IMSI() {
    READ_IMSI_SLOT1
}

# SIM Slot 1 ICCID — try AT+QCCID first, fall back to AT+CCID.
READ_ICCID_SLOT1() {
    local out
    out=$(gl_modem -B "$BUS" -U 1 AT AT+QCCID | tr -d '\r')
    if echo "$out" | grep -q '+QCCID:'; then
        echo "$out" | grep -o '+QCCID:.*' | sed 's/+QCCID: //' | tr -d 'F'
        return
    fi
    gl_modem -B "$BUS" -U 1 AT AT+CCID | tr -d '\r' | grep -o '+CCID:.*' | sed 's/+CCID: //' | tr -d 'F'
}

# SIM Slot 2 ICCID — reads via subscription 2.
READ_ICCID_SLOT2() {
    local out
    out=$(gl_modem -B "$BUS" -U 2 AT AT+QCCID | tr -d '\r')
    if echo "$out" | grep -q '+QCCID:'; then
        echo "$out" | grep -o '+QCCID:.*' | sed 's/+QCCID: //' | tr -d 'F'
        return
    fi
    gl_modem -B "$BUS" -U 2 AT AT+CCID | tr -d '\r' | grep -o '+CCID:.*' | sed 's/+CCID: //' | tr -d 'F'
}

# Generic READ_ICCID — slot 1 (backward-compat alias).
READ_ICCID() {
    READ_ICCID_SLOT1
}

# Write IMEI for SIM Slot 1 (AT+EGMR field 7).
SET_IMEI_SLOT1() {
    local imei="$1"
    if [ ${#imei} -ne 15 ]; then
        echo "blue-merle: SET_IMEI_SLOT1: expected 15-digit IMEI, got ${#imei} digits" >&2
        return 1
    fi
    local out
    out=$(_at "AT+EGMR=1,7,\"${imei}\"" 2>&1)
    if ! echo "$out" | grep -q "OK"; then
        echo "blue-merle: EGMR field 7 (slot 1) write failed" >&2
        return 1
    fi
    sleep 1
}

# Write IMEI for SIM Slot 2 / eSIM (AT+EGMR field 11).
# Also updates /root/esim/imei so the eSIM LPA uses this IMEI for RSP identity.
SET_IMEI_SLOT2() {
    local imei="$1"
    if [ ${#imei} -ne 15 ]; then
        echo "blue-merle: SET_IMEI_SLOT2: expected 15-digit IMEI, got ${#imei} digits" >&2
        return 1
    fi
    local out
    out=$(_at "AT+EGMR=1,11,\"${imei}\"" 2>&1)
    if ! echo "$out" | grep -q "OK"; then
        echo "blue-merle: EGMR field 11 (slot 2/eSIM) write failed" >&2
        return 1
    fi
    sleep 1
    [ -f /root/esim/imei ] && printf '%s\n' "$imei" > /root/esim/imei
}

# Write both IMEIs, persist all NV changes to flash, and refresh WebUI.
# $1 = Slot 1 IMEI (field 7), $2 = Slot 2/eSIM IMEI (field 11)
SET_IMEIS() {
    local imei1="$1" imei2="$2"
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

GENERATE_IMEI_STATIC() {
    lua /lib/blue-merle/imei_generate.lua static
}

# Deterministic IMEI keyed to SIM Slot 1 IMSI.
GENERATE_IMEI_DETERMINISTIC() {
    local imsi
    imsi=$(READ_IMSI_SLOT1)
    if [ -z "$imsi" ]; then
        echo "blue-merle: GENERATE_IMEI_DETERMINISTIC: could not read slot 1 IMSI" >&2
        return 1
    fi
    lua /lib/blue-merle/imei_generate.lua deterministic "$imsi"
}

# Deterministic IMEI keyed to SIM Slot 2 IMSI.
GENERATE_IMEI_DETERMINISTIC_SLOT2() {
    local imsi
    imsi=$(READ_IMSI_SLOT2)
    if [ -z "$imsi" ]; then
        echo "blue-merle: GENERATE_IMEI_DETERMINISTIC_SLOT2: could not read slot 2 IMSI" >&2
        return 1
    fi
    lua /lib/blue-merle/imei_generate.lua deterministic "$imsi"
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
        if [ -z "$static_imei" ]; then
            echo "blue-merle: slot ${slot} static IMEI not configured — using random IMEI" >&2
            GENERATE_IMEI
        else
            printf '%s\n' "$static_imei"
        fi
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

# Full modem reinit: power everything down then bring RF back off.
# Use after a physical SIM swap to force the modem to re-read the new SIM.
# Polls AT+CPIN? until the SIM is READY (or 30s timeout) before returning.
MODEM_RF_REINIT() {
    _at AT+CFUN=0 >/dev/null 2>&1    # full minimum-functionality (SIM and RF off)
    sleep 4
    _at AT+CFUN=4 >/dev/null 2>&1    # RF off, SIM re-initializes with new card

    local elapsed=0
    while [ "$elapsed" -lt 30 ]; do
        local cpin
        cpin=$(_at AT+CPIN? | tr -d '\r')
        if echo "$cpin" | grep -q 'READY'; then
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    # SIM not ready — caller will check IMSI and warn if unchanged.
    return 0
}

# Re-enable RF and wait for network re-attachment.
# Stops cellular_manager around the AT cycle to prevent state-machine conflict.
# Block until re-attach or $1 seconds timeout (default 90).
MODEM_RESET_FOR_PRIVACY() {
    local timeout="${1:-90}"

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

MAC_GEN() {
    local category="${1:-routers}"
    local ouis
    ouis=$(_load_ouis "$category")
    local oui
    oui=$(_pick_oui "$ouis")
    # Force LA bit on first octet (0x02 mask) — keeps channel co-location intact.
    local _first _rest
    _first=$(printf '%02x' $(( 0x${oui%%:*} | 0x02 )))
    _rest=${oui#*:}
    local nic
    nic=$(od -An -N3 -tx1 /dev/urandom | tr -d ' \n' | sed 's/\(..\)\(..\)\(..\)/\1:\2:\3/')
    echo "${_first}:${_rest}:${nic}" | tr '[:upper:]' '[:lower:]'
}

MAC_GEN_ROUTER()  { MAC_GEN routers; }
MAC_GEN_CLIENT()  { MAC_GEN clients; }
UNICAST_MAC_GEN() { MAC_GEN routers; }  # v1 compat alias

# ── Wireless UCI randomization ────────────────────────────────────────────────
# Mudi 7 uses named interfaces (wifi2g / wifi5g / wifi6g / sta / guest*g).

RANDOMIZE_MACADDR() {
    # Disable GL-iNet's BSSID randomization — we own MAC rotation from here.
    # LA bit is forced in MAC_GEN so Qualcomm's channel co-location still works.
    for _radio in wifi0 wifi1 wifi2; do
        uci -q set "wireless.${_radio}.random_bssid=0" 2>/dev/null
    done
    # AP interfaces: router-class OUI MACs (look like common home routers)
    for _iface in wifi2g wifi5g wifi6g guest2g guest5g guest6g; do
        uci get "wireless.${_iface}" >/dev/null 2>&1 && \
            uci set "wireless.${_iface}.macaddr=$(MAC_GEN_ROUTER)"
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
    for _radio in wifi0 wifi1 wifi2; do
        uci -q set "wireless.${_radio}.random_bssid=1" 2>/dev/null
    done
    uci commit wireless
}

RANDOMIZE_SSID() {
    local _idx _suffix _new_ssid
    _idx=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % 7 ))
    _suffix=$(od -An -N2 -tx1 /dev/urandom | tr -d ' \n' | tr '[:lower:]' '[:upper:]')
    case "$_idx" in
        0) _new_ssid="NETGEAR-${_suffix}" ;;
        1) _new_ssid="TP-Link-${_suffix}" ;;
        2) _new_ssid="ASUS-${_suffix}" ;;
        3) _new_ssid="Linksys-${_suffix}" ;;
        4) _new_ssid="eero-${_suffix}" ;;
        5) _new_ssid="ORBI-${_suffix}" ;;
        *) _new_ssid="HOME-${_suffix}" ;;
    esac
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
    local _main_pass _guest_pass
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
