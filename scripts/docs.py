#!/usr/bin/env python3
"""The docs-content pages the code owns, and the two archives a release attaches.

    scripts/docs.py generate --terraform-docs BIN   write the generated pages
    scripts/docs.py check --terraform-docs BIN      write nothing; exit 1 on any finding
    scripts/docs.py measure --version X --out FILE  run the checks a release reports, timed
    scripts/docs.py notes --version X --out FILE    the CHANGELOG section of a version
    scripts/docs.py pack --out DIR [--numbers FILE] build docs-content.tar.gz and source.tar.gz

scripts/docs.sh runs generate and check with the terraform-docs pinned in mise.toml.

What the code owns in docs-content/:

* the reference: one page for the root module, inputs-and-outputs.md, and one per module under
  modules/, module-<name>.md, each written from terraform-docs' reading of the module and from the
  error_message of each validation in its variables.tf;
* the Files section of each example's page, example-<name>.md: everything from its "## Files"
  heading to the end is the example's tracked files, shown whole.

The check fails when a generated page or section differs from what the code gives, when a folder
under examples/ has no page, when an example page has no "What it deploys", "What it costs to leave
running" or "Files" section, when a page names an example that does not exist, when an example or
reference page is not in sidebars.json, when a relative link names a page or an anchor that does not
exist, and when a brace or an angle bracket sits outside code (Docusaurus reads a page as MDX).

Standard library only, so CI needs nothing but python3.
"""

import argparse
import datetime
import gzip
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import time
import unicodedata
from pathlib import Path

DOCS_DIR = "docs-content"
SIDEBAR_FILE = "sidebars.json"
ROOT_PAGE = "inputs-and-outputs"
EXAMPLE_SECTIONS = ("## What it deploys", "## What it costs to leave running")
FILES_HEADING = "## Files"
NUMBERS_HEADING = "## Current numbers"
QUALITY_PAGES = ("testing-and-quality", "performance")
SOURCE_PATHS = ("versions.tf", "variables.tf", "main.tf", "outputs.tf", "modules", "examples", "README.md",
                "LICENSE", "CHANGELOG.md")
REPOSITORY = "github.com/cosyte/terraform-azurerm-pathways"
GENERATOR = "`scripts/docs.sh`"
RELEASE_CHECKS = (("validate", "scripts/validate.sh"), ("test", "tests/run.sh"))
LANGUAGES = {".tf": "hcl", ".hcl": "hcl", ".yaml": "yaml", ".yml": "yaml", ".json": "json", ".md": "markdown",
             ".sh": "bash"}


class DocsError(Exception):
    """A refusal: the input is not what this script can work from."""


# Text


MDX_SPECIAL = set("\\`*_{}<>[]|")


def mdx_text(text):
    """Plain text as Markdown that MDX reads as the same text: each paragraph on one line, and every
    character Markdown or MDX would read as markup escaped."""
    paragraphs = []
    for block in re.split(r"\n\s*\n", text.strip()):
        line = " ".join(part.strip() for part in block.splitlines() if part.strip())
        paragraphs.append("".join("\\" + ch if ch in MDX_SPECIAL else ch for ch in line))
    return "\n\n".join(p for p in paragraphs if p)


def mdx_prose(text):
    """Markdown prose, such as a README paragraph, made safe for MDX: lines joined, and a brace or an
    angle bracket outside a code span escaped. Code spans and other Markdown are left as written."""
    line = " ".join(part.strip() for part in text.strip().splitlines() if part.strip())
    pieces = re.split(r"(`[^`]*`)", line)
    for i in range(0, len(pieces), 2):
        pieces[i] = re.sub(r"(?<!\\)([{}<>])", r"\\\1", pieces[i])
    return "".join(pieces)


def slug(heading):
    """The anchor docs.cosyte.com gives a heading: a code span read as its content, a link as its
    text and an escape as its character, in lower case, keeping letters, marks, digits, underscores,
    spaces and hyphens, each space a hyphen."""
    text = re.sub(r"`([^`]*)`", r"\1", heading)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\\(.)", r"\1", text)
    kept = [ch for ch in text.lower() if unicodedata.category(ch)[0] in "LMN" or ch in "_- "]
    return "".join(kept).replace(" ", "-")


