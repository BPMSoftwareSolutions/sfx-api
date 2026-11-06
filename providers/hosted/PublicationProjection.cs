using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using ScenarioKernel.Adapters.Graph;

namespace Sfx.HostedProviders;

// Caller binding and HTTP representations. Publication authority and durable
// transactions belong to the estate's declared publication reader and writer.
public static class PublicationProjection
{
    static string Text(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";
    static JsonNode? Copy(JsonNode? n) => n?.DeepClone();
    static JsonObject Config(GraphExecutionContext c) => c.Configuration!["binding"]!["configuration"]!.AsObject();
    static bool Id(string s) => Guid.TryParseExact(s, "D", out _);
    static bool Digest(string s) => Regex.IsMatch(s, "^sha256:[a-f0-9]{64}$");
    internal static bool Path(string s) => s.Length is > 0 and <= 512 && Regex.IsMatch(s, "^[a-z0-9][a-z0-9/._-]*$") &&
        !s.Contains("..") && !s.Contains("//") && !s.Contains("/.") && !s.EndsWith('/') && !s.EndsWith('.');
    static JsonObject Error(string code, int status) => ContentProjection.Response(new JsonObject { ["error"] = code }, status);
    static JsonObject Dispatch(string capability, JsonNode request) => new() {
        ["executionTarget"] = capability, ["executionNamespace"] = "sidefx:capabilities", ["executionScenario"] = capability,
        ["inputType"] = "json", ["dispatchRequest"] = request
    };
    static JsonObject Refuse(string code, int status = 400) => Dispatch("answer-api-response", Error(code, status));
    internal static JsonObject Intent(JsonNode input, string operation)
    {
        var body = input["requestBody"] as JsonObject ?? throw new ArgumentException();
        if (!Id(Text(input["principalId"])) || !Regex.IsMatch(Text(body["idempotencyKey"]), "^[A-Za-z0-9_-]{16,100}$")) throw new ArgumentException();
        var fields = operation == "publish" ? new[] { "idempotencyKey", "siteId", "normalizedPath", "audience", "sourceReference", "contentRevision", "contentDigest", "manifestDigest" }
            : operation == "update" ? new[] { "idempotencyKey", "expectedPublicationRevision", "sourceReference", "contentRevision", "contentDigest", "manifestDigest" }
            : new[] { "idempotencyKey", "expectedPublicationRevision" };
        if (body.Any(x => !fields.Contains(x.Key))) throw new ArgumentException();
        var intent = new JsonObject { ["action"] = operation, ["idempotencyKey"] = Copy(body["idempotencyKey"]) };
        if (operation == "publish") {
            if (!Path(Text(body["normalizedPath"])) || !Regex.IsMatch(Text(body["siteId"]), "^[a-z0-9][a-z0-9-]{0,199}$") || Text(body["audience"]) != "public") throw new ArgumentException();
            intent["siteId"] = Copy(body["siteId"]); intent["normalizedPath"] = Copy(body["normalizedPath"]); intent["audience"] = "public";
        } else {
            if (!Id(Text(input["publicationId"])) || !Id(Text(body["expectedPublicationRevision"]))) throw new ArgumentException();
            intent["publicationId"] = Copy(input["publicationId"]); intent["expectedPublicationRevision"] = Copy(body["expectedPublicationRevision"]);
        }
        if (operation != "withdraw") {
            if (!Digest(Text(body["contentDigest"])) || Text(body["contentRevision"]) != Text(body["contentDigest"]) || !Digest(Text(body["manifestDigest"]))) throw new ArgumentException();
            var reference = body["sourceReference"] as JsonObject ?? throw new ArgumentException();
            var kind = Text(reference["kind"]);
            if (kind == "owned-artifact" && Id(Text(reference["artifactId"])) && reference.Count == 2)
                intent["sourceReference"] = new JsonObject { ["kind"] = kind, ["artifactId"] = Copy(reference["artifactId"]) };
            else if (kind == "retained-digest" && Text(reference["contentDigest"]) == Text(body["contentDigest"]) && reference.Count == 2)
                intent["sourceReference"] = new JsonObject { ["kind"] = kind, ["contentDigest"] = Copy(reference["contentDigest"]) };
            else throw new ArgumentException();
            foreach (var key in new[] { "contentRevision", "contentDigest", "manifestDigest" }) intent[key] = Copy(body[key]);
        }
        return intent;
    }
    public static JsonNode Prepare(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested(); var config = Config(context); var operation = Text(config["operation"]);
        if (operation == "withdraw") {
            if (Text(context.RootInput?["executionPath"]) != "request" || !Id(Text(context.RootInput?["requestExecutionId"]))) return Refuse("CONTENT_REQUEST_CONTEXT_MISSING", 502);
            try {
                var intent = Intent(input, operation); var request = intent.DeepClone().AsObject();
                request["intent"] = intent; request["principalId"] = Copy(input["principalId"]);
                return Dispatch(Text(config["writerCapabilityId"]), request);
            } catch (ArgumentException) { return Refuse("CONTENT_WRITE_INVALID"); }
        }
        if (operation != "public" && !Id(Text(input["principalId"]))) return Refuse("CALLER_REQUIRED", 401);
        var selection = new JsonObject { ["operation"] = operation, ["principalId"] = Copy(input["principalId"]) };
        if (operation is "publication" or "history") {
            if (!Id(Text(input["publicationId"]))) return Refuse("INVALID_CONTENT_SELECTION");
            selection["publicationId"] = Copy(input["publicationId"]);
        }
        if (operation == "request") {
            if (!Regex.IsMatch(Text(input["idempotencyKey"]), "^[A-Za-z0-9_-]{16,100}$")) return Refuse("INVALID_CONTENT_SELECTION");
            selection["idempotencyKey"] = Copy(input["idempotencyKey"]);
        }
        if (operation == "public") {
            var path = Text(input["path"]);
            if (!Id(Text(input["targetId"])) || path.Length is < 1 or > 2048 || Regex.IsMatch(path, "[\\\\%\u0000-\u001f\u007f?#]") || path.Split('/').Any(x => x is "" or "." or "..")) return Refuse("CONTENT_NOT_FOUND_OR_DENIED", 404);
            selection["targetId"] = Copy(input["targetId"]); selection["path"] = Copy(input["path"]);
        }
        foreach (var key in new[] { "offset", "limit" }) if (Text(input[key]) != "") {
            if (!int.TryParse(Text(input[key]), out var n) || n < (key == "limit" ? 1 : 0) || n > (key == "limit" ? 100 : 100000)) return Refuse("INVALID_CONTENT_SELECTION");
            selection[key] = n;
        }
        return Dispatch(Text(config["readerCapabilityId"]), selection);
    }
    public static JsonNode Answer(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested(); var body = input["result"];
        if (Text(body?["contractId"]) == "api-response.v1") return Copy(body)!;
        if (body is not JsonObject) return Error("CONTENT_PUBLICATION_SERVICE_UNAVAILABLE", 502);
        if (Text(body["contractId"]) == "content-write-outcome.v1") {
            var status = body["status"]?.GetValue<int>() ?? 502;
            return ContentProjection.Response(body.DeepClone(), status is >= 200 and <= 599 ? status : 502);
        }
        if (Text(body["status"]) == "NOT_FOUND") return Error("CONTENT_NOT_FOUND_OR_DENIED", 404);
        if (Text(body["status"]) != "READ") return Error("CONTENT_PUBLICATION_SERVICE_UNAVAILABLE", 502);
        var result = body.DeepClone();
        if (Text(result["contractId"]) == "published-content.v1" && result["descriptor"] is JsonObject descriptor) {
            var publicFields = new[] { "contentRevision", "contentDigest", "byteLength", "filename", "title", "language", "mediaType", "encoding", "dependencyManifest", "renderingProfileId", "renderingProfileVersion", "scriptDigests" };
            foreach (var key in descriptor.Select(x => x.Key).Where(x => !publicFields.Contains(x)).ToArray()) descriptor.Remove(key);
        }
        return ContentProjection.Response(result);
    }
}
