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
<p class="note">Kunden, Projekte, Foto- und Sprachberichte mit PDF-Export. Pakete für 5/10/20 Personen, Projektchat und WhatsApp-Einladungen als Teamserver-Pilot. Teamserver und automatisches Wetter sind noch nicht eingerichtet. Diese Testversion ersetzt LoRa Lab auf deinem iPhone.</p>
<p><a href="{html.escape(package_url, quote=True)}">Signierte IPA herunterladen</a></p>
<small>Profil gültig bis {expiry}. Die Installation und der Start müssen auf deinem Gerät geprüft werden.</small>
</main></body></html>'''
    (args.output / 'index.html').write_text(page, encoding='utf-8')
    # Invitation secrets stay in the URL fragment; Pages does not receive them.
    join_page = r"""<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><meta name="robots" content="noindex"><title>Werkbeleg · Einladung</title><style>body{font:17px/1.6 system-ui;background:#fff;color:#111;margin:0}main{max-width:560px;margin:auto;padding:44px 24px}h1{font-size:36px}a{color:#111}.button{display:block;padding:16px;margin:24px 0;border-radius:14px;background:#ff9800;text-align:center;text-decoration:none;font-weight:700}.tag{background:#ffde00;padding:6px 10px;border-radius:8px}small{color:#666}</style></head><body><main><span class="tag">WERKBELEG</span><h1>Einladung zum Team</h1><p id="server">Einladung wird geprüft …</p><a id="open" class="button" hidden>In Werkbeleg öffnen</a><p>App noch nicht installiert? <a href="./">Testversion installieren</a> und anschließend diesen Einladungslink erneut öffnen.</p><small>Der Link gilt einmalig für 48 Stunden. Akzeptiere nur Einladungen von einem Team, das du kennst. Join your team · Dołącz do zespołu.</small></main><script>
const p=new URLSearchParams(location.hash.slice(1));const address=p.get('server'),code=p.get('code');
try{const u=new URL(address);if(u.protocol!=='https:'||u.username||u.password||u.search||u.hash||!code||code.length>512)throw Error();document.getElementById('server').textContent='Teamserver: '+u.host;const target=new URL('werkbeleg://join');target.searchParams.set('server',u.href);target.searchParams.set('code',code);const a=document.getElementById('open');a.href=target.href;a.hidden=false;}catch(e){document.getElementById('server').textContent='Dieser Einladungslink ist unvollständig oder ungültig.';}
</script></body></html>"""
    (args.output / 'join.html').write_text(join_page, encoding='utf-8')
    (args.output / '.nojekyll').touch()
    public_info = {'build_id': args.build_id, 'version': info['CFBundleShortVersionString'],
                   'bundle_version': info['CFBundleVersion'], 'manifest_url': manifest_url,
                   'ipa_sha256': verification['ipa_sha256'], 'profile_expires_utc': verification['profile_expires_utc']}
    (args.output / 'latest.json').write_text(json.dumps(public_info, indent=2) + '\n')
    print('Prepared OTA page and versioned manifest for the verified signed IPA.')


if __name__ == '__main__':
    main()
