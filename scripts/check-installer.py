"""Inspect an Installer product without installing or executing its payload."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def check(package: Path, bundle: Path) -> None:
    project = Path(__file__).resolve().parent.parent
    source_info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    identifier = source_info["CFBundleIdentifier"]
    with tempfile.TemporaryDirectory(prefix="installer-check-", dir=project / ".build") as temporary:
        expanded = Path(temporary) / "expanded"
        subprocess.run(["pkgutil", "--expand-full", str(package), str(expanded)], check=True)
        distribution = ET.parse(expanded / "Distribution").getroot()
        assert distribution.find("options").get("hostArchitectures") == "arm64"
        domains = distribution.find("domains")
        assert domains.get("enable_localSystem") == "true"
        assert domains.get("enable_currentUserHome") == "false"
        assert domains.get("enable_anywhere") == "false"
        assert distribution.find("volume-check/allowed-os-versions/os-version").get("min") == "13.0"
        assert any(app.get("id") == identifier for app in distribution.findall("pkg-ref/must-close/app"))
        assert not distribution.findall("script"), "No custom installation scripts"

        components = list(expanded.glob("*.pkg"))
        assert len(components) == 1
        component = components[0]
        info = ET.parse(component / "PackageInfo").getroot()
        assert info.get("identifier") == "dev.filesweep.mac.pkg"
        assert info.get("version") == source_info["CFBundleShortVersionString"]
        assert info.get("install-location") == "/"
        assert info.get("relocatable") == "false"
        assert not (component / "Scripts").exists(), "No privileged scripts or preference migrations"
        for policy in ["bundle-version", "upgrade-bundle", "strict-identifier"]:
            assert [b.get("id") for b in info.findall(policy + "/bundle")] == [identifier], policy
        assert not info.findall("update-bundle/bundle"), "The package must support fresh installs too"
        assert not info.findall("relocate/bundle"), "Do not discover or replace arbitrary app copies"
        delivered = info.find("bundle")
        assert delivered.get("id") == identifier
        assert Path(delivered.get("path").lstrip("/")) == Path("Applications/FileSweep.app"), delivered.attrib
        assert delivered.get("CFBundleVersion") == source_info["CFBundleVersion"]

        payload = component / "Payload"
        app = payload / "Applications/FileSweep.app"
        assert app.is_dir()
        for path in payload.rglob("*"):
            relative = path.relative_to(payload)
            assert relative == Path("Applications") or relative.is_relative_to("Applications/FileSweep.app"), relative
        expected = {p.relative_to(bundle) for p in bundle.rglob("*") if p.is_file()}
        actual = {p.relative_to(app) for p in app.rglob("*") if p.is_file()}
        assert actual == expected
        for relative in expected:
            assert (app / relative).read_bytes() == (bundle / relative).read_bytes(), relative
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        print("PASS: Installer platform, running-app guard, fixed destination, isolated payload and app signature")


if __name__ == "__main__":
    check(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
