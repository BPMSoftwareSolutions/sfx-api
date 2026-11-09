"""Prove removal survives directory-based rebuilds and preserves other documents."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('unbundle', Path(__file__).with_name('unbundle-estate-capability.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class UnbundleTest(unittest.TestCase):
    def test_forward_removal_and_replay(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bundle = root / 'authorities/host-bundle'
            (bundle / 'capabilities').mkdir(parents=True)
            (root / 'providers').mkdir()
            entries = []
            for name in ('append-api-run-trace', 'unrelated'):
                content = json.dumps({'capabilityId': name}).encode()
                (bundle / 'capabilities' / (name + '.json')).write_bytes(content)
                entries.append({'capabilityId': name, 'document': 'capabilities/' + name + '.json',
                                'sha256Base64': base64.b64encode(hashlib.sha256(content).digest()).decode()})
            manifest = bundle / 'manifest.json'
            manifest.write_text(json.dumps({'capabilities': entries}))
            authority = root / 'providers/host-provider-authority.json'
            authority.write_text(json.dumps({'manifest': {'op': 'object', 'fields': {
                'path': {'op': 'literal', 'value': '../../authorities/host-bundle/manifest.json'},
                'sha256Base64': {'op': 'literal', 'value': 'old'}}},
                'ref': {'op': 'literal', 'value': 'sha256-base64:old'}}))
            unchanged = (bundle / 'capabilities/unrelated.json').read_bytes()
            first = module.unbundle(root, 'append-api-run-trace')
            self.assertEqual(first['removed'], 1)
            self.assertEqual([p.stem for p in (bundle / 'capabilities').glob('*.json')], ['unrelated'])
            self.assertEqual((bundle / 'capabilities/unrelated.json').read_bytes(), unchanged)
            pin = base64.b64encode(hashlib.sha256(manifest.read_bytes()).digest()).decode()
            self.assertEqual(json.loads(authority.read_bytes())['manifest']['fields']['sha256Base64']['value'], pin)
            before = (manifest.read_bytes(), authority.read_bytes())
            self.assertEqual(module.unbundle(root, 'append-api-run-trace')['removed'], 0)
            self.assertEqual((manifest.read_bytes(), authority.read_bytes()), before)


if __name__ == '__main__':
    unittest.main()
