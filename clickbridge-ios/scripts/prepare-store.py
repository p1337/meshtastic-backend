#!/usr/bin/env python3
"""Create a two-app OTA store while retaining the last verified Werkbeleg build."""
import argparse
import hashlib
import html
import json
from pathlib import Path
import plistlib
import re
import shutil
import urllib.parse
import urllib.request
import zipfile


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ClickBridge-store-builder/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def install_link(manifest_url: str) -> str:
    return "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-directory", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    base = args.base_url.rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme != "https" or not parsed.netloc or parsed.query or parsed.fragment or parsed.username:
        parser.error("base-url must be a public HTTPS URL without credentials, query or fragment")
    if not re.fullmatch(r"[0-9]+-[0-9]+", args.build_id):
        parser.error("build-id must be run ID and attempt")

    ipa = args.build_directory / "ClickBridge-Apple-signed.ipa"
    verification = json.loads((args.build_directory / "signature-verification.json").read_text())
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    if not (verification.get("apple_distribution_signature_verified") is True
            and verification.get("provisioning_profile_matches") is True
            and verification.get("bundle_id") == "de.p1337.ClickBridge"
            and digest == verification.get("ipa_sha256")):
        raise ValueError("Only a verified ClickBridge IPA may be published")
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read("Payload/ClickBridge.app/Info.plist"))
        if info["CFBundleIdentifier"] != "de.p1337.ClickBridge":
            raise ValueError("Unexpected ClickBridge bundle identifier")
        if "Payload/ClickBridge.app/embedded.mobileprovision" not in archive.namelist():
            raise ValueError("Missing ClickBridge provisioning profile")

    # Preserve the latest already-published, hash-verified Werkbeleg package.
    werk_info = json.loads(download(base + "/latest.json"))
    werk_id = str(werk_info["build_id"])
    if not re.fullmatch(r"[0-9]+-[0-9]+", werk_id):
        raise ValueError("Published Werkbeleg build ID is invalid")
    werk_manifest_url = base + "/builds/" + werk_id + "/manifest.plist"
    if werk_info.get("manifest_url") != werk_manifest_url:
        raise ValueError("Published Werkbeleg manifest URL is outside the store")
    werk_manifest_data = download(werk_manifest_url)
    werk_manifest = plistlib.loads(werk_manifest_data)
    werk_package_url = werk_manifest["items"][0]["assets"][0]["url"]
    expected_package = base + "/builds/" + werk_id + "/LoRaLab-Apple-signed.ipa"
    if werk_package_url != expected_package:
        raise ValueError("Published Werkbeleg package URL is outside the store")
    werk_ipa = download(werk_package_url)
    if hashlib.sha256(werk_ipa).hexdigest() != werk_info["ipa_sha256"]:
        raise ValueError("Published Werkbeleg IPA hash mismatch")

    output = args.output
    werk_destination = output / "builds" / werk_id
    werk_destination.mkdir(parents=True, exist_ok=True)
    (werk_destination / "manifest.plist").write_bytes(werk_manifest_data)
    (werk_destination / "LoRaLab-Apple-signed.ipa").write_bytes(werk_ipa)
    (output / "latest.json").write_text(json.dumps(werk_info, indent=2) + "\n")

    relative = "clickbridge/builds/" + args.build_id
    click_destination = output / relative
    click_destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ipa, click_destination / ipa.name)
    click_package_url = base + "/" + relative + "/" + ipa.name
    click_manifest_url = base + "/" + relative + "/manifest.plist"
    click_manifest = {"items": [{"assets": [{"kind": "software-package", "url": click_package_url}],
                                  "metadata": {"bundle-identifier": info["CFBundleIdentifier"],
                                               "bundle-version": str(info["CFBundleVersion"]),
                                               "kind": "software", "title": "ClickBridge"}}]}
    (click_destination / "manifest.plist").write_bytes(plistlib.dumps(click_manifest))
    click_latest = {"build_id": args.build_id, "version": info["CFBundleShortVersionString"],
                    "bundle_version": info["CFBundleVersion"], "manifest_url": click_manifest_url,
                    "ipa_sha256": digest, "profile_expires_utc": verification["profile_expires_utc"],
                    "hardware_tested": False, "incyclist_integration_verified": False}
    click_root = output / "clickbridge"; click_root.mkdir(exist_ok=True)
    (click_root / "latest.json").write_text(json.dumps(click_latest, indent=2) + "\n")

    style = """body{margin:0;background:#0b111b;color:#edf2fa;font:17px/1.55 system-ui,sans-serif}main{max-width:760px;margin:auto;padding:48px 22px}h1{font-size:38px;line-height:1.12}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:18px}.card{border:1px solid #344154;border-radius:18px;padding:22px;background:#111b29}.tag{color:#ff9a16;font-weight:700}.button{display:block;background:#ff9a16;color:#10151d;padding:14px;border-radius:12px;text-align:center;text-decoration:none;font-weight:750;margin:20px 0 8px}.secondary{background:#26364b;color:#edf2fa}small{color:#b8c6d9}.warn{border-left:4px solid #ff9a16;padding-left:12px}a{color:#a9d2ff}"""
    werk_install = install_link(werk_manifest_url)
    click_install = install_link(click_manifest_url)
    root = f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Eigener App Store</title><style>{style}</style></head><body><main><p class="tag">PRIVATER IPHONE-STORE</p><h1>Apps für dein registriertes iPhone</h1><div class="grid"><section class="card"><h2>Werkbeleg</h2><p>Version {html.escape(str(werk_info['version']))} · Build {html.escape(str(werk_info['bundle_version']))}</p><a class="button" href="{html.escape(werk_install, quote=True)}">Werkbeleg installieren</a><a href="./werkbeleg/">Details</a></section><section class="card"><h2>ClickBridge</h2><p>Version {html.escape(str(info['CFBundleShortVersionString']))} · Build {html.escape(str(info['CFBundleVersion']))}</p><a class="button" href="{html.escape(click_install, quote=True)}">ClickBridge installieren</a><a href="./clickbridge/">Details und Teststatus</a></section></div><p><small>Safari verwenden. Beide Apps besitzen getrennte Bundle-IDs und überschreiben einander nicht.</small></p></main></body></html>'''
    output.mkdir(parents=True, exist_ok=True)
    (output / "index.html").write_text(root)
    (output / ".nojekyll").touch()

    werk_page = f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Werkbeleg installieren</title><style>{style}</style></head><body><main><p class="tag">APPLE-SIGNIERTE TEST-APP</p><h1>Werkbeleg</h1><p>Version {html.escape(str(werk_info['version']))} · Build {html.escape(str(werk_info['bundle_version']))}</p><a class="button" href="{html.escape(werk_install, quote=True)}">Auf diesem iPhone installieren</a><a href="../">Zurück zum Store</a></main></body></html>'''
    werk_root = output / "werkbeleg"; werk_root.mkdir(exist_ok=True)
    (werk_root / "index.html").write_text(werk_page)

    click_page = f'''<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>ClickBridge installieren</title><style>{style}</style></head><body><main><p class="tag">APPLE-SIGNIERTER HARDWAREPROTOTYP</p><h1>ClickBridge</h1><p>Version {html.escape(str(info['CFBundleShortVersionString']))} · Build {html.escape(str(info['CFBundleVersion']))}</p><a class="button" href="{html.escape(click_install, quote=True)}">Auf diesem iPhone installieren</a><p class="warn">BLE-Erkennung und Diagnose sind implementiert. Reale Click-V2-/D100-Tests und die Steuerung einer unveränderten Incyclist-App sind noch nicht bestätigt.</p><p><a href="{html.escape(click_package_url, quote=True)}">Signierte IPA herunterladen</a></p><a href="../">Zurück zum Store</a><p><small>Profil gültig bis {html.escape(verification['profile_expires_utc'][:10])}. Das iPhone muss im Profil registriert sein.</small></p></main></body></html>'''
    (click_root / "index.html").write_text(click_page)
    print("Prepared verified two-app OTA store.")


if __name__ == "__main__":
    main()
