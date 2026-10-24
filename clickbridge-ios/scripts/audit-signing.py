#!/usr/bin/env python3
"""Read-only profile compatibility audit. Never exports credentials or device IDs."""
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

expected = "de.p1337.ClickBridge"
record = {"bundleID": expected, "certificateAndPasswordPresent": bool(os.environ.get("IOS_DISTRIBUTION_P12_BASE64") and os.environ.get("IOS_P12_PASSWORD")),
          "matchingProfile": False, "signedIPAProduced": False}
profile_data = os.environ.get("CLICKBRIDGE_ADHOC_PROFILE_BASE64") or os.environ.get("IOS_ADHOC_PROFILE_BASE64")
if not profile_data:
    record["status"] = "profile-not-available"
else:
    try:
        with tempfile.TemporaryDirectory(prefix="clickbridge-profile-audit-") as temporary:
            profile = Path(temporary) / "profile.mobileprovision"
            profile.write_bytes(base64.b64decode(profile_data, validate=True)); profile.chmod(0o600)
            result = subprocess.run(["security", "cms", "-D", "-i", str(profile)], capture_output=True, check=False)
            if result.returncode: raise ValueError("decode-failed")
            data = plistlib.loads(result.stdout)
            entitlement = data.get("Entitlements", {}).get("application-identifier", "")
            prefixes = data.get("ApplicationIdentifierPrefix", [])
            matches = any(entitlement == prefix + "." + expected or
                          (entitlement.endswith(".*") and (prefix + "." + expected).startswith(entitlement[:-1]))
                          for prefix in prefixes)
            expiry = data.get("ExpirationDate", datetime.datetime.min)
            valid = expiry > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
            adhoc = bool(data.get("ProvisionedDevices")) and not data.get("ProvisionsAllDevices", False)
            record.update(matchingProfile=matches, profileUnexpired=valid, adHocProfile=adhoc)
            record["status"] = "profile-compatible-signing-not-run" if matches and valid and adhoc else "requires-separate-clickbridge-profile"
    except Exception:
        record["status"] = "profile-audit-failed-no-credential-output"
out = Path("build/signing-audit.json"); out.parent.mkdir(exist_ok=True)
out.write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps(record, indent=2))
