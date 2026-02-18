.PHONY: build install run release clean

# Quick debug build
build:
	swift build

# Bundle release + install to Applications
install:
	./scripts/bundle.sh
	cp -r build/Erdos.app /Applications/
	@echo "\nInstalled to /Applications/Erdos.app"

# Debug build + run directly
run:
	swift run

# Build, zip, and publish a GitHub release
release:
ifndef VERSION
	$(error VERSION is required. Usage: make release VERSION=v0.0.2)
endif
	./scripts/bundle.sh
	cd build && zip -r /tmp/Erdos-$(VERSION).zip Erdos.app
	gh release create $(VERSION) /tmp/Erdos-$(VERSION).zip --title "Erdos $(VERSION)" --generate-notes

# Clean build artifacts
clean:
	swift package clean
	rm -rf build/
