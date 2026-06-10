#!/usr/bin/env bash
# Build blue-merle-v2_VERSION-Script-BUILDMETHOD.ipk without the OpenWrt SDK.
# ("Script" marks the build path, alongside the SDK workflow's -SDK- assets.)
# Usage: ./build-ipk.sh
# BUILD_METHOD env var controls the suffix: Local (default) | CI | Release
set -e

PKG_NAME=blue-merle-v2
PKG_VERSION=1.0.0
BUILD_METHOD="${BUILD_METHOD:-Local}"
ARCH=aarch64_cortex-a53

REPO="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${REPO}/build"
STAGING="${BUILD_DIR}/staging"
CONTROL_DIR="${BUILD_DIR}/control"
OUTPUT="${REPO}/${PKG_NAME}_${PKG_VERSION}-Script-${BUILD_METHOD}.ipk"

# ── Preflight ─────────────────────────────────────────────────────────────────

for _tool in ar tar install; do
    command -v "$_tool" >/dev/null || { echo "ERROR: '$_tool' not found"; exit 1; }
done

echo "==> Building $(basename "$OUTPUT")"

rm -rf "$BUILD_DIR"
mkdir -p "$STAGING" "$CONTROL_DIR"

# ── Stage files ───────────────────────────────────────────────────────────────

install -d "$STAGING/lib/blue-merle"
install -m 0644 "$REPO/files/lib/blue-merle/functions.sh"         "$STAGING/lib/blue-merle/functions.sh"
install -m 0644 "$REPO/files/lib/blue-merle/imei_generate.lua"    "$STAGING/lib/blue-merle/imei_generate.lua"
install -m 0644 "$REPO/files/lib/blue-merle/luhn.lua"             "$STAGING/lib/blue-merle/luhn.lua"

install -d "$STAGING/usr/bin"
install -m 0755 "$REPO/files/usr/bin/blue-merle"                  "$STAGING/usr/bin/blue-merle"
install -m 0755 "$REPO/files/usr/bin/blue-merle-touch"            "$STAGING/usr/bin/blue-merle-touch"

install -d "$STAGING/usr/libexec"
install -m 0755 "$REPO/files/usr/libexec/blue-merle"              "$STAGING/usr/libexec/blue-merle"

install -d "$STAGING/etc/init.d"
install -m 0755 "$REPO/files/etc/init.d/blue-merle-wireless"      "$STAGING/etc/init.d/blue-merle-wireless"
install -m 0755 "$REPO/files/etc/init.d/blue-merle-sim-swap"      "$STAGING/etc/init.d/blue-merle-sim-swap"
install -m 0755 "$REPO/files/etc/init.d/blue-merle-volatile-macs" "$STAGING/etc/init.d/blue-merle-volatile-macs"
install -m 0755 "$REPO/files/etc/init.d/blue-merle-touch"         "$STAGING/etc/init.d/blue-merle-touch"

install -d "$STAGING/usr/share/blue-merle"
install -m 0644 "$REPO/files/usr/share/blue-merle/tac_pool.json"  "$STAGING/usr/share/blue-merle/tac_pool.json"
install -m 0644 "$REPO/files/usr/share/blue-merle/oui_pool.json"  "$STAGING/usr/share/blue-merle/oui_pool.json"

install -d "$STAGING/usr/share/blue-merle/screens"
for _f in "$REPO/files/usr/share/blue-merle/screens/"*.rgb565; do
    install -m 0644 "$_f" "$STAGING/usr/share/blue-merle/screens/$(basename "$_f")"
done

install -d "$STAGING/usr/share/luci/menu.d"
install -m 0644 "$REPO/files/usr/share/luci/menu.d/luci-app-blue-merle.json" \
    "$STAGING/usr/share/luci/menu.d/luci-app-blue-merle.json"

install -d "$STAGING/usr/share/rpcd/acl.d"
install -m 0644 "$REPO/files/usr/share/rpcd/acl.d/luci-app-blue-merle.json" \
    "$STAGING/usr/share/rpcd/acl.d/luci-app-blue-merle.json"

