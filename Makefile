# Without `pipefail` a recipe that pipes xcodebuild reports the exit status of
# the pipe's last command — so a failed build looks like a successful `make`.
# `.SHELLFLAGS` would be the tidy place for it, but that arrived in Make 3.82
# and macOS ships 3.81, where it is silently ignored. Hence the prefix on each
# recipe that pipes.
SHELL := /bin/bash

.PHONY: test test-auth project build build-ios run run-ios lint archive-appstore screenshots upload-appstore

# A link failure after an API change in Core is almost always a stale incremental
# build, not a real error: object files still reference the previous mangled
# symbol. It has happened twice — once for an added enum case, once for a default
# argument — and both times cost a diagnosis before `swift package clean` fixed
# it in seconds. So: try once, and if the *linker* is what failed, clean and try
# again, saying so. A genuine error fails the second time too.
#
# `pipefail` is not decoration: without it the `if` reads `tee`'s exit status,
# which is always zero, and every run passes. That is the same mistake this
# Makefile already had in its build recipes — made again here, and caught by
# breaking a source file on purpose to see whether the retry masked it.
test:
	@set -o pipefail; cd Packages/Core && \
	  if swift test 2>&1 | tee /tmp/softcap-test.log; then \
	    exit 0; \
	  elif grep -q "link command failed\|Undefined symbols\|missing required module" /tmp/softcap-test.log; then \
	    echo "--- stale build; cleaning the package and retrying once ---"; \
	    swift package clean >/dev/null && swift test; \
	  else \
	    exit 1; \
	  fi

test-auth:
	python3 tools/test_authentication.py

project:
	xcodegen generate

# -allowProvisioningUpdates is a leftover: on macOS an app group needs no
# profile, manual signing with a real team certificate is enough. Harmless, and
# kept for the day the iOS targets are built for a device.
build: project
	@set -o pipefail; xcodebuild -project Softcap.xcodeproj -scheme Softcap \
		-configuration Debug -derivedDataPath build \
		-allowProvisioningUpdates build | grep -E "error:|warning:|BUILD"

run: build
	open build/Build/Products/Debug/Softcap.app

lint:
	swiftlint --quiet || true

# The build that store screenshots are taken from: fixture accounts, fixture
# history, settings held in memory. See App/ScreenshotFixtures.swift for what it
# refuses to touch and why.
#
# Its own derived data, not build/: that directory holds the app the author is
# running, and rebuilding into it replaces a bundle a live process launched from.
# DEBUG is defined alongside SCREENSHOTS so the error reporter stays compiled
# out — a run that exists to be photographed should not be able to file a report.
screenshots: project
	@set -o pipefail; xcodebuild -project Softcap.xcodeproj -scheme Softcap \
		-configuration Debug -derivedDataPath build-shots \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG SCREENSHOTS" \
		build | grep -E "error:|warning:|BUILD"
	@echo "built: build-shots/Build/Products/Debug/Softcap.app"

# The App Store lane: the same scheme with the sandboxed entitlements swapped
# in and the self-updater compiled out (see DECISIONS 2026-09-13). The archive
# signs with whatever Signing.local.xcconfig names; Organizer re-signs for
# distribution on upload. V and B are demanded rather than defaulted so every
# archive's number is chosen on purpose, never inherited from project.yml's
# base — the number race with the GitHub lane is decided at archive time.
#
# Unsigned, exactly as the workflow archives it. The signature is applied at
# export, by Apple's cloud signing, so this step needs no certificate — and
# building it the same way here as on a runner is the point: the two paths
# diverging is what cost three red releases before they were made one.
archive-appstore: project
	@if [ -z "$(V)" ] || [ -z "$(B)" ]; then \
		echo "usage: make archive-appstore V=0.1.4 B=1"; exit 1; fi
	@set -o pipefail; xcodebuild -project Softcap.xcodeproj -scheme Softcap \
		-configuration Release -derivedDataPath build \
		-archivePath build/Softcap.xcarchive \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
		SOFTCAP_APP_ENTITLEMENTS=App/Softcap.AppStore.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS=APPSTORE \
		MARKETING_VERSION=$(V) CURRENT_PROJECT_VERSION=$(B) \
		archive | grep -E "error:|ARCHIVE"
	@echo "next: make upload-appstore V=$(V) B=$(B)"

