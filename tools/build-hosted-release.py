"""Project the hosted v4 source declarations into the image's pinned host bundle.

Build providers/hosted/HostedProviders.csproj first. No deployment or credentials.
"""
import base64
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "authorities/host-bundle"
def read(path): return json.loads(path.read_text(encoding="utf-8"))
def write(path, value): path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
def lit(value): return {"op": "literal", "value": value}
def ref(path, source=None): return {"op": "path", "path": path, **({"from": source} if source else {})}
def obj(**fields): return {"op": "object", "fields": fields}
def equal(a,b): return {"op":"equals","left":a,"right":b}
def when(test, yes, no): return {"op":"if","when":test,"then":yes,"else":no}
def both(*tests):
    result=lit(True)
    for test in reversed(tests): result=when(test,result,lit(False))
    return result
def walk(value, action):
    if isinstance(value,dict):
        action(value)
        for item in list(value.values()): walk(item,action)
    elif isinstance(value,list):
        for item in value: walk(item,action)
def capability(name): return read(BUNDLE / "capabilities" / (name + ".json"))
def save(doc): write(BUNDLE / "capabilities" / (doc["capabilityId"] + ".json"), doc)
def bindings(doc): return doc["graphSource"]["interfaceAuthority"]["portBindings"]
def binding(doc, suffix): return next(b for b in bindings(doc) if b["portId"] == doc["capabilityId"] + "-" + suffix)
def digest(data): return "sha256:" + hashlib.sha256(data).hexdigest()

profile_bytes=(ROOT / "contracts/sfx-api-hosted-csharp.v1.profile.json").read_bytes()
profile=json.loads(profile_bytes); pin=digest(profile_bytes)
operator=profile["acceptance"]["coordinator"]["admittedCallers"][0]["principalId"]
plan=read(ROOT / "providers/hosted/acceptance-plan.json")
config={"operatorPrincipalId":operator,"profileDigest":pin,"requestKernelTimeout":"195000",
        "path":profile["acceptance"]["coordinator"]["path"],
        "recordDirectory":"/home/sjones/.local/share/sfx/hosted-acceptance",
        "credentialReference":"SFX_API_ACCEPTANCE_SESSION",
        "receiptValidator":"/opt/sfx/providers/hosted/validate.py",
        "receiptExpression":read(ROOT / "providers/hosted/receipt-expression.json"),
        "observationProgram":(ROOT / "providers/host-acceptance.py").read_text(encoding="utf-8"),
        "recordBinding":{"mechanicId":"sfx-api-host-acceptance-record-port.v1",
            "provider":{"providerProfileId":"sfx-api-host-acceptance-record","language":"csharp",
                "type":"Sfx.HostedProviders.HostedAcceptance","assembly":"/opt/sfx/providers/hosted/Sfx.HostedProviders.dll","method":"Retain"},
            "configuration":{"recordDirectory":"/home/sjones/.local/share/sfx/hosted-acceptance",
                "operatorPrincipalId":operator,"requestKernelTimeout":"195000"}}}
doc=capability('accept-hosted-execution-profile')
binding(doc,'authorize')['configuration']['expression']=obj(
    admission=when(both(equal(ref('caller.kind'),lit('user')),equal(ref('caller.principalId'),lit(operator))),lit('ADMITTED'),lit('ACCEPTANCE_PRINCIPAL_REQUIRED')),
    invocation=ref(''),plan={'op':'merge','values':[lit(plan),obj(requestExecutionId=ref('requestExecutionId'))]})
binding(doc,'exchange')['configuration']=copy.deepcopy(config)
doc['graphSource']['executionAuthorities'][0]['operations']=[op for op in doc['graphSource']['executionAuthorities'][0]['operations'] if not op['portId'].endswith('-evaluate')]
doc['graphSource']['interfaceAuthority']['portBindings']=[b for b in bindings(doc) if not b['portId'].endswith('-evaluate')]
doc['graphSource']['contractAuthorities']['contracts']['accept-hosted-execution-profile-request.v1']['schema']={'type':'object'}
# Full 2020-12 admission (including unevaluatedProperties and asserted formats)
# runs inside the provider before persistence. The kernel's older validator has
# a narrower vocabulary; its carrier contract does not stand in for admission.
doc['graphSource']['contractAuthorities']['contracts']['hosted-execution-acceptance.v1']['schema']={'type':'object'}
doc['closure'][0]['responsibility']='The pinned operator starts request-path acceptance; the provider retains its typed result before returning it.'
save(doc)

reader=capability('read-hosted-execution-profile')
binding(reader,'answer')['configuration']['expression']=lit({'contractId':'hosted-execution-profile-reading.v1',
    'profileId':profile['profileId'],'profileVersion':profile['profileVersion'],'profileDigest':pin,'profileText':profile_bytes.decode('utf-8')})