def outside_fences(text):
    """Each line of a page that is not front matter and not inside a fenced block, with its number."""
    lines = text.split("\n")
    start = 0
    if lines and lines[0] == "---":
        for i in range(1, len(lines)):
            if lines[i] == "---":
                start = i + 1
                break
    fence = None
    for number, line in enumerate(lines[start:], start + 1):
        match = re.match(r"^\s*(`{3,}|~{3,})", line)
        if fence is None and match:
            fence = match.group(1)
            continue
        if fence is not None:
            if line.strip().startswith(fence[0] * len(fence)) and line.strip().strip(fence[0]) == "":
                fence = None
            continue
        yield number, line


def anchors(text):
    """Every anchor the headings of a page get, a repeat numbered -1, -2, as the site numbers them."""
    seen = {}
    found = set()
    for _, line in outside_fences(text):
        match = re.match(r"^#{1,6}\s+(.*?)\s*#*\s*$", line)
        if not match:
            continue
        base = slug(match.group(1))
        count = seen.get(base, 0)
        seen[base] = count + 1
        found.add(base if count == 0 else f"{base}-{count}")
    return found


def unescaped_markup(text):
    """The lines holding a brace or an angle bracket outside code that MDX would read as markup."""
    bad = []
    for number, line in outside_fences(text):
        prose = re.sub(r"`[^`]*`", "", line)
        if re.search(r"(?<!\\)[{}<>]", prose):
            bad.append(number)
    return bad


def front_matter(page_id, title, label, description):
    if len(description) > 160:
        raise DocsError(f"{page_id}: the description is {len(description)} characters, over 160")
    return (f"---\nid: {page_id}\ntitle: {title}\nsidebar_label: {label}\n"
            f"description: {json.dumps(description, ensure_ascii=False)}\n---\n")


def page_id_of(text):
    match = re.search(r"^id:\s*(\S+)\s*$", text, re.M)
    return match.group(1) if match else None


# The reference


def refusals(variables_tf):
    """The error_message of each validation, by variable, in the order variables.tf gives them.

    Reads the file as `terraform fmt` writes it: a variable block opens at the start of a line and
    closes at the next line that is a lone closing brace."""
    found = {}
    current = None
    for line in variables_tf.splitlines():
        opened = re.match(r'^variable\s+"([^"]+)"\s*\{', line)
        if opened:
            current = opened.group(1)
            found.setdefault(current, [])
            continue
        if line.rstrip() == "}":
            current = None
            continue
        message = re.match(r'^\s*error_message\s*=\s*("(?:[^"\\]|\\.)*")\s*$', line)
        if current and message:
            found[current].append(json.loads(message.group(1)))
    return found


def dedent_type(text):
    lines = text.rstrip().split("\n")
    rest = [line for line in lines[1:] if line.strip()]
    if not rest:
        return lines[0]
    cut = min(len(line) - len(line.lstrip(" ")) for line in rest)
    return "\n".join([lines[0]] + [line[cut:] for line in lines[1:]])


def fence(body, language, title=None):
    longest = max((len(run) for run in re.findall(r"`+", body)), default=0)
    marks = "`" * max(3, longest + 1)
    info = language + (f' title="{title}"' if title else "")
    if not body.endswith("\n"):
        body += "\n"
    return f"{marks}{info}\n{body}{marks}"


def render_default(value):
    compact = json.dumps(value, ensure_ascii=False, separators=(", ", ": "))
    if len(compact) <= 80 and "`" not in compact:
        return f"Default: `{compact}`"
    return "Default:\n\n" + fence(json.dumps(value, ensure_ascii=False, indent=2), "json")


def resource_address(resource):
    kind = resource["type"]
    provider = resource.get("provider") or ""
    if provider and not kind.startswith(provider + "_"):
        kind = f"{provider}_{kind}"
    prefix = "data." if resource.get("mode") == "data" else ""
    return f"{prefix}{kind}.{resource['name']}"


