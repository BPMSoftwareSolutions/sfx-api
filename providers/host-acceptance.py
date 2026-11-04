"""The HTTPS client of accept-hosted-execution-profile (contracts/sfx-api-hosted-csharp.v1.profile.json, acceptance).

The C# program of sfx-api-host-http-request opens the host-vault entry sfx-api-acceptance-password inside its own call
and starts this script under /usr/bin/timeout in an empty environment that holds only SFX_ACCEPTANCE_PASSWORD and
SFX_API_IMAGE_DIGEST. argv[1] is the acceptance plan the coordinator declares. The script:

- attests the deployment it runs on: the deployer's recorded image digest, the bundle pin, the kernel install root it
  runs in, and the SHA-256 over the deployed host files;
- signs in over HTTPS as the plan's principal and accepts only AUTHENTICATED with the plan's principalId;
- submits each probe of the plan through POST /sfx/v1/runs, follows each run's event stream to its end frame, and reads
  its state and its output through the same endpoint, without following redirects;
- measures the payload probe's /output/payload from the HTTPS response, as UTF-8 bytes and their SHA-256;
- signs out.

It answers one JSON object of observations: what each request answered, or the stage and code at which a check could
not be observed. It decides no disposition: the coordinator's declared evaluation does. The password and the bearer
never leave this process.
"""
import hashlib
import http.client
import json
import os
import re
import ssl
import sys
import time
import uuid
from datetime import datetime, timezone

STARTED = time.monotonic()
HOST_FILES = ["/opt/sfx/host/serve.py", "/opt/sfx/sfx-api.config.json", "/opt/sfx/start.sh", None,
              "/opt/sfx/providers/host-provider-authority.json"]
MANIFEST = "/opt/sfx/authorities/host-bundle/manifest.json"
SHA256 = re.compile(r"^sha256:[0-9a-f]{64}$")
UUID = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
PIN = re.compile(r"^sha256-base64:[A-Za-z0-9+/]{43}=$")


class Failure(Exception):
    def __init__(self, stage, code, message):
        super().__init__(message)
        self.stage, self.code, self.message = stage, code, message[:500]


def now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def instant_ms(text):
    """An ISO 8601 instant as epoch milliseconds, or None."""
    if not isinstance(text, str):
        return None
    try:
        value = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return int(value.timestamp() * 1000)


def b64sha256(data):
    import base64
    return base64.b64encode(hashlib.sha256(data).digest()).decode()


def execution_path():
    """The path of the kernel this client runs under, from the kernel's --timeout among the configured kinds: request,
    worker, or what else it is. The client's parent is /usr/bin/timeout; the kernel is the nearest KernelEntry above."""
    config = json.loads(open("/opt/sfx/sfx-api.config.json", "rb").read())
    bound = lambda kind: config[kind]["command"][config[kind]["command"].index("--timeout") + 1]
    paths = {bound("kernel"): "request", bound("workers"): "worker"}
    pid = os.getppid()
    for _ in range(4):
        command = [part.decode("utf-8", "replace") for part in open("/proc/%d/cmdline" % pid, "rb").read().split(b"\0")]
        if command and command[0].endswith("KernelEntry") and "--timeout" in command:
            return paths.get(command[command.index("--timeout") + 1], "other")
        pid = int(open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()[1])
    return "unknown"


