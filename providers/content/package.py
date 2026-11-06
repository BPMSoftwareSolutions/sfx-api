"""Pure, offline inspection of an already-authorized immutable HTML package.

This provider discovers references; it grants no access and fetches no URL.
The caller must supply bytes from authorized reads and apply the delivery policy.
HTML is never rewritten or executed. Parser APIs: https://html5lib.readthedocs.io/
and https://doc.courtbouillon.org/tinycss2/stable/api_reference.html.
"""
import base64
import hashlib
import json
import posixpath
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

# The deployed provider uses -I -S and only its image-pinned parser packages.
sys.path.insert(0, str(Path(__file__).with_name("python")))
import html5lib
import tinycss2

MAX_BYTES = 8 * 1024 * 1024
MAX_ASSETS = 256
ASSET_TYPES = {"text/css", "image/png", "image/jpeg", "image/webp", "image/gif", "image/svg+xml", "font/woff", "font/woff2", "audio/mpeg", "video/mp4"}
DIGEST = re.compile(r"sha256:[0-9a-f]{64}\Z")


def digest(value):
    return "sha256:" + hashlib.sha256(value).hexdigest()


def original(carrier):
    encoded = carrier.get("base64")
    size = carrier.get("byteLength")
    if not isinstance(size, int) or isinstance(size, bool) or not 0 < size <= MAX_BYTES:
        raise ValueError("CONTENT_LIMIT_EXCEEDED")
    if not isinstance(encoded, str) or len(encoded) != ((size + 2) // 3) * 4:
        raise ValueError("CONTENT_ENCODING_INVALID")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except Exception as error:
        raise ValueError("CONTENT_ENCODING_INVALID") from error
    if base64.b64encode(raw).decode("ascii") != encoded:
        raise ValueError("CONTENT_ENCODING_INVALID")
    if len(raw) != size or digest(raw) != carrier.get("contentDigest"):
        raise ValueError("CONTENT_INTEGRITY_FAILURE")
    return raw


def relative_path(value, parent):
    if not isinstance(value, str) or len(value) > 2048 or re.search(r"[\x00-\x1f\x7f\\]", value):
        raise ValueError("CONTENT_PATH_INVALID")
    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc or parsed.path.startswith("/") or parsed.query:
        raise ValueError("CONTENT_EXTERNAL_REFERENCE")
    # Decode once, then reject double encodings and encoded path separators.
    path = unquote(parsed.path, errors="strict")
    if re.search(r"[%\\\x00-\x1f\x7f]", path) or re.search(r"%2f|%5c", parsed.path, re.I):
        raise ValueError("CONTENT_PATH_INVALID")
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(parent), path))
    if len(resolved) > 512 or resolved in (".", "..") or resolved.startswith("../") or resolved.startswith("/"):
        raise ValueError("CONTENT_PATH_INVALID")
    return resolved


def css_references(source):
    """Token parsing handles comments, nested functions and CSS escapes."""
    def walk(tokens):
        for token in tokens:
            if token.type == "error":
                raise ValueError("CONTENT_CSS_PARSE_ERROR")
            if token.type == "url":
                yield token.value
            elif token.type == "function":
                if token.lower_name == "url":
                    args = [x for x in token.arguments if x.type not in ("whitespace", "comment")]
                    if len(args) != 1 or args[0].type != "string":
                        raise ValueError("CONTENT_CSS_PARSE_ERROR")
                    yield args[0].value
                else:
                    if token.lower_name in ("image-set", "-webkit-image-set"):
                        for arg in token.arguments:
                            if arg.type == "string":
                                yield arg.value
                    yield from walk(token.arguments)
            for field in ("prelude", "content"):
                if getattr(token, field, None):
                    yield from walk(getattr(token, field))
            if token.type == "at-rule" and token.lower_at_keyword == "import":
                args = [x for x in token.prelude if x.type not in ("whitespace", "comment")]
                if args and args[0].type == "string":
                    yield args[0].value
    yield from walk(tinycss2.parse_stylesheet(source, skip_comments=True, skip_whitespace=True))