def render_reference(tfdocs, variables_tf, page_id, title, label, description, lead, source_dir):
    """One reference page: requirements, modules, resources, every input and every output."""
    where = "the repository root" if source_dir == "." else f"`{source_dir}/`"
    files = "variables.tf" if source_dir == "." else f"{source_dir}/variables.tf"
    out = [front_matter(page_id, title, label, description), f"# {title}", "", lead, "",
           f"This page is generated from the code in {where} by {GENERATOR}, and CI fails when it no longer "
           f"matches. Change `{files}` or its `outputs.tf`, then run {GENERATOR}.", ""]

    out += ["## Requirements", "", "| Name | Version |", "| --- | --- |"]
    for requirement in tfdocs.get("requirements") or []:
        out.append(f"| `{requirement['name']}` | `{requirement.get('version') or 'any'}` |")
    out.append("")

    modules = tfdocs.get("modules") or []
    if modules:
        out += ["## Modules", "", "| Name | Source |", "| --- | --- |"]
        for module in modules:
            out.append(f"| `{module['name']}` | `{module['source']}` |")
        out.append("")

    resources = tfdocs.get("resources") or []
    if resources:
        out += ["## Resources", ""]
        for resource in sorted(resources, key=resource_address):
            out.append(f"- `{resource_address(resource)}`")
        out.append("")

    checks = refusals(variables_tf)
    inputs = sorted(tfdocs.get("inputs") or [], key=lambda i: (not i.get("required"), i["name"]))
    required = sum(1 for i in inputs if i.get("required"))
    out += ["## Inputs", "",
            f"{len(inputs)} inputs, {required} of them required. The required ones come first, then the rest "
            "by name.", ""]
    for item in inputs:
        out += [f"### `{item['name']}`", ""]
        state = "Required." if item.get("required") else "Optional."
        if item.get("sensitive"):
            state += " Sensitive: Terraform hides its value in plans and output."
        out += [state, ""]
        if item.get("description"):
            out += [mdx_text(item["description"]), ""]
        out += ["Type:", "", fence(dedent_type(str(item.get("type") or "any")), "hcl"), ""]
        if not item.get("required"):
            out += [render_default(item.get("default")), ""]
        if checks.get(item["name"]):
            out += ["The plan refuses a value that breaks this rule, with this message:"
                    if len(checks[item["name"]]) == 1
                    else "The plan refuses a value that breaks one of these rules, with its message:", ""]
            out += [f"- {mdx_text(message)}" for message in checks[item["name"]]]
            out.append("")

    outputs = sorted(tfdocs.get("outputs") or [], key=lambda o: o["name"])
    out += ["## Outputs", "", f"{len(outputs)} outputs, by name.", ""]
    for item in outputs:
        out += [f"### `{item['name']}`", ""]
        if item.get("description"):
            out += [mdx_text(item["description"]), ""]
        if item.get("sensitive"):
            out += ["Sensitive: `terraform output` shows it only when named, as "
                    f"`terraform output -json {item['name']}`.", ""]
    return "\n".join(out).rstrip("\n") + "\n"


def readme_lead(module_dir):
    """The first paragraph of a module's README, after its title."""
    readme = module_dir / "README.md"
    if not readme.is_file():
        return f"The `{module_dir.name}` module."
    blocks = [b for b in re.split(r"\n\s*\n", readme.read_text(encoding="utf-8")) if b.strip()]
    blocks = [b for b in blocks if not b.lstrip().startswith("#")]
    if not blocks:
        return f"The `{module_dir.name}` module."
    lead = mdx_prose(blocks[0])
    # A paragraph that ends in a colon introduces the list after it, which comes along.
    if lead.endswith(":") and len(blocks) > 1 and blocks[1].lstrip().startswith("- "):
        items = re.split(r"\n(?=- )", blocks[1].strip())
        lead += "\n\n" + "\n".join("- " + mdx_prose(item[2:]) for item in items)
    return lead


def module_dirs(root):
    base = root / "modules"
    return sorted(p for p in base.iterdir() if p.is_dir()) if base.is_dir() else []


