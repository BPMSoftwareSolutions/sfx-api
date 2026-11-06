using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Runtime.CompilerServices;
using System.Collections.Concurrent;
using ScenarioKernel.Adapters.Graph;

[assembly: InternalsVisibleTo("ContentTests")]

namespace Sfx.HostedProviders;

// HTTP representation mechanics. Estate reads retain ownership authority;
// this provider cannot read a database, admit a run or publish content.
public static class ContentProjection
{
    // The generic nested-invocation carrier returns only its result. Keep this
    // scheduler clones root input for every cell. The HTTP host's random request
    // ID survives those copies; route bindings never accept it from the caller.
    // Bound concurrent state, lifetime and stage consumption independently.
    sealed class Continuation(JsonNode frame, string principal) {
        public JsonNode Frame = frame.DeepClone();
        public string Principal = principal;
        public int Stage = 1;
        public long Until = Environment.TickCount64 + 195000;
        public CancellationTokenRegistration Cancellation;
    }
    static readonly ConcurrentDictionary<string, Continuation> Continuations = new(StringComparer.Ordinal);
    static readonly Timer Expiry = new(_ => {
        foreach (var pair in Continuations)
            if (Environment.TickCount64 >= pair.Value.Until) Remove(pair.Key, pair.Value);
    }, null, TimeSpan.FromSeconds(15), TimeSpan.FromSeconds(15));
    static void Remove(string key, Continuation state) {
        if (Continuations.TryRemove(new KeyValuePair<string, Continuation>(key, state))) state.Cancellation.Unregister();
    }
    static string RequestKey(GraphExecutionContext context) =>
        Text(context.RootInput?["executionPath"]) == "request" &&
        Guid.TryParseExact(Text(context.RootInput?["requestExecutionId"]), "D", out var id) ? id.ToString("D") : "";

    static JsonNode Continue(JsonNode carrier, GraphExecutionContext context, int stage, Func<JsonNode, JsonNode>? next)
    {
        var key = RequestKey(context);
        if (key == "" || !Continuations.TryGetValue(key, out var state))
            return Terminal(carrier, Error("CONTENT_REQUEST_CONTEXT_MISSING", 502));
        lock (state) {
            if (state.Stage != stage || state.Principal != Text(context.RootInput?["principalId"]) || Environment.TickCount64 >= state.Until) {
                Remove(key, state);
                return Terminal(carrier, Error("CONTENT_REQUEST_CONTEXT_EXPIRED", 502));
            }
            var frame = state.Frame.DeepClone(); frame["result"] = Copy(carrier["result"]);
            state.Stage++;
            if (next is null) { Remove(key, state); return frame; }
            try { var prepared = next(frame); state.Frame = prepared.DeepClone(); return prepared; }
            catch { Remove(key, state); throw; }
        }
    }
    static string Text(JsonNode? value) => value is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";
    static JsonNode? Copy(JsonNode? value) => value?.DeepClone();
    static string Hash(byte[] bytes) => "sha256:" + Convert.ToHexStringLower(SHA256.HashData(bytes));
    static readonly Regex Digest = new("^sha256:[a-f0-9]{64}$", RegexOptions.CultureInvariant);
    static JsonObject Config(GraphExecutionContext context) => context.Configuration!["binding"]!["configuration"]!.AsObject();
    public static JsonObject Response(JsonNode body, int status = 200) => new() {
        ["contractId"] = "api-response.v1", ["status"] = status,
        ["headers"] = new JsonObject {
            ["content-type"] = "application/json; charset=utf-8", ["cache-control"] = "no-store",
            ["x-content-type-options"] = "nosniff", ["x-robots-tag"] = "noindex, nofollow"
        }, ["body"] = body
    };
    static JsonObject Error(string code, int status) => Response(new JsonObject { ["error"] = new JsonObject { ["code"] = code } }, status);

