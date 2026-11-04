# Zanzo AI — Flutter launch shortcuts
#
# Prerequisites:
#   config/test.json  — copy config/test.example.json and fill in your keys
#                       (see config/README.md)
#   LLDB disabled globally (flutter config --no-enable-lldb-debugging)
#   Xcode closed or a fresh session — avoids the CONFIGURATION_BUILD_DIR timeout
#
# Usage:
#   make run              debug build, any connected device
#   make run-release      release build, any connected device (USB-free after install)
#   make iphone           debug build, iPhone 16 Pro Max (fixed device ID)
#   make iphone-release   release build, iPhone 16 Pro Max (USB-free after install)
#
# Override the config file:
#   CONFIG=config/prod.json make run-release
#
# Override the device:
#   DEVICE=R3CWB0EJW6R make run   (Samsung Galaxy Z Flip5)

CONFIG  ?= config/test.json
DEVICE  ?=
IPHONE  := 00008140-001975440EFA801C

_DEVICE_FLAG  := $(if $(DEVICE),--device-id $(DEVICE),)
_IPHONE_FLAG  := --device-id $(IPHONE)

.PHONY: run run-release iphone iphone-release xcode-quit clean help

run:
	flutter run --dart-define-from-file=$(CONFIG) $(_DEVICE_FLAG)

run-release:
	flutter run --release --dart-define-from-file=$(CONFIG) $(_DEVICE_FLAG)

iphone: xcode-quit
	flutter run --dart-define-from-file=$(CONFIG) $(_IPHONE_FLAG)

iphone-release: xcode-quit
	flutter run --release --dart-define-from-file=$(CONFIG) $(_IPHONE_FLAG)

# Quit Xcode before flutter run to prevent the CONFIGURATION_BUILD_DIR timeout
# that occurs when a stale Xcode session is left open from a previous run.
xcode-quit:
	@osascript -e 'tell application "Xcode" to if it is running then quit it' 2>/dev/null; true

clean:
	flutter clean

help:
	@echo "Zanzo AI launch targets:"
	@echo "  make run             debug, any connected device"
	@echo "  make run-release     release, any connected device (USB-free after install)"
	@echo "  make iphone          debug, iPhone 16 Pro Max  (quits Xcode first)"
	@echo "  make iphone-release  release, iPhone 16 Pro Max (USB-free after install)"
	@echo "  make xcode-quit      quit Xcode to avoid CONFIGURATION_BUILD_DIR timeout"
	@echo "  make clean           flutter clean"
	@echo ""
	@echo "Override config:  CONFIG=config/prod.json make run-release"
	@echo "Override device:  DEVICE=<id> make run"