def module_page_id(module_dir):
    return "module-" + module_dir.name.replace("_", "-")


def reference_pages(root, tfdocs):
    """Every reference page, by file name, as the code gives it."""
    pages = {}
    pages[f"{ROOT_PAGE}.md"] = render_reference(
        tfdocs(root), read(root / "variables.tf"),
        page_id=ROOT_PAGE, title="Inputs and outputs", label="Inputs and outputs",
        description="Every input and output of the root module, with its type, its default and what the plan "
                    "refuses, generated from the code.",
        lead="The root module composes the modules under `modules/`: this is the page to read when you call "
             f"`source = \"{REPOSITORY}\"`. Each module has a page of its own as well.",
        source_dir=".",
    )
    for module_dir in module_dirs(root):
        name = module_dir.name
        page_id = module_page_id(module_dir)
        lead = (readme_lead(module_dir) + "\n\nUse it on its own with "
                f"`source = \"{REPOSITORY}//modules/{name}\"`.")
        pages[f"{page_id}.md"] = render_reference(
            tfdocs(module_dir), read(module_dir / "variables.tf"),
            page_id=page_id, title=f"The {name} module", label=name,
            description=f"Every input and output of the {name} module, generated from its code.",
            lead=lead, source_dir=f"modules/{name}",
        )
    return pages


# The examples


def tracked_files(root, path):
    """The files git tracks under a path, relative to the root, sorted."""
    result = subprocess.run(["git", "ls-files", "-z", "--", path], cwd=root, capture_output=True, check=True)
    names = [n for n in result.stdout.decode("utf-8").split("\0") if n]
    return sorted(n for n in names if (root / n).is_file())


def example_dirs(root):
    base = root / "examples"
    if not base.is_dir():
        return []
    return sorted(p.name for p in base.iterdir() if p.is_dir() and tracked_files(root, f"examples/{p.name}"))


def example_page_id(name):
    return "example-" + name.replace("_", "-")


def files_section(root, name):
    folder = f"examples/{name}"
    out = [FILES_HEADING, "",
           f"Every file in `{folder}`, as the repository holds it. {GENERATOR} writes this section from the "
           "folder, and CI fails when the two differ.", ""]
    for path in tracked_files(root, folder):
        relative = path[len(folder) + 1:]
        body = (root / path).read_text(encoding="utf-8")
        language = LANGUAGES.get(Path(path).suffix, "text")
        out += [f"### `{relative}`", "", fence(body, language, path), ""]
    return "\n".join(out).rstrip("\n") + "\n"


def example_page(root, name, current):
    """The page with its Files section as the folder gives it, and the findings about its shape."""
    findings = []
    page = f"{DOCS_DIR}/{example_page_id(name)}.md"
    lines = current.split("\n")
    if page_id_of(current) != example_page_id(name):
        findings.append(f"{page}: its front matter id is not {example_page_id(name)}")
    positions = {}
    for heading in EXAMPLE_SECTIONS + (FILES_HEADING,):
        if heading in lines:
            positions[heading] = lines.index(heading)
        else:
            findings.append(f"{page}: no \"{heading}\" section; every example page says what it deploys, what it "
                            "costs to leave running, and shows its files")
    if FILES_HEADING in positions:
        if any(positions[h] > positions[FILES_HEADING] for h in EXAMPLE_SECTIONS if h in positions):
            findings.append(f"{page}: \"{FILES_HEADING}\" comes last, after what it deploys and what it costs")
        head = "\n".join(lines[:positions[FILES_HEADING]]).rstrip("\n")
    else:
        head = current.rstrip("\n")
    return head + "\n\n" + files_section(root, name), findings


# Generate and check


def read(path):
    return path.read_text(encoding="utf-8") if path.is_file() else ""


def sidebar_ids(node):
    if isinstance(node, str):
        return [node]
    if isinstance(node, list):
        return [i for item in node for i in sidebar_ids(item)]
    if isinstance(node, dict):
        return [i for value in node.values() for i in sidebar_ids(value)]
    return []