def deployment():
    """The deployment this process runs on, read here, or why it cannot be established."""
    try:
        config = json.loads(open("/opt/sfx/sfx-api.config.json", "rb").read())
        root = config["kernel"]["root"]
        if os.path.realpath(os.getcwd()) != os.path.realpath(root):
            raise ValueError("the coordinator does not run in the configured kernel install root")
        kernel = os.path.basename(root.rstrip("/"))
        if not re.fullmatch(r"[0-9a-f]{64}", kernel):
            raise ValueError("the kernel install root is not named by its digest")
        files = [path or os.path.join(root, "kernel-host.json") for path in HOST_FILES]
        digest = hashlib.sha256()
        for path in files:
            digest.update(open(path, "rb").read())
        authority = open("/opt/sfx/providers/host-provider-authority.json", encoding="utf-8").read()
        pins = sorted(set(re.findall(r'"(sha256-base64:[A-Za-z0-9+/]{43}=)"', authority)))
        manifest_pin = "sha256-base64:" + b64sha256(open(MANIFEST, "rb").read())
        if pins != [manifest_pin]:
            raise ValueError("the provider authority does not pin the deployed bundle manifest")
        image = os.environ.get("SFX_API_IMAGE_DIGEST", "")
        if not SHA256.match(image):
            raise ValueError("the deployer recorded no image digest (SFX_API_IMAGE_DIGEST)")
        return {"established": True, "imageDigest": image, "bundleDigest": manifest_pin,
                "kernelArtifactDigest": "sha256:" + kernel, "hostFilesDigest": "sha256:" + digest.hexdigest()}
    except (OSError, ValueError, KeyError, TypeError) as error:
        return {"established": False, "code": "ACCEPTANCE_DEPLOYMENT_UNESTABLISHED",
                "message": type(error).__name__ + ": " + str(error)[:300]}


