#!/usr/bin/env python3
"""Package the already verified Apple-signed IPA for HTTPS OTA distribution."""
import argparse
import hashlib
import html
import json
import pathlib
import plistlib
import re
import shutil
import urllib.parse
import zipfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-directory', type=pathlib.Path, required=True)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--build-id', required=True)
    parser.add_argument('--output', type=pathlib.Path, required=True)
    args = parser.parse_args()
    base = args.base_url.rstrip('/')
    url = urllib.parse.urlsplit(base)
    if url.scheme != 'https' or not url.netloc or url.query or url.fragment or url.username:
        parser.error('base-url must be a public HTTPS URL without credentials, query or fragment')
    if not re.fullmatch(r'[0-9]+-[0-9]+', args.build_id):
        parser.error('build-id must be run ID followed by attempt, e.g. 12345-1')
    ipa = args.build_directory / 'LoRaLab-Apple-signed.ipa'
    verification = json.loads((args.build_directory / 'signature-verification.json').read_text())
    if not (verification.get('apple_distribution_signature_verified') is True
            and verification.get('provisioning_profile_matches') is True
            and hashlib.sha256(ipa.read_bytes()).hexdigest() == verification['ipa_sha256']):
        raise ValueError('Only the verified signed IPA may be published')
    with zipfile.ZipFile(ipa) as archive:
        info = plistlib.loads(archive.read('Payload/LoRaLab.app/Info.plist'))
        if info['CFBundleIdentifier'] != 'de.p1337.LoRaLab':
            raise ValueError('Unexpected bundle identifier')
        if 'Payload/LoRaLab.app/embedded.mobileprovision' not in archive.namelist():
            raise ValueError('Missing embedded profile')
    relative = 'builds/' + args.build_id
    destination = args.output / relative
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ipa, destination / ipa.name)
    package_url = base + '/' + relative + '/' + ipa.name
    manifest_url = base + '/' + relative + '/manifest.plist'
    manifest = {'items': [{'assets': [{'kind': 'software-package', 'url': package_url}],
                           'metadata': {'bundle-identifier': info['CFBundleIdentifier'],
                                        'bundle-version': str(info['CFBundleVersion']),
                                        'kind': 'software', 'title': 'Werkbeleg'}}]}
    (destination / 'manifest.plist').write_bytes(plistlib.dumps(manifest))
    install_url = 'itms-services://?action=download-manifest&url=' + urllib.parse.quote(manifest_url, safe='')
    expiry = html.escape(verification['profile_expires_utc'][:10])
    version = html.escape(str(info['CFBundleShortVersionString']))
    build = html.escape(str(info['CFBundleVersion']))
    page = f'''<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Werkbeleg installieren</title>
<style>body{{margin:0;background:#0c1421;color:#edf2fa;font:17px/1.6 system-ui,sans-serif}}
main{{max-width:620px;margin:auto;padding:56px 24px}}h1{{font-size:36px;line-height:1.15}}
.tag{{color:#ff9a16}}.button{{display:block;background:#ff9a16;color:#0c1421;padding:16px;border-radius:12px;text-align:center;text-decoration:none;font-weight:700;margin:28px 0 12px}}
a{{color:#9dcaff}}small{{color:#b8c6d9}}.note{{padding:16px;border:1px solid #35445b;border-radius:12px}}</style></head>
<body><main><p class="tag">APPLE-SIGNIERTE TEST-APP</p><h1>Werkbeleg auf dein iPhone.</h1>
<p>Version {version} · Build {build}</p>
<a class="button" href="{html.escape(install_url, quote=True)}">Auf diesem iPhone installieren</a>
<p>Öffne diese Seite in Safari und bestätige die Installation. Dein iPhone muss im Signierprofil registriert sein.</p>
<p class="note">Kunden, Aufträge, Foto- und Sprachberichte mit PDF-Export. Teamserver und automatisches Wetter sind noch nicht eingerichtet. Diese Testversion ersetzt LoRa Lab auf deinem iPhone.</p>
<p><a href="{html.escape(package_url, quote=True)}">Signierte IPA herunterladen</a></p>
<small>Profil gültig bis {expiry}. Die Installation und der Start müssen auf deinem Gerät geprüft werden.</small>
</main></body></html>'''
    (args.output / 'index.html').write_text(page, encoding='utf-8')
    (args.output / '.nojekyll').touch()
    public_info = {'build_id': args.build_id, 'version': info['CFBundleShortVersionString'],
                   'bundle_version': info['CFBundleVersion'], 'manifest_url': manifest_url,
                   'ipa_sha256': verification['ipa_sha256'], 'profile_expires_utc': verification['profile_expires_utc']}
    (args.output / 'latest.json').write_text(json.dumps(public_info, indent=2) + '\n')
    print('Prepared OTA page and versioned manifest for the verified signed IPA.')


if __name__ == '__main__':
    main()