    public static JsonNode Prepare(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var operation = Text(Config(context)["operation"]);
        JsonNode frame;
        if (operation is "publish" or "update") {
            try {
                var intent = PublicationProjection.Intent(input, operation);
                var reference = intent["sourceReference"]!;
                var selection = new JsonObject { ["principalId"] = Copy(input["principalId"]), ["contentDigest"] = Copy(intent["contentDigest"]),
                    ["revision"] = Copy(intent["contentRevision"]), ["artifactId"] = Copy(reference["artifactId"]) };
                frame = PrepareRead(selection, Text(reference["kind"]) == "owned-artifact" ? "revision" : "resolve", Text(Config(context)["sourceCapabilityId"]));
                frame["publicationIntent"] = intent;
            } catch (ArgumentException) { frame = Terminal(input, Error("CONTENT_WRITE_INVALID", 400)); }
        } else frame = PrepareRead(input, operation, Text(Config(context)["sourceCapabilityId"]));
        var key = RequestKey(context);
        if (key == "" || key != Text(input["requestExecutionId"])) return Terminal(frame, Error("CONTENT_REQUEST_CONTEXT_MISSING", 502));
        if (Continuations.Count >= 64) return Terminal(frame, Error("CONTENT_REQUEST_CAPACITY_EXCEEDED", 503));
        var state = new Continuation(frame, Text(input["principalId"]));
        if (!Continuations.TryAdd(key, state)) return Terminal(frame, Error("CONTENT_REQUEST_CONTEXT_REUSED", 502));
        state.Cancellation = token.Register(() => Remove(key, state));
        if (token.IsCancellationRequested) { Remove(key, state); token.ThrowIfCancellationRequested(); }
        return frame;
    }
    public static JsonNode PrepareRead(JsonNode input, string operation, string sourceCapabilityId = "read-owned-html-source")
    {
        JsonObject Refuse(string code, int status) => new() {
            ["operation"] = operation, ["executionTarget"] = "answer-api-response", ["executionNamespace"] = "sidefx:capabilities",
            ["executionScenario"] = "answer-api-response", ["inputType"] = "json", ["dispatchRequest"] = Error(code, status)
        };
        if (!Guid.TryParseExact(Text(input["principalId"]), "D", out var principal)) return Refuse("CALLER_REQUIRED", 401);
        if (!new[] { "library", "revision", "resolve", "body", "retained-body", "asset", "retained-asset" }.Contains(operation)) return Refuse("CONTENT_OPERATION_INVALID", 400);
        var request = new JsonObject { ["principalId"] = principal.ToString("D") };
        foreach (var name in new[] { "artifactId", "collectionId" }) {
            var value = Text(input[name]);
            if (value == "") continue;
            if (!Guid.TryParseExact(value, "D", out var id)) return Refuse("INVALID_CONTENT_SELECTION", 400);
            request[name] = id.ToString("D");
        }
        var contentDigest = Text(input["contentDigest"]); var revision = Text(input["revision"]);
        if (contentDigest != "" && !Digest.IsMatch(contentDigest) || revision != "" && !Digest.IsMatch(revision)) return Refuse("INVALID_CONTENT_SELECTION", 400);
        if (contentDigest != "" && revision != "" && contentDigest != revision) return Refuse("CONTENT_REFERENCE_MISMATCH", 409);
        if (contentDigest != "" || revision != "") request["contentDigest"] = contentDigest != "" ? contentDigest : revision;
        if (new[] { "revision", "body", "asset" }.Contains(operation) && request["artifactId"] is null ||
            new[] { "resolve", "retained-body", "retained-asset" }.Contains(operation) && contentDigest == "") return Refuse("INVALID_CONTENT_SELECTION", 400);
        if (new[] { "body", "retained-body", "asset", "retained-asset" }.Contains(operation) && revision == "") return Refuse("INVALID_CONTENT_SELECTION", 400);
        if (operation is "asset" or "retained-asset") {
            var path = Text(input["path"]);
            if (path.Length is < 1 or > 512 || path.Any(c => char.IsControl(c) || c is '\\' or '%' or '?' or '#') ||
                path.Split('/').Any(part => part is "" or "." or "..")) return Refuse("INVALID_CONTENT_SELECTION", 400);
            request["assetPath"] = path;
        }
        var limit = 100; var offset = 0; var scope = Hash(Encoding.UTF8.GetBytes(principal + "\n" + Text(request["collectionId"])))[7..23];
        if (operation == "library") {
            if (Text(input["mediaType"]) is not ("" or "text/html")) return Refuse("UNSUPPORTED_CONTENT_TYPE", 400);
            var count = Text(input["limit"]);
            if (count != "" && (!int.TryParse(count, NumberStyles.None, CultureInfo.InvariantCulture, out limit) || limit is < 1 or > 100)) return Refuse("INVALID_CONTENT_SELECTION", 400);
            var cursor = Text(input["cursor"]);
            if (cursor != "") {
                var parts = cursor.Split('.');
                if (parts.Length != 3 || parts[0] != "v1" || parts[1] != scope || !int.TryParse(parts[2], NumberStyles.None, CultureInfo.InvariantCulture, out offset) || offset is < 0 or > 100000)
                    return Refuse("CONTENT_CURSOR_INVALID", 400);
            }
        }
        request["limit"] = operation == "library" ? limit : 1;
        request["offset"] = offset; request["includeBody"] = operation != "library";
        request["includeAssets"] = operation is "revision" or "resolve" or "asset" or "retained-asset";
        return new JsonObject {
            ["operation"] = operation, ["cursorScope"] = scope, ["selection"] = Copy(request),
            ["executionTarget"] = sourceCapabilityId, ["executionNamespace"] = "sidefx:capabilities",
            ["executionScenario"] = sourceCapabilityId, ["inputType"] = "json", ["dispatchRequest"] = request
        };
    }