def expected_pages(root, tfdocs):
    """What the code gives: every generated page, by file name, and the findings about examples."""
    docs = root / DOCS_DIR
    pages = reference_pages(root, tfdocs)
    findings = []
    names = example_dirs(root)
    for name in names:
        filename = f"{example_page_id(name)}.md"
        current = read(docs / filename)
        if not current:
            findings.append(f"examples/{name} has no page: write {DOCS_DIR}/{filename}, with \"What it deploys\", "
                            f"\"What it costs to leave running\" and \"{FILES_HEADING}\" sections, and list it in "
                            f"{SIDEBAR_FILE}")
            continue
        pages[filename], page_findings = example_page(root, name, current)
        findings += page_findings
    known = {example_page_id(n) for n in names}
    for path in sorted(docs.glob("example-*.md")) if docs.is_dir() else []:
        if path.stem not in known:
            findings.append(f"{DOCS_DIR}/{path.name} is a page for an example that does not exist: no folder "
                            f"examples/{path.stem[len('example-'):]} with tracked files")
    return pages, findings


def generate(root, tfdocs):
    pages, findings = expected_pages(root, tfdocs)
    for filename, text in pages.items():
        path = root / DOCS_DIR / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        if read(path) != text:
            path.write_text(text, encoding="utf-8")
    return findings


def check(root, tfdocs):
    """Every finding, without writing anything."""
    docs = root / DOCS_DIR
    pages, findings = expected_pages(root, tfdocs)
    for filename, text in sorted(pages.items()):
        if read(docs / filename) != text:
            findings.append(f"{DOCS_DIR}/{filename} differs from what the code gives: run {GENERATOR} and commit it")

    try:
        listed = set(sidebar_ids(json.loads(read(docs / SIDEBAR_FILE) or "null")))
    except json.JSONDecodeError as error:
        listed = set()
        findings.append(f"{DOCS_DIR}/{SIDEBAR_FILE} is not JSON: {error}")
    for filename in sorted(pages):
        page_id = filename[:-3]
        if page_id not in listed:
            findings.append(f"{page_id} is not in the sidebar: list it in {DOCS_DIR}/{SIDEBAR_FILE}")

    texts = {p.name: read(p) for p in sorted(docs.glob("*.md"))} if docs.is_dir() else {}
    texts.update(pages)
    for filename, text in sorted(texts.items()):
        for number in unescaped_markup(text):
            findings.append(f"{DOCS_DIR}/{filename}:{number}: a brace or an angle bracket outside code; "
                            "write it in code or escape it, since the site reads the page as MDX")
        for number, line in outside_fences(text):
            for target in re.findall(r"\]\((\./[^)\s]+)\)", re.sub(r"`[^`]*`", "", line)):
                path, _, anchor = target.partition("#")
                name = path[2:]
                if name not in texts:
                    findings.append(f"{DOCS_DIR}/{filename}:{number}: the link {target} names no page")
                elif anchor and anchor not in anchors(texts[name]):
                    findings.append(f"{DOCS_DIR}/{filename}:{number}: the link {target} names no heading on {name}")
    return findings


# Release numbers


def count_tests(root):
    """The test files and run blocks of the root module and of each module under modules/."""
    rows = []
    for folder in [root] + module_dirs(root):
        files = sorted((folder / "tests").glob("*.tftest.hcl"))
        runs = sum(len(re.findall(r'^run\s+"', read(f), re.M)) for f in files)
        rows.append({"folder": "." if folder == root else folder.relative_to(root).as_posix(),
                     "test_files": len(files), "run_blocks": runs})
    return rows


def numbers_heading_line(numbers):
    return (f"Measured by the release workflow for version `{numbers['version']}`, at commit "
            f"`{numbers['commit'][:12]}`, on {numbers['date']}, with Terraform {numbers['terraform']} on a "
            f"GitHub-hosted runner ({numbers['runner']}).")


