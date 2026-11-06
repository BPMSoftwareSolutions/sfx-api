"""Project the content HTTP declarations into the image-owned bundle.

No estate installation or deployment. build-hosted-release.py subsequently pins
the complete bundle and provider authority, including these declarations.
"""
import base64
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "authorities/host-bundle"


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def write(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def project():
    authority = read(ROOT / "sej/content-api.v1.json")
    template = read(BUNDLE / "capabilities/read-run-output.json")
    source_binding = next(x for x in template["graphSource"]["interfaceAuthority"]["portBindings"] if x["platformCapabilityId"] == "generic-capability-invocation.v1")
    front = read(BUNDLE / "capabilities/serve-api-request.json")
    carry = next(x for x in front["graphSource"]["semanticTransformations"] if x["id"] == "serve-carry-interface")
    routes = carry["expression"]["fields"]["result"]["fields"]["value"]["fields"]["interface"]["value"]["operations"]
    for operation in authority["operations"]:
        name = operation["operationId"]
        document = json.loads(json.dumps(template).replace("read-run-output", name))
        graph = document["graphSource"]
        graph["semanticTransformations"] = []
        publication_read = operation.get("family") == "publication"
        publication_write = operation["projection"] in ("publish", "update")
        steps = ("prepare", "source", "answer") if publication_read else ("prepare", "source", "receipts", "receipt-source", "retained", "retained-source", "project")
        if publication_write:
            steps += ("writer", "answer")
        graph["executionAuthorities"][0]["operations"] = [
            {"operationId": name + "." + step, "kind": "invoke-port", "portId": name + "-" + step}
            for step in steps]
        source = copy.deepcopy(source_binding)
        source["portId"] = name + "-source"
        graph["interfaceAuthority"]["portBindings"] = [
            {"portId": name + "-prepare", "platformCapabilityId": "sfx-api-content-selection-port.v1",
             "configuration": {"operation": operation["projection"], "sourceCapabilityId": authority["sourceCapabilityId"]}},
            source,
            {"portId": name + "-receipts", "platformCapabilityId": authority["providers"]["receipts"] + "-port.v1",
             "configuration": {"receiptCapabilityId": authority["receiptCapabilityId"]}},
            {**copy.deepcopy(source), "portId": name + "-receipt-source"},
            {"portId": name + "-retained", "platformCapabilityId": authority["providers"]["retained"] + "-port.v1",
             "configuration": {"retainedCapabilityId": authority["retainedCapabilityId"]}},
            {**copy.deepcopy(source), "portId": name + "-retained-source"},
            {"portId": name + "-project", "platformCapabilityId": "sfx-api-content-package-port.v1" if publication_write else "sfx-api-content-projection-port.v1",
             "configuration": {**{key: authority["providers"][key] for key in ("python", "analyzer")},
                               "writerCapabilityId": authority["writerCapabilityId"],
                               "interactiveProfile": authority["interactiveProfile"]}}]
        if publication_read:
            graph["interfaceAuthority"]["portBindings"] = [
                {"portId": name + "-prepare", "platformCapabilityId": "sfx-api-publication-selection-port.v1",
                 "configuration": {"operation": operation["projection"], "readerCapabilityId": authority["publicationReaderCapabilityId"], "writerCapabilityId": authority["writerCapabilityId"]}},
                source]
        if publication_write:
            graph["interfaceAuthority"]["portBindings"].append({**copy.deepcopy(source), "portId": name + "-writer"})
        if publication_write or publication_read:
            graph["interfaceAuthority"]["portBindings"].append({"portId": name + "-answer", "platformCapabilityId": "sfx-api-publication-answer-port.v1", "configuration": {}})
        graph["contractAuthorities"]["contracts"] = {
            name + "-request.v1": {"schemaRef": name + "-request.v1.schema.json", "schema": {"type": "object"}},
            name + "-result.v1": {"schemaRef": name + "-result.v1.schema.json", "schema": {
                "type": "object", "required": ["contractId", "status", "body"],
                "properties": {"contractId": {"const": "api-response.v1"}, "status": {"type": "integer"}, "body": {"type": "object"}}}}
        }
        closure_digest = base64.b64encode(hashlib.sha256(json.dumps(graph, ensure_ascii=False, separators=(",", ":")).encode()).digest()).decode()
        for closure in document["closure"]:
            closure["responsibility"] = operation["meaning"]
            closure["scenario_definition_digest"] = closure_digest
        write(BUNDLE / "capabilities" / (name + ".json"), document)
        segments = {"0": "", "1": "sfx", "2": "v1"}
        inputs = {"principalId": "$caller.principalId", "requestExecutionId": "$request.requestExecutionId", "executionPath": "$request.executionPath"}
        for i, segment in enumerate(operation["path"].strip("/").split("/"), 3):
            if segment.startswith("{"):
                key = segment[1:-1]
                segments[str(i)] = {"param": key}
                inputs[key] = "$path." + key
            else:
                segments[str(i)] = segment
        inputs.update({key: "$query." + key for key in operation["query"]})
        if operation.get("method", "GET") == "POST":
            inputs["requestBody"] = "$body"
        routes[:] = [route for route in routes if route["operationId"] != name]
        routes.append({"operationId": name, "method": operation.get("method", "GET"), "path": operation["path"], "callers": operation.get("callers", ["user"]),
                       "segments": segments, "input": inputs, "resolves": {"kind": "capability", "capabilityId": name},
                       "meaning": operation["meaning"]})
    # Identity resolution can return null for a request without a session.
    # Only a route explicitly declaring anonymous access accepts that caller.
    def anonymous_routes(node):
        if isinstance(node, dict):
            condition = node.get("when", {})
            if (node.get("op") == "if" and condition.get("op") == "equals"
                    and condition.get("left", {}).get("op") == "type"
                    and condition["left"].get("value", {}).get("op") == "path"
                    and condition["left"]["value"].get("path") == "caller"
                    and condition.get("right") == {"op": "literal", "value": "null"}
                    and node.get("else", {}).get("op") == "includes"
                    and node["else"].get("in", {}).get("path") == "callers"):
                node["then"] = {"op": "includes", "in": {"op": "path", "from": "operation", "path": "callers"}, "value": {"op": "literal", "value": "anonymous"}}
            for value in node.values(): anonymous_routes(value)
        elif isinstance(node, list):
            for value in node: anonymous_routes(value)
    anonymous_routes(front)
    write(BUNDLE / "capabilities/serve-api-request.json", front)
    providers = read(ROOT / "providers/host-provider-authority.json")
    material = bytearray()
    for filename in ("providers/hosted/ContentProjection.cs", "providers/hosted/PublicationProjection.cs", "providers/content/package.py", "providers/content/requirements.txt"):
        raw = (ROOT / filename).read_bytes()
        material.extend(filename.encode() + b"\0" + str(len(raw)).encode() + b"\0" + raw)
    source_digest = "sha256:" + hashlib.sha256(material).hexdigest()
    registrations = [(authority["providers"][kind], "ContentProjection", method) for kind, method in (("selection", "Prepare"), ("receipts", "Receipts"), ("retained", "BodyReference"), ("projection", "Project"))]
    registrations += [("sfx-api-content-package", "ContentProjection", "PreparePublication"), ("sfx-api-publication-selection", "PublicationProjection", "Prepare"), ("sfx-api-publication-answer", "PublicationProjection", "Answer")]
    for identity, class_name, method in registrations:
        mechanic = identity + "-port.v1"
        providers["declaredProviders"][:] = [x for x in providers["declaredProviders"] if x["providerProfileId"] != identity]
        providers["overlayBindings"][:] = [x for x in providers["overlayBindings"] if x["mechanicId"] != mechanic]
        providers["declaredProviders"].append({"providerProfileId": identity, "language": "csharp", "type": "Sfx.HostedProviders." + class_name,
            "assembly": "../../providers/hosted/Sfx.HostedProviders.dll", "method": method, "effectClassification": "observation", "sourceProviderDefinitionDigest": source_digest})
        providers["overlayBindings"].append({"mechanicId": mechanic, "providerProfileId": identity, "providerProfileDigest": source_digest,
            "implementationRef": "providers/hosted/" + class_name + ".cs#" + method})
    write(ROOT / "providers/host-provider-authority.json", providers)
    print(json.dumps({"projectedContentOperations": len(authority["operations"]), "deployed": False}))


if __name__ == "__main__":
    project()