    static JsonObject Dispatch(JsonNode input, string capability, JsonNode request)
    {
        var next = input.DeepClone().AsObject(); next.Remove("result");
        next["executionTarget"] = capability; next["executionNamespace"] = "sidefx:capabilities";
        next["executionScenario"] = capability; next["inputType"] = "json"; next["dispatchRequest"] = Copy(request);
        return next;
    }
    static JsonObject Terminal(JsonNode input, JsonNode response)
    {
        var next = Dispatch(input, "answer-api-response", response); next["terminalResponse"] = Copy(response); return next;
    }
    static JsonObject Skip(JsonNode input) => Dispatch(input, "answer-api-response", Response(new JsonObject { ["contractId"] = "content-stage-skipped.v1" }));

    public static JsonNode Receipts(JsonNode input, GraphExecutionContext context, CancellationToken token) =>
        Continue(input, context, 1, frame => PrepareReceipts(frame, Text(Config(context)["receiptCapabilityId"])));
    internal static JsonNode PrepareReceipts(JsonNode input, string receiptCapabilityId)
    {
        var owned = input["result"];
        if (Text(owned?["contractId"]) == "api-response.v1") return Terminal(input, owned!);
        if (Text(owned?["contractId"]) != "owned-html-source.v1" || Text(owned?["status"]) is not ("READ" or "NOT_FOUND") || owned?["items"] is not JsonArray items)
            return Terminal(input, Error("CONTENT_SOURCE_UNAVAILABLE", 502));
        var selection = input["selection"]!; var operation = Text(input["operation"]);
        var next = input.DeepClone().AsObject(); next["ownedResult"] = Copy(owned);
        // A collection owns artifact addresses. Retained producer receipts have no collection membership.
        if (Text(selection["collectionId"]) != "" || operation is "revision" or "body" or "asset" || operation != "library" && items.Count != 0) {
            next["receiptsResult"] = new JsonObject { ["contractId"] = "principal-html-receipts.v1", ["status"] = "READ", ["matchingCount"] = 0, ["items"] = new JsonArray() };
            return Skip(next);
        }
        var request = new JsonObject { ["principalId"] = Copy(selection["principalId"]), ["limit"] = 1, ["offset"] = 0 };
        request["includeBody"] = operation != "library";
        if (operation == "library") {
            var total = owned!["matchingCount"]!.GetValue<int>(); var offset = selection["offset"]!.GetValue<int>();
            request["offset"] = Math.Max(0, offset - total);
            request["limit"] = Math.Max(1, selection["limit"]!.GetValue<int>() - items.Count);
        } else request["contentDigest"] = Copy(selection["contentDigest"]);
        return Dispatch(next, receiptCapabilityId, request);
    }

