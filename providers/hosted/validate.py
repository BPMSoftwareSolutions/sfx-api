"""Full host contract admission; stdin is non-secret receipt material, no values are echoed."""
import importlib.util
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "providers/schema-python"))
spec = importlib.util.spec_from_file_location("receipt_validator", root / "contracts/validate-hosted-execution-receipt.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
try:
    value = json.loads(sys.stdin.buffer.read(), object_pairs_hook=validator.unique_object)
    validator.validate_receipt(value)
except Exception:
    sys.exit(1)
