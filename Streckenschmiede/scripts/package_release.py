#!/usr/bin/env python3
"""Verify a signed iOS IPA and prepare Streckenschmiede's OTA GitHub Pages release.

No unsigned/development-only IPA can produce release.json with ready=true.
Run on a macOS GitHub Actions runner; no third-party Python dependencies.
"""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlsplit

EXPECTED_BUNDLE_ID = "de.p1337.Streckenschmiede"


def fail(message: str) -> None:
    raise ValueError(message)


def verify_ipa(ipa: Path) -> tuple[str, str]:
    if sys.platform != "darwin":
        fail("Apple codesign verification requires macOS")
    with zipfile.ZipFile(ipa) as archive:
        entries = archive.namelist()
        for item in entries:
            if item.startswith("/") or ".." in Path(item).parts or "\\" in item:
                fail(f"Unsafe IPA path: {item}")
        apps = [
            m.group(1) for item in entries
            if (m := re.fullmatch(r"Payload/([^/]+\.app)/Info\.plist", item))
        ]
        if len(apps) != 1:
            fail("IPA must contain exactly one Payload/*.app/Info.plist")
        app = f"Payload/{apps[0]}"
        info = plistlib.loads(archive.read(f"{app}/Info.plist"))
        bundle_id = info.get("CFBundleIdentifier")
        version = str(info.get("CFBundleShortVersionString", ""))
        build = str(info.get("CFBundleVersion", ""))
        if bundle_id != EXPECTED_BUNDLE_ID:
            fail(f"Wrong bundle ID: {bundle_id!r} (expected {EXPECTED_BUNDLE_ID})")
        if not version or not build:
            fail("IPA is missing its app version or build number")
        if f"{app}/_CodeSignature/CodeResources" not in entries:
            fail("IPA is missing its code signature")
        if f"{app}/embedded.mobileprovision" not in entries:
            fail("IPA is missing its provisioning profile")

        with tempfile.TemporaryDirectory(prefix="streckenschmiede-verify-") as tmp:
            archive.extractall(tmp)
            app_path = Path(tmp) / app
            subprocess.run(
                ["/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app_path)],
                check=True,
            )
            profile_file = app_path / "embedded.mobileprovision"
            output = subprocess.run(
                ["/usr/bin/security", "cms", "-D", "-i", str(profile_file)],
                capture_output=True, check=True,
            )
            profile = plistlib.loads(output.stdout)
            entitlement = profile.get("Entitlements", {})
            profile_bundle = str(entitlement.get("application-identifier", ""))
            if not profile_bundle.endswith("." + EXPECTED_BUNDLE_ID):
                fail("Provisioning profile does not match Streckenschmiede's bundle ID")
            if not (profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")):
                fail("Provisioning profile is not for ad-hoc or in-house OTA distribution")
            expiry = profile.get("ExpirationDate")
            if not isinstance(expiry, datetime):
                fail("Provisioning profile does not contain an expiry date")
            if expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
                fail("Provisioning profile has expired")
    return version, build


def build_release(ipa: Path, store_html: Path, output: Path, base_url: str) -> None:
    url = urlsplit(base_url)
    if url.scheme != "https" or not url.netloc or url.query or url.fragment:
        fail("Public base URL must be a clean HTTPS directory URL")
    if not base_url.endswith("/"):
        fail("Public base URL must end with /")
    version, build = verify_ipa(ipa)
    output.mkdir(parents=True, exist_ok=True)
    ipa_name = "Streckenschmiede.ipa"
    shutil.copyfile(ipa, output / ipa_name)
    shutil.copyfile(store_html, output / "index.html")
    ipa_url = urljoin(base_url, ipa_name)
    manifest = {
        "items": [{
            "assets": [{"kind": "software-package", "url": ipa_url}],
            "metadata": {
                "bundle-identifier": EXPECTED_BUNDLE_ID,
                "bundle-version": build,
                "kind": "software",
                "title": "Streckenschmiede",
            },
        }],
    }
    with (output / "manifest.plist").open("wb") as dest:
        plistlib.dump(manifest, dest)
    sha256 = hashlib.sha256((output / ipa_name).read_bytes()).hexdigest()
    release = {
        "ready": True,
        "version": version,
        "build": build,
        "bundleId": EXPECTED_BUNDLE_ID,
        "manifest": "manifest.plist",
        "sha256": sha256,
        "publishedAt": datetime.now(timezone.utc).isoformat(),
    }
    (output / "release.json").write_text(
        json.dumps(release, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Postconditions: all URLs point to actual files and refer to our own app.
    for name in ("index.html", "manifest.plist", "release.json", ipa_name):
        if not (output / name).is_file():
            fail(f"Release is incomplete: {name}")
    print(f"Verified signed OTA release: {EXPECTED_BUNDLE_ID} {version} ({build})")
    print(f"IPA SHA-256: {sha256}")
    print(f"Manifest: {urljoin(base_url, 'manifest.plist')}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--store-html", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--base-url", required=True)
    args = parser.parse_args()
    try:
        build_release(args.ipa, args.store_html, args.out, args.base_url)
    except (ValueError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as exc:
        parser.exit(1, f"Release verification failed: {exc}\n")
