import base64
import unittest

from package import analyze, digest


def carrier(text, **extra):
    raw = text.encode("utf-8")
    return {"base64": base64.b64encode(raw).decode("ascii"), "contentDigest": digest(raw), "byteLength": len(raw), **extra}


class PackageTests(unittest.TestCase):
    def test_original_filenames_with_spaces_and_encoded_resource_names(self):
        result = analyze({"filename": "asset article.html", "html": carrier('<img src="images/blue%20sky.png">'),
                          "assets": [carrier("image", path="images/blue sky.png", mediaType="image/png")]})
        self.assertEqual(result["status"], "COMPLETE")
        self.assertEqual(result["dependencyManifest"]["entries"][0]["path"], "images/blue sky.png")

    def test_navigation_does_not_publish_siblings_or_enable_scripts(self):
        result = analyze({"html": carrier('<a href="private.html">Private sibling</a><form action="save"><input></form><script src="app.js"></script>'),
                          "assets": [carrier("private", path="private.html", mediaType="text/html")]})
        self.assertEqual(result["status"], "COMPLETE")
        self.assertEqual(result["dependencyManifest"]["entries"], [])
        self.assertEqual(result["navigation"], [{"from": "index.html", "reference": "private.html"}])

    def test_exact_unicode_bytes_and_inert_scripts(self):
        html = '<!doctype html><html lang="fr"><title>Résumé</title><style>p{color:red}</style><p>Café</p><script>throw new Error("must not execute")</script></html>'
        result = analyze({"html": carrier(html)})
        self.assertEqual(result["status"], "COMPLETE")
        self.assertEqual(result["contentDigest"], digest(html.encode()))
        self.assertEqual(result["title"], "Résumé")
        self.assertEqual(result["language"], "fr")
        self.assertEqual(result["dependencyManifest"]["entries"], [])
        self.assertEqual(len(result["observedInlineScriptDigests"]), 1)
        self.assertEqual(len(result["executableInlineScriptDigests"]), 1)

    def test_inert_json_is_separate_from_executable_script(self):
        result = analyze({"html": carrier('<script type="application/json">{"scene":1}</script><script>const x=1;</script>')})
        self.assertEqual(len(result["observedInlineScriptDigests"]), 2)
        self.assertEqual(result["executableInlineScriptDigests"], [digest(b"const x=1;")])

    def test_dependency_closure_includes_escaped_css_urls_and_nested_import(self):
        html = '<link rel="stylesheet" href="css/main.css"><img src="images/caf&#233;.png">'
        assets = [carrier('@import "nested.css";p{background:u\\72l(../images/background.png)}', path="css/main.css", mediaType="text/css"),
                  carrier('@font-face{src:url("../fonts/regular.woff2")}', path="css/nested.css", mediaType="text/css"),
                  carrier("image", path="images/café.png", mediaType="image/png"),
                  carrier("image2", path="images/background.png", mediaType="image/png"),
                  carrier("font", path="fonts/regular.woff2", mediaType="font/woff2"),
                  carrier("private unrelated page", path="private.html", mediaType="text/html")]
        result = analyze({"html": carrier(html), "assets": assets})
        self.assertEqual(result["status"], "COMPLETE", result)
        paths = [x["path"] for x in result["dependencyManifest"]["entries"]]
        self.assertEqual(len(paths), 5)
        self.assertNotIn("private.html", paths)
        reverse = analyze({"html": carrier(html), "assets": list(reversed(assets))})
        self.assertEqual(result["dependencyManifest"], reverse["dependencyManifest"])

    def test_missing_ambiguous_and_external_references_never_become_permissions(self):
        html = '<img src="missing.png"><img src="../../secret"><img src="%252e%252e/secret"><img src="https://example.invalid/a"><base href="https://example.invalid/"><iframe src="child.html"></iframe>'
        result = analyze({"html": carrier(html)})
        self.assertEqual(result["status"], "INCOMPLETE")
        codes = {x["code"] for x in result["unresolved"]}
        self.assertTrue({"CONTENT_DEPENDENCY_MISSING", "CONTENT_PATH_INVALID", "CONTENT_EXTERNAL_REFERENCE", "CONTENT_BASE_URL_UNSUPPORTED", "CONTENT_ACTIVE_ELEMENT_BLOCKED"} <= codes)
        self.assertEqual(result["dependencyManifest"]["entries"], [])

    def test_source_and_transitive_css_integrity_are_verified(self):
        changed = carrier("private")
        changed["base64"] = base64.b64encode(b"changed").decode()
        with self.assertRaises(ValueError):
            analyze({"html": changed})
        css = carrier("p{color:red}", path="a.css", mediaType="text/css")
        css["contentDigest"] = "sha256:" + "0" * 64
        with self.assertRaisesRegex(ValueError, "CONTENT_INTEGRITY_FAILURE"):
            analyze({"html": carrier('<link href="a.css" rel="stylesheet">'), "assets": [css]})

    def test_responsive_candidates_and_data_url_commas(self):
        result = analyze({"html": carrier('<img srcset="data:image/png;base64,YQ== 1x, two.png 2x">'),
                          "assets": [carrier("two", path="two.png", mediaType="image/png")]})
        self.assertEqual(result["status"], "COMPLETE")
        self.assertEqual([x["path"] for x in result["dependencyManifest"]["entries"]], ["two.png"])
        result = analyze({"html": carrier('<img srcset="one.png 1x 2x">')})
        self.assertEqual(result["status"], "INCOMPLETE")
        self.assertEqual(result["unresolved"][0]["code"], "CONTENT_SRCSET_INVALID")


if __name__ == "__main__":
    unittest.main()
