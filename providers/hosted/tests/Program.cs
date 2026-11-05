using System.Diagnostics;
using System.Text.Json.Nodes;
using ScenarioKernel.Adapters.Consumer;
using ScenarioKernel.Adapters.Graph;
using Sfx.HostedProviders;

if (args[0] == "lock") {
    using var held = new FileStream(Path.Combine(args[1],"coordinator.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);
    Console.WriteLine("LOCKED"); await Task.Delay(Timeout.Infinite); return;
}
var repo=Path.GetFullPath(args[0]); var directory=Path.Combine(Path.GetTempPath(),"sfx-hosted-"+Guid.NewGuid()); Directory.CreateDirectory(directory);
Directory.CreateDirectory(Path.Combine(repo,".tmp"));
int passed=0;
void Check(bool condition,string message) { if(!condition)throw new Exception(message); passed++; }
JsonNode Load(string p)=>HostedAcceptance.Parse(File.ReadAllText(Path.Combine(repo,p)));
var id="11111111-1111-4111-8111-000000000011";
try {
    var synthetic=Convert.ToBase64String(Enumerable.Range(0,32).Select(x=>(byte)x).ToArray());
    string Request(string headers,string body="{}")=>"POST /sfx/v1/hosted-execution/acceptance HTTP/1.1\r\n"+headers+"\r\n\r\n"+body;
    HostedAcceptance.CaptureRequestCredential(id,Request("Authorization: Bearer "+synthetic));
    Check(HostedAcceptance.TakeRequestCredential(id)==synthetic,"request session not available");
    Check(HostedAcceptance.TakeRequestCredential(id)=="","request session replay");
    HostedAcceptance.CaptureRequestCredential(id,Request("Authorization: Bearer "+synthetic));
    Check(HostedAcceptance.TakeRequestCredential(Guid.NewGuid().ToString())=="","cross-request credential release");
    Check(HostedAcceptance.TakeRequestCredential(id)=="","mismatched request left credential");
    foreach(var raw in new[]{Request("Authorization: Bearer "+synthetic+"\r\nauthorization: Bearer "+synthetic),
        Request("", "Authorization: Bearer "+synthetic), Request("Authorization: Bearer invalid"),
        Request("Authorization: Bearer "+synthetic).Replace("POST ","GET "),
        Request("Authorization: Bearer "+synthetic).Replace("/acceptance ","/acceptance/other ")}) {
        HostedAcceptance.CaptureRequestCredential(id,raw);Check(HostedAcceptance.TakeRequestCredential(id)=="","invalid credential carrier admitted");
    }
    HostedAcceptance.CaptureRequestCredential(id,Request("Authorization: Bearer "+synthetic));
    HostedAcceptance.CaptureRequestCredential("","");
    Check(HostedAcceptance.TakeRequestCredential(id)=="","next ingress did not clear credential");
    var redacted=ScenarioKernel.Bootstrap.ReleasedCredentials.Process.Redact(new JsonObject{["text"]=synthetic});
    Check(!redacted.ToJsonString().Contains(synthetic),"request session not registered for redaction");
    foreach(var value in new[]{"{\"a\":1,\"\\u0061\":2}","{\"x\":{\"a\":1,\"a\":2}}"}) {
        bool refused=false; try{HostedAcceptance.Parse(value);}catch(InvalidDataException){refused=true;} Check(refused,"duplicate accepted");
    }
    var config=new JsonObject{["operatorPrincipalId"]="565de6d4-ebcd-408b-9359-04d21dc62183",["requestKernelTimeout"]="195000",["recordDirectory"]=directory};
    var context=new GraphExecutionContext("g","c","cell","root","sfx-api-host-http-request",new JsonObject{["binding"]=new JsonObject{["configuration"]=config}},null,null);
    var wrong=HostedAcceptance.Read(new JsonObject{["attemptId"]=id,["caller"]=new JsonObject{["kind"]="user",["principalId"]="forged"}},context,CancellationToken.None);
    Check(wrong["code"]!.GetValue<string>()=="ACCEPTANCE_PRINCIPAL_REQUIRED","caller gate");
    Check(!Directory.EnumerateFiles(directory).Any(),"unauthorized read touched records");
    var forged=Load("contracts/examples/hosted-execution-v5/trusted-context.json");
    var gate=await HostedAcceptance.Accept(new JsonObject{["context"]=new JsonObject{["invocation"]=forged}},context,CancellationToken.None);
    Check(gate.OutcomeValue!["code"]!.GetValue<string>()=="ACCEPTANCE_REQUEST_PATH_REQUIRED","forged request path admitted");
    var absent=HostedAcceptance.ReadRecord(directory,id); Check(absent["status"]!.GetValue<string>()=="NOT_FOUND","read created an attempt");
    var record=Load("contracts/examples/hosted-execution-v5/read-result-running.json"); id=record["attemptId"]!.GetValue<string>();
    File.WriteAllText(Path.Combine(directory,id+".json"),record.ToJsonString());
    var unknown=HostedAcceptance.ReadRecord(directory,id); Check(unknown["status"]!.GetValue<string>()=="UNKNOWN","abandoned attempt not unknown");
    Check(LoadExternal(Path.Combine(directory,id+".json"))["status"]!.GetValue<string>()=="UNKNOWN","unknown not durable");
    File.WriteAllText(Path.Combine(directory,id+".json"),record.ToJsonString());
    File.WriteAllText(Path.Combine(directory,"active.json"),new JsonObject{["attemptId"]=id}.ToJsonString());
    var start=new ProcessStartInfo(Environment.ProcessPath!){UseShellExecute=false,RedirectStandardOutput=true};
    start.ArgumentList.Add("lock");start.ArgumentList.Add(directory);
    using(var child=Process.Start(start)!) {
        try {
            Check(await child.StandardOutput.ReadLineAsync()=="LOCKED","separate process lock");
            var live=HostedAcceptance.ReadRecord(directory,id);
            Check(live["status"]!.GetValue<string>()=="RUNNING","live lock not honored: "+live.ToJsonString());
        } finally { child.Kill(true); await child.WaitForExitAsync(); }
    }
    JsonNode afterCrash=HostedAcceptance.ReadRecord(directory,id);
    for(var tries=0;tries<100 && afterCrash["status"]!.GetValue<string>()=="RUNNING";tries++) {
        await Task.Delay(10); afterCrash=HostedAcceptance.ReadRecord(directory,id);
    }
    Check(afterCrash["status"]!.GetValue<string>()=="UNKNOWN","crash retained admission ownership");
    var retained=Load("contracts/examples/hosted-execution-v5/read-result-receipt.json");
    id=retained["attemptId"]!.GetValue<string>();File.WriteAllText(Path.Combine(directory,id+".json"),retained.ToJsonString());
    Check(JsonNode.DeepEquals(HostedAcceptance.ReadRecord(directory,id),retained),"receipt bytes changed after restart");
    var authority=Load("authorities/host-bundle/capabilities/serve-api-request.json");
    var expressions=authority["graphSource"]!["semanticTransformations"]!.AsArray().ToDictionary(x=>x!["id"]!.GetValue<string>(),x=>x!["expression"]!.AsObject());
    var engine=new SemanticTransformationEngine();
    var incoming=new JsonObject{["request"]=new JsonObject{["method"]="POST",["segments"]=JsonNode.Parse("[\"\",\"sfx\",\"v1\",\"hosted-execution\",\"acceptance\"]"),
        ["body"]="{}",["query"]=new JsonObject(),["headers"]=new JsonObject{["x-sfx-acceptance-attempt-id"]=id,["x-sfx-hosted-profile-digest"]=forged["expectedProfileDigest"]!.DeepClone()},
        ["requestExecutionId"]=forged["requestExecutionId"]!.DeepClone(),["executionPath"]="request"},["caller"]=forged["caller"]!.DeepClone()};
    var carried=engine.Transform(expressions["serve-carry-interface"],incoming);
    var resolved=engine.Transform(expressions["serve-resolve-request"],carried)!;
    var input=resolved["dispatchRequest"]!;
    Check(input["requestExecutionId"]?.GetValue<string>()==forged["requestExecutionId"]!.GetValue<string>(),"request identity not bound");
    Check(input["request"]?["body"] is JsonObject b&&b.Count==0,"empty body not bound");
    Check(input["caller"]?["principalId"]?.GetValue<string>()==config["operatorPrincipalId"]!.GetValue<string>(),"trusted operator not bound");
    incoming["caller"]=null;
    var unauth=engine.Transform(expressions["serve-resolve-request"],engine.Transform(expressions["serve-carry-interface"],incoming))!;
    Check(unauth["dispatchRequest"]?["body"]?["contractId"]?.GetValue<string>()=="hosted-execution-invocation-error.v1","unauthenticated request lacks typed failure");
    Check(unauth["dispatchRequest"]?["body"]?["requestExecutionId"] is null,"unauthenticated failure claims coordinator identity");
    var expression=Load("providers/hosted/receipt-expression.json").AsObject();
    var example=Load("contracts/examples/hosted-execution-v5/receipt-accepted.json");
    var observations=new JsonObject{["contractId"]="hosted-acceptance-observations.v1",["executionId"]=example["evaluator"]!["executionId"]!.DeepClone(),
        ["executedAt"]=example["executedAt"]!.DeepClone(),["deployment"]=example["deployment"]!.DeepClone(),["invocation"]=forged.DeepClone(),
        ["coordinator"]=new JsonObject{["executionPath"]="request",["workerSlots"]=0},["checks"]=new JsonObject()};
    observations["deployment"]!["established"]=true;
    foreach(var pair in example["checks"]!.AsObject()) {
        var entry=new JsonObject{["attemptId"]=forged["attemptId"]!.DeepClone(),["runIds"]=pair.Value!["runIds"]!.DeepClone()};
        var field=pair.Key switch{"T3"=>"observed","T4"=>"measurement","T7"=>"runs",_=>"output"};
        entry[field]=(pair.Key=="T7"?pair.Value!["observed"]!["runs"]:pair.Value!["observed"])!.DeepClone();
        if(pair.Key=="T7")foreach(var run in entry["runs"]!.AsArray())foreach(var stamp in new[]{"startedAt","endedAt"})
            run![stamp+"Ms"]=DateTimeOffset.Parse(run[stamp]!.GetValue<string>()).ToUnixTimeMilliseconds();
        observations["checks"]![pair.Key]=entry;
    }
    var receipt=engine.Transform(expression,observations)!;
    File.WriteAllText(Path.Combine(repo,".tmp/projected-receipt.json"),receipt.ToJsonString());
    Check(receipt["status"]!.GetValue<string>()=="ACCEPTED","synthetic passing observations rejected");
    Check(receipt["evaluator"]!["executionId"]!.GetValue<string>()==receipt["invocation"]!["requestExecutionId"]!.GetValue<string>(),"receipt lost actual request identity");
    // Exercise the exact declared ingress program with mixed-case duplicate headers.
    var provider=Load("providers/host-provider-authority.json")["declaredProviders"]!.AsArray().Single(p=>p!["providerProfileId"]!.GetValue<string>()=="sfx-api-ingress-resolve.v2")!.AsObject();
    provider["assembly"]=typeof(HostedAcceptance).Assembly.Location;
    var ingress=DeclaredProviderResolver.ResolveProvider(provider);
    var ingressBinding=Load("authorities/host-bundle/capabilities/serve-http-request.json")["graphSource"]!["interfaceAuthority"]!["portBindings"]!.AsArray()
        .Single(b=>b!["portId"]!.GetValue<string>()=="serve-http-request-ingress")!;
    var ingressContext=context with { Configuration=new JsonObject{["binding"]=ingressBinding.DeepClone()} };
    foreach(var duplicate in new[]{false,true}) {
        var raw="POST /sfx/v1/hosted-execution/acceptance HTTP/1.1\r\nX-SFX-Acceptance-Attempt-Id: "+id+"\r\n"+
            (duplicate?"x-sfx-acceptance-attempt-id: "+id+"\r\n":"")+"\r\n{}";
        var parsed=await ingress(new JsonObject{["raw"]=raw,["requestExecutionId"]=id,["executionPath"]="request"},ingressContext,CancellationToken.None);
        Check(parsed.OutcomeValue!["headers"]!["x-sfx-acceptance-attempt-id"]!.GetValue<string>()==(duplicate?"":id),"duplicate header ambiguity");
    }
    var hostAuthority=Load("providers/host-provider-authority.json");
    var bundleProvider=hostAuthority["declaredProviders"]!.AsArray().Single(p=>p!["providerProfileId"]!.GetValue<string>()=="sfx-api-host-bundle-read")!.AsObject();
    var manifestBinding=hostAuthority["eventPorts"]![0]!["configuration"]!["graphSource"]!["interfaceAuthority"]!["portBindings"]!.AsArray()
        .Single(b=>b!["portId"]!.GetValue<string>()=="answer-host-declared-read-manifest-request")!;
    var manifestRequest=engine.Transform(manifestBinding["configuration"]!["expression"]!.AsObject(),new JsonObject())!;
    manifestRequest["path"]=Path.Combine(repo,"authorities/host-bundle/manifest.json");
    var manifestRead=await DeclaredProviderResolver.ResolveProvider(bundleProvider)(manifestRequest,context,CancellationToken.None);
    Check(manifestRead.OutcomeValue?["text"]?.GetValue<string>()==File.ReadAllText(Path.Combine(repo,"authorities/host-bundle/manifest.json")),"startup manifest byte pin failed");
    Console.WriteLine($"{passed} provider checks passed (synthetic; no deployment claim).");
} catch(Exception error) { Console.Error.WriteLine(error); throw; }
finally { try { Directory.Delete(directory,true); } catch(IOException) { Console.Error.WriteLine("Test temporary directory retained: "+directory); } }
static JsonNode LoadExternal(string path)=>HostedAcceptance.Parse(File.ReadAllText(path));