def numbers_section(page, numbers):
    out = [NUMBERS_HEADING, "", numbers_heading_line(numbers), ""]
    if page == "testing-and-quality":
        files = sum(r["test_files"] for r in numbers["folders"])
        runs = sum(r["run_blocks"] for r in numbers["folders"])
        out += ["| Folder | Test files | Run blocks |", "| --- | --- | --- |"]
        out += [f"| `{r['folder']}` | {r['test_files']} | {r['run_blocks']} |" for r in numbers["folders"]]
        out += ["", f"In all, {files} test files and {runs} run blocks, each a plan against mocked providers.", "",
                "| Check | Command | Result |", "| --- | --- | --- |"]
        out += [f"| {c['name']} | `{c['command']}` | {'passed' if c['passed'] else 'failed'} |"
                for c in numbers["checks"]]
    else:
        out += ["| Command | Seconds | Result |", "| --- | --- | --- |"]
        out += [f"| `{c['command']}` | {c['seconds']:.1f} | {'passed' if c['passed'] else 'failed'} |"
                for c in numbers["checks"]]
        out += ["", "One run each, on one runner: a second run of the same commit can take a different time."]
    return out


def fill_numbers(text, page, numbers):
    """The page with its "Current numbers" section replaced by the numbers a release measured."""
    lines = text.split("\n")
    if NUMBERS_HEADING not in lines:
        raise DocsError(f"{page}.md has no \"{NUMBERS_HEADING}\" section to fill")
    start = lines.index(NUMBERS_HEADING)
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^#{1,2}\s", lines[i]):
            end = i
            break
    tail = lines[end:]
    return "\n".join(lines[:start] + numbers_section(page, numbers) + ([""] + tail if tail else [""]))


def measure(root, version):
    """Run the checks a release reports, timed, and gather what the quality pages show."""
    checks = []
    for name, command in RELEASE_CHECKS:
        started = time.monotonic()
        code = subprocess.run([str(root / command)], cwd=root).returncode
        checks.append({"name": name, "command": command, "seconds": round(time.monotonic() - started, 1),
                       "passed": code == 0})
    terraform = json.loads(subprocess.run(["terraform", "version", "-json"], cwd=root, capture_output=True,
                                          check=True).stdout)["terraform_version"]
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, check=True,
                            text=True).stdout.strip()
    runner = ", ".join(v for v in (os.environ.get("ImageOS") or os.environ.get("RUNNER_OS"),
                                   os.environ.get("RUNNER_ARCH")) if v) or "unknown"
    return {
        "version": version,
        "commit": commit,
        "date": datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
        "terraform": terraform,
        "runner": runner,
        "folders": count_tests(root),
        "checks": checks,
    }


def release_notes(changelog, version):
    """The CHANGELOG section headed with the version, without its heading."""
    lines = changelog.split("\n")
    heading = f"## {version}"
    if heading not in lines:
        raise DocsError(f"CHANGELOG.md has no \"{heading}\" section: name the release there before tagging it")
    start = lines.index(heading) + 1
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))
    body = "\n".join(lines[start:end]).strip()
    if not body:
        raise DocsError(f"CHANGELOG.md: the \"{heading}\" section is empty")
    return body + "\n"


# Archives


def write_tar_gz(fileobj, entries, mtime):
    """A gzip-compressed tar of (name, bytes[, mode]) entries, the same bytes for the same input: no
    time or name in the gzip header, and every member owned by 0 with the given time."""
    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for entry in entries:
            name, data = entry[0], entry[1]
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = mtime
            info.mode = entry[2] if len(entry) > 2 else 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            tar.addfile(info, io.BytesIO(data))
    with gzip.GzipFile(filename="", fileobj=fileobj, mode="wb", mtime=0, compresslevel=9) as gz:
        gz.write(raw.getvalue())


def commit_time(root):
    result = subprocess.run(["git", "log", "-1", "--format=%ct"], cwd=root, capture_output=True, text=True)
    return int(result.stdout.strip()) if result.returncode == 0 and result.stdout.strip() else 0


