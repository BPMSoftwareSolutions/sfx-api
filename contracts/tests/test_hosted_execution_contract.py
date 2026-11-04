"""Local authoring checks. Synthetic fixtures are never deployment receipts.

Run with: python -B -m unittest discover -s contracts/tests -v
Install contracts/tests/requirements.txt first. No network or host mutation during tests.
"""
import copy
import hashlib
import json
from pathlib import Path
import unittest

from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"
CHECKS = tuple(f"T{i}" for i in range(1, 8))
IDS = [f"11111111-1111-4111-8111-{i:012d}" for i in range(1, 12)]
SYNTHETIC_DIGEST = "sha256:" + "a" * 64


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("DUPLICATE_KEY:" + key)
        result[key] = value
    return result


def parse(text):
    # The deployed parser must implement this rule before schema validation.
    return json.loads(text, object_pairs_hook=unique_object)


def read(name):
    return parse((CONTRACTS / name).read_bytes())


def digest(data):
    return "sha256:" + hashlib.sha256(data).hexdigest()


def fixture(profile):
    payload = ("aé€😀abcdef" * 393216).encode("utf-8")
    observations = {
        "T1": {
            "runtimeLanguage": "csharp", "user": "sjones", "uid": 1000,
            "environmentKeys": [],
            "python": {
                "path": "/usr/local/bin/python3", "implementation": "cpython",
                "version": "3.12.16", "soabi": "cpython-312-x86_64-linux-gnu",
                "machine": "x86_64", "glibcVersion": "2.36",
                "loadableTags": profile["childProcesses"]["executables"][0]["wheelTags"],
            },
            "temporaryStorage": {
                "path": "/tmp", "created": True, "written": True,
                "readBack": True, "deleted": True, "freeBytes": 67108864,
            },
        },
        "T2": {
            "timeoutSeconds": 2, "killAfterSeconds": 2, "ignoredTermination": True,
            "exitCode": 137, "elapsedMs": 4100, "childPid": 123, "childRemaining": False,
        },
        "T3": {
            "errorCode": "PROVIDER_LANGUAGE_UNAVAILABLE",
            "providerProfileId": "sfx-api-acceptance-python-only",
            "declaredLanguage": "python", "runtimeLanguage": "csharp",
        },
        "T4": {
            "transport": "https", "method": "GET",
            "url": profile["host"]["endpoint"] + f"/sfx/v1/runs/{IDS[4]}/output",
            "statusCode": 200, "redirected": False, "payloadPointer": "/output/payload",
            "expectedBytes": len(payload), "receivedBytes": len(payload),
            "expectedSha256": digest(payload), "receivedSha256": digest(payload),
        },
        "T5": {
            "timeoutSeconds": 2, "exitCode": 124, "elapsedMs": 2100,
            "childPid": 124, "childRemaining": False,
            "versionLine": "timeout (GNU coreutils) 9.1",
        },
        "T6": {
            "configurationDigest": SYNTHETIC_DIGEST, "settingsDigest": SYNTHETIC_DIGEST,
            "request": {key: profile["executionPaths"]["request"][key] for key in
                        ("kernels", "waitForKernelMs", "deliveryBoundMs", "answerBoundMs")},
            "worker": profile["executionPaths"]["worker"],
        },
        "T7": {
            "coordinatorExecutionPath": "request", "coordinatorWorkerSlots": 0,
            "admitted": 3, "maxConcurrent": 2, "thirdStartedAfterAnEnd": True,
            "runs": [
                {"runId": IDS[7], "startedAt": "2026-11-04T18:00:00Z", "endedAt": "2026-11-04T18:00:05Z"},
                {"runId": IDS[8], "startedAt": "2026-11-04T18:00:01Z", "endedAt": "2026-11-04T18:00:06Z"},
                {"runId": IDS[9], "startedAt": "2026-11-04T18:00:05Z", "endedAt": "2026-11-04T18:00:10Z"},
            ],
        },
    }
    return {
        "contractId": "hosted-execution-acceptance.v1", "profileId": profile["profileId"],
        "profileVersion": profile["profileVersion"],
        "profileDigest": digest((CONTRACTS / "sfx-api-hosted-csharp.v1.profile.json").read_bytes()),
        "deployment": {
            "host": "sfx-api-test", "imageDigest": SYNTHETIC_DIGEST,
            "bundleDigest": "sha256-base64:" + "A" * 43 + "=",
            "kernelArtifactDigest": SYNTHETIC_DIGEST, "hostFilesDigest": SYNTHETIC_DIGEST,
        },
        "executedAt": "2026-11-04T18:00:11Z",
        "evaluator": {"capabilityId": "accept-hosted-execution-profile",
                      "executionPath": "request", "executionId": IDS[0]},
        "invocation": {
            "attemptId": IDS[10], "requestExecutionId": IDS[0], "method": "POST",
            "path": profile["acceptance"]["coordinator"]["path"], "executionPath": "request",
            "initiator": profile["acceptance"]["coordinator"]["admittedCallers"][0],
            "probePrincipalId": profile["acceptance"]["coordinator"]["probeAuthority"]["principalId"],
            "authoritySource": "authenticated-caller-and-pinned-host-bindings",
            "expectedProfileDigest": digest((CONTRACTS / "sfx-api-hosted-csharp.v1.profile.json").read_bytes()),
        },
        "checks": {name: {"kind": "OBSERVED", "status": "PASSED",
                           "runIds": IDS[7:10] if name == "T7" else [IDS[index + 1]],
                           "observed": value}
                   for index, (name, value) in enumerate(observations.items())},
        "status": "ACCEPTED",
    }


