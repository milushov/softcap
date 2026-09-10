#!/usr/bin/env python3
"""Test the macOS browser controller with real loopback sockets and fake accounts.

Stages the two App sources into a temporary SwiftPM package, keeping AppKit out
of Core. Nothing opens a browser or reads the user's credential store.
"""
import pathlib
import shutil
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix="softcap-auth-tests-") as directory:
    stage = pathlib.Path(directory)
    # A relative dependency avoids embedding any machine's home path in a fixture.
    (stage / "Core").symlink_to(root / "Packages/Core", target_is_directory=True)
    source = stage / "Tests/BrowserTests"
    source.mkdir(parents=True)
    for name in ("LoginController.swift", "BrowserCallbackListener.swift"):
        shutil.copy2(root / "App" / name, source / name)
    shutil.copy2(root / "Tests/AuthenticationTests/LoginControllerTests.swift", source)
    products = ("ProviderKit", "ClaudeProvider", "CodexProvider", "Credentials", "Diagnostics", "StatusUI")
    dependencies = ",\n".join(f'.product(name: "{name}", package: "Core")' for name in products)
    (stage / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "BrowserTests", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "Core")],
    targets: [.testTarget(name: "BrowserTests", dependencies: [
''' + dependencies + "\n])])\n")
    result = subprocess.run(["swift", "test", "--package-path", str(stage)])
    raise SystemExit(result.returncode)