def pack(root, out, numbers):
    """Build out/docs-content.tar.gz, the contents of docs-content/ at its root with the release's
    numbers in the quality pages, and out/source.tar.gz, the module's tracked source at its root.
    Every input is read before out/ is made, so a refusal leaves nothing behind."""
    docs_files = tracked_files(root, DOCS_DIR)
    for required in (f"{DOCS_DIR}/intro.md", f"{DOCS_DIR}/{SIDEBAR_FILE}"):
        if required not in docs_files:
            raise DocsError(f"{required} is missing: the docs site needs it in docs-content.tar.gz")
    mtime = commit_time(root)

    def mode(path):
        return 0o755 if os.access(root / path, os.X_OK) else 0o644

    docs_entries = []
    for path in docs_files:
        data = (root / path).read_bytes()
        stem = Path(path).stem
        if numbers is not None and Path(path).parent.as_posix() == DOCS_DIR and stem in QUALITY_PAGES:
            data = fill_numbers(data.decode("utf-8"), stem, numbers).encode("utf-8")
        docs_entries.append((path[len(DOCS_DIR) + 1:], data, mode(path)))
    source_entries = [(path, (root / path).read_bytes(), mode(path))
                      for path in tracked_files(root, ".") if path.split("/")[0] in SOURCE_PATHS]

    docs_buffer, source_buffer = io.BytesIO(), io.BytesIO()
    write_tar_gz(docs_buffer, docs_entries, mtime)
    write_tar_gz(source_buffer, source_entries, mtime)
    out.mkdir(parents=True, exist_ok=True)
    (out / "docs-content.tar.gz").write_bytes(docs_buffer.getvalue())
    (out / "source.tar.gz").write_bytes(source_buffer.getvalue())
    return [out / "docs-content.tar.gz", out / "source.tar.gz"]


# The command


def terraform_docs(binary):
    def run(directory):
        result = subprocess.run([binary, "json", "--sort=false", str(directory)], capture_output=True, text=True)
        if result.returncode != 0:
            raise DocsError(f"terraform-docs failed in {directory}: {result.stderr.strip()}")
        return json.loads(result.stdout)
    return run


def main(argv):
    parser = argparse.ArgumentParser(prog="scripts/docs.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("generate", "check"):
        p = sub.add_parser(name)
        p.add_argument("--terraform-docs", required=True)
    p = sub.add_parser("measure")
    p.add_argument("--version", required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("notes")
    p.add_argument("--version", required=True)
    p.add_argument("--out", required=True)
    p = sub.add_parser("pack")
    p.add_argument("--out", required=True)
    p.add_argument("--numbers")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parent.parent

    try:
        if args.command == "generate":
            findings = generate(root, terraform_docs(args.terraform_docs))
            for finding in findings:
                print(f"scripts/docs.py: {finding}", file=sys.stderr)
            print(f"Generated the reference and example pages in {DOCS_DIR}/.")
            return 1 if findings else 0
        if args.command == "check":
            findings = check(root, terraform_docs(args.terraform_docs))
            for finding in findings:
                print(f"scripts/docs.py: {finding}", file=sys.stderr)
            if findings:
                print(f"scripts/docs.py: {len(findings)} finding(s) in {DOCS_DIR}/", file=sys.stderr)
                return 1
            print(f"{DOCS_DIR}/ matches the code: every reference page, every example and its files.")
            return 0
        if args.command == "measure":
            numbers = measure(root, args.version)
            Path(args.out).write_text(json.dumps(numbers, indent=2) + "\n", encoding="utf-8")
            failed = [c["command"] for c in numbers["checks"] if not c["passed"]]
            if failed:
                print(f"scripts/docs.py: failed: {', '.join(failed)}", file=sys.stderr)
                return 1
            return 0
        if args.command == "notes":
            Path(args.out).write_text(release_notes(read(root / "CHANGELOG.md"), args.version), encoding="utf-8")
            return 0
        if args.command == "pack":
            numbers = json.loads(Path(args.numbers).read_text(encoding="utf-8")) if args.numbers else None
            for path in pack(root, Path(args.out).resolve(), numbers):
                print(path)
            return 0
    except DocsError as error:
        print(f"scripts/docs.py: {error}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
