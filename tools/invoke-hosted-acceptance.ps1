# Retired version 2 password workflow. Keep this entry point harmless for old instructions.
[CmdletBinding()]
param([string]$OutputDirectory)

Write-Warning 'HOSTED_ACCEPTANCE_PASSWORD_FLOW_RETIRED: use the installed sfx-api capability observe accept-hosted-execution-profile command with your existing user session. No separate acceptance credential is required. This helper prompts for no password and starts no request.'
exit 3