install -d "$STAGING/www/luci-static/resources/view"
install -m 0644 "$REPO/files/www/luci-static/resources/view/blue_merle.js" \
    "$STAGING/www/luci-static/resources/view/blue_merle.js"

# ── Installed size (kB) ───────────────────────────────────────────────────────

INSTALLED_SIZE=$(du -sk "$STAGING" | awk '{print $1}')

# ── Control file ──────────────────────────────────────────────────────────────

cat > "$CONTROL_DIR/control" <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Depends: luci-base, lua, luabitop
Source: ${PKG_NAME}
License: GPL-2.0-only
Section: utils
Maintainer: Blue Merle Contributors
Architecture: ${ARCH}
Installed-Size: ${INSTALLED_SIZE}
Description: Anonymity Enhancements for GL-iNet GL-E5800 Mudi 7
 blue-merle enhances anonymity and reduces forensic traceability of the
 GL-iNet GL-E5800 (Mudi 7) 5G mobile Wi-Fi router by randomizing IMEI,
 MAC addresses, SSID, hostname, and Wi-Fi password on every boot or on demand.
EOF

# ── preinst ───────────────────────────────────────────────────────────────────

cat > "$CONTROL_DIR/preinst" <<'PREINST'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

_require_tty() {
    if [ ! -t 0 ]; then
        echo "Non-interactive install — cannot confirm. Re-run 'opkg install' from an SSH shell."
        exit 1
    fi
}

_abort_model() {
    echo ""
    echo "blue-merle v2 is designed for the GL-iNet GL-E5800 (Mudi 7)."
    [ -f /tmp/sysinfo/model ] && echo "Detected device: $(cat /tmp/sysinfo/model)"
    _require_tty
    printf "Continue installation on unsupported device? (y/N): "
    read -r answer
    case "$answer" in [yY]*) ;; *) exit 1 ;; esac
}

_abort_version() {
    echo ""
    echo "blue-merle v2 has been tested on GL-E5800 firmware 4.8.3 and 4.8.5 only."
    [ -f /etc/glversion ] && echo "Detected firmware: $(cat /etc/glversion)"
    echo "Newer firmware versions may have changed the AT interface or UCI layout."
    _require_tty
    printf "Continue installation on untested firmware? (y/N): "
    read -r answer
    case "$answer" in [yY]*) ;; *) exit 1 ;; esac
}

if ! grep -qi "E5800" /tmp/sysinfo/model 2>/dev/null; then
    _abort_model
fi

if [ -f /etc/glversion ]; then
    GL_VERSION="$(cat /etc/glversion)"
    case "$GL_VERSION" in
        4.8.3|4.8.5)
                echo "Firmware $GL_VERSION confirmed supported." ;;
        4.8.*)  echo "Firmware $GL_VERSION is newer than tested — probably compatible."
                _abort_version ;;
        4.*)    echo "Firmware $GL_VERSION has not been tested with blue-merle v2."
                _abort_version ;;
        *)      echo "Unrecognised firmware version: $GL_VERSION"
                _abort_version ;;
    esac
fi

[ -x /etc/init.d/gl_clients ] && /etc/init.d/gl_clients stop 2>/dev/null
exit 0
PREINST

# ── postinst ──────────────────────────────────────────────────────────────────

cat > "$CONTROL_DIR/postinst" <<'POSTINST'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

for _radio in wifi0 wifi1 wifi2; do
    uci -q set "wireless.${_radio}.random_bssid=0" 2>/dev/null
done
uci -q commit wireless

/etc/init.d/blue-merle-volatile-macs enable
/etc/init.d/blue-merle-wireless enable
/etc/init.d/blue-merle-sim-swap enable

# Touchscreen trigger: respect a preference saved by a previous install
# (LuCI toggle persists it to UCI); default to enabled on fresh installs.
if [ "$(uci -q get blue-merle.options.touch_enabled 2>/dev/null)" != "0" ]; then
    /etc/init.d/blue-merle-touch enable
    /etc/init.d/blue-merle-touch start
