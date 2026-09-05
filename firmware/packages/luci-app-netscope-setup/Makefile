include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netscope-setup
PKG_VERSION:=0.2.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=lststrdst

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-netscope-setup
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=NETSCOPE VPN Quick setup (configuration drafts)
  DEPENDS:=+luci-base +luci-lib-nixio +luci-lib-jsonc +libuci-lua
  PKGARCH:=all
endef

define Package/luci-app-netscope-setup/description
  Authenticated Lua LuCI wizard for private WireGuard, AmneziaWG v1,
  VLESS/Xray and Mieru configuration drafts. No VPN autostart or firewall changes.
  Requires writable storage mounted at /mnt/sda1; VPN binaries are optional.
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
endef

$(eval $(call BuildPackage,luci-app-netscope-setup))
