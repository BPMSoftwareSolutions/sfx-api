import base64
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("host_acceptance", ROOT / "providers/host-acceptance.py")
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)


class Client:
    def __init__(self, status=200, principal="probe"):
        self.status, self.principal, self.calls, self.bearer = status, principal, 0, None

    def json(self, *args):
        self.calls += 1
        return self.status, {"status": "READ", "principalId": self.principal}


class SessionBoundaryTests(unittest.TestCase):
    def test_invalid_format_is_distinct_without_network_or_disclosure(self):
        for secret in ("not-a-session", "Bearer " + "A" * 43 + "=", "A" * 43 + "=\n", "A" * 42 + "B=", '{"session":"private"}'):
            client = Client()
            with self.assertRaises(host.Failure) as raised:
                host.session_check(client, {"principalId": "probe"}, secret)
            self.assertEqual(raised.exception.code, "ACCEPTANCE_SESSION_FORMAT_INVALID")
            self.assertNotIn(secret, raised.exception.message)
            self.assertEqual(client.calls, 0)
            self.assertIsNone(client.bearer)

    def test_all_canonical_last_bytes_agree_with_ingress(self):
        declaration = (ROOT / "providers/sfx-api-ingress.dependency.json").read_text()
        self.assertIn(host.SESSION_BEARER.pattern, declaration)
        for last in range(256):
            secret = base64.b64encode(bytes(31) + bytes([last])).decode()
            client = Client()
            self.assertEqual(host.session_check(client, {"principalId": "probe"}, secret)["disposition"], "CONFIRMED")
            self.assertEqual(client.calls, 1)

    def test_valid_format_can_still_be_rejected_by_session_authority(self):
        secret = base64.b64encode(bytes(32)).decode()
        client = Client(status=401)
        with self.assertRaises(host.Failure) as raised:
            host.session_check(client, {"principalId": "probe"}, secret)
        self.assertEqual(raised.exception.code, "ACCEPTANCE_SESSION_REJECTED")
        self.assertEqual(client.calls, 1)
        self.assertIsNone(client.bearer)

    def test_wrong_principal_cannot_be_used_for_probes(self):
        client = Client(principal="another")
        with self.assertRaises(host.Failure) as raised:
            host.session_check(client, {"principalId": "probe"}, base64.b64encode(bytes(32)).decode())
        self.assertEqual(raised.exception.code, "ACCEPTANCE_PRINCIPAL_MISMATCH")
        self.assertIsNone(client.bearer)


if __name__ == "__main__":
    unittest.main()
