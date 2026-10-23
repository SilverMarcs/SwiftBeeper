#!/usr/bin/env python3
"""Build the app's Matrix core for an Apple target."""
import fcntl
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

tools = Path(__file__).resolve().parent
matrix = tools.parent
platform = sys.argv[1] if len(sys.argv) > 1 else "macos"
component = sys.argv[2] if len(sys.argv) > 2 else "core"
if component not in ("core", "notifications"):
    raise SystemExit("Expected core or notifications")
targets = {
    "macos": ("macosx", "arm64-apple-macos26.2", "darwin"),
    "ios": ("iphoneos", "arm64-apple-ios26.2", "ios"),
    "simulator": ("iphonesimulator", "arm64-apple-ios26.2-simulator", "ios"),
}
if platform not in targets:
    raise SystemExit("Expected macos, ios or simulator")
sdk, target, go_os = targets[platform]
build = matrix / "Build"
build.mkdir(exist_ok=True)

def output(arguments):
    return subprocess.check_output(arguments, text=True).strip()

with (build / "core.lock").open("w") as lock:
    # Xcode may build multiple destinations together. Keep SDK preparation and
    # matrix compilation serialized so every compiler sees a complete source.
    fcntl.flock(lock, fcntl.LOCK_EX)
    patch = tools / "gomuks.patch"
    signature = hashlib.sha256(b"gomuks-v0.2601.0-apple-client-only-v2\n" + patch.read_bytes()).hexdigest()
    vendor = matrix / "SDKSource/gomuks"
    stamp = build / "sdk-source.sha256"
    if not vendor.exists() or not stamp.exists() or stamp.read_text() != signature:
        cache = Path(output(["go", "env", "GOMODCACHE"]))
        source = cache / "go.mau.fi/gomuks@v0.2601.0"
        if not source.exists():
            subprocess.run(["go", "mod", "download", "go.mau.fi/gomuks@v0.2601.0"], cwd=matrix, check=True)
        vendor.parent.mkdir(exist_ok=True)
        temporary = Path(tempfile.mkdtemp(prefix="sdk-", dir=build))
        try:
            prepared = temporary / "gomuks"
            prepared.mkdir()
            for name in ("go.mod", "go.sum", "LICENSE"):
                shutil.copyfile(source / name, prepared / name)
            for package in ("hicli", "rainbow"):
                shutil.copytree(source / "pkg" / package, prepared / "pkg" / package,
                    ignore=shutil.ignore_patterns("*_test.go", "testdata", "*_wasm.go", "print", "hitest"))
            for path in prepared.rglob("*"):
                path.chmod(0o755 if path.is_dir() else 0o644)
            prepared.chmod(0o755)
            subprocess.run(["/usr/bin/patch", "-s", "-p1", "-i", str(patch)], cwd=prepared, check=True)
            if vendor.exists():
                shutil.rmtree(vendor)
            prepared.rename(vendor)
            stamp.write_text(signature)
        finally:
            shutil.rmtree(temporary)
    destination = build / platform
    library = "RelayCore" if component == "core" else "RelayNotifications"
    package = "ffi" if component == "core" else "notifications"
    headers = destination / ("Headers" if component == "core" else "NotificationHeaders")
    archive = destination / ("lib" + library + ".a")
    # Xcode runs this phase on every build. Skip the Go link, and Xcode's relink
    # of the app, when nothing changed since the last one: no source file or
    # directory (catching deletions and renames), and the same toolchain and SDK.
    sdk_path = output(["xcrun", "--sdk", sdk, "--show-sdk-path"])
    stamp_file = destination / (library + ".stamp")
    stamp_text = "\n".join([output(["go", "version"]), sdk_path, target])
    inputs = [path for root in ("cmd", "internal", "SDKSource") for path in (matrix / root).rglob("*")
              if path.is_dir() or path.suffix == ".go"]
    inputs += [matrix / "go.mod", matrix / "go.sum", patch, Path(__file__)]
    if archive.exists() and (headers / ("lib" + library + ".h")).exists() and \
            stamp_file.exists() and stamp_file.read_text() == stamp_text and \
            archive.stat().st_mtime >= max(path.stat().st_mtime for path in inputs):
        print("Relay " + component + " for " + platform + " is up to date")
        sys.exit(0)
    flags = "-target " + target + " -isysroot " + sdk_path
    environment = os.environ.copy()
    environment.update({"CGO_ENABLED": "1", "GOOS": go_os, "GOARCH": "arm64",
        "CC": output(["xcrun", "--sdk", sdk, "--find", "clang"]) + " " + flags,
        "CXX": output(["xcrun", "--sdk", sdk, "--find", "clang++"]) + " " + flags,
        "CGO_CFLAGS": flags, "CGO_CXXFLAGS": flags, "CGO_LDFLAGS": flags})
    headers.mkdir(parents=True, exist_ok=True)
    subprocess.run(["go", "build", "-tags", "goolm", "-trimpath", "-buildmode=c-archive", "-o", str(archive), "./cmd/" + package], cwd=matrix, env=environment, check=True)
    shutil.copyfile(destination / ("lib" + library + ".h"), headers / ("lib" + library + ".h"))
    stamp_file.write_text(stamp_text)
    (headers / "module.modulemap").write_text('module ' + library + ' {\n    header "lib' + library + '.h"\n    export *\n}\n')
print("Built Relay " + component + " for " + platform)
