using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using Sfx.HostedProviders;
using ScenarioKernel.Adapters.Graph;


void Check(bool passed, string message) { if (!passed) throw new Exception(message); }
string Text(JsonNode? n) => n?.GetValue<string>() ?? "";
const string principal = "565de6d4-ebcd-408b-9359-04d21dc62183";
const string artifact = "7a5e9ac6-8bcf-400c-a4f5-07314982d054";
JsonNode Prepare(string operation, params (string, string)[] fields) {
    var input = new JsonObject { ["principalId"] = principal };
    foreach (var (key,value) in fields) input[key] = value;
    return ContentProjection.PrepareRead(input, operation);
}
var list = Prepare("library", ("limit","10"));
Check(Text(list["executionTarget"]) == "read-owned-html-source", "source reader");
Check(Text(list["dispatchRequest"]!["principalId"]) == principal, "principal binding");
Check(list["dispatchRequest"]!["limit"]!.GetValue<int>() == 10, "bounded page");
Check(!list["dispatchRequest"]!["includeBody"]!.GetValue<bool>(), "library omits bodies");
foreach (var count in new[] { "0", "101", "1e2", "-1" }) {
    var refused = Prepare("library", ("limit",count));
    Check(Text(refused["executionTarget"]) == "answer-api-response", "invalid selection never queries another principal");
    Check(refused["dispatchRequest"]!["status"]!.GetValue<int>() == 400, "explicit bad selection");
}
var bytes = Encoding.UTF8.GetBytes("<!doctype html><title>Résumé</title><p>Café</p>");
var digest = "sha256:" + Convert.ToHexStringLower(SHA256.HashData(bytes));
var source = new JsonObject { ["artifactId"] = artifact, ["contentDigest"] = digest,
    ["byteLength"] = bytes.Length, ["filename"] = "page.html", ["contentBase64"] = Convert.ToBase64String(bytes) };
