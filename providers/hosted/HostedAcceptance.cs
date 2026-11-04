using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using ScenarioKernel.Adapters.Graph;
using ScenarioKernel.Adapters.Consumer;

namespace Sfx.HostedProviders;

// Host-owned implementations below the provider-profile boundary. All identities,
// paths, the measurement plan and the receipt expression are port configuration.
public static class HostedAcceptance
{
    static readonly Regex Uuid = new("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$");
    static string Text(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : "";
    static JsonObject Config(GraphExecutionContext c) => c.Configuration!["binding"]!["configuration"]!.AsObject();
    static string Hash(byte[] bytes) => "sha256:" + Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    static JsonNode Clone(JsonNode? node) => node!.DeepClone();
    public static JsonNode Parse(string text)
    {
        using var document = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 128 });
        void Check(JsonElement node)
        {
            if (node.ValueKind == JsonValueKind.Object) {
                var keys = new HashSet<string>(StringComparer.Ordinal);
                foreach (var member in node.EnumerateObject()) {
                    if (!keys.Add(member.Name)) throw new InvalidDataException("Duplicate JSON key");
                    Check(member.Value);
                }
            } else if (node.ValueKind == JsonValueKind.Array) foreach (var item in node.EnumerateArray()) Check(item);
        }
        Check(document.RootElement); return JsonNode.Parse(text)!;
    }
    public static JsonObject Error(string attempt, string stage, string code, int status, string? execution = null) => new() {
        ["contractId"] = "hosted-execution-invocation-error.v1", ["attemptId"] = attempt,
        ["outcome"] = code == "ACCEPTANCE_TRANSPORT_UNCERTAIN" ? "UNKNOWN" : "FAILED", ["stage"] = stage, ["code"] = code,
        ["httpStatus"] = status, ["requestExecutionId"] = stage is "caller" or "discovery" ? null : execution,
        ["message"] = "The hosted acceptance invocation could not complete: " + code + ".",
        ["automaticRetry"] = false, ["receipt"] = null
    };
    static bool Caller(JsonNode input, JsonObject config) => Text(input["caller"]?["kind"]) == "user" &&
        Text(input["caller"]?["principalId"]) == Text(config["operatorPrincipalId"]);
    static bool RequestPath(JsonObject config)
    {
        // This is a fact about the current kernel process, not caller input.
        if (!OperatingSystem.IsLinux()) return false;
        var command = File.ReadAllText("/proc/self/cmdline").Split('\0');
        var index = Array.IndexOf(command, "--timeout");
        return index >= 0 && index + 1 < command.Length && command[index + 1] == Text(config["requestKernelTimeout"]);
    }
    static FileStream? Lock(string root)
    {
        Directory.CreateDirectory(root);
        try { return new FileStream(Path.Combine(root, "coordinator.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException e) when ((e.HResult & 0xffff) is 11 or 32 or 33) { return null; }
    }
    static void Write(string target, JsonNode value)
    {
        var temporary = target + "." + Guid.NewGuid().ToString("D") + ".tmp";
        try {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) {
                file.Write(Encoding.UTF8.GetBytes(value.ToJsonString())); file.Flush(true);
            }
            File.Move(temporary, target, true);
        } finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
    static JsonObject Record(string attempt, string status, string execution, string digest) => new() {
        ["contractId"] = "hosted-execution-acceptance-read-result.v1", ["attemptId"] = attempt,
        ["status"] = status, ["requestExecutionId"] = execution, ["profileDigest"] = digest
    };
    public static JsonNode Read(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        var config = Config(context); var attempt = Text(input["attemptId"]);
        if (!Uuid.IsMatch(attempt)) return Error(Guid.NewGuid().ToString("D"), "dispatch", "ACCEPTANCE_REQUEST_INVALID", 400);
        if (!Caller(input, config)) return Error(attempt, "caller", "ACCEPTANCE_PRINCIPAL_REQUIRED", 403);
        if (!RequestPath(config)) return Error(attempt, "dispatch", "ACCEPTANCE_REQUEST_PATH_REQUIRED", 403);
        try { return ReadRecord(Text(config["recordDirectory"]), attempt); }
        catch { return Error(attempt, "execution", "ACCEPTANCE_RECORD_UNAVAILABLE", 503); }
    }
    public static JsonNode Retain(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        var config = Config(context); var attempt = Text(input["record"]?["attemptId"]);
        if (!Caller(input, config) || !RequestPath(config) || !Uuid.IsMatch(attempt)) throw new InvalidDataException();
        token.ThrowIfCancellationRequested();
        Write(Path.Combine(Text(config["recordDirectory"]), attempt + ".json"), input["record"]!);
        return new JsonObject { ["disposition"] = "STORED", ["attemptId"] = attempt };
    }
    static async Task RetainRecord(JsonNode record, JsonNode invocation, JsonObject config, GraphExecutionContext context, CancellationToken token)
    {
        var binding = config["recordBinding"]!.AsObject();
        var provider = DeclaredProviderResolver.ResolveProvider(binding["provider"]!.AsObject());
        var bound = context with { ProviderProfileId = Text(binding["provider"]!["providerProfileId"]),
            Configuration = new JsonObject { ["binding"] = new JsonObject { ["configuration"] = Clone(binding["configuration"]) } } };
        var outcome = await provider(new JsonObject { ["caller"] = Clone(invocation["caller"]), ["record"] = Clone(record) }, bound, token);
        if (Text(outcome.OutcomeValue?["disposition"]) != "STORED" || Text(outcome.OutcomeValue?["attemptId"]) != Text(record["attemptId"])) throw new IOException();
    }
    public static JsonNode ReadRecord(string root, string attempt)
    {
        if (!Uuid.IsMatch(attempt)) throw new InvalidDataException();
        using var admission = Lock(root);
        var file = Path.Combine(root, attempt + ".json");
        if (!File.Exists(file)) return new JsonObject { ["contractId"] = "hosted-execution-acceptance-read-result.v1", ["attemptId"] = attempt, ["status"] = "NOT_FOUND" };
        var record = Parse(File.ReadAllText(file));
        if (Text(record["attemptId"]) != attempt) throw new InvalidDataException();
        if (Text(record["status"]) == "RUNNING") {
            // Lock ownership, shared by all request kernels/instances, is the
            // liveness proof. An abandoned attempt is never replayed.
            var activePath = Path.Combine(root, "active.json");
            var active = File.Exists(activePath) ? Parse(File.ReadAllText(activePath)) : null;
            if (admission is not null || Text(active?["attemptId"]) != attempt) {
                record["status"] = "UNKNOWN";
                if (admission is not null) Write(file, record);
            }
        }
        return record;
    }
    public static async Task<GraphProviderOutcome> Accept(JsonNode input, GraphExecutionContext context, CancellationToken token)
    {
        var config = Config(context); var invocation = input["context"]?["invocation"];
        var attempt = Text(invocation?["attemptId"]); if (!Uuid.IsMatch(attempt)) attempt = Guid.NewGuid().ToString("D");
        var execution = Text(invocation?["requestExecutionId"]);
        GraphProviderOutcome Fail(string stage, string code, int status) => new(Error(attempt, stage, code, status, Uuid.IsMatch(execution) ? execution : null));
        if (invocation is null || !Caller(invocation, config)) return Fail("caller", "ACCEPTANCE_PRINCIPAL_REQUIRED", 403);
        if (!RequestPath(config) || Text(invocation["executionPath"]) != "request") return Fail("dispatch", "ACCEPTANCE_REQUEST_PATH_REQUIRED", 403);
        if (!Uuid.IsMatch(execution) || !Uuid.IsMatch(Text(invocation["attemptId"])) ||
            invocation["request"]?["body"] is not JsonObject body || body.Count != 0 ||
            Text(invocation["request"]?["method"]) != "POST" || Text(invocation["request"]?["path"]) != Text(config["path"]))
            return Fail("dispatch", "ACCEPTANCE_REQUEST_INVALID", 400);
        if (Text(invocation["expectedProfileDigest"]) != Text(config["profileDigest"])) return Fail("dispatch", "PROFILE_CHANGED", 409);
        var root = Text(config["recordDirectory"]); var file = Path.Combine(root, attempt + ".json");
        FileStream? admission;
        try { admission = Lock(root); } catch { return Fail("execution", "ACCEPTANCE_RECORD_UNAVAILABLE", 503); }
        if (admission is null) return Fail("dispatch", "ACCEPTANCE_BUSY", 409);
        using (admission) {
            if (File.Exists(file)) return Fail("dispatch", "ACCEPTANCE_REQUEST_INVALID", 409);
            var record = Record(attempt, "RUNNING", execution, Text(config["profileDigest"]));
            try { await RetainRecord(record, invocation, config, context, token); Write(Path.Combine(root, "active.json"), new JsonObject { ["attemptId"] = attempt }); }
            catch { return Fail("execution", "ACCEPTANCE_RECORD_UNAVAILABLE", 503); }
            JsonNode result;
            try {
                token.ThrowIfCancellationRequested();
                if (Text(input["context"]?["admission"]) != "ADMITTED") throw new CredentialUnavailable();
                var observations = await Observe(input, config, token);
                observations["executionId"] = execution;
                observations["invocation"] = Clone(invocation);
                if (observations["deployment"]?["established"]?.GetValue<bool>() != true)
                    result = Error(attempt, "execution", "ACCEPTANCE_CLIENT_FAILED", 503, execution);
                else result = new SemanticTransformationEngine().Transform(config["receiptExpression"]!.AsObject(), observations)!;
                if (Text(result["contractId"]) != "hosted-execution-acceptance.v1" && Text(result["contractId"]) != "hosted-execution-invocation-error.v1")
                    result = Error(attempt, "execution", "ACCEPTANCE_CLIENT_FAILED", 503, execution);
                if (Text(result["contractId"]) == "hosted-execution-acceptance.v1" && !await ValidateReceipt(result, config, token))
                    result = Error(attempt, "verification", "ACCEPTANCE_RECEIPT_INVALID", 502, execution);
            } catch (CredentialUnavailable) { result = Error(attempt, "credential", "ACCEPTANCE_CREDENTIAL_UNAVAILABLE", 503, execution); }
            catch (OperationCanceledException) { result = Error(attempt, "collection", "ACCEPTANCE_TRANSPORT_UNCERTAIN", 504, execution); }
            catch { result = Error(attempt, "execution", "ACCEPTANCE_CLIENT_FAILED", 503, execution); }
            try {
                if (Text(result["contractId"]) == "hosted-execution-acceptance.v1") {
                    var bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
                    record["status"] = "RECEIPT_AVAILABLE"; record["receiptByteLength"] = bytes.Length;
                    record["receiptSha256"] = Hash(bytes); record["receiptBytesBase64"] = Convert.ToBase64String(bytes); record["receipt"] = Clone(result);
                } else if (Text(result["outcome"]) == "UNKNOWN") record["status"] = "UNKNOWN";
                else record = new JsonObject { ["contractId"] = "hosted-execution-acceptance-read-result.v1", ["attemptId"] = attempt,
                    ["status"] = "FAILED", ["error"] = Clone(result) };
                // Cancellation stops probes, but cannot skip the terminal record.
                await RetainRecord(record, invocation, config, context, CancellationToken.None);
            } catch { return Fail("execution", "ACCEPTANCE_RECORD_UNAVAILABLE", 503); }
            return new(result);
        }
    }
    sealed class CredentialUnavailable : Exception;
    static async Task<bool> ValidateReceipt(JsonNode receipt, JsonObject config, CancellationToken token)
    {
        var start = new ProcessStartInfo("/usr/local/bin/python3") { UseShellExecute = false,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.Environment.Clear();
        foreach (var arg in new[] { "-I", "-S", "-B", Text(config["receiptValidator"]) }) start.ArgumentList.Add(arg);
        using var child = Process.Start(start) ?? throw new IOException();
        using var bound = CancellationTokenSource.CreateLinkedTokenSource(token); bound.CancelAfter(5000);
        var stdout = child.StandardOutput.ReadToEndAsync(bound.Token); var stderr = child.StandardError.ReadToEndAsync(bound.Token);
        try {
            await child.StandardInput.WriteAsync(receipt.ToJsonString().AsMemory(), bound.Token); child.StandardInput.Close();
            await child.WaitForExitAsync(bound.Token); await stdout; await stderr; return child.ExitCode == 0;
        } finally { if (!child.HasExited) { child.Kill(true); await child.WaitForExitAsync(CancellationToken.None); } }
    }
    static async Task<JsonNode> Observe(JsonNode input, JsonObject config, CancellationToken token)
    {
        byte[]? key = null, plaintext = null;
        string secret;
        try {
            var reference = Text(config["credentialReference"]);
            if (Text(input["credentialReference"]) != reference) throw new CredentialUnavailable();
            var vault = input["vault"]!; var entry = vault["entries"]![reference]!;
            var start = new ProcessStartInfo("secret-tool") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var arg in new[] { "lookup", "service", Text(input["keyService"]), "key", Text(input["keyReference"]) }) start.ArgumentList.Add(arg);
            using var process = Process.Start(start) ?? throw new CredentialUnavailable();
            using var bound = CancellationTokenSource.CreateLinkedTokenSource(token); bound.CancelAfter(10000);
            var stderr = process.StandardError.ReadToEndAsync(bound.Token);
            string output;
            try { output = await process.StandardOutput.ReadToEndAsync(bound.Token); await process.WaitForExitAsync(bound.Token); await stderr; }
            finally { if (!process.HasExited) { process.Kill(true); await process.WaitForExitAsync(CancellationToken.None); } }
            if (process.ExitCode != 0) throw new CredentialUnavailable();
            key = Convert.FromBase64String(output.Trim());
            var ciphertext = Convert.FromBase64String(Text(entry["ciphertext"])); plaintext = new byte[ciphertext.Length];
            var associated = Encoding.UTF8.GetBytes("{\"keyVersion\":" + entry["keyVersion"]!.ToJsonString() + ",\"referenceName\":\"" + reference + "\",\"vaultId\":\"" + Text(vault["vaultId"]) + "\"}");
            using var cipher = new AesGcm(key, 16);
            cipher.Decrypt(Convert.FromBase64String(Text(entry["nonce"])), ciphertext, Convert.FromBase64String(Text(entry["tag"])), plaintext, associated);
            secret = new UTF8Encoding(false, true).GetString(plaintext);
        } catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch { throw new CredentialUnavailable(); }
        finally { if (key is not null) CryptographicOperations.ZeroMemory(key); if (plaintext is not null) CryptographicOperations.ZeroMemory(plaintext); }
        var child = new ProcessStartInfo("/usr/bin/timeout") { UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, RedirectStandardInput = true };
        child.Environment.Clear(); child.Environment["SFX_ACCEPTANCE_SESSION"] = secret;
        child.Environment["SFX_API_IMAGE_DIGEST"] = Environment.GetEnvironmentVariable("SFX_API_IMAGE_DIGEST");
        foreach (var arg in new[] { "--kill-after=5", "175", "/usr/local/bin/python3", "-I", "-S", "-B", "-c", Text(config["observationProgram"]), input["context"]!["plan"]!.ToJsonString() }) child.ArgumentList.Add(arg);
        using var driver = Process.Start(child) ?? throw new IOException();
        child.Environment.Remove("SFX_ACCEPTANCE_SESSION"); secret = ""; driver.StandardInput.Close();
        var errors = driver.StandardError.ReadToEndAsync(token);
        try {
            var output = await driver.StandardOutput.ReadToEndAsync(token); await driver.WaitForExitAsync(token); await errors;
            if (driver.ExitCode != 0) throw new IOException();
            return Parse(output);
        } finally { if (!driver.HasExited) { driver.Kill(true); await driver.WaitForExitAsync(CancellationToken.None); } }
    }
}
