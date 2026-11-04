# Retired version 2 password workflow. Keep this entry point harmless for old instructions.
[CmdletBinding()]
param([string]$OutputDirectory)

Write-Warning 'HOSTED_ACCEPTANCE_PASSWORD_FLOW_RETIRED: profile version 3 uses SFX_API_ACCEPTANCE_SESSION through the host vault. This helper prompts for no password, changes no credential, and starts no request. The host must invoke its declared acceptance route and produce the receipt.'
exit 3
