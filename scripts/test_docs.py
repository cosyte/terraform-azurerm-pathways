"""Tests for scripts/docs.py: the generated reference, the example pages, the release numbers and
the two archives. Standard library only; no test reads the network or runs Terraform.

    python3 -m unittest discover -s scripts -p 'test_*.py'
"""

import gzip
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import docs  # noqa: E402

VARIABLES_TF = '''variable "name" {
  description = "Short name."
  type        = string

  validation {
    condition     = length(var.name) > 2
    error_message = "name must be 3 to 16 lowercase letters."
  }
}

variable "ports" {
  description = <<-EOT
    The ports, such as {2575}
    and <none> else.
  EOT
  type    = list(number)
  default = [2575]

  validation {
    condition     = length(var.ports) <= 6
    error_message = "ports must hold 1 to 6 ports: one main and five more."
  }

  validation {
    condition     = !contains(var.ports, 80)
    error_message = "Port 80 belongs to the \\"http\\" ingress."
  }
}
'''

TFDOCS = {
    "requirements": [
        {"name": "terraform", "version": ">= 1.9.0"},
        {"name": "azurerm", "version": ">= 4.42.0, < 5.0.0"},
    ],
    "providers": [{"name": "azurerm", "alias": None, "version": ">= 4.42.0, < 5.0.0"}],
    "modules": [],
    "resources": [
        {"type": "key_vault", "name": "this", "provider": "azurerm", "mode": "managed"},
    ],
    "inputs": [
        {"name": "ports", "type": "list(number)", "description": "The ports, such as {2575}\nand <none> else.\n",
         "default": [2575], "required": False, "sensitive": False},
        {"name": "name", "type": "string", "description": "Short name.", "default": None,
         "required": True, "sensitive": False},
        {"name": "settings", "type": "object({\n    a = optional(string)\n  })", "description": "Settings.",
         "default": {}, "required": False, "sensitive": False},
    ],
    "outputs": [
        {"name": "url", "description": "The URL, a <secret>.", "sensitive": True},
        {"name": "name", "description": "The name.", "sensitive": False},
    ],
}

SIDEBAR = {
    "docs": [
        "intro",
        {"type": "category", "label": "Reference", "items": [
            "inputs-and-outputs",
            {"type": "category", "label": "Modules", "items": ["module-logs"]},
            {"type": "category", "label": "Examples", "items": ["example-basic"]},
        ]},
    ]
}

EXAMPLE_PAGE = """---
id: example-basic
title: The basic example
sidebar_label: basic
description: "One slot."
---

# The basic example

## What it deploys

One slot.

## What it costs to leave running

Some.

## Files
"""


def git(cwd, *args):
    subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True)


class Repo:
    """A throwaway repository with a module, one example and a docs-content folder."""

    def __init__(self, test):
        self._tmp = tempfile.TemporaryDirectory()
        test.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.write("variables.tf", VARIABLES_TF)
        self.write("main.tf", "# The composition.\n")
        self.write("outputs.tf", "")
        self.write("versions.tf", "")
        self.write("README.md", "# readme\n")
        self.write("LICENSE", "MIT\n")
        self.write("CHANGELOG.md", "# Changelog\n")
        self.write("modules/logs/variables.tf", "")
        self.write("modules/logs/main.tf", "")
        self.write("examples/basic/main.tf", 'module "x" {\n  source = "../.."\n}\n')
        self.write("examples/basic/versions.tf", "terraform {}\n")
        self.write("docs-content/intro.md", "---\nid: intro\n---\n\n# Intro\n\nSee [the reference](./inputs-and-outputs.md).\n")
        self.write("docs-content/sidebars.json", json.dumps(SIDEBAR, indent=2) + "\n")
        self.write("docs-content/example-basic.md", EXAMPLE_PAGE)
        git(self.root, "init", "-q")
        self.add()

    def write(self, rel, text):
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def add(self):
        git(self.root, "add", "-A")

    def tfdocs(self, _directory):
        return TFDOCS


class TextTest(unittest.TestCase):
    def test_mdx_text_escapes_what_mdx_would_read_as_code_or_markup(self):
        self.assertEqual(docs.mdx_text("a {b} <c> *d* `e` [f] g_h"), r"a \{b\} \<c\> \*d\* \`e\` \[f\] g\_h")

    def test_mdx_text_joins_the_lines_of_a_paragraph(self):
        self.assertEqual(docs.mdx_text("one\ntwo\n\nthree\n"), "one two\n\nthree")

    def test_slug_follows_the_sites_heading_anchors(self):
        self.assertEqual(docs.slug("`storage`"), "storage")
        self.assertEqual(docs.slug("What it costs to leave running"), "what-it-costs-to-leave-running")


