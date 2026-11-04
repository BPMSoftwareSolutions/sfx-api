"""Fixed probes of the hosted execution profile (contracts/sfx-api-hosted-csharp.v1.profile.json).

The C# program of sfx-api-host-child-process starts this script under /usr/bin/timeout with an empty environment.
argv[1] names one probe; any other name is refused. argv[2] is the language of the program that started it, which only
that language's kernel can run. Each probe answers one JSON object and measures only what it reports.
"""
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import time

PYTHON = "/usr/local/bin/python3"
TIMEOUT = "/usr/bin/timeout"
CONFIGURATION = "/opt/sfx/sfx-api.config.json"
SETTINGS = "/opt/sfx/authorities/host-bundle/capabilities/read-api-host-configuration.json"


def remaining(pid):
    """Whether a process with this pid still runs: absent, or a zombie, is not running."""
    try:
        with open("/proc/%d/stat" % pid) as stat:
            return stat.read().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def loadable_tags(major, minor, machine, glibc):
    """The wheel tags this interpreter can load, as the packaging specification derives them for manylinux."""
    tags = ["py3-none-any"]
    if machine != "x86_64" or glibc < (2, 17):
        return tags
    for libc_minor in range(17, glibc[1] + 1):
        platform_tag = "manylinux_2_%d_%s" % (libc_minor, machine)
        tags.append("cp%d%d-cp%d%d-%s" % (major, minor, major, minor, platform_tag))
        tags.extend("cp%d%d-abi3-%s" % (major, abi3, platform_tag) for abi3 in range(2, minor + 1))
    return tags


def runtime(language):
    import pwd
    libc = os.confstr("CS_GNU_LIBC_VERSION") or ""
    glibc_text = libc.split()[-1] if libc.startswith("glibc ") else ""
    glibc = tuple(int(part) for part in glibc_text.split(".")[:2]) if glibc_text else (0, 0)
    major, minor = sys.version_info[:2]
    storage = {"path": tempfile.gettempdir(), "created": False, "written": False, "readBack": False, "deleted": False}
    data = os.urandom(65536)
    handle, path = tempfile.mkstemp(prefix="sfx-acceptance-")
    storage["created"] = True
    with os.fdopen(handle, "wb") as file:
        file.write(data)
    storage["written"] = True
    with open(path, "rb") as file:
        storage["readBack"] = file.read() == data
    os.remove(path)
    storage["deleted"] = not os.path.exists(path)
    storage["freeBytes"] = shutil.disk_usage(storage["path"]).free
    return {"runtimeLanguage": language, "user": pwd.getpwuid(os.getuid()).pw_name, "uid": os.getuid(),
            "environmentKeys": sorted(os.environ), "python": {
                "path": sys.executable, "implementation": sys.implementation.name, "version": platform.python_version(),
                "soabi": sysconfig.get_config_var("SOABI"), "machine": platform.machine(), "glibcVersion": glibc_text,
                "loadableTags": loadable_tags(major, minor, platform.machine(), glibc)},
            "temporaryStorage": storage}


def under_timeout(arguments, child):
    """Run child under timeout with these arguments: its exit code, elapsed time, pid and whether it remains."""
    started = time.monotonic()
    process = subprocess.Popen([TIMEOUT] + arguments + [PYTHON, "-I", "-S", "-B", "-c", child],
                               stdout=subprocess.PIPE, env={})
    first = process.stdout.readline().decode("utf-8", "replace").split()
    exit_code = process.wait()
    # A process ended by a signal is reported as the shell reports it, 128 plus the signal, as GNU timeout documents
    # its exit statuses: timeout ends itself with the KILL it sends.
    exit_code = 128 - exit_code if exit_code < 0 else exit_code
    elapsed = int((time.monotonic() - started) * 1000)
    pid = int(first[0]) if first else 0
    time.sleep(0.2)
    return {"exitCode": exit_code, "elapsedMs": elapsed, "childPid": pid,
            "childRemaining": remaining(pid) if pid else True, "readiness": first[1:]}


def forced_termination(language):
    child = ("import os, signal, time\n"
             "signal.signal(signal.SIGTERM, signal.SIG_IGN)\n"
             "print(os.getpid(), 'ignoring', flush=True)\n"
             "time.sleep(60)\n")
    measured = under_timeout(["--kill-after=2", "2"], child)
    ignored = measured.pop("readiness") == ["ignoring"]
    return dict(measured, timeoutSeconds=2, killAfterSeconds=2, ignoredTermination=ignored)


def graceful_termination(language):
    version = subprocess.run([TIMEOUT, "--version"], capture_output=True, env={}).stdout.decode("utf-8", "replace")
    child = ("import os, time\n"
             "print(os.getpid(), 'running', flush=True)\n"
             "time.sleep(60)\n")
    measured = under_timeout(["2"], child)
    measured.pop("readiness")
    return dict(measured, timeoutSeconds=2, versionLine=version.splitlines()[0] if version else "")


def payload(language):
    text = "aé€😀abcdef" * 393216
    data = text.encode("utf-8")
    return {"contractId": "hosted-execution-payload.v1", "payloadBytes": len(data),
            "payloadSha256": "sha256:" + hashlib.sha256(data).hexdigest(), "payload": text}


def hold(language):
    started = time.time()
    time.sleep(5)
    return {"heldMs": int((time.time() - started) * 1000)}


def configuration(language):
    """The deployed facade configuration and the deployed bundle's declared host settings, read from their files.
    settingsDigest is the SHA-256 of read-api-host-configuration's literal answer as canonical JSON (keys sorted, no
    whitespace, UTF-8)."""
    raw = open(CONFIGURATION, "rb").read()
    host = json.loads(raw)
    bound = lambda kind: int(host[kind]["command"][host[kind]["command"].index("--timeout") + 1])
    declared = json.loads(open(SETTINGS, "rb").read())
    answer = next(binding["configuration"]["expression"]["value"]
                  for binding in declared["graphSource"]["interfaceAuthority"]["portBindings"]
                  if binding["portId"] == "read-api-host-configuration-answer")
    canonical = json.dumps(answer, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return {"configurationDigest": "sha256:" + hashlib.sha256(raw).hexdigest(),
            "settingsDigest": "sha256:" + hashlib.sha256(canonical).hexdigest(),
            "request": {"kernels": host["kernel"]["instances"], "waitForKernelMs": answer["request"]["waitMilliseconds"],
                        "deliveryBoundMs": bound("kernel"), "answerBoundMs": host["kernel"]["answerTimeoutMs"]},
            "worker": {"deliveryBoundMs": bound("workers"), "answerBoundMs": host["workers"]["answerTimeoutMs"],
                       "concurrentRuns": host["workers"]["instances"], "waitingRuns": answer["runs"]["queue"]["waiting"]}}


PROBES = {"runtime": runtime, "forced-termination": forced_termination, "graceful-termination": graceful_termination,
          "payload": payload, "hold": hold, "configuration": configuration}

try:
    name, language = sys.argv[1], sys.argv[2]
    if name not in PROBES:
        raise ValueError("PROBE_NOT_DECLARED")
    answer = dict(PROBES[name](language), probe=name, status="MEASURED")
except Exception as error:
    answer = {"probe": sys.argv[1] if len(sys.argv) > 1 else "", "status": "FAILED", "finding": type(error).__name__ + ": " + str(error)[:300]}
print(json.dumps(answer, ensure_ascii=False, separators=(",", ":")))