fi

/etc/init.d/blue-merle-volatile-macs start
[ -x /etc/init.d/gl_clients ] && /etc/init.d/gl_clients start 2>/dev/null

/usr/bin/blue-merle install

echo "blue-merle: installation complete. Rotate identity via: blue-merle rotate"
exit 0
POSTINST

# ── prerm ─────────────────────────────────────────────────────────────────────

cat > "$CONTROL_DIR/prerm" <<'PRERM'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

# Stop AND disable here, while the init scripts still exist — opkg deletes
# package files before postrm runs, so doing either there is a no-op.
/etc/init.d/blue-merle-touch stop 2>/dev/null
/etc/init.d/blue-merle-wireless stop 2>/dev/null
/etc/init.d/blue-merle-sim-swap stop 2>/dev/null
/etc/init.d/blue-merle-volatile-macs stop 2>/dev/null

/etc/init.d/blue-merle-touch disable 2>/dev/null
/etc/init.d/blue-merle-wireless disable 2>/dev/null
/etc/init.d/blue-merle-sim-swap disable 2>/dev/null
/etc/init.d/blue-merle-volatile-macs disable 2>/dev/null

[ -x /usr/bin/blue-merle ] && /usr/bin/blue-merle restore 2>/dev/null
exit 0
PRERM

# ── postrm ────────────────────────────────────────────────────────────────────

cat > "$CONTROL_DIR/postrm" <<'POSTRM'
#!/bin/sh
[ -n "${IPKG_INSTROOT}" ] && exit 0

for _radio in wifi0 wifi1 wifi2; do
    uci -q set "wireless.${_radio}.random_bssid=1" 2>/dev/null
done
uci -q commit wireless

# Services were stopped/disabled in prerm (scripts are deleted by now);
# sweep any rc.d symlinks left behind so nothing dangles.
rm -f /etc/rc.d/S*blue-merle* /etc/rc.d/K*blue-merle*

rm -f /etc/blue-merle.last_imei_rotate \
      /etc/blue-merle.last_wireless_rotate \
      /etc/blue-merle.sim-swap-pending

echo "blue-merle: uninstalled. Factory identity restored."
exit 0
POSTRM

chmod 0755 "$CONTROL_DIR/preinst" "$CONTROL_DIR/postinst" \
           "$CONTROL_DIR/prerm"   "$CONTROL_DIR/postrm"

# ── Assemble archives ─────────────────────────────────────────────────────────

echo "  Packing data..."
(cd "$STAGING"     && tar czf "$BUILD_DIR/data.tar.gz"    --owner=0 --group=0 .)

echo "  Packing control..."
(cd "$CONTROL_DIR" && tar czf "$BUILD_DIR/control.tar.gz" --owner=0 --group=0 .)

printf '2.0\n' > "$BUILD_DIR/debian-binary"

# ── Build IPK (gzip-compressed tar) ──────────────────────────────────────────
# This opkg uses the classic ipkg format: a gzip-compressed tar containing
# ./debian-binary, ./control.tar.gz, and ./data.tar.gz — NOT a Debian ar archive.

echo "  Creating IPK..."
rm -f "$OUTPUT"
(cd "$BUILD_DIR" && tar czf "$OUTPUT" --owner=0 --group=0 \
    ./debian-binary ./control.tar.gz ./data.tar.gz)

# ── Done ──────────────────────────────────────────────────────────────────────

SIZE=$(du -sh "$OUTPUT" | awk '{print $1}')
echo ""
echo "==> ${OUTPUT} (${SIZE})"
echo ""
echo "Install on device:"
echo "  scp -O '${OUTPUT}' root@192.168.8.1:/tmp/"
echo "  ssh root@192.168.8.1 'opkg install --force-reinstall /tmp/$(basename "$OUTPUT")'"
