include $(TOPDIR)/rules.mk

PKG_NAME:=netscope-wifi7-lab
PKG_VERSION:=0.3.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/netscope-wifi7-lab
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=NETSCOPE Wi-Fi 7 fail-closed preflight and renderer
  PKGARCH:=all
endef

define Package/netscope-wifi7-lab/description
  NETSCOPE read-only board/capability checks and target-state renderer for
  Xiaomi BE7000. This package contains no live activation or autostart path.
endef

define Build/Compile
endef

define Package/netscope-wifi7-lab/install
	$(INSTALL_DIR) $(1)/etc/netscope/wifi7
	$(INSTALL_CONF) ./files/etc/netscope/wifi7/profile.conf $(1)/etc/netscope/wifi7/profile.conf
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/netscope-wifi7-lab $(1)/usr/libexec/netscope-wifi7-lab
endef

$(eval $(call BuildPackage,netscope-wifi7-lab))
