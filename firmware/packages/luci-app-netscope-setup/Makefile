include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netscope-setup
PKG_VERSION:=0.7.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=lststrdst

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-netscope-setup
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=NETSCOPE VPN Quick setup (configuration drafts)
  DEPENDS:=+luci-base +luci-lib-nixio +luci-lib-jsonc +libuci-lua +wireguard-tools +kmod-wireguard +iptables
  PKGARCH:=all
endef

define Package/luci-app-netscope-setup/description
  Authenticated Lua LuCI wizard for private WireGuard, AmneziaWG v1,
  VLESS/Xray, Mieru and Hysteria 2 configurations. Every available runtime has explicit
  preflight, activation, confirmation and protocol-scoped rollback. No profile
  changes UCI, DNS or the default route. Requires writable /mnt/sda1 storage;
  protocol binaries remain optional and are checked before activation.
endef

define Build/Compile
endef

define Package/luci-app-netscope-setup/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller $(1)/usr/lib/lua/luci/model
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/controller/netscope_setup.lua $(1)/usr/lib/lua/luci/controller/
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/model/*.lua $(1)/usr/lib/lua/luci/model/
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/netscope $(1)/www/luci-static/netscope
	$(INSTALL_DATA) ./files/usr/lib/lua/luci/view/netscope/setup.htm $(1)/usr/lib/lua/luci/view/netscope/
	$(INSTALL_DATA) ./files/www/luci-static/netscope/setup.js $(1)/www/luci-static/netscope/
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/netscope-vpn-profile $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-install-hysteria $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-install-mieru $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-install-hev $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-voice-update $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-voice-route $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-hy2-udp-probe $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-tun-udp-probe $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-mieru-tun $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-voice-monitor $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-voice-boot $(1)/usr/libexec/
	$(INSTALL_BIN) ./files/usr/libexec/netscope-l2tp-watchdog $(1)/usr/libexec/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/netscope-voice $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/etc/init.d/netscope-l2tp-watchdog $(1)/etc/init.d/
endef

$(eval $(call BuildPackage,luci-app-netscope-setup))
