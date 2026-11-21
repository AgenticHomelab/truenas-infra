"""Validate the exact declared history-free public source selection offline."""

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "publication/candidate-files.txt"
REQUIRED = {
    ".github/workflows/validate.yml",
    "tests/test_public_export.py",
    "publication/candidate-files.txt",
}
ROOT_ALIASES = (
    ("publication/README.public.md", "README.md"),
    ("publication/AGENTS.public.md", "AGENTS.md"),
    ("publication/garage-backup.public.md", "docs/garage-backup.md"),
)


def candidate_paths():
    return [
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


class PublicExportTests(unittest.TestCase):
    def test_manifest_is_closed_over_checked_in_validation(self):
        paths = candidate_paths()
        self.assertEqual(len(paths), len(set(paths)))
        self.assertTrue(REQUIRED.issubset(paths))
        for draft, public in ROOT_ALIASES:
            self.assertTrue(
                (draft in paths) != (public in paths),
                f"Exactly one root source is required: {draft} or {public}",
            )
        for rel in paths:
            with self.subTest(path=rel):
                relative = Path(rel)
                self.assertFalse(relative.is_absolute() or ".." in relative.parts)
                rendered = {"publication/README.public.md": "README.md",
                            "publication/AGENTS.public.md": "AGENTS.md",
                            "publication/garage-backup.public.md": "docs/garage-backup.md"}.get(rel, rel)
                self.assertTrue((ROOT / relative).is_file() or (ROOT / rendered).is_file())
                self.assertFalse((ROOT / relative).is_symlink())

    def test_excludes_private_evidence_and_runtime_artifacts(self):
        paths = candidate_paths()
        for rel in paths:
            with self.subTest(path=rel):
                self.assertNotEqual(rel, "docs/adoption.md")
                if rel == "docs/garage-backup.md":
                    self.assertIn(
                        "This guide describes the reusable desired-state",
                        (ROOT / rel).read_text(encoding="utf-8"),
                        "Only the sanitized public guide may be selected",
                    )
                self.assertNotIn(".terraform", Path(rel).parts)
                self.assertNotIn(Path(rel).suffix, {".tfstate", ".tfplan", ".pem", ".key"})

    def test_workflow_runs_only_included_test(self):
        workflow = (ROOT / ".github/workflows/validate.yml").read_text(encoding="utf-8")
        self.assertIn("tests -p 'test_public_export.py'", workflow)
        self.assertNotIn("test_publication_scope.py", workflow)


if __name__ == "__main__":
    unittest.main()
