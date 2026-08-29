ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = QQ

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QQFarm

QQFarm_FILES = Tweak.x \
               src/hooks/QQFarmWebSocket.x \
               src/utils/QQFarmUtils.m \
               src/ui/QQFarmOverlay.mm \
               src/ui/QQFarmFloatingBall.mm

QQFarm_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
