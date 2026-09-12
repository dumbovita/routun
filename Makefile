SWIFTC = swiftc
MACOS_DEPLOYMENT_TARGET = 14.0
ARCH ?= $(shell uname -m)
SWIFT_FLAGS = -O -target $(ARCH)-apple-macos$(MACOS_DEPLOYMENT_TARGET)
SOURCES := $(wildcard Sources/*.swift)
TARGET = routun

.PHONY: all build test install uninstall clean status doctor logs restart

all: build

build: $(TARGET)

$(TARGET): $(SOURCES)
	$(SWIFTC) $(SWIFT_FLAGS) $(SOURCES) -o $(TARGET)

test:
	swift test

install:
	@./install.sh

uninstall:
	@if command -v routun >/dev/null 2>&1; then sudo routun uninstall; else sudo ./uninstall.sh; fi

clean:
	rm -f $(TARGET)

status:
	@if command -v routun >/dev/null 2>&1; then routun status; elif [ -x ./$(TARGET) ]; then ./$(TARGET) status; else echo "Please install or run 'make build' first"; fi

doctor:
	@if command -v routun >/dev/null 2>&1; then routun doctor; elif [ -x ./$(TARGET) ]; then ./$(TARGET) doctor; else echo "Please install or run 'make build' first"; fi

logs:
	@if command -v routun >/dev/null 2>&1; then routun logs -f; elif [ -x ./$(TARGET) ]; then ./$(TARGET) logs -f; else echo "Please install or run 'make build' first"; fi

restart:
	@if command -v routun >/dev/null 2>&1; then sudo routun restart; elif [ -x ./$(TARGET) ]; then sudo ./$(TARGET) restart; else echo "Please install or run 'make build' first"; fi
