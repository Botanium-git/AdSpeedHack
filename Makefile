ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = AddSpeedHack

AddSpeedHack_FILES = Runtime.m
AddSpeedHack_CFLAGS = -fobjc-arc
AddSpeedHack_FRAMEWORKS = Foundation AVFoundation WebKit

include $(THEOS_MAKE_PATH)/library.mk
