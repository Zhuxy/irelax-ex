# iRelaxEx：一键编译打包安装，全程不用开 Xcode
#
#   make build      只编译（Release），产物在 build/DerivedData/.../iRelaxEx.app
#   make install    编译 + 安装到 /Applications + 启动
#   make uninstall  从 /Applications 删除并退出运行中的实例
#   make clean      清理 build/ 目录
#
# 签名沿用工程里已配置的 Development Team（你自己的 Apple ID 个人团队），
# 免费账号即可，无需付费开发者计划。

APP_NAME     := iRelaxEx
PROJECT      := iRelaxEx.xcodeproj
TARGET       := iRelaxEx
CONFIG       := Release
BUILD_DIR    := $(CURDIR)/build
DERIVED_DATA := $(BUILD_DIR)/DerivedData
APP_BUNDLE   := $(DERIVED_DATA)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_PATH := /Applications/$(APP_NAME).app

.PHONY: build install uninstall clean

build:
	xcodebuild \
		-project $(PROJECT) \
		-target $(TARGET) \
		-configuration $(CONFIG) \
		-derivedDataPath $(DERIVED_DATA) \
		build

install: build
	@echo "==> 关闭运行中的 $(APP_NAME)（如有）…"
	-@pkill -x $(APP_NAME) 2>/dev/null; true
	@sleep 1
	@echo "==> 安装到 $(INSTALL_PATH)…"
	@rm -rf "$(INSTALL_PATH)"
	@ditto "$(APP_BUNDLE)" "$(INSTALL_PATH)"
	@echo "==> 启动…"
	@open "$(INSTALL_PATH)"
	@echo ""
	@echo "完成。如需开机启动，请在 App 弹窗里打开“开机启动”开关（换位置安装后需重新打开一次）。"

uninstall:
	-@pkill -x $(APP_NAME) 2>/dev/null; true
	rm -rf "$(INSTALL_PATH)"
	@echo "已从 $(INSTALL_PATH) 卸载。"

clean:
	rm -rf "$(BUILD_DIR)"
	@echo "已清理 build/。"