save(reader)

# Make readback a separate declared capability with no vault or HTTP probe ports.
reader=copy.deepcopy(reader)
reader=json.loads(json.dumps(reader).replace('read-hosted-execution-profile','read-hosted-execution-acceptance').replace('hosted-execution-profile-reading.v1','hosted-execution-acceptance-read-result.v1'))
reader['graphSource']['interfaceAuthority']['portBindings']=[{'portId':'read-hosted-execution-acceptance-answer',
    'platformCapabilityId':'sfx-api-host-acceptance-record-port.v1','configuration':{k:config[k] for k in ('operatorPrincipalId','requestKernelTimeout','recordDirectory')}}]
reader['graphSource']['contractAuthorities']['contracts']={name:{'schemaRef':name+'.schema.json','schema':{'type':'object'}} for name in ('read-hosted-execution-acceptance-request.v1','hosted-execution-acceptance-read-result.v1')}
reader['closure'][0]['responsibility']='Read one non-secret retained acceptance attempt for the pinned operator, without opening a probe credential.'
save(reader)

# The trusted HTTP envelope supplies identity outside the raw request bytes.
doc=capability('serve-http-request')
binding(doc,'read')['configuration']['expression']=ref('')
doc['cliConfiguration']['input']={'type':'json','contract':'serve-http-request-request.v1'}
doc['graphSource']['interfaceAuthority']['interfaces'][0]['configuration']['input']=copy.deepcopy(doc['cliConfiguration']['input'])
schema=doc['graphSource']['contractAuthorities']['contracts']['serve-http-request-request.v1']['schema']
schema['properties'].update({'requestExecutionId':{'type':'string','pattern':'^[0-9a-f-]{36}$'},'executionPath':{'const':'request'}})
schema['required']=['contractId','raw','requestExecutionId','executionPath']
def ingress_context(node):
    if node.get('op')=='object' and all(k in node.get('fields',{}) for k in ('method','segments','body','headers')):
        node['fields']['requestExecutionId']=ref('requestExecutionId'); node['fields']['executionPath']=ref('executionPath')
walk(binding(doc,'prepare')['configuration']['expression'],ingress_context)
save(doc)
diagnostic=capability('resolve-http-request')
binding(diagnostic,'read')['configuration']['expression']=ref('')
save(diagnostic)
settings=capability('read-api-host-configuration')
def json_envelope(node):
    if node.get('subject')=='serve-http-request': node['inputType']='json'
walk(settings,json_envelope); save(settings)

# Probe admission evidence retains only the declared, non-secret check selector.
# Other capabilities (including credential storage) never retain their input here.
admit=capability('admit-api-run-live')
answer=binding(admit,'answer')['configuration']['expression']
fields=answer['bindings']['capability']['fields']
fields['probeInput']=when({'op':'includes','in':lit(['probe-hosted-execution','probe-hosted-execution-language-refusal']),
    'value':ref('admission.subject','admitted')},
    when(equal(ref('admission.subject','admitted'),lit('probe-hosted-execution')),obj(check=ref('admission.input.check','admitted')),lit({})),lit(None))
save(admit)

# Preserve the existing ingress implementation and add exactly-one header reads.
dependency=read(ROOT/'providers/sfx-api-ingress.dependency.json')
operation=dependency['operations'][0]
operation['parameters']=[{'name':'raw','source':'input','path':'raw'},
    {'name':'requestExecutionId','source':'input','path':'requestExecutionId'},
    {'name':'executionPath','source':'input','path':'executionPath'}]
program=operation['programs']['csharp']
# Idempotent rebuild strips only these generated statements.
program[:]=[s for s in program if not s.get('bind','').startswith('hosted') and not s.get('invocation','').startswith('hosted') and
    not (s.get('invocation') in ('headers.Add','value.Add') and s.get('arguments',[{}])[0].get('value') in
         ('x-sfx-acceptance-attempt-id','x-sfx-hosted-profile-digest','requestExecutionId','executionPath'))]
scope=lambda name: {'op':'path','from':'scope','path':name}
extra=[]
for stem,header in [('hostedAttempt','x-sfx-acceptance-attempt-id'),('hostedProfile','x-sfx-hosted-profile-digest')]:
    # A duplicate (even mixed case or with identical value) makes the extraction empty.
    pattern=r'(?im)\A(?![\s\S]*^'+header+r':[\s\S]*^'+header+r':)[\s\S]*?^'+header+r':[ \t]*([^\r\n]*?)[ \t]*\r?$'
    extra += [{'bind':stem+'Pattern','invocation':'new System.Text.RegularExpressions.Regex, System.Text.RegularExpressions','arguments':[lit(pattern)]},
        {'bind':stem+'Match','invocation':stem+'Pattern.Match','arguments':[scope('head')]},
        {'bind':stem+'Groups','invocation':stem+'Match.$computed.$read','selector':lit('Groups')},
        {'bind':stem+'Group','invocation':stem+'Groups.$computed.$read','selector':lit(1)},
        {'bind':stem,'invocation':stem+'Group.$computed.$read','selector':lit('Value')},
        {'invocation':'headers.Add','arguments':[lit(header),scope(stem)]}]
