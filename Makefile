DERIVED := .build/xcode
APP := $(DERIVED)/Build/Products/Debug/MinorREST.app

.PHONY: gen build run test clean

gen:
	xcodegen generate --quiet

build: gen
	xcodebuild -project MinorREST.xcodeproj -scheme MinorREST -configuration Debug \
		-derivedDataPath $(DERIVED) -quiet build

run: build
	open $(APP)

test:
	cd Packages/MinorRESTCore && swift test

clean:
	rm -rf .build MinorREST.xcodeproj App/Info.plist Packages/MinorRESTCore/.build
