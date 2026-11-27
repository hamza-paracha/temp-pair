APP := build/Temp Pair.app
SWIFTC := xcrun --sdk macosx swiftc -swift-version 5 -target $(shell uname -m)-apple-macos12
SOURCES := $(wildcard Sources/*.swift)

.PHONY: app test sample
app: build/Temp\ Pair.app/Contents/_CodeSignature/CodeResources

build/Temp\ Pair.app/Contents/_CodeSignature/CodeResources: $(SOURCES) Info.plist LICENSE Makefile
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	$(SWIFTC) -O -whole-module-optimization $(SOURCES) -o "$(APP)/Contents/MacOS/TempPair"
	cp Info.plist "$(APP)/Contents/"
	cp LICENSE "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"
	codesign --verify --strict "$(APP)"

test:
	mkdir -p build
	$(SWIFTC) $(filter-out Sources/main.swift,$(SOURCES)) Tests/TemperatureOnlyCheck.swift -o build/temperature-check
	build/temperature-check

sample: app
	"$(APP)/Contents/MacOS/TempPair" --sample