class RefusalsTest(unittest.TestCase):
    def test_each_variables_error_messages_in_order(self):
        refusals = docs.refusals(VARIABLES_TF)
        self.assertEqual(refusals["name"], ["name must be 3 to 16 lowercase letters."])
        self.assertEqual(
            refusals["ports"],
            ["ports must hold 1 to 6 ports: one main and five more.", 'Port 80 belongs to the "http" ingress.'],
        )

    def test_a_variable_with_no_validation_has_none(self):
        self.assertEqual(docs.refusals('variable "a" {\n  type = string\n}\n').get("a", []), [])


class ReferenceTest(unittest.TestCase):
    def setUp(self):
        self.page = docs.render_reference(
            TFDOCS,
            VARIABLES_TF,
            page_id="inputs-and-outputs",
            title="Inputs and outputs",
            label="Inputs and outputs",
            description="Every input and output of the root module.",
            lead="The root module.",
            source_dir=".",
        )

    def test_opens_with_the_front_matter_the_standard_asks_for(self):
        self.assertTrue(self.page.startswith(
            '---\nid: inputs-and-outputs\ntitle: Inputs and outputs\nsidebar_label: Inputs and outputs\n'
            'description: "Every input and output of the root module."\n---\n'
        ))

    def test_required_inputs_come_first_then_optional_by_name(self):
        name, ports, settings = (self.page.index("### `name`"), self.page.index("### `ports`"),
                                 self.page.index("### `settings`"))
        self.assertLess(name, ports)
        self.assertLess(ports, settings)
        self.assertIn("Required.", self.page[name:ports])

    def test_shows_types_defaults_and_refusals(self):
        ports = self.page[self.page.index("### `ports`"):self.page.index("### `settings`")]
        self.assertIn("```hcl\nlist(number)\n```", ports)
        self.assertIn("Default: `[2575]`", ports)
        self.assertIn(r"The ports, such as \{2575\} and \<none\> else.", ports)
        self.assertIn("- ports must hold 1 to 6 ports: one main and five more.", ports)
        settings = self.page[self.page.index("### `settings`"):]
        self.assertIn("```hcl\nobject({\n  a = optional(string)\n})\n```", settings)
        self.assertIn("Default: `{}`", settings)

    def test_lists_every_output_and_marks_the_sensitive_ones(self):
        outputs = self.page[self.page.index("## Outputs"):]
        self.assertIn("### `url`", outputs)
        self.assertIn(r"The URL, a \<secret\>.", outputs)
        self.assertLess(outputs.index("### `name`"), outputs.index("### `url`"))
        self.assertIn("Sensitive", outputs[outputs.index("### `url`"):])
        self.assertNotIn("Sensitive", outputs[outputs.index("### `name`"):outputs.index("### `url`")])

    def test_names_the_requirements_and_resources(self):
        self.assertIn("| `azurerm` | `>= 4.42.0, < 5.0.0` |", self.page)
        self.assertIn("`azurerm_key_vault.this`", self.page)

    def test_holds_no_brace_or_angle_bracket_outside_code(self):
        self.assertEqual(docs.unescaped_markup(self.page), [])


