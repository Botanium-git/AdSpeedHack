ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AdSpeedHack

AdSpeedHack_FILES = Runtime.m
AdSpeedHack_CFLAGS = -fobjc-arc
AdSpeedHack_FRAMEWORKS = Foundation AVFoundation WebKit

include $(THEOS_MAKE_PATH)/library.mk