# Exports the archive and sends it to App Store Connect, without Xcode.
#
# Signing needs no preparation: `-allowProvisioningUpdates` with an App Store
# Connect key lets xcodebuild mint the distribution and installer certificates
# and both provisioning profiles on first use — this account had none.
#
# The key is named by environment rather than written here: ASC_KEY_ID and
# ASC_ISSUER_ID identify an Apple account, and this repository publishes
# everything in it. ASC_KEY_PATH points at the .p8 file, which never belongs in
# a checkout at all.
upload-appstore: archive-appstore
	@if [ -z "$(ASC_KEY_ID)" ] || [ -z "$(ASC_ISSUER_ID)" ] || [ -z "$(ASC_KEY_PATH)" ] \
	   || [ -z "$(ASC_TEAM_ID)" ]; then \
		echo "usage: ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_TEAM_ID=… \\"; \
		echo "       ASC_KEY_PATH=/path/AuthKey_….p8 make upload-appstore V=0.1.5 B=1"; \
		exit 1; fi
	@# The team is named here rather than in the checked-in plist: it is the
	@# Apple team identifier, and this repository publishes what it holds.
	@cp tools/ExportOptions.AppStore.plist build/ExportOptions.plist
	@/usr/libexec/PlistBuddy -c "Add :teamID string $(ASC_TEAM_ID)" build/ExportOptions.plist
	@set -o pipefail; xcodebuild -exportArchive \
		-archivePath build/Softcap.xcarchive \
		-exportPath build/appstore-export \
		-exportOptionsPlist build/ExportOptions.plist \
		-allowProvisioningUpdates \
		-authenticationKeyPath "$(ASC_KEY_PATH)" \
		-authenticationKeyID "$(ASC_KEY_ID)" \
		-authenticationKeyIssuerID "$(ASC_ISSUER_ID)" \
		| grep -E "error:|Exported|EXPORT"
	@# Silent, and deliberately: make would otherwise echo the recipe, and the
	@# issuer id names the Apple account. A build log is a thing people paste.
	@xcrun altool --upload-app -f build/appstore-export/Softcap.pkg -t macos \
		--apiKey "$(ASC_KEY_ID)" --apiIssuer "$(ASC_ISSUER_ID)"
	@echo "uploaded; the build appears under TestFlight once Apple finishes processing it"

# iOS build and simulator run. The scheme has code signing disabled, so it needs
# no certificate: the app runs in the simulator only.
build-ios: project
	@set -o pipefail; xcodebuild -project Softcap.xcodeproj -scheme SoftcapiOS \
		-destination 'generic/platform=iOS Simulator' \
		-derivedDataPath build-ios build | grep -E "error:|warning:|BUILD"

# The simulator is found with `sed`, not `grep`, and that is the whole point of
# this comment. `GREP_OPTIONS=--color=always` is set on this machine, so every
# grep emits ANSI codes whether or not anything is watching — and a UDID captured
# through one arrives wrapped in them. simctl then answered "Invalid device"
# three times over, naming a device that boots perfectly by hand, and the escape
# codes were invisible in the error because the terminal rendered them as the
# colour they are. `sed` has no opinion about colour.
run-ios: build-ios
	@SIM=$$(xcrun simctl list devices available \
		| sed -n 's/.*iPhone 1[6-7].*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1); \
	if [ -z "$$SIM" ]; then \
		SIM=$$(xcrun simctl list devices available \
			| sed -n 's/.*iPhone.*(\([0-9A-F-]\{36\}\)).*/\1/p' | head -1); \
	fi; \
	if [ -z "$$SIM" ]; then echo "run-ios: no iPhone simulator installed"; exit 1; fi; \
	case "$$SIM" in \
		[0-9A-F]*-*-*-*-*) ;; \
		*) echo "run-ios: that is not a device id: $$SIM" | cat -v; exit 1 ;; \
	esac; \
	xcrun simctl boot $$SIM 2>/dev/null || true; \
	xcrun simctl bootstatus $$SIM -b; \
	open -a Simulator; \
	xcrun simctl install $$SIM build-ios/Build/Products/Debug-iphonesimulator/SoftcapiOS.app; \
	xcrun simctl launch $$SIM app.softcap.Softcap.ios