class CheckTest(unittest.TestCase):
    def test_a_generated_tree_checks_clean(self):
        repo = Repo(self)
        docs.generate(repo.root, repo.tfdocs)
        self.assertEqual(docs.check(repo.root, repo.tfdocs), [])

    def test_an_example_folder_with_no_page_fails(self):
        repo = Repo(self)
        repo.write("examples/sftp/main.tf", "# sftp\n")
        repo.add()
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("examples/sftp" in f and "no page" in f for f in findings), findings)

    def test_an_example_page_missing_a_section_fails(self):
        repo = Repo(self)
        repo.write("docs-content/example-basic.md", EXAMPLE_PAGE.replace("## What it costs to leave running\n\nSome.\n\n", ""))
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("What it costs to leave running" in f for f in findings), findings)

    def test_an_example_page_whose_files_drifted_fails_until_regenerated(self):
        repo = Repo(self)
        docs.generate(repo.root, repo.tfdocs)
        repo.write("examples/basic/main.tf", 'module "x" {\n  source = "../../"\n}\n')
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("example-basic.md" in f for f in findings), findings)
        docs.generate(repo.root, repo.tfdocs)
        self.assertEqual(docs.check(repo.root, repo.tfdocs), [])
        page = (repo.root / "docs-content/example-basic.md").read_text()
        self.assertIn('```hcl title="examples/basic/main.tf"\nmodule "x" {\n  source = "../../"\n}\n```', page)
        self.assertIn("## What it deploys\n\nOne slot.", page)

    def test_a_page_for_an_example_that_does_not_exist_fails(self):
        repo = Repo(self)
        repo.write("docs-content/example-gone.md", EXAMPLE_PAGE.replace("example-basic", "example-gone"))
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("example-gone.md" in f and "examples/gone" in f for f in findings), findings)

    def test_an_example_page_not_in_the_sidebar_fails(self):
        repo = Repo(self)
        sidebar = json.loads(json.dumps(SIDEBAR))
        sidebar["docs"][1]["items"] = ["inputs-and-outputs", "module-logs"]
        repo.write("docs-content/sidebars.json", json.dumps(sidebar))
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("example-basic" in f and "sidebar" in f for f in findings), findings)

    def test_a_stale_reference_page_fails(self):
        repo = Repo(self)
        docs.generate(repo.root, repo.tfdocs)
        path = repo.root / "docs-content/inputs-and-outputs.md"
        path.write_text(path.read_text().replace("Short name.", "A name."))
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("inputs-and-outputs.md" in f for f in findings), findings)

    def test_every_module_gets_a_reference_page(self):
        repo = Repo(self)
        docs.generate(repo.root, repo.tfdocs)
        self.assertTrue((repo.root / "docs-content/module-logs.md").is_file())

    def test_a_link_to_a_page_that_does_not_exist_fails(self):
        repo = Repo(self)
        repo.write("docs-content/intro.md", "---\nid: intro\n---\n\nSee [gone](./gone.md#x).\n")
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("./gone.md" in f for f in findings), findings)

    def test_a_link_to_an_anchor_no_heading_gets_fails(self):
        repo = Repo(self)
        repo.write("docs-content/intro.md", "---\nid: intro\n---\n\nSee [x](./inputs-and-outputs.md#nope) and "
                   "[y](./inputs-and-outputs.md#ports) and [z](./example-basic.md#what-it-deploys).\n")
        docs.generate(repo.root, repo.tfdocs)
        findings = docs.check(repo.root, repo.tfdocs)
        self.assertTrue(any("#nope" in f for f in findings), findings)
        self.assertFalse(any("#ports" in f or "#what-it-deploys" in f for f in findings), findings)

    def test_check_writes_nothing(self):
        repo = Repo(self)
        before = (repo.root / "docs-content/example-basic.md").read_text()
        docs.check(repo.root, repo.tfdocs)
        self.assertEqual((repo.root / "docs-content/example-basic.md").read_text(), before)
        self.assertFalse((repo.root / "docs-content/inputs-and-outputs.md").exists())


QUALITY = """---
id: performance
---

# Performance

## What we measure

Words.

## Current numbers

The numbers for this section are measured on `main` at each release and filled in when the
release is built. They are never typed by hand.

## How to run them

More words.
"""

NUMBERS = {
    "commit": "0123456789abcdef0123456789abcdef01234567",
    "date": "2026-11-12",
    "version": "0.0.1",
    "terraform": "1.15.7",
    "runner": "ubuntu-24.04, X64",
    "folders": [
        {"folder": ".", "test_files": 3, "run_blocks": 40},
        {"folder": "modules/logs", "test_files": 1, "run_blocks": 4},
    ],
    "checks": [
        {"name": "validate", "command": "scripts/validate.sh", "seconds": 51.2, "passed": True},
        {"name": "test", "command": "tests/run.sh", "seconds": 43.0, "passed": True},
    ],
}