    public static JsonNode BodyReference(JsonNode input, GraphExecutionContext context, CancellationToken token) =>
        Continue(input, context, 2, frame => PrepareRetainedBody(frame, Text(Config(context)["retainedCapabilityId"])));
    internal static JsonNode PrepareRetainedBody(JsonNode input, string retainedCapabilityId)
    {
        if (input["terminalResponse"] is JsonNode terminal) return Terminal(input, terminal);
        var receipts = input["receiptsResult"] ?? input["result"];
        if (Text(receipts?["contractId"]) != "principal-html-receipts.v1" || Text(receipts?["status"]) is not ("READ" or "NOT_FOUND") || receipts?["items"] is not JsonArray items)
            return Terminal(input, Error("CONTENT_RECEIPTS_UNAVAILABLE", 502));
        var next = input.DeepClone().AsObject(); next["receiptsResult"] = Copy(receipts);
        if (Text(input["operation"]) == "library" || input["ownedResult"]?["items"] is JsonArray owned && owned.Count != 0) return Skip(next);
        if (Text(input["operation"]) is not ("resolve" or "retained-body" or "retained-asset") || items.Count != 1)
            return Terminal(next, Error("CONTENT_NOT_FOUND_OR_DENIED", 404));
        var receipt = items[0]!;
        if (!Digest.IsMatch(Text(receipt["contentDigest"])) || Text(receipt["contentDigest"]) != Text(input["selection"]?["contentDigest"]) ||
            receipt["byteLength"] is not JsonValue size || !size.TryGetValue<int>(out var length) || length is < 1 or > 8388608)
            return Terminal(next, Error("CONTENT_RECEIPT_INVALID", 502));
        next["retainedReceipt"] = Copy(receipt);
        // Some producers retain the original HTML in the owned completion
        // receipt rather than the separate content-object store.
        if (receipt["contentBase64"] is JsonValue) return Skip(next);
        return Dispatch(next, retainedCapabilityId, new JsonObject { ["contentDigest"] = Copy(receipt["contentDigest"]) });
    }

    public static JsonObject Summary(JsonNode source, bool retained = false) => new() {
        ["contractId"] = "content-summary.v1", ["sourceReference"] = retained
            ? new JsonObject { ["kind"] = "retained-digest", ["contentDigest"] = Copy(source["contentDigest"]) }
            : new JsonObject { ["kind"] = "owned-artifact", ["artifactId"] = Copy(source["artifactId"]) },
        ["contentRevision"] = Copy(source["contentDigest"]), ["contentDigest"] = Copy(source["contentDigest"]),
        ["byteLength"] = Copy(source["byteLength"]), ["filename"] = Copy(source["filename"]),
        ["title"] = Copy(source["filename"]), ["mediaType"] = "text/html", ["encoding"] = "utf-8",
        ["collectionId"] = Copy(source["collectionId"]), ["updatedAt"] = Copy(source["producedAt"]),
        ["producerCapabilityId"] = Copy(source["capabilityId"]), ["producerRunId"] = Copy(source["runId"])
    };

