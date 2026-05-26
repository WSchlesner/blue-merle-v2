include $(TOPDIR)/rules.mk

PKG_NAME:=blue-merle
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_MAINTAINER:=Blue Merle Contributors
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/package.mk

define Package/blue-merle
	SECTION:=utils
	CATEGORY:=Utilities
	PKGARCH:=all
	EXTRA_DEPENDS:=luci-base, coreutils-shred
	TITLE:=Anonymity Enhancements for GL-iNet GL-E5800 Mudi 7
endef

define Package/blue-merle/description
	blue-merle enhances anonymity and reduces forensic traceability of the
	GL-iNet GL-E5800 (Mudi 7) 5G mobile Wi-Fi router by randomizing IMEI,
	MAC addresses, SSID, hostname, and Wi-Fi password on every boot or on demand.
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/blue-merle/install
	$(INSTALL_DIR) $(1)/lib/blue-merle
	$(INSTALL_DATA) ./files/lib/blue-merle/functions.sh        $(1)/lib/blue-merle/functions.sh
	$(INSTALL_DATA) ./files/lib/blue-merle/imei_generate.lua   $(1)/lib/blue-merle/imei_generate.lua
	$(INSTALL_DATA) ./files/lib/blue-merle/luhn.lua            $(1)/lib/blue-merle/luhn.lua

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/blue-merle                  $(1)/usr/bin/blue-merle

	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/blue-merle              $(1)/usr/libexec/blue-merle

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-wireless      $(1)/etc/init.d/blue-merle-wireless
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-sim-swap       $(1)/etc/init.d/blue-merle-sim-swap
	$(INSTALL_BIN) ./files/etc/init.d/blue-merle-volatile-macs $(1)/etc/init.d/blue-merle-volatile-macs

	$(INSTALL_DIR) $(1)/usr/share/blue-merle
	$(INSTALL_DATA) ./files/usr/share/blue-merle/tac_pool.json $(1)/usr/share/blue-merle/tac_pool.json
	$(INSTALL_DATA) ./files/usr/share/blue-merle/oui_pool.json $(1)/usr/share/blue-merle/oui_pool.json

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

define Package/blue-merle/preinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

_abort_model() {
	echo ""
	echo "blue-merle v2 is designed for the GL-iNet GL-E5800 (Mudi 7)."
	if [ -f /tmp/sysinfo/model ]; then
		echo "Detected device: $$(cat /tmp/sysinfo/model)"
	fi
	echo -n "Continue installation on unsupported device? (y/N): "
	read answer
	case $$answer in
		[yY]*) ;;
		*) exit 1 ;;
	esac
}

_abort_version() {
	echo ""
	echo "blue-merle v2 has been tested on GL-E5800 firmware 4.8.3 only."
	if [ -f /etc/glversion ]; then
		echo "Detected firmware: $$(cat /etc/glversion)"
	fi
	echo "Newer firmware versions may have changed the AT interface or UCI layout."
	echo -n "Continue installation on untested firmware? (y/N): "
	read answer
	case $$answer in
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
		4.8.3)
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

define Package/blue-merle/postinst
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

# Start volatile-macs immediately so the client database moves to RAM.
/etc/init.d/blue-merle-volatile-macs start

# Restart gl_clients against the now-tmpfs-backed database directory.
[ -x /etc/init.d/gl_clients ] && /etc/init.d/gl_clients start 2>/dev/null

# Capture factory state (idempotent — safe to run on reinstall).
/usr/bin/blue-merle install

echo "blue-merle: installation complete. Rotate identity via: blue-merle rotate"
exit 0
endef

define Package/blue-merle/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Stop services while their scripts are still installed.
/etc/init.d/blue-merle-wireless stop 2>/dev/null
/etc/init.d/blue-merle-sim-swap stop 2>/dev/null
/etc/init.d/blue-merle-volatile-macs stop 2>/dev/null

# Restore factory IMEIs, MACs, SSIDs, and hostname while the binary still exists.
[ -x /usr/bin/blue-merle ] && /usr/bin/blue-merle restore 2>/dev/null

exit 0
endef

define Package/blue-merle/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

# Re-enable GL-iNet's BSSID randomization now that blue-merle is removed.
for _radio in wifi0 wifi1 wifi2; do
	uci -q set "wireless.$${_radio}.random_bssid=1" 2>/dev/null
done
uci -q commit wireless

# Disable all services (removes rc.d symlinks).
/etc/init.d/blue-merle-volatile-macs disable 2>/dev/null
/etc/init.d/blue-merle-wireless disable 2>/dev/null
/etc/init.d/blue-merle-sim-swap disable 2>/dev/null

# Clean up runtime state files.
rm -f /etc/blue-merle.last_imei_rotate \
      /etc/blue-merle.last_wireless_rotate \
      /etc/blue-merle.sim-swap-pending

echo "blue-merle: uninstalled. Factory identity restored."
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
