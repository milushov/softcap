#!/usr/bin/env python3
"""Test the macOS browser controller with real loopback sockets and fake accounts.

Stages the App authentication sources into a temporary SwiftPM package, keeping AppKit out
of Core. Nothing opens a browser or reads the user's credential store.
Additional arguments are forwarded to swift test, for example --jobs 2.
"""
import pathlib
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="softcap-auth-tests-") as directory:
    stage = pathlib.Path(directory)
    # A relative dependency avoids embedding any machine's home path in a fixture.
    (stage / "Core").symlink_to(root / "Packages/Core", target_is_directory=True)
    source = stage / "Tests/BrowserTests"
    source.mkdir(parents=True)
    # `ProviderNaming.swift` travels with the controller: its default
    # key-authentication closure names a service by its product name, which is
    # the app layer's mapping and not one Core carries.
    for name in ("LoginController.swift", "BrowserCallbackListener.swift",
                 "BrowserSignInPage.swift", "ProviderNaming.swift"):
        shutil.copy2(root / "App" / name, source / name)
    for test in (root / "Tests/AuthenticationTests").glob("*.swift"):
        shutil.copy2(test, source / test.name)
    products = ("ProviderKit", "ClaudeProvider", "CodexProvider", "CopilotProvider",
                "ZaiProvider", "KimiProvider", "Credentials", "Diagnostics", "StatusUI")
    dependencies = ",\n".join(f'.product(name: "{name}", package: "Core")' for name in products)
    (stage / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "BrowserTests", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "Core")],
    targets: [.testTarget(name: "BrowserTests", dependencies: [
''' + dependencies + "\n])])\n")
    result = subprocess.run(["swift", "test", "--package-path", str(stage), *sys.argv[1:]])
    raise SystemExit(result.returncode)