var body = Prepare("body", ("artifactId",artifact), ("revision",digest));
body["result"] = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "READ", ["items"] = new JsonArray(source.DeepClone()) };
var projected = await ContentProjection.ProjectRead(body, new JsonObject(), CancellationToken.None);
Check(projected["status"]!.GetValue<int>() == 200 && Text(projected["body"]!["contractId"]) == "content-bytes.v1", "JSON byte carrier");
Check(Text(projected["body"]!["base64"]) == Convert.ToBase64String(bytes), "exact bytes");
body["result"]!["items"]![0]!["artifactId"] = "00000000-0000-0000-0000-000000000001";
projected = await ContentProjection.ProjectRead(body, new JsonObject(), CancellationToken.None);
Check(Text(projected["body"]!["error"]!["code"]) == "CONTENT_REFERENCE_MISMATCH", "source must match selected address even when its own hash is valid");
body["result"]!["items"]![0]!["artifactId"] = artifact;
body["result"]!["items"]![0]!["contentBase64"] = Convert.ToBase64String(bytes) + "\n";
projected = await ContentProjection.ProjectRead(body, new JsonObject(), CancellationToken.None);
Check(Text(projected["body"]!["error"]!["code"]) == "CONTENT_ENCODING_INVALID", "canonical bounded carrier");
body["result"]!["items"]![0]!["contentBase64"] = Convert.ToBase64String(bytes);
body["result"]!["items"]![0]!["contentDigest"] = "sha256:" + new string('0',64);
projected = await ContentProjection.ProjectRead(body, new JsonObject(), CancellationToken.None);
Check(projected["status"]!.GetValue<int>() == 502, "digest mismatch");
body["result"] = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "NOT_FOUND", ["items"] = new JsonArray() };
projected = await ContentProjection.ProjectRead(body, new JsonObject(), CancellationToken.None);
Check(projected["status"]!.GetValue<int>() == 404, "no metadata for denied source");
list["result"] = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "READ", ["offset"] = 0, ["matchingCount"] = 2, ["items"] = new JsonArray(source.DeepClone()) };
projected = await ContentProjection.ProjectRead(list, new JsonObject(), CancellationToken.None);
Check(Text(projected["body"]!["coverage"]) == "partial", "unimplemented digest inventory is not complete");
var cursor = Text(projected["body"]!["nextCursor"]);
Check(Prepare("library", ("cursor",cursor))["dispatchRequest"]!["offset"]!.GetValue<int>() == 1, "cursor continuation");
var other = ContentProjection.PrepareRead(new JsonObject { ["principalId"] = "00000000-0000-0000-0000-000000000001", ["cursor"] = cursor }, "library");
Check(Text(other["executionTarget"]) == "answer-api-response", "cursor scope");
var retained = Prepare("retained-body", ("contentDigest",digest), ("revision",digest));
retained["result"] = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "NOT_FOUND", ["items"] = new JsonArray() };
var receiptRead = ContentProjection.PrepareReceipts(retained, "receipt-reader");
Check(Text(receiptRead["executionTarget"]) == "receipt-reader", "digest-only references require principal evidence");
Check(Text(receiptRead["dispatchRequest"]!["principalId"]) == principal, "receipt reader receives the bound principal");
receiptRead["result"] = new JsonObject { ["contractId"] = "principal-html-receipts.v1", ["status"] = "NOT_FOUND", ["items"] = new JsonArray() };
var denied = ContentProjection.PrepareRetainedBody(receiptRead, "retained-byte-reader");
Check(Text(denied["executionTarget"]) == "answer-api-response" && denied["terminalResponse"]!["status"]!.GetValue<int>() == 404, "no global bytes lookup without ownership evidence");
var receiptMetadata = source.DeepClone().AsObject(); receiptMetadata.Remove("contentBase64");
receiptRead["result"] = new JsonObject { ["contractId"] = "principal-html-receipts.v1", ["status"] = "READ", ["items"] = new JsonArray(receiptMetadata) };
var retainedRead = ContentProjection.PrepareRetainedBody(receiptRead, "retained-byte-reader");
Check(Text(retainedRead["executionTarget"]) == "retained-byte-reader", "authorized retained lookup");
retainedRead["result"] = new JsonObject { ["contractId"] = "retained-artifact.v1", ["status"] = "READ", ["contentDigest"] = digest, ["byteLength"] = bytes.Length, ["isText"] = true, ["text"] = Encoding.UTF8.GetString(bytes) };
projected = await ContentProjection.ProjectRead(retainedRead, new JsonObject(), CancellationToken.None);
Check(Text(projected["body"]!["base64"]) == Convert.ToBase64String(bytes), "digest receipt reconstructs exact UTF-8 original");
retainedRead["result"]!["text"] = "changed";
projected = await ContentProjection.ProjectRead(retainedRead, new JsonObject(), CancellationToken.None);
Check(projected["status"]!.GetValue<int>() == 502, "retained body must match receipt length and hash");
receiptRead["result"]!["items"]![0]!["contentBase64"] = Convert.ToBase64String(bytes);
var embedded = ContentProjection.PrepareRetainedBody(receiptRead, "retained-byte-reader");
Check(Text(embedded["executionTarget"]) == "answer-api-response", "original retained in owned receipt requires no global lookup");
projected = await ContentProjection.ProjectRead(embedded, new JsonObject(), CancellationToken.None);
Check(Text(projected["body"]!["base64"]) == Convert.ToBase64String(bytes), "owned producer receipt preserves exact original bytes");
var crossing = Prepare("body", ("artifactId",artifact), ("revision",digest));
crossing["result"] = retained["result"]!.DeepClone();
var noFallback = ContentProjection.PrepareReceipts(crossing, "receipt-reader");
noFallback["result"] = ContentProjection.Response(new JsonObject());
noFallback = ContentProjection.PrepareRetainedBody(noFallback, "retained-byte-reader");
Check(noFallback["terminalResponse"]!["status"]!.GetValue<int>() == 404, "missing artifact cannot be replaced by an unrelated digest receipt");
// Match the real generic-invocation carrier: it drops all request fields.
var root = new JsonObject { ["principalId"] = principal, ["artifactId"] = artifact, ["revision"] = digest,
    ["requestExecutionId"] = Guid.NewGuid().ToString("D"), ["executionPath"] = "request" };
var config = new JsonObject { ["operation"] = "body", ["sourceCapabilityId"] = "read-owned-html-source", ["receiptCapabilityId"] = "receipt-reader", ["retainedCapabilityId"] = "retained-byte-reader" };
var context = new GraphExecutionContext("g","c","cell","root","content", new JsonObject { ["binding"] = new JsonObject { ["configuration"] = config } }, null, null) { RootInput = root.DeepClone() };
GraphExecutionContext StepContext() => context with { RootInput = root.DeepClone() };
JsonNode Carrier(JsonNode result) => new JsonObject { ["executionTarget"] = "child", ["disposition"] = "terminated", ["result"] = result.DeepClone() };
ContentProjection.Prepare(root, context, CancellationToken.None);
var sourceResult = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "READ", ["items"] = new JsonArray(source.DeepClone()) };
var foreignRoot = root.DeepClone(); foreignRoot["requestExecutionId"] = Guid.NewGuid().ToString("D");
var foreign = context with { RootInput = foreignRoot };
var cross = ContentProjection.Receipts(Carrier(sourceResult), foreign, CancellationToken.None);
Check(Text(cross["terminalResponse"]?["body"]?["error"]?["code"]) == "CONTENT_REQUEST_CONTEXT_MISSING", "equal selectors cannot acquire another HTTP request's context");
var first = ContentProjection.Receipts(Carrier(sourceResult), StepContext(), CancellationToken.None);
Check(Text(first["selection"]!["artifactId"]) == artifact, "request selection survives the actual nested carrier shape");
var second = ContentProjection.BodyReference(Carrier(first["dispatchRequest"]!), StepContext(), CancellationToken.None);
var final = await ContentProjection.Project(Carrier(second["dispatchRequest"]!), StepContext(), CancellationToken.None);
Check(Text(final.OutcomeValue?["body"]?["base64"]) == Convert.ToBase64String(bytes), "complete native stage sequence preserves exact original bytes");
var replay = await ContentProjection.Project(Carrier(second["dispatchRequest"]!), StepContext(), CancellationToken.None);
Check(Text(replay.OutcomeValue?["body"]?["error"]?["code"]) == "CONTENT_REQUEST_CONTEXT_MISSING", "completed request continuation cannot be replayed");
using var cancelled = new CancellationTokenSource();
ContentProjection.Prepare(foreignRoot, foreign, cancelled.Token); cancelled.Cancel();
cross = ContentProjection.Receipts(Carrier(sourceResult), foreign, CancellationToken.None);
Check(Text(cross["terminalResponse"]?["body"]?["error"]?["code"]) == "CONTENT_REQUEST_CONTEXT_MISSING", "cancelled request releases its continuation");
var declaredProfile = new JsonObject { ["profileId"] = "interactive-document", ["profileVersion"] = "1", ["capabilityId"] = "producer",
    ["rendererId"] = "fixed-renderer", ["rendererDigest"] = digest, ["scriptDigest"] = digest };
