include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-netscope
PKG_VERSION:=0.5.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=lststrdst

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-netscope
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=4. Themes
  TITLE:=NETSCOPE theme for Xiaomi BE7000
  DEPENDS:=+luci-base
  PKGARCH:=all
endef

define Package/luci-theme-netscope/description
  NETSCOPE dark LuCI shell with Russian navigation, embedded Traffic view,
  firmware attribution and native password form controls. QWRT and LuCI
  attribution is retained in the UI and source tree.
endef

define Build/Compile
endef

define Package/luci-theme-netscope/install
	$(INSTALL_DIR) $(1)
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,luci-theme-netscope))
