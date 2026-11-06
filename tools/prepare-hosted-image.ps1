param(
    [Parameter(Mandatory=$true)][string]$KernelRoot,
    [Parameter(Mandatory=$true)][string]$Destination
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$kernel = (Resolve-Path -LiteralPath $KernelRoot).Path
$target = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $target) { throw 'Build destination must be new.' }
if ((Split-Path $kernel -Leaf) -notmatch '^[0-9a-f]{64}$') { throw 'Use the admitted kernel artifact directory.' }
& 'C:/Program Files/dotnet/dotnet.exe' build (Join-Path $repo 'providers/hosted/HostedProviders.csproj') -c Release "-p:KernelRoot=$kernel" --nologo
if ($LASTEXITCODE) { throw 'Provider build failed.' }
& python -B (Join-Path $repo 'tools/build-content-release.py')
if ($LASTEXITCODE) { throw 'Content declaration projection failed.' }
& python -B (Join-Path $repo 'tools/build-hosted-release.py')
if ($LASTEXITCODE) { throw 'Bundle projection failed.' }
New-Item -ItemType Directory -Path $target | Out-Null
Copy-Item -LiteralPath $kernel -Destination (Join-Path $target 'kernel') -Recurse
foreach ($name in @('Dockerfile','start.sh','kernel-host.json')) {
    Copy-Item -LiteralPath (Join-Path $repo "deploy/$name") -Destination (Join-Path $target $name)
}
Copy-Item -LiteralPath (Join-Path $repo 'sfx-api.config.json') -Destination $target
foreach ($name in @('host','authorities/host-bundle')) {
    $destinationPath = Join-Path $target $name
    New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null
    $sourcePath = Join-Path $repo $name
    Get-ChildItem -LiteralPath $sourcePath -File | Copy-Item -Destination $destinationPath
    if ($name -eq 'authorities/host-bundle') { Copy-Item -LiteralPath (Join-Path $sourcePath 'capabilities') -Destination $destinationPath -Recurse }
}
New-Item -ItemType Directory -Path (Join-Path $target 'providers/hosted'),(Join-Path $target 'contracts') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'providers/host-provider-authority.json') -Destination (Join-Path $target 'providers')
foreach ($name in @('validate.py','requirements.txt')) {
    Copy-Item -LiteralPath (Join-Path $repo "providers/hosted/$name") -Destination (Join-Path $target 'providers/hosted')
}
Copy-Item -LiteralPath (Join-Path $repo 'providers/hosted/bin/Release/net10.0/Sfx.HostedProviders.dll') -Destination (Join-Path $target 'providers/hosted')
New-Item -ItemType Directory -Path (Join-Path $target 'providers/content') -Force | Out-Null
foreach ($name in @('package.py','requirements.txt')) {
    Copy-Item -LiteralPath (Join-Path $repo "providers/content/$name") -Destination (Join-Path $target 'providers/content')
}
Get-ChildItem -LiteralPath (Join-Path $repo 'contracts') -File | Where-Object { $_.Extension -in '.json','.py' } | Copy-Item -Destination (Join-Path $target 'contracts')
# File-byte pins are verified from the final context, not merely the checkout.
$verify = @'
import base64, hashlib, json, pathlib, sys
p=pathlib.Path(sys.argv[1]); m=p/'authorities/host-bundle/manifest.json'
for c in json.loads(m.read_bytes())['capabilities']:
 assert base64.b64encode(hashlib.sha256((m.parent/c['document']).read_bytes()).digest()).decode()==c['sha256Base64'],c['capabilityId']
authority=json.loads((p/'providers/host-provider-authority.json').read_bytes())
bindings=authority['eventPorts'][0]['configuration']['graphSource']['interfaceAuthority']['portBindings']
expected=next(b['configuration']['expression']['fields']['sha256Base64']['value'] for b in bindings if b['portId']=='answer-host-declared-read-manifest-request')
assert base64.b64encode(hashlib.sha256(m.read_bytes()).digest()).decode()==expected,'startup manifest pin'
# The Dockerfile overlays this root kernel-host.json on the admitted kernel.
# Hash the final image bytes, not the pre-overlay kernel/kernel-host.json.
host_files=['host/serve.py','sfx-api.config.json','start.sh','kernel-host.json',
 'providers/host-provider-authority.json','providers/hosted/Sfx.HostedProviders.dll',
 'providers/hosted/validate.py','contracts/validate-hosted-execution-receipt.py',
 'providers/content/package.py','providers/content/requirements.txt']
host_digest=hashlib.sha256()
for name in host_files: host_digest.update((p/name).read_bytes())
print('Host files: sha256:'+host_digest.hexdigest())
print('Verified build context: '+str(p))
'@
$verify | python - $target
if ($LASTEXITCODE) { throw 'Context pin verification failed.' }