var profileConfig = new JsonObject { ["interactiveProfile"] = declaredProfile };
var provenance = new JsonObject { ["capabilityId"] = "producer", ["rendererId"] = "fixed-renderer", ["rendererDigest"] = digest };
var observed = new JsonObject { ["executableInlineScriptDigests"] = new JsonArray(digest) };
Check(Text(ContentProjection.RenderingProfile(provenance, observed, profileConfig)["renderingProfileId"]) == "interactive-document", "approved producer, renderer and exact executable script qualify the interactive profile");
provenance["rendererId"] = "unreviewed";
Check(Text(ContentProjection.RenderingProfile(provenance, observed, profileConfig)["interactionStatus"]) == "scripts-disabled", "observed script hashes alone grant no permission");
provenance["rendererId"] = "fixed-renderer"; observed["executableInlineScriptDigests"]!.AsArray().Add("sha256:" + new string('0',64));
Check(Text(ContentProjection.RenderingProfile(provenance, observed, profileConfig)["renderingProfileId"]) == "article", "an additional executable script cannot inherit the approved profile");
Console.WriteLine("PASS: content request binding, bounded source reads, exact-byte projection and scoped pagination (local fixtures).");
var writeInput = new JsonObject { ["principalId"] = principal, ["requestBody"] = new JsonObject {
    ["idempotencyKey"] = "content-test-request-0001", ["siteId"] = "provider-registry", ["normalizedPath"] = "articles/first-page", ["audience"] = "public",
    ["sourceReference"] = new JsonObject { ["kind"] = "retained-digest", ["contentDigest"] = digest },
    ["contentRevision"] = digest, ["contentDigest"] = digest, ["manifestDigest"] = digest } };
var writeIntent = PublicationProjection.Intent(writeInput, "publish");
Check(Text(writeIntent["action"]) == "publish" && writeIntent["principalId"] is null, "actor comes from the authenticated route, not client intent");
writeInput["requestBody"]!["principalId"] = artifact;
try { PublicationProjection.Intent(writeInput,"publish"); throw new Exception("client actor accepted"); } catch (ArgumentException) { }
writeInput["requestBody"]!.AsObject().Remove("principalId");
foreach(var badPath in new[] { "../draft", "/root", "a//b", "a/../b", "a%2fb", "A", "draft/", "a/.hidden" })
    Check(!PublicationProjection.Path(badPath), "publication path rejects ambiguous alias: " + badPath);
writeInput["requestBody"]!["contentRevision"] = "sha256:" + new string('0',64);
try { PublicationProjection.Intent(writeInput,"publish"); throw new Exception("revision mismatch accepted"); } catch (ArgumentException) { }
var publicResponse = PublicationProjection.Answer(Carrier(new JsonObject { ["contractId"] = "published-content.v1", ["status"] = "READ", ["descriptor"] = new JsonObject {
    ["title"] = "Public title", ["contentDigest"] = digest, ["producerRunId"] = "private-run", ["sourceReference"] = new JsonObject { ["artifactId"] = artifact } } }), context, CancellationToken.None);
Check(Text(publicResponse["body"]!["descriptor"]!["title"]) == "Public title" && publicResponse["body"]!["descriptor"]!["producerRunId"] is null && publicResponse["body"]!["descriptor"]!["sourceReference"] is null,
    "public representation excludes private source and execution identifiers");
Console.WriteLine("PASS: publication intent, actor boundary, canonical paths and public metadata minimization.");