    public static async Task<GraphProviderOutcome> Project(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        var frame = Continue(input, context, 3, null);
        try { return new(await ProjectRead(frame, Config(context), token)); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { return new(Error("CONTENT_ANALYSIS_TIMEOUT", 503)); }
        catch (InvalidDataException) { return new(Error("CONTENT_INTEGRITY_FAILURE", 502)); }
        catch (IOException) { return new(Error("CONTENT_ANALYSIS_UNAVAILABLE", 503)); }
    }

    public static async Task<GraphProviderOutcome> PreparePublication(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        var frame = Continue(input, context, 3, null);
        JsonNode response;
        try { response = await ProjectRead(frame, Config(context), token); }
        catch (Exception e) when (e is IOException or InvalidDataException or OperationCanceledException && !token.IsCancellationRequested) {
            return new(Terminal(frame, Error("CONTENT_PACKAGE_UNAVAILABLE", 503)));
        }
        if (response["status"]?.GetValue<int>() != 200 || frame["publicationIntent"] is not JsonObject intent)
            return new(Terminal(frame, response));
        var package = response["body"]!; var descriptor = package["descriptor"]!;
        if (Text(descriptor["dependencyStatus"]) != "COMPLETE") return new(Terminal(frame, Error("CONTENT_DEPENDENCIES_INCOMPLETE", 422)));
        if (Text(descriptor["contentDigest"]) != Text(intent["contentDigest"]) || Text(descriptor["dependencyManifest"]?["manifestDigest"]) != Text(intent["manifestDigest"]))
            return new(Terminal(frame, Error("CONTENT_REVISION_CHANGED", 409)));
        var request = intent.DeepClone().AsObject(); request["intent"] = Copy(intent);
        request["principalId"] = Copy(frame["selection"]!["principalId"]); request["package"] = Copy(package);
        return new(Dispatch(frame, Text(Config(context)["writerCapabilityId"]), request));
    }

    internal static async Task<JsonNode> ProjectRead(JsonNode input, JsonObject configuration, CancellationToken token)
    {
        if (input["terminalResponse"] is JsonNode terminal) return Copy(terminal)!;
        var result = input["ownedResult"] ?? input["result"];
        if (input["retainedReceipt"] is JsonNode receipt) {
            var receiptSource = receipt.DeepClone().AsObject();
            if (receiptSource["contentBase64"] is null) {
                var retained = input["result"];
                if (Text(retained?["contractId"]) != "retained-artifact.v1" || Text(retained?["status"]) != "READ" ||
                    Text(retained?["contentDigest"]) != Text(receipt["contentDigest"]) || retained?["byteLength"]?.ToJsonString() != receipt["byteLength"]?.ToJsonString())
                    return Error("CONTENT_RETAINED_BYTES_UNAVAILABLE", 502);
                receiptSource["contentBase64"] = retained!["isText"]?.GetValue<bool>() == true
                    ? Convert.ToBase64String(Encoding.UTF8.GetBytes(Text(retained["text"]))) : Copy(retained["contentBase64"]);
            }
            result = new JsonObject { ["contractId"] = "owned-html-source.v1", ["status"] = "READ", ["items"] = new JsonArray(receiptSource) };
        }
        if (Text(result?["contractId"]) == "api-response.v1") return Copy(result)!;
        if (Text(result?["contractId"]) != "owned-html-source.v1") return Error("CONTENT_SOURCE_UNAVAILABLE", 502);
        if (Text(result!["status"]) == "NOT_FOUND") return Error("CONTENT_NOT_FOUND_OR_DENIED", 404);
        if (Text(result["status"]) != "READ" || result["items"] is not JsonArray items) return Error("CONTENT_SOURCE_UNAVAILABLE", 502);
        var operation = Text(input["operation"]);
        if (operation == "library") {
            var offset = result["offset"]!.GetValue<int>(); var total = result["matchingCount"]!.GetValue<int>();
            var summaries = new JsonArray(); foreach (var item in items) summaries.Add(Summary(item!));
            var receiptResult = input["receiptsResult"];
            if (receiptResult?["items"] is JsonArray retainedItems) {
                total += receiptResult["matchingCount"]!.GetValue<int>();
                var limit = input["selection"]!["limit"]!.GetValue<int>();
                foreach (var item in retainedItems.Take(Math.Max(0, limit - summaries.Count))) summaries.Add(Summary(item!, true));
            }
            return Response(new JsonObject {
                ["contractId"] = "content-library.v1", ["items"] = summaries, ["coverage"] = "partial",
                ["nextCursor"] = offset + summaries.Count < total ? "v1." + Text(input["cursorScope"]) + "." + (offset + summaries.Count) : null,
                ["matchingCount"] = total, ["coverageDetail"] = new JsonObject {
                    ["ownedArtifacts"] = "read", ["retainedDigests"] = receiptResult is null ? "required-service-work" : "completed-root-producer-runs",
                    ["nestedProducerReceipts"] = "required-service-work", ["pagination"] = "owned-addresses-then-retained-receipts; current reads, no snapshot guarantee" }
            });
        }
        if (items.Count != 1) return Error("CONTENT_NOT_FOUND_OR_DENIED", 404);
        var source = items[0]!;
        var selection = input["selection"] ?? input["dispatchRequest"];
        if (selection is not JsonObject ||
            Text(selection["artifactId"]) is var selectedArtifact && selectedArtifact != "" && selectedArtifact != Text(source["artifactId"]) ||
            Text(selection?["contentDigest"]) is var selectedDigest && selectedDigest != "" && selectedDigest != Text(source["contentDigest"]))
            return Error("CONTENT_REFERENCE_MISMATCH", 502);
        var bodyError = Text(source["bodyError"]);
        if (bodyError != "") return Error(bodyError, bodyError == "CONTENT_LIMIT_EXCEEDED" ? 413 : 502);
        if (source["byteLength"] is not JsonValue lengthNode || !lengthNode.TryGetValue<int>(out var length) || length is < 1 or > 8388608)
            return Error("CONTENT_LIMIT_EXCEEDED", 413);
        var encoded = Text(source["contentBase64"]);
        if (encoded.Length != ((length + 2) / 3) * 4) return Error("CONTENT_ENCODING_INVALID", 502);
        byte[] bytes;
        try { bytes = Convert.FromBase64String(encoded); }
        catch (FormatException) { return Error("CONTENT_ENCODING_INVALID", 502); }
        if (Convert.ToBase64String(bytes) != encoded) return Error("CONTENT_ENCODING_INVALID", 502);
        if (bytes.Length != length || Hash(bytes) != Text(source["contentDigest"])) return Error("CONTENT_INTEGRITY_FAILURE", 502);
        try { _ = new UTF8Encoding(false, true).GetString(bytes); } catch (DecoderFallbackException) { return Error("CONTENT_ENCODING_INVALID", 502); }
        if (operation is "body" or "retained-body") return Response(new JsonObject {
            ["contractId"] = "content-bytes.v1", ["contentDigest"] = Copy(source["contentDigest"]), ["byteLength"] = bytes.Length,
            ["mediaType"] = "text/html", ["encoding"] = "utf-8", ["base64"] = Convert.ToBase64String(bytes)
        });
        if (Text(source["assetError"]) is var assetError && assetError != "")
            return Error(assetError, assetError.Contains("LIMIT", StringComparison.Ordinal) ? 413 : 422);
        var assets = source["assets"] as JsonArray ?? new JsonArray();
        var analysisInput = new JsonObject { ["filename"] = Copy(source["filename"]), ["html"] = new JsonObject {
            ["contentDigest"] = Copy(source["contentDigest"]), ["byteLength"] = bytes.Length, ["base64"] = Convert.ToBase64String(bytes)
        }, ["assets"] = Copy(assets) };
        var analysis = await Analyze(analysisInput, configuration, token);
        if (Text(analysis["status"]) == "REFUSED" && Regex.IsMatch(Text(analysis["code"]), "^CONTENT_[A-Z_]{1,70}$"))
            return Error(Text(analysis["code"]), Text(analysis["code"]).Contains("LIMIT", StringComparison.Ordinal) ? 413 : 422);
        if (Text(analysis["contractId"]) != "content-package-analysis.v1" || Text(analysis["status"]) is not ("COMPLETE" or "INCOMPLETE") ||
            Text(analysis["contentDigest"]) != Hash(bytes)) return Error("CONTENT_ANALYSIS_UNAVAILABLE", 503);
        var entries = analysis["dependencyManifest"]!["entries"]!.AsArray();
        var included = new JsonArray();
        foreach (var entry in entries) {
            var asset = assets.SingleOrDefault(x => Text(x?["path"]) == Text(entry?["path"]));
            if (asset is null) return Error("CONTENT_DEPENDENCY_NOT_DECLARED", 404);
            var carrier = AssetBytes(asset);
            foreach (var field in new[] { "contentDigest", "byteLength", "mediaType" })
                if (entry![field]?.ToJsonString() != carrier[field]?.ToJsonString()) throw new InvalidDataException();
            var retained = asset.DeepClone(); included.Add(retained);
        }
        if (operation is "asset" or "retained-asset") {
            if (Text(analysis["status"]) != "COMPLETE") return Error("CONTENT_DEPENDENCIES_INCOMPLETE", 422);
            var asset = included.SingleOrDefault(x => Text(x?["path"]) == Text(selection?["assetPath"]));
            return asset is null ? Error("CONTENT_DEPENDENCY_NOT_DECLARED", 404) : Response(AssetBytes(asset));
        }
        var descriptor = Summary(source, operation == "resolve"); descriptor["contractId"] = "content-revision.v1";
        descriptor["encodedFilename"] = Uri.EscapeDataString(Text(source["filename"]));
        if (Text(analysis["title"]) != "") descriptor["title"] = Copy(analysis["title"]);
        descriptor["language"] = Copy(analysis["language"]); descriptor["dependencyManifest"] = Copy(analysis["dependencyManifest"]);
        descriptor["dependencyStatus"] = Copy(analysis["status"]); descriptor["unresolvedDependencies"] = Copy(analysis["unresolved"]);
        descriptor["navigationReferences"] = Copy(analysis["navigation"]); descriptor["assetScope"] = Copy(source["assetScope"]);
        var profile = RenderingProfile(source, analysis, configuration);
        foreach (var entry in profile) descriptor[entry.Key] = Copy(entry.Value);
        var ready = Text(analysis["status"]) == "COMPLETE";
        descriptor["availability"] = new JsonObject {
            ["download"] = new JsonObject { ["available"] = true },
            ["preview"] = new JsonObject { ["available"] = ready, ["reason"] = ready ? null : "CONTENT_DEPENDENCIES_INCOMPLETE" },
            ["publish"] = new JsonObject { ["available"] = ready, ["reason"] = ready ? null : "CONTENT_DEPENDENCIES_INCOMPLETE" }
        };
        if (input["publicationIntent"] is JsonObject) return Response(new JsonObject {
            ["descriptor"] = descriptor, ["base64"] = Convert.ToBase64String(bytes), ["assets"] = included
        });
        return Response(descriptor);
    }

    internal static JsonObject AssetBytes(JsonNode asset)
    {
        if (asset["byteLength"] is not JsonValue size || !size.TryGetValue<int>(out var length) || length is < 1 or > 8388608) throw new InvalidDataException();
        var encoded = Text(asset["base64"]); byte[] bytes;
        try { bytes = Convert.FromBase64String(encoded); } catch (FormatException) { throw new InvalidDataException(); }
        if (encoded.Length != ((length + 2) / 3) * 4 || Convert.ToBase64String(bytes) != encoded || bytes.Length != length || Hash(bytes) != Text(asset["contentDigest"])) throw new InvalidDataException();
        var media = Text(asset["mediaType"]);
        if (!new[] { "text/css", "image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml", "font/woff", "font/woff2", "audio/mpeg", "video/mp4" }.Contains(media)) throw new InvalidDataException();
        var textual = media is "text/css" or "image/svg+xml";
        if (textual) { try { _ = new UTF8Encoding(false, true).GetString(bytes); } catch (DecoderFallbackException) { throw new InvalidDataException(); } }
        return new JsonObject { ["contractId"] = "content-bytes.v1", ["contentDigest"] = Copy(asset["contentDigest"]), ["byteLength"] = length,
            ["mediaType"] = media, ["encoding"] = textual ? "utf-8" : "binary", ["base64"] = encoded };
    }

    internal static JsonObject RenderingProfile(JsonNode source, JsonNode analysis, JsonObject configuration)
    {
        var declared = configuration["interactiveProfile"];
        var scripts = analysis["executableInlineScriptDigests"] as JsonArray ?? new JsonArray();
        var interactive = declared is JsonObject && analysis["externalScripts"]?.GetValue<int>() is not > 0 &&
            Text(source["capabilityId"]) == Text(declared["capabilityId"]) &&
            Text(source["rendererId"]) == Text(declared["rendererId"]) &&
            Digest.IsMatch(Text(source["rendererDigest"])) && Text(source["rendererDigest"]) == Text(declared["rendererDigest"]) &&
            scripts.Count == 1 && Digest.IsMatch(Text(scripts[0])) && Text(scripts[0]) == Text(declared["scriptDigest"]);
        var articleVersion = analysis["dependencyManifest"]?["entries"] is JsonArray entries && entries.Count > 0 ? "2" : "1";
        return new JsonObject {
            ["renderingProfileId"] = interactive ? Text(declared!["profileId"]) : "article",
            ["renderingProfileVersion"] = interactive ? Text(declared!["profileVersion"]) : articleVersion,
            ["renderingProfile"] = interactive ? "interactive-document.v1" : "static-article.v" + articleVersion,
            ["interactionStatus"] = interactive ? "read-only-interactions" : scripts.Count == 0 && analysis["externalScripts"]?.GetValue<int>() is not > 0 ? "static" : "scripts-disabled",
            ["scriptDigests"] = interactive ? Copy(scripts) : new JsonArray(),
            ["rendererId"] = Copy(source["rendererId"]), ["rendererDigest"] = Copy(source["rendererDigest"])
        };
    }

    internal static async Task<JsonNode> Analyze(JsonNode request, JsonObject configuration, CancellationToken token)
    {
        using var bound = CancellationTokenSource.CreateLinkedTokenSource(token); bound.CancelAfter(TimeSpan.FromSeconds(30));
        using var child = new Process { StartInfo = new ProcessStartInfo {
            FileName = Text(configuration["python"]), UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardInputEncoding = new UTF8Encoding(false), StandardOutputEncoding = new UTF8Encoding(false)
        } };
        child.StartInfo.ArgumentList.Add("-I"); child.StartInfo.ArgumentList.Add("-S"); child.StartInfo.ArgumentList.Add("-B");
        child.StartInfo.ArgumentList.Add(Text(configuration["analyzer"])); child.StartInfo.Environment.Clear();
        try {
            if (!child.Start()) throw new IOException();
            async Task<string> ReadBounded(StreamReader reader) {
                var text = new StringBuilder(); var buffer = new char[4096]; int n;
                while ((n = await reader.ReadAsync(buffer, bound.Token)) != 0) {
                    if (text.Length + n > 2 * 1024 * 1024) throw new IOException("CONTENT_ANALYSIS_LIMIT_EXCEEDED");
                    text.Append(buffer, 0, n);
                }
                return text.ToString();
            }
            var output = ReadBounded(child.StandardOutput); var error = ReadBounded(child.StandardError);
            await child.StandardInput.WriteAsync(request.ToJsonString().AsMemory(), bound.Token); child.StandardInput.Close();
            await child.WaitForExitAsync(bound.Token);
            var received = await output; _ = await error;
            if (child.ExitCode != 0) throw new IOException();
            return HostedAcceptance.Parse(received);
        } finally { try { if (!child.HasExited) child.Kill(entireProcessTree: true); } catch (InvalidOperationException) { } }
    }
}
