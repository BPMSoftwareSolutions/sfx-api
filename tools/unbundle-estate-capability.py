"""Remove a stale packaged capability so the existing resolver reads the estate.

Run against a checkout or an image's /opt/sfx tree. Deletes only the named
capability document, preserving every other document and updating manifest pins.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path


def unbundle(root, capability):
    bundle = root / 'authorities/host-bundle'
    manifest_path = bundle / 'manifest.json'
    authority_path = root / 'providers/host-provider-authority.json'
    manifest = json.loads(manifest_path.read_bytes())
    selected = [c for c in manifest['capabilities'] if c['capabilityId'] == capability]
    for item in selected:
        document = (bundle / item['document']).resolve()
        if not document.is_relative_to((bundle / 'capabilities').resolve()):
            raise ValueError('Document is outside the capability bundle')
        data = document.read_bytes()
        digests = {base64.b64encode(hashlib.sha256(b).digest()).decode() for b in (data, data.replace(b'\r\n', b'\n'))}
        if item['sha256Base64'] not in digests:
            raise ValueError('Packaged document differs from its manifest')
        document.unlink()
    manifest['capabilities'] = [c for c in manifest['capabilities'] if c['capabilityId'] != capability]
    encoded = (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode()
    manifest_path.write_bytes(encoded)
    pin = base64.b64encode(hashlib.sha256(encoded).digest()).decode()
    authority = json.loads(authority_path.read_bytes())

    def repin(value):
        if isinstance(value, dict):
            if value.get('op') == 'literal' and isinstance(value.get('value'), str) and value['value'].startswith('sha256-base64:'):
                value['value'] = 'sha256-base64:' + pin
            if value.get('op') == 'object' and value.get('fields', {}).get('path', {}).get('value') == '../../authorities/host-bundle/manifest.json':
                value['fields']['sha256Base64'] = {'op': 'literal', 'value': pin}
            for child in value.values():
                repin(child)
        elif isinstance(value, list):
            for child in value:
                repin(child)

    repin(authority)
    authority_path.write_bytes((json.dumps(authority, ensure_ascii=False, indent=2) + '\n').encode())
    return {'capabilityId': capability, 'removed': len(selected), 'remaining': len(manifest['capabilities']), 'manifestSha256Base64': pin}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('capability')
    args = parser.parse_args()
    print(json.dumps(unbundle(args.root, args.capability)))