at=next(i for i,s in enumerate(program) if s.get('bind')=='value')
program[at:at]=extra
for name in ('requestExecutionId','executionPath'): program.append({'invocation':'value.Add','arguments':[lit(name),scope(name)]})
write(ROOT/'providers/sfx-api-ingress.dependency.json',dependency)

front=capability('serve-api-request')
transforms={t['id']:t for t in front['graphSource']['semanticTransformations']}
operations=transforms['serve-carry-interface']['expression']['fields']['result']['fields']['value']['fields']['interface']['value']['operations']
accept=next(o for o in operations if o['operationId']=='accept-hosted-execution-profile')
accept['input']={'attemptId':'$header.x-sfx-acceptance-attempt-id','expectedProfileDigest':'$header.x-sfx-hosted-profile-digest',
    'requestExecutionId':'$request.requestExecutionId','executionPath':'$request.executionPath',
    'caller':{'kind':'$caller.kind','principalId':'$caller.principalId'},
    'request':{'method':'$request.method','path':config['path'],'body':'$body'}}
accept['meaning']='The pinned host operator initiates the v4 coordinator with an empty body. Ingress binds the caller and actual request admission identity; headers only correlate the attempt and discovered profile.'
operations[:]=[o for o in operations if o['operationId']!='read-hosted-execution-acceptance']
operations.append({'operationId':'read-hosted-execution-acceptance','method':'GET','path':'/hosted-execution/acceptance/{attemptId}',
    'callers':['user'],'resolves':{'kind':'capability','capabilityId':'read-hosted-execution-acceptance'},
    'input':{'attemptId':'$path.attemptId','caller':{'kind':'$caller.kind','principalId':'$caller.principalId'}},
    'segments':{'0':'','1':'sfx','2':'v1','3':'hosted-execution','4':'acceptance','5':{'param':'attemptId'}},
    'meaning':'Read the named retained attempt through the same pinned operator binding. No probe credential or worker admission.'})
resolve=transforms['serve-resolve-request']['expression']
if 'hostedResolution' in resolve.get('bindings',{}): resolve=resolve['bindings']['hostedResolution']
def template_context(node):
    if node.get('op')=='object' and '$header' in node.get('fields',{}): node['fields']['$request']=ref('request','payload')
    if node.get('pattern')==r'^\$(body|(path|query|caller|header)\.[A-Za-z0-9_-]+)$': node['pattern']=r'^\$(body|(path|query|caller|header|request)\.[A-Za-z0-9_-]+)$'
walk(resolve,template_context)
payload=ref('result.value')
on_acceptance=both(equal(ref('result.value.request.segments.3'),lit('hosted-execution')),
    equal(ref('result.value.request.segments.4'),lit('acceptance')))