class NumbersTest(unittest.TestCase):
    def test_fill_replaces_only_the_current_numbers_section(self):
        filled = docs.fill_numbers(QUALITY, "performance", NUMBERS)
        self.assertIn("## What we measure\n\nWords.", filled)
        self.assertIn("## How to run them\n\nMore words.", filled)
        self.assertNotIn("never typed by hand", filled)
        self.assertIn("`0123456789ab`", filled)
        self.assertIn("| `tests/run.sh` | 43.0 |", filled)

    def test_testing_numbers_count_the_run_blocks(self):
        filled = docs.fill_numbers(QUALITY.replace("performance", "testing-and-quality"), "testing-and-quality", NUMBERS)
        self.assertIn("| `modules/logs` | 1 | 4 |", filled)
        self.assertIn("44 run blocks", filled)

    def test_a_page_without_the_section_is_refused(self):
        with self.assertRaises(docs.DocsError):
            docs.fill_numbers("# Performance\n", "performance", NUMBERS)

    def test_count_run_blocks(self):
        repo = Repo(self)
        repo.write("tests/a.tftest.hcl", 'run "one" {\n  command = plan\n}\n\nrun "two" {\n  command = plan\n}\n')
        repo.write("modules/logs/tests/b.tftest.hcl", 'run "one" {\n  command = plan\n}\n')
        counts = docs.count_tests(repo.root)
        self.assertEqual(counts, [
            {"folder": ".", "test_files": 1, "run_blocks": 2},
            {"folder": "modules/logs", "test_files": 1, "run_blocks": 1},
        ])


def members(path):
    with tarfile.open(path, "r:gz") as tar:
        return {m.name: tar.extractfile(m).read() if m.isfile() else None for m in tar.getmembers()}


class PackTest(unittest.TestCase):
    def test_both_archives_hold_their_files_at_the_root(self):
        repo = Repo(self)
        repo.write("docs-content/performance.md", QUALITY)
        repo.add()
        out = repo.root / "dist-artifacts"
        docs.pack(repo.root, out, NUMBERS)
        content = members(out / "docs-content.tar.gz")
        self.assertIn("intro.md", content)
        self.assertIn("sidebars.json", content)
        self.assertNotIn("never typed by hand", content["performance.md"].decode())
        self.assertFalse(any(name.startswith(("./", "/")) for name in content))
        source = members(out / "source.tar.gz")
        for name in ("main.tf", "variables.tf", "README.md", "LICENSE", "CHANGELOG.md", "modules/logs/main.tf",
                     "examples/basic/main.tf"):
            self.assertIn(name, source)
        self.assertFalse(any(name.startswith("docs-content/") for name in source))

    def test_the_same_tree_packs_to_the_same_bytes(self):
        repo = Repo(self)
        a, b = repo.root / "a", repo.root / "b"
        docs.pack(repo.root, a, None)
        docs.pack(repo.root, b, None)
        for name in ("docs-content.tar.gz", "source.tar.gz"):
            self.assertEqual((a / name).read_bytes(), (b / name).read_bytes(), name)

    def test_without_numbers_the_placeholder_is_left_and_flagged(self):
        repo = Repo(self)
        repo.write("docs-content/performance.md", QUALITY)
        repo.add()
        docs.pack(repo.root, repo.root / "out", None)
        content = members(repo.root / "out" / "docs-content.tar.gz")
        self.assertIn("never typed by hand", content["performance.md"].decode())

    def test_refuses_a_tree_without_intro_or_sidebar(self):
        repo = Repo(self)
        os.remove(repo.root / "docs-content/intro.md")
        with self.assertRaises(docs.DocsError):
            docs.pack(repo.root, repo.root / "out", None)
        self.assertFalse((repo.root / "out").exists())


class NotesTest(unittest.TestCase):
    CHANGELOG = "# Changelog\n\n## Unreleased (patch)\n\n- Next.\n\n## 0.0.2\n\n- Two.\n- More.\n\n## 0.0.1\n\n- One.\n"

    def test_the_notes_are_the_versions_section(self):
        self.assertEqual(docs.release_notes(self.CHANGELOG, "0.0.2"), "- Two.\n- More.\n")
        self.assertEqual(docs.release_notes(self.CHANGELOG, "0.0.1"), "- One.\n")

    def test_a_version_with_no_section_is_refused(self):
        with self.assertRaises(docs.DocsError):
            docs.release_notes(self.CHANGELOG, "0.0.3")


class GzipTest(unittest.TestCase):
    def test_the_gzip_header_carries_no_time_or_name(self):
        buffer = io.BytesIO()
        docs.write_tar_gz(buffer, [("a.txt", b"a\n")], 0)
        raw = buffer.getvalue()
        self.assertEqual(raw[4:8], b"\x00\x00\x00\x00")
        self.assertEqual(gzip.decompress(raw)[:5], b"a.txt")


if __name__ == "__main__":
    unittest.main()