def srcset_references(source):
    """WHATWG image candidate token boundaries, including commas in data URLs.

    https://html.spec.whatwg.org/multipage/images.html#parse-a-srcset-attribute
    Invalid descriptors are explicit findings rather than an empty manifest.
    """
    whitespace = "\t\n\f\r "
    offset = 0
    while offset < len(source):
        while offset < len(source) and source[offset] in whitespace + ",":
            offset += 1
        start = offset
        while offset < len(source) and source[offset] not in whitespace:
            offset += 1
        url = source[start:offset]
        if not url:
            return
        if url.endswith(","):
            yield url.rstrip(",")
            continue
        start = offset
        depth = 0
        while offset < len(source):
            char = source[offset]
            if char == "," and depth == 0:
                break
            if char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
            offset += 1
        descriptors = source[start:offset].split()
        offset += 1
        seen = set()
        for descriptor in descriptors:
            match = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)([wxh])", descriptor)
            if not match or match[2] in seen or float(match[1]) <= 0 or (match[2] in "wh" and "." in match[1]):
                raise ValueError("CONTENT_SRCSET_INVALID")
            seen.add(match[2])
        if ("x" in seen and len(seen) != 1) or ("h" in seen and "w" not in seen):
            raise ValueError("CONTENT_SRCSET_INVALID")
        yield url


