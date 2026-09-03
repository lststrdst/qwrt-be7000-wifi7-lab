include $(TOPDIR)/rules.mk

PKG_NAME:=be7000-wifi7-lab
PKG_VERSION:=0.2.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/be7000-wifi7-lab
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=BE7000 Wi-Fi 7 fail-closed preflight and renderer
  PKGARCH:=all
endef

define Package/be7000-wifi7-lab/description
  Read-only board/capability checks and a stock-like target-state renderer.
  This package contains no live activation or autostart path.
endef

define Build/Compile
endef

define Package/be7000-wifi7-lab/install
	$(INSTALL_DIR) $(1)/etc/be7000-wifi7
	$(INSTALL_CONF) ./files/etc/be7000-wifi7/profile.conf $(1)/etc/be7000-wifi7/profile.conf
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./files/usr/libexec/be7000-wifi7-lab $(1)/usr/libexec/be7000-wifi7-lab
endef

$(eval $(call BuildPackage,be7000-wifi7-lab))
