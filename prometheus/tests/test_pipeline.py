import importlib.util
import json
from pathlib import Path
import os
import tempfile
import unittest
from unittest.mock import patch

OVERLAY = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pipeline", OVERLAY / "pipeline.py")
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)


class PipelineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name)
        files = {
            "frontend/src/data/standards.json": json.dumps([{"name": "standards.Existing", "keep": {"x": [1, 2]}}]),
            "backend/Modules/CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1":
                "$TenantFilter $Type $Action $Identity $Parameters",
            "backend/Modules/CIPPCore/Public/Set-CIPPStandardsCompareField.ps1": "$TenantFilter",
            "build/Dockerfile.release": "FROM scratch",
        }
        for name, text in files.items():
            target = self.source / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

    def test_preserves_existing_catalog_and_copies_backend(self):
        original = json.loads((self.source / "frontend/src/data/standards.json").read_text())
        self.assertEqual(pipeline.prepare(self.source), 1)
        combined = json.loads((self.source / "frontend/src/data/standards.json").read_text())
        self.assertEqual(combined[:-1], original)
        function = self.source / f"backend/Modules/CIPPStandards/Public/Standards/{pipeline.SOURCE_FILE}"
        self.assertEqual(function.read_bytes(), (OVERLAY / pipeline.SOURCE_FILE).read_bytes())

    def test_repeat_application_stops_without_overwriting(self):
        pipeline.prepare(self.source)
        catalog = self.source / "frontend/src/data/standards.json"
        before = catalog.read_bytes()
        with self.assertRaisesRegex(ValueError, "Duplicate"):
            pipeline.prepare(self.source)
        self.assertEqual(catalog.read_bytes(), before)

    def test_changed_helper_stops_before_source_mutation(self):
        helper = self.source / "backend/Modules/CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1"
        helper.write_text("$TenantFilter")
        before = (self.source / "frontend/src/data/standards.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "contract changed"):
            pipeline.prepare(self.source)
        self.assertEqual((self.source / "frontend/src/data/standards.json").read_bytes(), before)

    def test_rejects_prerelease(self):
        with patch.object(pipeline, "api", return_value={"tag_name": "v12.0.0-preview", "draft": False, "prerelease": True}):
            with self.assertRaises(ValueError):
                pipeline.resolve()

    def test_resolves_exact_stable_commit_with_custom_version(self):
        with patch.object(pipeline, "api", side_effect=[
            {"tag_name": "v11.0.2", "draft": False, "prerelease": False}, {"sha": "a" * 40}
        ]):
            result = pipeline.resolve()
        self.assertEqual(result["upstream_sha"], "a" * 40)
        self.assertRegex(result["version"], r"^11\.0\.2\+prometheus\.aaaaaaaa\.[a-f0-9]{12}$")
        self.assertEqual(result["image_tag"], result["version"].replace("+", "-", 1))
        self.assertRegex(result["image_tag"], r"^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$")
        self.assertEqual(result["build"], "true")

    def test_smoke_rejects_container_missing_compiled_standard(self):
        directory = self.source / "API/Modules/CIPPStandards"
        directory.mkdir(parents=True)
        (directory / "CIPPStandards.psd1").write_text("@{ FunctionsToExport = '*' }")
        (directory / "CIPPStandards.psm1").write_text("function Existing {}")
        with self.assertRaisesRegex(ValueError, "not compiled"):
            pipeline.smoke(self.source, "test")

    def resolve_recorded_build(self, recorded_sha="a" * 40, force=False, recorded_version=None):
        (self.source / "build-state.json").write_text(json.dumps({
            "version": recorded_version or "11.0.2+prometheus.aaaaaaaa.123456789abc.build.12345",
            "upstream_sha": recorded_sha,
        }))
        with patch.object(pipeline, "ROOT", self.source), \
                patch.object(pipeline, "overlay_hash", return_value="123456789abc"), \
                patch.object(pipeline, "api", side_effect=[
                    {"tag_name": "v11.0.2", "draft": False, "prerelease": False},
                    {"sha": "a" * 40},
                ]), patch.dict(os.environ, {"GITHUB_RUN_ID": "67890"}):
            return pipeline.resolve(force)

    def test_daily_check_preserves_successful_forced_build(self):
        self.assertEqual(self.resolve_recorded_build()["build"], "false")

    def test_changed_upstream_still_builds_after_forced_build(self):
        self.assertEqual(self.resolve_recorded_build(recorded_sha="b" * 40)["build"], "true")

    def test_requested_forced_rebuild_gets_distinct_version(self):
        result = self.resolve_recorded_build(force=True)
        self.assertEqual(result["build"], "true")
        self.assertEqual(result["version"], "11.0.2+prometheus.aaaaaaaa.123456789abc.build.67890")
        self.assertEqual(result["image_tag"], "11.0.2-prometheus.aaaaaaaa.123456789abc.build.67890")

    def test_existing_prerelease_version_is_rebuilt_with_correct_metadata(self):
        result = self.resolve_recorded_build(recorded_version="11.0.2-prometheus.aaaaaaaa.123456789abc")
        self.assertEqual(result["build"], "true")
        self.assertEqual(result["version"], "11.0.2+prometheus.aaaaaaaa.123456789abc")


if __name__ == "__main__":
    unittest.main()
