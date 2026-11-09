"""Carry original native events through the deployed trace encoder's existing result.

The estate append port consumes this field in its existing identity SQL invocation.
No extra capability, network request, or model is added to trace persistence.
"""
import argparse
import json
from pathlib import Path


def project(root):
    path = root / 'providers/host-provider-authority.json'
    authority = json.loads(path.read_bytes())
    profile = next(p for p in authority['declaredProviders'] if p['providerProfileId'] == 'sfx-api-run-trace-encode.v2')
    program = next(o for o in profile['operations'] if o['operationId'] == 'encode-chunk')['program']
    if not any(s.get('invocation') == 'value.Add' and s.get('arguments', [{}])[0].get('value') == 'nativeEvents' for s in program):
        program.append({'invocation': 'value.Add', 'arguments': [
            {'op': 'literal', 'value': 'nativeEvents'},
            {'op': 'path', 'from': 'scope', 'path': 'events'}]})
    path.write_bytes((json.dumps(authority, ensure_ascii=False, indent=2) + '\n').encode())
    return {'providerProfileId': profile['providerProfileId'], 'field': 'nativeEvents'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    print(json.dumps(project(parser.parse_args().root)))
