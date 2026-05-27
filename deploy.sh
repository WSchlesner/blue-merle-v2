#!/usr/bin/env bash
# Deploy blue-merle v2 files to the Mudi 7 over SSH.
# Usage:  ./deploy.sh [host]   (default host: root@192.168.8.1)
set -e
HOST="${1:-root@192.168.8.1}"
REPO="$(cd "$(dirname "$0")" && pwd)"

echo "==> Deploying blue-merle v2 to $HOST"

# Create target directories
ssh "$HOST" 'mkdir -p /lib/blue-merle /usr/bin /usr/libexec /usr/share/blue-merle /etc/init.d \
    /usr/share/luci/menu.d /usr/share/rpcd/acl.d /www/luci-static/resources/view'

# Library files (-O forces legacy SCP protocol; OpenWrt busybox sshd needs it)
scp -O "$REPO/files/lib/blue-merle/functions.sh"      "$HOST:/lib/blue-merle/functions.sh"
scp -O "$REPO/files/lib/blue-merle/imei_generate.lua" "$HOST:/lib/blue-merle/imei_generate.lua"
scp -O "$REPO/files/lib/blue-merle/luhn.lua"          "$HOST:/lib/blue-merle/luhn.lua"

# CLI
scp -O "$REPO/files/usr/bin/blue-merle"       "$HOST:/usr/bin/blue-merle"
scp -O "$REPO/files/usr/bin/blue-merle-touch" "$HOST:/usr/bin/blue-merle-touch"
ssh "$HOST" 'chmod +x /usr/bin/blue-merle /usr/bin/blue-merle-touch'

# init.d services
scp -O "$REPO/files/etc/init.d/blue-merle-wireless"      "$HOST:/etc/init.d/blue-merle-wireless"
scp -O "$REPO/files/etc/init.d/blue-merle-sim-swap"      "$HOST:/etc/init.d/blue-merle-sim-swap"
scp -O "$REPO/files/etc/init.d/blue-merle-volatile-macs" "$HOST:/etc/init.d/blue-merle-volatile-macs"
scp -O "$REPO/files/etc/init.d/blue-merle-touch"         "$HOST:/etc/init.d/blue-merle-touch"
ssh "$HOST" 'chmod +x /etc/init.d/blue-merle-wireless /etc/init.d/blue-merle-sim-swap \
        /etc/init.d/blue-merle-volatile-macs /etc/init.d/blue-merle-touch \
    && rm -f /etc/rc.d/S*blue-merle-wireless /etc/rc.d/S*blue-merle-sim-swap \
        /etc/rc.d/S*blue-merle-volatile-macs /etc/rc.d/S*blue-merle-touch \
    && /etc/init.d/blue-merle-wireless enable \
    && /etc/init.d/blue-merle-sim-swap enable \
    && /etc/init.d/blue-merle-volatile-macs enable \
    && /etc/init.d/blue-merle-touch enable'

# Data pools and splash frames
scp -O "$REPO/files/usr/share/blue-merle/tac_pool.json" "$HOST:/usr/share/blue-merle/tac_pool.json"
scp -O "$REPO/files/usr/share/blue-merle/oui_pool.json" "$HOST:/usr/share/blue-merle/oui_pool.json"
ssh "$HOST" 'mkdir -p /usr/share/blue-merle/screens'
scp -O "$REPO/files/usr/share/blue-merle/screens/"*.rgb565 "$HOST:/usr/share/blue-merle/screens/"

# LuCI Phase 3 — modern LuCI2 JS view
# Remove old Lua/HTM approach if it was previously deployed
ssh "$HOST" 'rm -f /usr/lib/lua/luci/controller/blue_merle.lua \
    /usr/lib/lua/luci/view/blue_merle/index.htm \
    && rmdir /usr/lib/lua/luci/view/blue_merle /usr/lib/lua/luci/view 2>/dev/null; true'

# rpcd exec backend
scp -O "$REPO/files/usr/libexec/blue-merle" "$HOST:/usr/libexec/blue-merle"
ssh "$HOST" 'chmod +x /usr/libexec/blue-merle'

# Menu and ACL registration
scp -O "$REPO/files/usr/share/luci/menu.d/luci-app-blue-merle.json" \
    "$HOST:/usr/share/luci/menu.d/luci-app-blue-merle.json"
scp -O "$REPO/files/usr/share/rpcd/acl.d/luci-app-blue-merle.json" \
    "$HOST:/usr/share/rpcd/acl.d/luci-app-blue-merle.json"

# JS view
scp -O "$REPO/files/www/luci-static/resources/view/blue_merle.js" \
    "$HOST:/www/luci-static/resources/view/blue_merle.js"
# Remove the old hyphen-named file if it was previously deployed
ssh "$HOST" 'rm -f /www/luci-static/resources/view/blue-merle.js'

# Reload rpcd so the new ACL is picked up; clear LuCI caches
ssh "$HOST" '/etc/init.d/rpcd reload; rm -f /tmp/luci-indexcache*'

echo ""
echo "==> Deploy complete. Verify with: ssh $HOST blue-merle status"
echo "    LuCI page: http://${HOST#*@}:8080 → Services → Blue Merle"
