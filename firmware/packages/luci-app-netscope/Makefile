include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netscope
PKG_VERSION:=0.7.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=lststrdst

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-netscope
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=NETSCOPE traffic inventory and controlled capture
  DEPENDS:=+luci-base +luci-lib-nixio +luci-lib-jsonc +libuci-lua +tcpdump +iptables +openssl-util
  PKGARCH:=all
endef

define Package/luci-app-netscope/description
  Authenticated NETSCOPE traffic inventory, bounded USB PCAP sessions and an
  optional transparent HTTPS inspection controller. Capture and interception
  are disabled after installation and never resume automatically after failure.
endef

define Build/Compile
endef

define Package/luci-app-netscope/install
	$(INSTALL_DIR) $(1)
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,luci-app-netscope))
