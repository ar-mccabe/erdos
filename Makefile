.PHONY: build install run clean

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

# Clean build artifacts
clean:
	swift package clean
	rm -rf build/
