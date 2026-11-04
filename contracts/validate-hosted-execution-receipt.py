"""Validate a received receipt locally; this does not create deployment evidence."""
import hashlib
import base64
import json
from pathlib import Path
import sys
from datetime import datetime

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

ROOT = Path(__file__).resolve().parent


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result


def read(path):
    return json.loads(Path(path).read_bytes(), object_pairs_hook=unique_object)


def validate_schema(value, name):
    schema = read(ROOT / name)
    checker = FormatChecker()
    if not checker.conforms("2026-11-04T17:41:28Z", "date-time") or checker.conforms("bad", "date-time"):
        raise ValueError("date-time validator unavailable; install contracts/tests/requirements.txt")
    Draft202012Validator.check_schema(schema)
    registry = Registry()
    for filename in ("hosted-execution-acceptance.v1.schema.json", "hosted-execution-invocation-error.v1.schema.json"):
        referenced = read(ROOT / filename)
        registry = registry.with_resource(referenced["$id"], Resource.from_contents(referenced))
    errors = list(Draft202012Validator(schema, format_checker=checker, registry=registry).iter_errors(value))
    if errors:
        # No values or arbitrary receipt strings are echoed.
        raise ValueError("schema validation failed (%d violations)" % len(errors))


def validate_receipt(receipt):
    validate_schema(receipt, "hosted-execution-acceptance.v1.schema.json")
    profile_path = ROOT / "sfx-api-hosted-csharp.v1.profile.json"
    profile_digest = "sha256:" + hashlib.sha256(profile_path.read_bytes()).hexdigest()
    if receipt["profileDigest"] != profile_digest:
        raise ValueError("receipt profile digest differs from the local profile")
    if receipt["invocation"]["requestExecutionId"] != receipt["evaluator"]["executionId"]:
        raise ValueError("request execution identity mismatch")
    t4 = receipt["checks"]["T4"]
    if t4["kind"] == "OBSERVED":
        endpoint = read(profile_path)["host"]["endpoint"]
        if len(t4["runIds"]) != 1 or t4["observed"]["url"] != endpoint + "/sfx/v1/runs/" + t4["runIds"][0] + "/output":
            raise ValueError("T4 readback does not name its admitted run")
    t7 = receipt["checks"]["T7"]
    if t7["kind"] == "OBSERVED":
        observed = t7["observed"]
        runs = observed["runs"]
        if sorted(run["runId"] for run in runs) != sorted(t7["runIds"]):
            raise ValueError("T7 intervals do not name the admitted runs")
        intervals = sorted((datetime.fromisoformat(run["startedAt"].replace("Z", "+00:00")),
                            datetime.fromisoformat(run["endedAt"].replace("Z", "+00:00"))) for run in runs)
        if any(end <= start for start, end in intervals):
            raise ValueError("invalid T7 execution interval")
        events = sorted([(start, 1) for start, _ in intervals] + [(end, -1) for _, end in intervals])
        active = maximum = 0
        for _, change in events:  # End events sort before starts: intervals are half-open.
            active += change
            maximum = max(maximum, active)
        if observed["maxConcurrent"] != maximum or observed["thirdStartedAfterAnEnd"] != (intervals[2][0] >= min(end for _, end in intervals[:2])):
            raise ValueError("T7 concurrency assertions differ from the intervals")


def validate_delivery_proof(proof, receipt_bytes):
    validate_schema(proof, "hosted-execution-delivery-proof.v1.schema.json")
    receipt = proof["receipt"]
    validate_receipt(receipt)
    if not (proof["attemptId"] == proof["exchange"]["attemptId"] == receipt["invocation"]["attemptId"]):
        raise ValueError("invocation attempt identity mismatch")
    artifact = proof["receiptArtifact"]
    profile = read(ROOT / "sfx-api-hosted-csharp.v1.profile.json")
    expected_reference = profile["host"]["endpoint"] + profile["acceptance"]["invocation"]["readback"]["path"].replace("{attemptId}", proof["attemptId"])
    if artifact["reference"] != expected_reference:
        raise ValueError("receipt artifact reference does not name the declared attempt readback")
    if artifact["byteLength"] != len(receipt_bytes) or artifact["sha256"] != "sha256:" + hashlib.sha256(receipt_bytes).hexdigest():
        raise ValueError("retained receipt bytes do not match the proof")
    if json.loads(receipt_bytes, object_pairs_hook=unique_object) != receipt:
        raise ValueError("retained receipt value differs from the embedded receipt")


def validate_readback(record):
    validate_schema(record, "hosted-execution-acceptance-read-result.v1.schema.json")
    if record["status"] == "FAILED":
        if record["attemptId"] != record["error"]["attemptId"]:
            raise ValueError("retained error attempt identity mismatch")
    if record["status"] != "RECEIPT_AVAILABLE":
        return None
    raw = base64.b64decode(record["receiptBytesBase64"], validate=True)
    if record["receiptByteLength"] != len(raw) or record["receiptSha256"] != "sha256:" + hashlib.sha256(raw).hexdigest():
        raise ValueError("retained receipt encoding does not match its digest and size")
    receipt = json.loads(raw, object_pairs_hook=unique_object)
    if receipt != record["receipt"]:
        raise ValueError("retained receipt encoding does not match its value")
    validate_receipt(receipt)
    if (record["attemptId"] != receipt["invocation"]["attemptId"] or
            record["requestExecutionId"] != receipt["invocation"]["requestExecutionId"] or
            record["profileDigest"] != receipt["profileDigest"]):
        raise ValueError("retained receipt identity mismatch")
    return raw


def main():
    if len(sys.argv) not in (2, 4) or len(sys.argv) == 4 and sys.argv[2] != "--receipt-artifact":
        raise ValueError("provide a receipt, or a delivery proof with --receipt-artifact PATH")
    receipt = read(sys.argv[1])
    if receipt.get("contractId") == "hosted-execution-acceptance-read-result.v1":
        validate_readback(receipt)
        print("Readback record validated; status=" + receipt["status"])
        return
    if receipt.get("contractId") == "hosted-execution-delivery-proof.v1":
        if len(sys.argv) != 4:
            raise ValueError("delivery proof requires the independently read receipt artifact")
        validate_delivery_proof(receipt, Path(sys.argv[3]).read_bytes())
        print("Delivery proof structure, identities and artifact bytes validated; status=" + receipt["status"])
        print("Live execution and current deployment provenance still require independent readback.")
        return
    validate_receipt(receipt)
    print("Receipt schema valid; status=" + receipt["status"])
    print("This validates structure and thresholds; deployment provenance still requires independent readback.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError) as error:
        print("Receipt validation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