caller_failure=both(on_acceptance,{'op':'includes','in':lit([401,403]),'value':ref('dispatchRequest.status','hostedResolution')})
attempt=ref('result.value.request.headers.x-sfx-acceptance-attempt-id')
valid_attempt=when(equal({'op':'type','value':attempt},lit('string')),
    {'op':'matches','value':attempt,'pattern':r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'},lit(False))
failure_body=obj(contractId=lit('hosted-execution-invocation-error.v1'),attemptId=when(valid_attempt,attempt,ref('result.value.request.requestExecutionId')),
    outcome=lit('FAILED'),stage=lit('caller'),code=when(equal(ref('dispatchRequest.status','hostedResolution'),lit(401)),lit('CALLER_REQUIRED'),lit('ACCEPTANCE_PRINCIPAL_REQUIRED')),
    httpStatus=ref('dispatchRequest.status','hostedResolution'),requestExecutionId=lit(None),message=lit('The pinned operator session is required.'),automaticRetry=lit(False),receipt=lit(None))
transforms['serve-resolve-request']['expression']={'op':'let','bindings':{'hostedResolution':resolve},'value':when(caller_failure,
    {'op':'merge','values':[ref('','hostedResolution'),obj(dispatchRequest=obj(contractId=lit('api-response.v1'),status=ref('dispatchRequest.status','hostedResolution'),
        headers=lit({'content-type':'application/json; charset=utf-8'}),body=failure_body))]},ref('','hostedResolution'))}
compose=transforms['serve-compose-response']['expression']
if compose.get('when')==equal(ref('result.contractId'),lit('hosted-execution-invocation-error.v1')): compose=compose['else']
transforms['serve-compose-response']['expression']=when(equal(ref('result.contractId'),lit('hosted-execution-invocation-error.v1')),
    obj(contractId=lit('api-response.v1'),status=ref('result.httpStatus'),headers=lit({'content-type':'application/json; charset=utf-8'}),body=ref('result')),compose)
# Read-result NOT_FOUND is a successful typed lookup, not a missing API route.
def lookup_status(node):
    if node.get('op')=='if' and node.get('then')==lit(404) and node.get('when')==equal(ref('result.status'),lit('NOT_FOUND')):
        node['when']=both(equal(ref('result.status'),lit('NOT_FOUND')),{'op':'if','when':equal(ref('result.contractId'),lit('hosted-execution-acceptance-read-result.v1')),'then':lit(False),'else':lit(True)})
walk(transforms['serve-compose-response']['expression'],lookup_status)
save(front)

# Source module identity is explicit in the provider declaration and is attested
# with the host files. The shared record path is the deployment-wide lock domain.
authority=read(ROOT/'providers/host-provider-authority.json')
source=digest((ROOT/'providers/hosted/HostedAcceptance.cs').read_bytes())
for identity,method,mechanic in [('sfx-api-host-http-request','Accept','sfx-api-host-http-request-port.v1'),
                                  ('sfx-api-host-acceptance-record','Read','sfx-api-host-acceptance-record-port.v1')]:
    authority['declaredProviders'][:]=[p for p in authority['declaredProviders'] if p['providerProfileId']!=identity]
    authority['overlayBindings'][:]=[b for b in authority['overlayBindings'] if b['mechanicId']!=mechanic]
    authority['declaredProviders'].append({'providerProfileId':identity,'language':'csharp','type':'Sfx.HostedProviders.HostedAcceptance',
        'assembly':'../../providers/hosted/Sfx.HostedProviders.dll','method':method,'effectClassification':'observation',
        'sourceProviderDefinitionDigest':source})
    authority['overlayBindings'].append({'mechanicId':mechanic,'providerProfileId':identity,'providerProfileDigest':source,
        'implementationRef':'providers/hosted/HostedAcceptance.cs#'+method})
for provider in authority['declaredProviders']:
    if provider['providerProfileId']=='sfx-api-ingress-resolve.v2':
        provider['operations'][0]['parameters']=copy.deepcopy(operation['parameters'])
        provider['operations'][0]['program']=copy.deepcopy(program)
        provider['sourceProviderDefinitionDigest']=digest((ROOT/'providers/sfx-api-ingress.dependency.json').read_bytes())
        next(b for b in authority['overlayBindings'] if b['providerProfileId']==provider['providerProfileId'])['providerProfileDigest']=provider['sourceProviderDefinitionDigest']

manifest=read(BUNDLE/'manifest.json')
for name in ('accept-hosted-execution-profile','read-hosted-execution-profile','read-hosted-execution-acceptance','serve-api-request','serve-http-request','resolve-http-request','read-api-host-configuration','admit-api-run-live'):
    docpath=BUNDLE/'capabilities'/(name+'.json')
    doc=read(docpath)
    # Closure identities track the final declaration, not a copied earlier one.
    closure_digest=base64.b64encode(hashlib.sha256(json.dumps(doc['graphSource'],ensure_ascii=False,separators=(',',':')).encode()).digest()).decode()
    for entry in doc['closure']: entry['scenario_definition_digest']=closure_digest
    write(docpath,doc)
manifest['capabilities']=[{'capabilityId':read(p)['capabilityId'],'namespaceId':'sidefx:capabilities','document':'capabilities/'+p.name,
    'sha256Base64':base64.b64encode(hashlib.sha256(p.read_bytes()).digest()).decode()} for p in sorted((BUNDLE/'capabilities').glob('*.json'))]
write(BUNDLE/'manifest.json',manifest)
bundle_pin='sha256-base64:'+base64.b64encode(hashlib.sha256((BUNDLE/'manifest.json').read_bytes()).digest()).decode()
def repin(value):
    if value.get('op')=='literal' and isinstance(value.get('value'),str) and value['value'].startswith('sha256-base64:'): value['value']=bundle_pin
    if value.get('op')=='object' and value.get('fields',{}).get('path',{}).get('value')=='../../authorities/host-bundle/manifest.json':
        value['fields']['sha256Base64']=lit(bundle_pin.removeprefix('sha256-base64:'))
walk(authority,repin)
write(ROOT/'providers/host-provider-authority.json',authority)
print(json.dumps({'profileDigest':pin,'bundleDigest':bundle_pin,'capabilities':len(manifest['capabilities'])}))
