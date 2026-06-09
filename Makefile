include $(TOPDIR)/rules.mk

PKG_NAME:=blue-merle-v2
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Blue Merle Contributors
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/blue-merle-v2
	SECTION:=utils
	CATEGORY:=Utilities
	EXTRA_DEPENDS:=luci-base, lua, luabitop
	TITLE:=Anonymity Enhancements for GL-iNet GL-E5800 Mudi 7
endef

define Package/blue-merle-v2/description
	blue-merle enhances anonymity and reduces forensic traceability of the
	GL-iNet GL-E5800 (Mudi 7) 5G mobile Wi-Fi router by randomizing IMEI,
	MAC addresses, SSID, hostname, and Wi-Fi password on every boot or on demand.
endef

# Local source package — no PKG_SOURCE tarball, so stage src/ into the
# build dir ourselves before compiling the touchscreen daemon.
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

define Build/Configure
endef

# Compile the blue-merle-touch evdev daemon for the target arch (statically
# linked, matching the prebuilt binary build-ipk.sh bundles).
define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -O2 -static \
		-o $(PKG_BUILD_DIR)/blue-merle-touch \
		$(PKG_BUILD_DIR)/blue-merle-touch.c
endef

define Package/blue-merle-v2/install
	$(INSTALL_DIR) $(1)/lib/blue-merle
	$(INSTALL_DATA) ./files/lib/blue-merle/functions.sh        $(1)/lib/blue-merle/functions.sh
	$(INSTALL_DATA) ./files/lib/blue-merle/imei_generate.lua   $(1)/lib/blue-merle/imei_generate.lua
	$(INSTALL_DATA) ./files/lib/blue-merle/luhn.lua            $(1)/lib/blue-merle/luhn.lua

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/blue-merle                  $(1)/usr/bin/blue-merle
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/blue-merle-touch           $(1)/usr/bin/blue-merle-touch

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/blue-merle              $(1)/usr/libexec/blue-merle

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-wireless      $(1)/etc/init.d/blue-merle-wireless
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-sim-swap      $(1)/etc/init.d/blue-merle-sim-swap
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-volatile-macs $(1)/etc/init.d/blue-merle-volatile-macs
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-touch         $(1)/etc/init.d/blue-merle-touch

	$(INSTALL_DIR) $(1)/usr/share/blue-merle
	$(INSTALL_DATA) ./files/usr/share/blue-merle/tac_pool.json $(1)/usr/share/blue-merle/tac_pool.json
	$(INSTALL_DATA) ./files/usr/share/blue-merle/oui_pool.json $(1)/usr/share/blue-merle/oui_pool.json

	$(INSTALL_DIR) $(1)/usr/share/blue-merle/screens
	$(INSTALL_DATA) ./files/usr/share/blue-merle/screens/*.rgb565 $(1)/usr/share/blue-merle/screens/

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-blue-merle.json \
		$(1)/usr/share/luci/menu.d/luci-app-blue-merle.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-blue-merle.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-blue-merle.json

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) ./files/www/luci-static/resources/view/blue_merle.js \
		$(1)/www/luci-static/resources/view/blue_merle.js
endef

define Package/blue-merle-v2/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

_require_tty() {
	if [ ! -t 0 ]; then
		echo "Non-interactive install — cannot confirm. Re-run 'opkg install' from an SSH shell."
		exit 1
	fi
}

_abort_model() {
	echo ""
	echo "blue-merle v2 is designed for the GL-iNet GL-E5800 (Mudi 7)."
	if [ -f /tmp/sysinfo/model ]; then
		echo "Detected device: $$(cat /tmp/sysinfo/model)"
	fi
	_require_tty
	printf "Continue installation on unsupported device? (y/N): "
	read -r answer
	case "$$answer" in
		[yY]*) ;;
		*) exit 1 ;;
	esac
}

_abort_version() {
	echo ""
	echo "blue-merle v2 has been tested on GL-E5800 firmware 4.8.3 and 4.8.5 only."
	if [ -f /etc/glversion ]; then
		echo "Detected firmware: $$(cat /etc/glversion)"
	fi
	echo "Newer firmware versions may have changed the AT interface or UCI layout."
	_require_tty
	printf "Continue installation on untested firmware? (y/N): "
	read -r answer
	case "$$answer" in
		[yY]*) ;;
		*) exit 1 ;;
	esac
}

# Device model check
if ! grep -qi "E5800" /tmp/sysinfo/model 2>/dev/null; then
	_abort_model
fi

# Firmware version check
if [ -f /etc/glversion ]; then
	GL_VERSION="$$(cat /etc/glversion)"
	case "$$GL_VERSION" in
		4.8.3|4.8.5)
			echo "Firmware $$GL_VERSION confirmed supported."
			;;
		4.8.*)
			echo "Firmware $$GL_VERSION is newer than tested — probably compatible."
			_abort_version
			;;
		4.*)
			echo "Firmware $$GL_VERSION has not been tested with blue-merle v2."
			_abort_version
			;;
		*)
			echo "Unrecognised firmware version: $$GL_VERSION"
			_abort_version
			;;
	esac
fi

# Stop gl_clients before volatile-macs mounts tmpfs over its database directory.
[ -x /etc/init.d/gl_clients ] && /etc/init.d/gl_clients stop 2>/dev/null

exit 0
endef

define Package/blue-merle-v2/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Disable GL-iNet's BSSID randomization — blue-merle owns MAC rotation.
for _radio in wifi0 wifi1 wifi2; do
	uci -q set "wireless.$${_radio}.random_bssid=0" 2>/dev/null
done
uci -q commit wireless

# Enable all blue-merle init.d services.
/etc/init.d/blue-merle-volatile-macs enable
/etc/init.d/blue-merle-wireless enable
/etc/init.d/blue-merle-sim-swap enable

# Touchscreen trigger: respect a preference saved by a previous install
# (LuCI toggle persists it to UCI); default to enabled on fresh installs.
if [ "$$(uci -q get blue-merle.options.touch_enabled 2>/dev/null)" != "0" ]; then
	/etc/init.d/blue-merle-touch enable
	/etc/init.d/blue-merle-touch start
fi

# Start volatile-macs immediately so the client database moves to RAM.
/etc/init.d/blue-merle-volatile-macs start

# Restart gl_clients against the now-tmpfs-backed database directory.
[ -x /etc/init.d/gl_clients ] && /etc/init.d/gl_clients start 2>/dev/null

# Capture factory state (idempotent — safe to run on reinstall).
/usr/bin/blue-merle install

echo "blue-merle: installation complete. Rotate identity via: blue-merle rotate"
exit 0
endef

define Package/blue-merle-v2/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Stop AND disable while the init scripts still exist — opkg deletes
# package files before postrm runs, so doing either there is a no-op.
/etc/init.d/blue-merle-touch stop 2>/dev/null
/etc/init.d/blue-merle-wireless stop 2>/dev/null
/etc/init.d/blue-merle-sim-swap stop 2>/dev/null
/etc/init.d/blue-merle-volatile-macs stop 2>/dev/null

/etc/init.d/blue-merle-touch disable 2>/dev/null
/etc/init.d/blue-merle-wireless disable 2>/dev/null
/etc/init.d/blue-merle-sim-swap disable 2>/dev/null
/etc/init.d/blue-merle-volatile-macs disable 2>/dev/null

# Restore factory IMEIs, MACs, SSIDs, and hostname while the binary still exists.
[ -x /usr/bin/blue-merle ] && /usr/bin/blue-merle restore 2>/dev/null

exit 0
endef

define Package/blue-merle-v2/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Re-enable GL-iNet's BSSID randomization now that blue-merle is removed.
for _radio in wifi0 wifi1 wifi2; do
	uci -q set "wireless.$${_radio}.random_bssid=1" 2>/dev/null
done
uci -q commit wireless

# Services were stopped/disabled in prerm (scripts are deleted by now);
# sweep any rc.d symlinks left behind so nothing dangles.
rm -f /etc/rc.d/S*blue-merle* /etc/rc.d/K*blue-merle*

# Clean up runtime state files.
rm -f /etc/blue-merle.last_imei_rotate \
      /etc/blue-merle.last_wireless_rotate \
      /etc/blue-merle.sim-swap-pending

echo "blue-merle: uninstalled. Factory identity restored."
exit 0
endef

$(eval $(call BuildPackage,blue-merle-v2))