def analyze(request):
    raw = original(request["html"])
    html = raw.decode("utf-8", errors="strict")
    filename = request.get("filename", "index.html")
    if relative_path(filename, "index.html") != filename:
        raise ValueError("CONTENT_PATH_INVALID")
    assets = request.get("assets", [])
    if not isinstance(assets, list) or len(assets) > MAX_ASSETS:
        raise ValueError("CONTENT_ASSET_LIMIT_EXCEEDED")
    catalog = {}
    for asset in assets:
        path = asset.get("path")
        if relative_path(path, "index.html") != path or path == filename or path in catalog:
            raise ValueError("CONTENT_PATH_COLLISION")
        if not DIGEST.fullmatch(asset.get("contentDigest", "")) or not isinstance(asset.get("byteLength"), int) or not 0 < asset["byteLength"] <= MAX_BYTES:
            raise ValueError("CONTENT_ASSET_INVALID")
        if not isinstance(asset.get("mediaType"), str) or not re.fullmatch(r"[a-z0-9.+-]+/[a-z0-9.+-]+", asset["mediaType"]):
            raise ValueError("CONTENT_ASSET_INVALID")
        catalog[path] = asset
    unresolved, references, navigation, included, scanned = [], [], [], {}, {filename}
    queue = [(filename, "text/html", html)]
    title, language, script_hashes, executable_hashes, external_scripts = "", "", [], [], 0

    def finding(code, reference, parent):
        item = {"code": code, "reference": reference, "from": parent}
        if item not in unresolved:
            unresolved.append(item)

    def discover(reference, parent):
        if not reference or reference.startswith("#") or reference.lower().startswith("data:"):
            return
        try:
            path = relative_path(reference, parent)
        except (ValueError, UnicodeError) as error:
            finding(str(error), reference, parent)
            return
        if path == filename:
            return
        references.append({"from": parent, "reference": reference, "path": path})
        asset = catalog.get(path)
        if asset is None:
            finding("CONTENT_DEPENDENCY_MISSING", path, parent)
            return
        if asset["mediaType"] not in ASSET_TYPES:
            finding("CONTENT_DEPENDENCY_TYPE_UNSUPPORTED", path, parent)
            return
        included[path] = {key: asset[key] for key in ("path", "contentDigest", "byteLength", "mediaType")}
        if path in scanned:
            return
        scanned.add(path)
        if asset["mediaType"] in ("text/css", "text/html", "image/svg+xml"):
            if "base64" not in asset:
                finding("CONTENT_DEPENDENCY_BYTES_REQUIRED", path, parent)
            else:
                queue.append((path, asset["mediaType"], original(asset).decode("utf-8", errors="strict")))

    while queue:
        parent, media_type, text = queue.pop(0)
        if media_type == "text/css":
            try:
                for reference in css_references(text):
                    discover(reference, parent)
            except ValueError as error:
                finding(str(error), parent, parent)
            continue
        document = html5lib.parse(text, namespaceHTMLElements=False)
        for element in document.iter():
            if not isinstance(element.tag, str):
                continue
            tag = element.tag.rsplit("}", 1)[-1]
            attrs = {key.rsplit("}", 1)[-1]: value for key, value in element.attrib.items()}
            if parent == filename and tag == "title" and not title:
                title = "".join(element.itertext())[:1000]
            if parent == filename and tag == "html":
                language = attrs.get("lang", "")[:100]
            if tag == "base" and "href" in attrs:
                finding("CONTENT_BASE_URL_UNSUPPORTED", attrs["href"], parent)
            if tag in ("iframe", "object", "embed"):
                finding("CONTENT_ACTIVE_ELEMENT_BLOCKED", tag, parent)
            if tag == "script" and "src" not in attrs:
                # Observation only. This is never an authorization to execute.
                script_hash = digest((element.text or "").encode("utf-8"))
                script_hashes.append(script_hash)
                if attrs.get("type", "").strip().lower() not in ("application/json", "application/ld+json"):
                    executable_hashes.append(script_hash)
            elif tag == "script":
                external_scripts += 1
            # Script and form effects are disabled by the article delivery policy.
            # They are not assets whose publication could enable execution.
            for name in (() if tag == "script" else ("src", "poster", "background")):
                if name in attrs:
                    discover(attrs[name], parent)
            if "href" in attrs and tag != "base":
                if tag in ("a", "area"):
                    navigation.append({"from": parent, "reference": attrs["href"]})
                elif tag != "link" or set(attrs.get("rel", "").lower().split()) & {"stylesheet", "icon"}:
                    discover(attrs["href"], parent)
            if "srcset" in attrs or "imagesrcset" in attrs:
                value = attrs.get("srcset", attrs.get("imagesrcset"))
                try:
                    for reference in srcset_references(value):
                        discover(reference, parent)
                except ValueError as error:
                    finding(str(error), value, parent)
            for css in ([element.text or ""] if tag == "style" else []) + (["x{" + attrs["style"] + "}"] if "style" in attrs else []):
                try:
                    for reference in css_references(css):
                        discover(reference, parent)
                except ValueError as error:
                    finding(str(error), parent, parent)
    entries = [included[path] for path in sorted(included)]
    manifest_bytes = json.dumps(entries, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return {"contractId": "content-package-analysis.v1", "status": "INCOMPLETE" if unresolved else "COMPLETE",
            "contentDigest": digest(raw), "byteLength": len(raw), "title": title, "language": language,
            "dependencyManifest": {"entries": entries, "manifestDigest": digest(manifest_bytes)},
            "references": references, "navigation": navigation, "unresolved": unresolved, "observedInlineScriptDigests": script_hashes,
            "executableInlineScriptDigests": executable_hashes, "externalScripts": external_scripts}


if __name__ == "__main__":
    # Invocation is bounded by the declared host provider as well as this carrier.
    value = sys.stdin.buffer.read(32 * 1024 * 1024 + 1)
    try:
        if len(value) > 32 * 1024 * 1024:
            raise ValueError("CONTENT_PACKAGE_LIMIT_EXCEEDED")
        result = analyze(json.loads(value))
    except (ValueError, KeyError, TypeError, UnicodeError) as error:
        result = {"contractId": "content-package-analysis.v1", "status": "REFUSED", "code": str(error)}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))
