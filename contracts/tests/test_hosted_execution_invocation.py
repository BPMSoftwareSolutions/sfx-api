"""Contract authoring checks only; these synthetic exchanges never attest a deployment."""
import copy
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator

from test_hosted_execution_contract import ROOT, IDS, SYNTHETIC_DIGEST, execution_error, fixture, read


spec = importlib.util.spec_from_file_location("hosted_receipt_validator", ROOT / "contracts/validate-hosted-execution-receipt.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def proof_fixture(receipt):
    raw = (json.dumps(receipt, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    attempt = receipt["invocation"]["attemptId"]
    return {
        "contractId": "hosted-execution-delivery-proof.v1", "status": "FULFILLED",
        "attemptId": attempt, "observedAt": "2026-11-04T18:00:12Z",
        "client": {"product": "sfx-api", "version": "synthetic-fixture-only", "artifactDigest": SYNTHETIC_DIGEST,
                   "surface": "capability observe", "capabilityId": "accept-hosted-execution-profile",
                   "input": {}, "authentication": "existing-operator-session"},
        "exchange": {"method": "POST", "url": "https://sfx-api-test.azurewebsites.net/sfx/v1/hosted-execution/acceptance",
                     "httpStatus": 200, "redirected": False, "dispatch": "declared-request-route",
                     "coordinatorWorkerSlots": 0, "attemptId": attempt},
        "receiptArtifact": {"reference": "https://sfx-api-test.azurewebsites.net/sfx/v1/hosted-execution/acceptance/" + attempt,
                            "sha256": "sha256:" + hashlib.sha256(raw).hexdigest(),
                            "byteLength": len(raw), "readbackVerified": True},
        "receipt": receipt,
    }, raw


class HostedInvocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = read("sfx-api-hosted-csharp.v1.profile.json")
        cls.profile_validator = Draft202012Validator(read("hosted-execution-profile.v1.schema.json"))
        cls.good = fixture(cls.profile)

    def test_new_schemas_are_valid_and_referenced_by_the_profile(self):
        for name in ("hosted-execution-acceptance-request.v1", "hosted-execution-acceptance-context.v1",
                     "hosted-execution-invocation-error.v1", "hosted-execution-delivery-proof.v1",
                     "hosted-execution-acceptance-read-request.v1", "hosted-execution-acceptance-read-result.v1"):
            Draft202012Validator.check_schema(read(name + ".schema.json"))
            self.assertIn(name, json.dumps(self.profile["acceptance"]["invocation"]))
        validator.validate_receipt(self.good)
        proof, raw = proof_fixture(self.good)
        validator.validate_delivery_proof(proof, raw)

    def test_request_refuses_identity_secret_destination_and_dispatch_injection(self):
        request = Draft202012Validator(read("hosted-execution-acceptance-request.v1.schema.json"))
        self.assertTrue(request.is_valid({}))
        for payload in ({"principalId": self.good["invocation"]["probePrincipalId"]}, {"token": "synthetic"},
                        {"password": "synthetic"}, {"endpoint": "https://example.invalid"},
                        {"executionPath": "worker"}, {"attemptId": IDS[0]}, [], None):
            with self.subTest(payload=payload):
                self.assertFalse(request.is_valid(payload))

    def test_every_invocation_obligation_is_required_and_typed(self):
        expected = self.profile["acceptance"]["invocation"]
        def check_members(value, path=()):
            for key, item in value.items():
                missing = copy.deepcopy(self.profile)
                target = missing["acceptance"]["invocation"]
                for member in path:
                    target = target[member]
                del target[key]
                self.assertFalse(self.profile_validator.is_valid(missing), path + (key,))
                if isinstance(item, dict):
                    check_members(item, path + (key,))
        check_members(expected)
        for path, value in (("owner", "consumer"), ("dispatch.executionPath", "worker"),
                            ("dispatch.automaticRetry", True), ("dispatch.maximumConcurrentCoordinators", 2),
                            ("credentials.passwordPrompt", True), ("credentials.accountSwitch", True),
                            ("credentials.revokeSession", True), ("credentials.fallbackPrincipal", True),
                            ("completion.consumerClientImplementationRequired", True)):
            broken = copy.deepcopy(self.profile)
            target = broken["acceptance"]["invocation"]
            parts = path.split(".")
            for part in parts[:-1]:
                target = target[part]
            target[parts[-1]] = value
            self.assertFalse(self.profile_validator.is_valid(broken), path)

    def test_receipt_cannot_omit_or_substitute_invocation_identity(self):
        for field in self.good["invocation"]:
            broken = copy.deepcopy(self.good)
            del broken["invocation"][field]
            with self.assertRaises(ValueError):
                validator.validate_receipt(broken)
        for defect in ("requestExecutionId", "initiator", "probePrincipalId", "worker"):
            broken = copy.deepcopy(self.good)
            if defect == "requestExecutionId":
                broken["invocation"][defect] = IDS[10]
            elif defect == "initiator":
                broken["invocation"][defect]["principalId"] = IDS[0]
            elif defect == "probePrincipalId":
                broken["invocation"][defect] = IDS[0]
            else:
                broken["invocation"]["executionPath"] = "worker"
            with self.assertRaises(ValueError):
                validator.validate_receipt(broken)

    def test_delivery_requires_return_readback_and_one_correlated_attempt(self):
        proof, raw = proof_fixture(self.good)
        for defect in ("no_receipt", "no_client", "no_artifact", "no_readback", "attempt", "exchange_attempt", "redirect", "worker", "reference", "fake_hash"):
            broken = copy.deepcopy(proof)
            if defect.startswith("no_") and defect != "no_readback":
                del broken[{"no_receipt": "receipt", "no_client": "client", "no_artifact": "receiptArtifact"}[defect]]
            elif defect == "no_readback":
                broken["receiptArtifact"]["readbackVerified"] = False
            elif defect == "attempt":
                broken["attemptId"] = IDS[0]
            elif defect == "exchange_attempt":
                broken["exchange"]["attemptId"] = IDS[0]
            elif defect == "redirect":
                broken["exchange"]["redirected"] = True
            elif defect == "worker":
                broken["exchange"]["coordinatorWorkerSlots"] = 1
            elif defect == "reference":
                broken["receiptArtifact"]["reference"] = "https://example.invalid/unrelated"
            else:
                broken["receiptArtifact"]["sha256"] = SYNTHETIC_DIGEST
            with self.subTest(defect=defect), self.assertRaises(ValueError):
                validator.validate_delivery_proof(broken, raw)
        with self.assertRaises(ValueError):
            validator.validate_delivery_proof(proof, raw + b" ")

    def test_successful_transport_of_rejected_receipt_is_not_fulfillment(self):
        rejected = copy.deepcopy(self.good)
        rejected["status"] = "REJECTED"
        rejected["checks"]["T1"] = execution_error("precondition")
        proof, raw = proof_fixture(rejected)
        with self.assertRaises(ValueError):
            validator.validate_delivery_proof(proof, raw)
        proof["status"] = "UNFULFILLED"
        validator.validate_delivery_proof(proof, raw)

    def test_error_codes_are_typed_and_uncertainty_cannot_claim_success(self):
        errors = Draft202012Validator(read("hosted-execution-invocation-error.v1.schema.json"))
        for stage, code in (("discovery", "CLIENT_DISPATCH_UNSUPPORTED"), ("caller", "CALLER_REQUIRED"),
                            ("credential", "ACCEPTANCE_SESSION_REJECTED"), ("dispatch", "ACCEPTANCE_BUSY"),
                            ("execution", "ACCEPTANCE_CLIENT_FAILED"), ("verification", "ACCEPTANCE_RECEIPT_INVALID")):
            value = {"contractId": "hosted-execution-invocation-error.v1", "attemptId": IDS[10],
                     "outcome": "FAILED", "stage": stage, "code": code, "httpStatus": 0,
                     "requestExecutionId": None, "message": "Synthetic failure only", "automaticRetry": False, "receipt": None}
            self.assertTrue(errors.is_valid(value), code)
            for field, replacement in (("automaticRetry", True), ("receipt", self.good), ("outcome", "ACCEPTED")):
                broken = dict(value, **{field: replacement})
                self.assertFalse(errors.is_valid(broken))
        unknown = dict(value, outcome="UNKNOWN", stage="collection", code="ACCEPTANCE_TRANSPORT_UNCERTAIN")
        self.assertTrue(errors.is_valid(unknown))
        self.assertFalse(errors.is_valid(dict(unknown, outcome="FAILED")))
        self.assertFalse(errors.is_valid(dict(unknown, stage="caller")))
        self.assertFalse(errors.is_valid(dict(value, stage="caller", code="PROFILE_DISCOVERY_FAILED")))

    def test_verifier_reconciles_run_references_and_interval_arithmetic(self):
        for defect in ("t4", "t7_ids", "t7_overlap"):
            broken = copy.deepcopy(self.good)
            if defect == "t4":
                broken["checks"]["T4"]["runIds"] = [IDS[0]]
            elif defect == "t7_ids":
                broken["checks"]["T7"]["observed"]["runs"][0]["runId"] = IDS[0]
            else:
                broken["checks"]["T7"]["observed"]["runs"][2]["startedAt"] = "2026-11-04T18:00:02Z"
            with self.subTest(defect=defect), self.assertRaises(ValueError):
                validator.validate_receipt(broken)

    def test_internal_context_and_read_request_are_closed_payloads(self):
        context_schema = Draft202012Validator(read("hosted-execution-acceptance-context.v1.schema.json"))
        value = {"attemptId": IDS[10], "expectedProfileDigest": self.good["profileDigest"],
                 "requestExecutionId": IDS[0], "executionPath": "request",
                 "caller": {"kind": "user", "principalId": self.good["invocation"]["initiator"]["principalId"]},
                 "request": {"method": "POST", "path": self.good["invocation"]["path"], "body": {}}}
        self.assertTrue(context_schema.is_valid(value))
        for field in value:
            broken = copy.deepcopy(value)
            del broken[field]
            self.assertFalse(context_schema.is_valid(broken), field)
        broken = copy.deepcopy(value)
        broken["request"]["body"] = {"caller": value["caller"]}
        self.assertFalse(context_schema.is_valid(broken))
        read_request = Draft202012Validator(read("hosted-execution-acceptance-read-request.v1.schema.json"))
        self.assertTrue(read_request.is_valid({"attemptId": IDS[10]}))
        for bad in ({}, {"attemptId": "../../vault"}, {"attemptId": IDS[10], "principalId": IDS[0]}):
            self.assertFalse(read_request.is_valid(bad))

    def test_retained_readback_bytes_and_identity_are_verified(self):
        proof, raw = proof_fixture(self.good)
        record = {"contractId": "hosted-execution-acceptance-read-result.v1", "attemptId": proof["attemptId"],
                  "status": "RECEIPT_AVAILABLE", "requestExecutionId": self.good["evaluator"]["executionId"],
                  "profileDigest": self.good["profileDigest"], "receiptSha256": proof["receiptArtifact"]["sha256"],
                  "receiptByteLength": len(raw), "receiptBytesBase64": base64.b64encode(raw).decode(), "receipt": self.good}
        self.assertEqual(validator.validate_readback(record), raw)
        for field, value in (("attemptId", IDS[0]), ("requestExecutionId", IDS[10]),
                             ("receiptSha256", SYNTHETIC_DIGEST), ("receiptByteLength", 1),
                             ("receiptBytesBase64", base64.b64encode(b"{}").decode())):
            broken = copy.deepcopy(record)
            broken[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                validator.validate_readback(broken)
        absent = {"contractId": record["contractId"], "attemptId": IDS[10], "status": "NOT_FOUND"}
        self.assertIsNone(validator.validate_readback(absent))
        with self.assertRaises(ValueError):
            validator.validate_readback(dict(absent, receipt=self.good))

    def test_checked_in_payload_examples_match_their_contracts(self):
        examples = ROOT / "contracts/examples/hosted-execution-v5"
        schemas = {"request.json": "hosted-execution-acceptance-request.v1.schema.json",
                   "trusted-context.json": "hosted-execution-acceptance-context.v1.schema.json",
                   "read-request.json": "hosted-execution-acceptance-read-request.v1.schema.json"}
        for name, schema in schemas.items():
            validator.validate_schema(json.loads((examples / name).read_bytes()), schema)
        raw = (examples / "receipt-accepted.json").read_bytes()
        for name in ("receipt-accepted.json", "receipt-rejected.json"):
            validator.validate_receipt(json.loads((examples / name).read_bytes()))
        validator.validate_delivery_proof(json.loads((examples / "delivery-proof-fulfilled.json").read_bytes()), raw)
        for path in examples.glob("read-result-*.json"):
            validator.validate_readback(json.loads(path.read_bytes()))
        for path in examples.glob("error-*.json"):
            validator.validate_schema(json.loads(path.read_bytes()), "hosted-execution-invocation-error.v1.schema.json")
        bad_schemas = {"invalid-request-identity.json": "hosted-execution-acceptance-request.v1.schema.json",
                       "invalid-context-missing-attempt.json": "hosted-execution-acceptance-context.v1.schema.json"}
        for name, schema in bad_schemas.items():
            with self.assertRaises(ValueError):
                validator.validate_schema(json.loads((examples / name).read_bytes()), schema)
        for path in examples.glob("invalid-proof-*.json"):
            with self.assertRaises(ValueError):
                validator.validate_delivery_proof(json.loads(path.read_bytes()), raw)
        with self.assertRaises(ValueError):
            validator.validate_readback(json.loads((examples / "invalid-read-result-size.json").read_bytes()))


if __name__ == "__main__":
    unittest.main()