class Client:
    """HTTPS to the plan's endpoint only, one request per connection, never following a redirect."""

    def __init__(self, endpoint, deadline):
        match = re.fullmatch(r"https://([a-z0-9.-]+)", endpoint)
        if not match:
            raise Failure("precondition", "ACCEPTANCE_ENDPOINT_INVALID", "the plan's endpoint is not an HTTPS origin")
        self.endpoint, self.host, self.deadline, self.bearer = endpoint, match.group(1), deadline, None
        self.context = ssl.create_default_context()

    def remaining(self):
        return self.deadline - time.monotonic()

    def request(self, stage, method, path, body=None, headers=None, stream_end=False):
        """(status, headers, body bytes) of one complete exchange, or Failure at this stage."""
        timeout = self.remaining()
        if timeout <= 1:
            raise Failure(stage, "ACCEPTANCE_BUDGET_EXHAUSTED", "%s %s was not sent: the acceptance budget ran out" % (method, path))
        send = {"Accept": "text/event-stream" if stream_end else "application/json", "Connection": "close"}
        if self.bearer:
            send["Authorization"] = "Bearer " + self.bearer
        data = None
        if body is not None:
            data = json.dumps(body, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
            send["Content-Type"] = "application/json; charset=utf-8"
        send.update(headers or {})
        connection = http.client.HTTPSConnection(self.host, 443, timeout=min(timeout, 120), context=self.context)
        try:
            connection.request(method, path, body=data, headers=send)
            response = connection.getresponse()
            payload = response.read()
            return response.status, {k.lower(): v for k, v in response.getheaders()}, payload
        except http.client.IncompleteRead as error:
            raise Failure(stage, "ACCEPTANCE_RESPONSE_INCOMPLETE", "%s %s: the response ended after %d bytes" % (method, path, len(error.partial)))
        except (OSError, http.client.HTTPException) as error:
            raise Failure(stage, "ACCEPTANCE_TRANSPORT_FAILED", "%s %s: %s: %s" % (method, path, type(error).__name__, str(error)[:200]))
        finally:
            connection.close()

    def json(self, stage, method, path, body=None, headers=None):
        status, _, payload = self.request(stage, method, path, body, headers)
        try:
            document = json.loads(payload.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            raise Failure(stage, "ACCEPTANCE_RESPONSE_UNDECODABLE", "%s %s answered %d with a body that is not JSON" % (method, path, status))
        return status, document


def sign_in(client, plan, password):
    """The plan principal's session, or Failure at precondition."""
    if not password:
        raise Failure("precondition", "ACCEPTANCE_CREDENTIAL_UNAVAILABLE", "the host vault released no acceptance password")
    status, answer = client.json("precondition", "POST", "/sfx/v1/session",
                                 {"identifier": plan["identifier"], "password": password})
    disposition = answer.get("status") if isinstance(answer, dict) else None
    if status != 200 or disposition != "AUTHENTICATED":
        code = {"THROTTLED": "ACCEPTANCE_SIGN_IN_THROTTLED"}.get(disposition, "ACCEPTANCE_SIGN_IN_REJECTED")
        raise Failure("precondition", code, "the acceptance sign-in answered %d %s" % (status, disposition))
    principal = str(answer.get("principalId", "")).lower()
    if principal != plan["principalId"]:
        raise Failure("precondition", "ACCEPTANCE_PRINCIPAL_MISMATCH", "the acceptance sign-in named another principal")
    client.bearer = answer.get("token")
    if not client.bearer:
        raise Failure("precondition", "ACCEPTANCE_SIGN_IN_REJECTED", "the acceptance sign-in answered no bearer")
    return {"disposition": "AUTHENTICATED", "principalId": principal}


def admit(client, probe, attempt):
    """The admitted run id of one probe, or Failure at admission."""
    status, answer = client.json("admission", "POST", "/sfx/v1/runs",
                                 {"object": "capability", "operation": "observe", "subject": probe["capabilityId"],
                                  "input": probe["input"]}, {"Idempotency-Key": attempt})
    run_id = answer.get("runId") if isinstance(answer, dict) else None
    if status not in (200, 201, 202) or not isinstance(run_id, str) or not UUID.match(run_id):
        code = (answer.get("error") or {}).get("code") if isinstance(answer, dict) else None
        raise Failure("admission", "ACCEPTANCE_ADMISSION_REFUSED", "POST /sfx/v1/runs answered %d %s" % (status, code or ""))
    return run_id


def follow(client, run_id):
    """Read the run's event stream to its end frame, within the acceptance budget."""
    path = "/sfx/v1/runs/%s/events/stream?after=0" % run_id
    if client.remaining() <= 1:
        raise Failure("collection", "ACCEPTANCE_BUDGET_EXHAUSTED", "the run was not followed: the acceptance budget ran out")
    connection = http.client.HTTPSConnection(client.host, 443, timeout=min(client.remaining(), 60), context=client.context)
    try:
        connection.request("GET", path, headers={"Accept": "text/event-stream", "Connection": "close",
                                                 "Authorization": "Bearer " + client.bearer})
        response = connection.getresponse()
        if response.status != 200 or not (response.getheader("content-type") or "").startswith("text/event-stream"):
            response.read()
            raise Failure("collection", "ACCEPTANCE_STREAM_REFUSED", "the run's event stream answered %d" % response.status)
        event = None
        while True:
            if client.remaining() <= 1:
                raise Failure("collection", "ACCEPTANCE_BUDGET_EXHAUSTED", "the run did not end within the acceptance budget")
            line = response.readline()
            if not line:
                raise Failure("collection", "ACCEPTANCE_STREAM_INTERRUPTED", "the run's event stream closed before its end frame")
            text = line.decode("utf-8", "replace").rstrip("\r\n")
            if text.startswith("event:"):
                event = text[6:].strip()
            elif not text:
                if event == "end":
                    return
                if event == "session-ended":
                    raise Failure("collection", "ACCEPTANCE_SESSION_ENDED", "the acceptance session ended while its run was followed")
                event = None
    except (OSError, http.client.HTTPException) as failure:
        raise Failure("collection", "ACCEPTANCE_TRANSPORT_FAILED", "GET %s: %s: %s" % (path, type(failure).__name__, str(failure)[:200]))
    finally:
        connection.close()


def state(client, run_id, capability):
    status, answer = client.json("collection", "GET", "/sfx/v1/runs/%s" % run_id)
    run = answer.get("run") if isinstance(answer, dict) else None
    if status != 200 or not isinstance(run, dict):
        raise Failure("collection", "ACCEPTANCE_STATE_UNAVAILABLE", "GET /sfx/v1/runs/%s answered %d with no run" % (run_id, status))
    if run.get("runId") != run_id or (run.get("capability") or {}).get("subject") != capability:
        raise Failure("verification", "ACCEPTANCE_RUN_IDENTITY", "the run read back is not the admitted probe")
    return {"state": run.get("state"), "exitCode": run.get("exitCode"), "startedAt": run.get("startedAt"),
            "endedAt": run.get("endedAt"), "startedAtMs": instant_ms(run.get("startedAt")),
            "endedAtMs": instant_ms(run.get("endedAt")), "failure": run.get("failure"),
            "outputAvailable": (run.get("output") or {}).get("available") is True}


def output(client, run_id):
    status, answer = client.json("collection", "GET", "/sfx/v1/runs/%s/output" % run_id)
    if status != 200 or not isinstance(answer, dict) or not isinstance(answer.get("output"), dict):
        raise Failure("collection", "ACCEPTANCE_OUTPUT_UNAVAILABLE", "GET /sfx/v1/runs/%s/output answered %d with no output" % (run_id, status))
    return answer["output"]


def measure(client, run_id):
    """T4: the payload as the deployed HTTPS route answers it."""
    path = "/sfx/v1/runs/%s/output" % run_id
    status, headers, payload = client.request("collection", "GET", path)
    measured = {"transport": "https", "method": "GET", "url": client.endpoint + path, "statusCode": status,
                "redirected": False, "payloadPointer": "/output/payload"}
    try:
        document = json.loads(payload.decode("utf-8"))
        produced = document["output"]
        text = produced["payload"]
        if not isinstance(text, str):
            raise TypeError("/output/payload is not a string")
    except (UnicodeDecodeError, ValueError, KeyError, TypeError) as error:
        raise Failure("collection", "ACCEPTANCE_OUTPUT_UNDECODABLE", "%s answered %d: %s" % (path, status, type(error).__name__))
    data = text.encode("utf-8")
    return dict(measured, expectedBytes=produced.get("payloadBytes"), receivedBytes=len(data),
                expectedSha256=produced.get("payloadSha256"), receivedSha256="sha256:" + hashlib.sha256(data).hexdigest())


def refusal(failure):
    """T3: what the run's failure names, read from its code and message."""
    failure = failure if isinstance(failure, dict) else {}
    message = str(failure.get("message") or "")
    named = re.search(r"'([^']+)' is declared for '([^']+)', not '([^']+)'", message)
    if not named:
        raise Failure("collection", "ACCEPTANCE_REFUSAL_UNREADABLE", "the failed run's failure names no provider and languages")
    return {"errorCode": failure.get("code"), "providerProfileId": named.group(1), "declaredLanguage": named.group(2),
            "runtimeLanguage": named.group(3)}


def error(failure, runs):
    return {"stage": failure.stage, "code": failure.code, "message": failure.message, "runIds": runs}


def observe_checks(client, plan):
    checks = {}
    pending = []
    for probe in plan["probes"]:
        attempt = str(uuid.uuid4())
        entry = {"attemptId": attempt, "runIds": [], "error": None}
        checks[probe["checkId"]] = entry
        try:
            entry["runIds"] = [admit(client, probe, attempt)]
            pending.append((probe, entry))
        except Failure as failure:
            entry["error"] = error(failure, [])
    for probe, entry in pending:
        run_id = entry["runIds"][0]
        try:
            follow(client, run_id)
            entry["state"] = state(client, run_id, probe["capabilityId"])
            expect = probe.get("expect", "completed")
            if entry["state"]["state"] != expect:
                raise Failure("execution", "ACCEPTANCE_PROBE_" + str(entry["state"]["state"]).upper().replace("-", "_"),
                              "the probe run ended %s, not %s: %s" % (entry["state"]["state"], expect,
                                                                    json.dumps(entry["state"]["failure"])[:300]))
            if probe.get("observe") == "refusal":
                entry["observed"] = refusal(entry["state"]["failure"])
            elif probe.get("observe") == "payload":
                entry["measurement"] = measure(client, run_id)
            else:
                produced = output(client, run_id)
                if produced.get("status") != "MEASURED":
                    raise Failure("execution", "ACCEPTANCE_PROBE_UNMEASURED", "the probe answered %s: %s" % (
                        produced.get("status"), str(produced.get("finding"))[:300]))
                entry["output"] = produced
        except Failure as failure:
            entry["error"] = error(failure, entry["runIds"])
    return checks


def observe_concurrency(client, plan):
    holds = plan["concurrency"]
    attempt = str(uuid.uuid4())
    entry = {"attemptId": attempt, "runIds": [], "runs": [], "error": None}
    try:
        for index in range(holds["count"]):
            entry["runIds"].append(admit(client, holds, attempt + "-%d" % index))
        for run_id in entry["runIds"]:
            follow(client, run_id)
            read = state(client, run_id, holds["capabilityId"])
            if read["state"] != "completed" or read["startedAtMs"] is None or read["endedAtMs"] is None:
                raise Failure("execution", "ACCEPTANCE_HOLD_INTERVAL_INVALID", "a hold run has no completed interval")
            entry["runs"].append({"runId": run_id, "startedAt": read["startedAt"], "endedAt": read["endedAt"],
                                  "startedAtMs": read["startedAtMs"], "endedAtMs": read["endedAtMs"]})
    except Failure as failure:
        entry["error"] = error(failure, entry["runIds"])
    return entry


def main():
    plan = json.loads(sys.argv[1])
    answer = {"contractId": "hosted-acceptance-observations.v1", "executionId": str(uuid.uuid4()), "executedAt": now()}
    answer["deployment"] = deployment()
    password = os.environ.pop("SFX_ACCEPTANCE_PASSWORD", "")
    if not answer["deployment"]["established"]:
        # No receipt can name an unestablished deployment, so nothing is signed in or submitted.
        return answer
    try:
        path = execution_path()
    except (OSError, ValueError, KeyError, IndexError) as failure:
        path = "unknown: " + type(failure).__name__
    answer["coordinator"] = {"executionPath": path, "workerSlots": 0 if path == "request" else 1 if path == "worker" else -1}
    if path != "request":
        # Only the request path's acceptance route admits the caller by its session: anywhere else, nothing is signed in.
        answer["deployment"] = {"established": False, "code": "ACCEPTANCE_NOT_ON_REQUEST_PATH",
                                "message": "the coordinator runs on the %s path, not the request path" % path}
        return answer
    client = Client(plan["endpoint"], STARTED + plan["budgetMs"] / 1000)
    try:
        answer["signIn"] = sign_in(client, plan, password)
    except Failure as failure:
        # No probe is submitted without the session: every check is unobserved at its precondition.
        answer["signIn"] = {"disposition": "FAILED", "code": failure.code, "message": failure.message}
        answer["checks"] = {check: {"attemptId": str(uuid.uuid4()), "runIds": [], "error": error(failure, [])}
                            for check in [probe["checkId"] for probe in plan["probes"]] + [plan["concurrency"]["checkId"]]}
        answer["elapsedMs"] = int((time.monotonic() - STARTED) * 1000)
        return answer
    finally:
        password = None
    try:
        answer["checks"] = observe_checks(client, plan)
        answer["checks"][plan["concurrency"]["checkId"]] = observe_concurrency(client, plan)
    finally:
        try:
            client.request("collection", "POST", "/sfx/v1/session/logout")
        except Failure:
            pass
        client.bearer = None
    answer["elapsedMs"] = int((time.monotonic() - STARTED) * 1000)
    return answer


try:
    result = main()
except Exception as unexpected:
    result = {"contractId": "hosted-acceptance-observations.v1", "failed": True,
              "code": "ACCEPTANCE_CLIENT_FAILED", "message": type(unexpected).__name__ + ": " + str(unexpected)[:300]}
print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
