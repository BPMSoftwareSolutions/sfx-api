"""Old password instructions must stop before prompting, storing, or sending a request."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from test_hosted_execution_contract import ROOT


class RetiredAcceptanceClientTests(unittest.TestCase):
    def test_old_password_entry_point_has_no_effects(self):
        shells = [path for name in ("powershell", "pwsh") if (path := shutil.which(name))]
        if not shells:
            self.skipTest("PowerShell is unavailable")
        with tempfile.TemporaryDirectory(prefix="sfx-retired-client-test-") as temporary:
            folder = Path(temporary)
            wrapper = folder / "check-retired.ps1"
            wrapper.write_text('''
param($Helper, $Destination, $Marker)
function UnexpectedCall {
    [IO.File]::WriteAllText($Marker, 'unexpected effect')
    throw 'Retired helper must not perform this action'
}
function Read-Host { UnexpectedCall }
function sfx-api { UnexpectedCall }
function Invoke-WebRequest { UnexpectedCall }
function Invoke-RestMethod { UnexpectedCall }
& $Helper -OutputDirectory $Destination
exit $LASTEXITCODE
''', encoding="utf-8")
            for shell in shells:
                with self.subTest(shell=shell):
                    destination = folder / "output"
                    marker = folder / "effect.txt"
                    result = subprocess.run([shell, "-NoProfile", "-NonInteractive", "-File", str(wrapper),
                                             str(ROOT / "tools/invoke-hosted-acceptance.ps1"),
                                             str(destination), str(marker)],
                                            capture_output=True, text=True, timeout=15,
                                            env={k: v for k, v in os.environ.items() if k.lower() != "psmodulepath"})
                    self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
                    self.assertIn("HOSTED_ACCEPTANCE_PASSWORD_FLOW_RETIRED", result.stdout)
                    self.assertFalse(destination.exists())
                    self.assertFalse(marker.exists())


if __name__ == "__main__":
    unittest.main()