def execution_error(stage="execution"):
    return {
        "kind": "EXECUTION_ERROR", "status": "FAILED", "attemptId": IDS[10],
        "runIds": [] if stage in ("admission", "precondition") else [IDS[1]],
        "error": {"stage": stage, "code": "EXECUTABLE_NOT_FOUND",
                  "message": "Synthetic failure before observations were obtained"},
    }


class HostedExecutionContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.profile = read("sfx-api-hosted-csharp.v1.profile.json")
        cls.profile_schema = read("hosted-execution-profile.v1.schema.json")
        cls.receipt_schema = read("hosted-execution-acceptance.v1.schema.json")
        if "date-time" not in FormatChecker().checkers:
            raise RuntimeError("Install contracts/tests/requirements.txt to enable date-time assertions")
        cls.validator = Draft202012Validator(cls.receipt_schema, format_checker=FormatChecker())
        cls.good = fixture(cls.profile)

    def assert_valid(self, value):
        errors = list(self.validator.iter_errors(value))
        self.assertFalse(errors, [(list(e.path), e.message) for e in errors])

    def test_schemas_profile_and_synthetic_receipt(self):
        for schema in (self.profile_schema, self.receipt_schema):
            Draft202012Validator.check_schema(schema)
        Draft202012Validator(self.profile_schema).validate(self.profile)
        self.assert_valid(self.good)

    def test_profile_pin_and_canonical_feature_agree(self):
        pin = self.good["profileDigest"]
        self.assertEqual(pin, self.receipt_schema["properties"]["profileDigest"]["const"])
        feature = (ROOT / "features/hosted-execution-profile.feature").read_text(encoding="utf-8")
        self.assertIn(pin, feature)
        self.assertIn(self.profile["acceptance"]["coordinator"]["path"], feature)
        self.assertEqual(set(CHECKS), {c["checkId"] for c in self.profile["acceptance"]["checks"]})
        self.assertEqual(set(CHECKS), set(self.receipt_schema["properties"]["checks"]["required"]))
        # The pinned profile must survive a checkout on Windows or Linux byte for byte.
        self.assertNotIn(b"\r", (CONTRACTS / "sfx-api-hosted-csharp.v1.profile.json").read_bytes())

    def test_duplicate_keys_fail_before_validation(self):
        for text in ('{"T1":{},"T1":{}}', '{"checks":{"T1":{},"T1":{}}}',
                     '{"checks":{"T\\u0031":{},"T1":{}}}'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                parse(text)

    def test_original_receipt_rejections(self):
        for name in CHECKS:
            for defect in ("missing", "empty", "extra", "failed"):
                with self.subTest(check=name, defect=defect):
                    value = copy.deepcopy(self.good)
                    if defect == "missing":
                        del value["checks"][name]
                    elif defect == "empty":
                        value["checks"][name]["observed"] = {}
                    elif defect == "extra":
                        value["checks"][name]["observed"]["extra"] = True
                    else:
                        value["checks"][name].update(status="FAILED", finding="Synthetic failure")
                    self.assertFalse(self.validator.is_valid(value))
        for defect in ("unknown", "only_one", "all_pass_rejected", "old_pin"):
            with self.subTest(defect=defect):
                value = copy.deepcopy(self.good)
                if defect == "unknown":
                    value["checks"]["T999"] = copy.deepcopy(value["checks"]["T1"])
                elif defect == "only_one":
                    value["checks"] = {"T1": value["checks"]["T1"]}
                elif defect == "all_pass_rejected":
                    value["status"] = "REJECTED"
                else:
                    value["profileDigest"] = "sha256:b387ad0c7321c6a1e4bbf063b54009ed3e917f8609de884f811d0eca01390efd"
                self.assertFalse(self.validator.is_valid(value))

    def test_wrong_observations_cannot_pass(self):
        mutations = [
            ("T1.python.version", "3.11.9"), ("T1.python.glibcVersion", "2.16"),
            ("T1.python.loadableTags", []), ("T1.environmentKeys", ["HOME"]),
            ("T1.temporaryStorage.freeBytes", 67108863),
            ("T2.exitCode", 0), ("T2.elapsedMs", 3999), ("T2.elapsedMs", 5001),
            ("T2.childRemaining", True), ("T3.errorCode", "OTHER"),
            ("T4.receivedSha256", SYNTHETIC_DIGEST), ("T4.receivedBytes", 6291455),
            ("T4.transport", "in-process"), ("T4.method", "POST"),
            ("T4.url", f"https://localhost/sfx/v1/runs/{IDS[4]}/output"),
            ("T4.redirected", True), ("T4.payloadPointer", "/output"), ("T4.statusCode", 502),
            ("T5.exitCode", 137), ("T5.elapsedMs", 3001), ("T5.versionLine", "other timeout"),
            ("T6.request.answerBoundMs", 1), ("T6.worker.concurrentRuns", 3),
            ("T7.maxConcurrent", 1), ("T7.maxConcurrent", 3),
            ("T7.thirdStartedAfterAnEnd", False), ("T7.coordinatorWorkerSlots", 1),
            ("T7.coordinatorExecutionPath", "worker"), ("T7.runs", []),
        ]
        for path, replacement in mutations:
            with self.subTest(path=path, replacement=replacement):
                value = copy.deepcopy(self.good)
                name, *parts = path.split(".")
                target = value["checks"][name]["observed"]
                for part in parts[:-1]:
                    target = target[part]
                target[parts[-1]] = replacement
                self.assertFalse(self.validator.is_valid(value))

    def test_measured_failure_is_a_valid_rejection(self):
        value = copy.deepcopy(self.good)
        value["status"] = "REJECTED"
        value["checks"]["T2"].update(status="FAILED", finding="Observed exit 0")
        value["checks"]["T2"]["observed"]["exitCode"] = 0
        self.assert_valid(value)

    def test_raw_probe_requires_the_receipt_projection(self):
        value = copy.deepcopy(self.good)
        del value["checks"]["T1"]["kind"]
        self.assertFalse(self.validator.is_valid(value))
        value = copy.deepcopy(self.good)
        value["checks"]["T1"]["observed"].update(probe="runtime", status="MEASURED")
        self.assertFalse(self.validator.is_valid(value))
        self.assert_valid(self.good)

    def test_early_errors_are_honest_rejections_for_every_check(self):
        for name in CHECKS:
            for stage in ("precondition", "admission", "execution", "collection", "verification"):
                with self.subTest(check=name, stage=stage):
                    value = copy.deepcopy(self.good)
                    value["status"] = "REJECTED"
                    value["checks"][name] = execution_error(stage)
                    self.assert_valid(value)
                    value["status"] = "ACCEPTED"
                    self.assertFalse(self.validator.is_valid(value))

    def test_error_variant_cannot_claim_observations_or_pass(self):
        for defect in ("passed", "observed", "no_error", "extra_error", "no_run", "no_attempt"):
            with self.subTest(defect=defect):
                value = copy.deepcopy(self.good)
                value["status"] = "REJECTED"
                error = execution_error()
                if defect == "passed":
                    error["status"] = "PASSED"
                elif defect == "observed":
                    error["observed"] = {}
                elif defect == "no_error":
                    del error["error"]
                elif defect == "extra_error":
                    error["error"]["extra"] = True
                elif defect == "no_run":
                    error["runIds"] = []
                else:
                    del error["attemptId"]
                value["checks"]["T1"] = error
                self.assertFalse(self.validator.is_valid(value))

    def test_all_checks_can_fail_without_fabricated_observations(self):
        value = copy.deepcopy(self.good)
        value["status"] = "REJECTED"
        value["checks"] = {name: execution_error("precondition") for name in CHECKS}
        self.assert_valid(value)

    def test_coordinator_and_run_identity_shapes(self):
        for field, replacement in (("runIds", IDS[7:9]), ("runIds", IDS[7:11]),
                                   ("runIds", [IDS[7]] * 3)):
            value = copy.deepcopy(self.good)
            value["checks"]["T7"][field] = replacement
            self.assertFalse(self.validator.is_valid(value))
        value = copy.deepcopy(self.good)
        value["evaluator"]["executionPath"] = "worker"
        self.assertFalse(self.validator.is_valid(value))
        value = copy.deepcopy(self.good)
        value["checks"]["T7"]["observed"]["runs"][0]["startedAt"] = "yesterday"
        self.assertFalse(self.validator.is_valid(value))
        for field, replacement in (("executionPath", "worker"), ("workerSlotsHeld", 1)):
            profile = copy.deepcopy(self.profile)
            profile["acceptance"]["coordinator"][field] = replacement
            self.assertFalse(Draft202012Validator(self.profile_schema).is_valid(profile))

    def test_coordinator_authority_and_capacity(self):
        """The host's amendments: who may start the probes, with what authority, on how many request kernels, by when."""
        for field, replacement in (("admittedCallers", ["user"]), ("admittedCallers", ["machine", "user"]),
                                   ("probeAuthority", {"caller": "user", "credential": "host-machine-credential",
                                                       "release": "declared-credential-pointer"}),
                                   ("probeAuthority", {"caller": "machine", "credential": "host-machine-credential",
                                                       "release": "input"}),
                                   ("requestKernelsRequired", 1), ("probeCompletion", "poll")):
            profile = copy.deepcopy(self.profile)
            profile["acceptance"]["coordinator"][field] = replacement
            self.assertFalse(Draft202012Validator(self.profile_schema).is_valid(profile), field)
        coordinator, request = self.profile["acceptance"]["coordinator"], self.profile["executionPaths"]["request"]
        self.assertLessEqual(coordinator["requestKernelsRequired"], request["kernels"])
        self.assertLess(coordinator["budgetMs"], request["deliveryBoundMs"])
        value = copy.deepcopy(self.good)
        value["checks"]["T6"]["observed"]["request"]["kernels"] = 1
        self.assertFalse(self.validator.is_valid(value))

    def test_dedicated_session_authority_is_narrow(self):
        coordinator = self.profile["acceptance"]["coordinator"]
        self.assertEqual(coordinator["admittedCallers"], [
            {"kind": "user", "principalRef": "host-acceptance-operator",
             "principalId": "565de6d4-ebcd-408b-9359-04d21dc62183", "match": "resolved-principal-id"}
        ])
        authority = coordinator["probeAuthority"]
        self.assertEqual(authority["principalRef"], "staging-release-acceptance")
        self.assertNotEqual(authority["principalId"], coordinator["admittedCallers"][0]["principalId"])
        self.assertEqual(authority["caller"], "user")
        self.assertEqual(authority["authentication"], "stored-session")
        self.assertEqual(authority["credential"], "SFX_API_ACCEPTANCE_SESSION")
        self.assertEqual(authority["provisioning"], "store-credential")
        validator = Draft202012Validator(self.profile_schema)
        mutations = [
            ("admittedCallers.0.kind", "machine"),
            ("admittedCallers.0.principalRef", "another-user"),
            ("admittedCallers.0.principalId", authority["principalId"]),
            ("admittedCallers.0.match", "request-body-name"),
            ("probeAuthority.caller", "machine"),
            ("probeAuthority.principalRef", "another-user"),
            ("probeAuthority.principalId", coordinator["admittedCallers"][0]["principalId"]),
            ("probeAuthority.authentication", "https-session-login"),
            ("probeAuthority.credential", "sfx-api-acceptance-password"),
            ("probeAuthority.provisioning", "operator-script"),
            ("probeAuthority.sessionCheckPath", "/other-session"),
            ("probeAuthority.release", "request-body"),
            ("probeAuthority.runVisibility", "all-runs"),
            ("probeAuthority.sessionUse", "acceptance-invocation"),
        ]
        for path, replacement in mutations:
            with self.subTest(path=path):
                profile = copy.deepcopy(self.profile)
                target = profile["acceptance"]["coordinator"]
                parts = path.split(".")
                for part in parts[:-1]:
                    target = target[int(part)] if isinstance(target, list) else target[part]
                target[parts[-1]] = replacement
                self.assertFalse(validator.is_valid(profile))
        for field in authority:
            with self.subTest(missing_authority_field=field):
                profile = copy.deepcopy(self.profile)
                del profile["acceptance"]["coordinator"]["probeAuthority"][field]
                self.assertFalse(validator.is_valid(profile))

    def test_published_version_one_cannot_be_relabelled_as_current(self):
        self.assertEqual(self.profile["profileVersion"], 4)
        for version, digest in ((1, "sha256:7c555f52f36a6060453451a79092a2ecc34a653fcb0c4b871fe991305b4da804"),
                                (2, "sha256:a27ac5f5d28f8dd511fe3763bafb188c1bf4dfc60632447d1ba43622e104e414"),
                                (3, "sha256:53d88521d1767295fd4967ce3bcf90d3606b7e0b63e2c2c3ba66a5a685e6957b")):
            with self.subTest(version=version):
                value = copy.deepcopy(self.good)
                value["profileVersion"] = version
                value["profileDigest"] = digest
                self.assertFalse(self.validator.is_valid(value))


if __name__ == "__main__":
    unittest.main()
