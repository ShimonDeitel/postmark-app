XCODEGEN ?= $(shell command -v xcodegen 2>/dev/null || echo /opt/homebrew/bin/xcodegen)

.PHONY: gen build

gen:
	@if [ ! -f Secrets.xcconfig ]; then \
		cp Secrets.xcconfig.example Secrets.xcconfig; \
		echo "Created Secrets.xcconfig from Secrets.xcconfig.example"; \
	fi
	$(XCODEGEN) generate

build: gen
	xcodebuild -project Postmark.xcodeproj -scheme Postmark -destination 'generic/platform=iOS Simulator' build
