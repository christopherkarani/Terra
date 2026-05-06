#!/usr/bin/env python3
"""Validate public Markdown snippets that coding agents are likely to copy."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

DOCS = [
    ROOT / "README.md",
    ROOT / "Docs" / "cookbook.md",
    ROOT / "Docs" / "integrations.md",
]

DOCC_DIR = ROOT / "Sources" / "TerraAutoInstrument" / "Terra.docc"
EXAMPLES_DIR = ROOT / "Examples"
EXAMPLE_EXTENSIONS = {".md", ".swift"}

BANNED_SWIFT_PATTERNS = [
    "Terra.trace(",
    "Terra.agentic(",
    "Terra.loop(",
    "TraceHandle",
    "Terra.ModelID(",
    "Terra.ToolCallID(",
    "callID:",
    ".execute {",
    ".includeContent()",
]

FENCE_RE = re.compile(r"```(?P<label>[^\n`]*)\n(?P<body>.*?)```", re.DOTALL)
DOCC_LINK_RE = re.compile(r"<doc:([^>#]+)")


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def public_paths() -> list[pathlib.Path]:
    paths = list(DOCS)
    paths.extend(sorted(DOCC_DIR.glob("*.md")))
    if EXAMPLES_DIR.exists():
        paths.extend(
            path
            for path in sorted(EXAMPLES_DIR.rglob("*"))
            if path.is_file() and path.suffix in EXAMPLE_EXTENSIONS
        )
    return paths


def validate_docc_links(paths: list[pathlib.Path]) -> None:
    docc_paths = [path for path in paths if path.parent == DOCC_DIR and path.suffix == ".md"]
    available_pages = {path.stem for path in docc_paths}
    for path in docc_paths:
        source = path.read_text(encoding="utf-8")
        for match in DOCC_LINK_RE.finditer(source):
            target = match.group(1).split("/", 1)[0]
            if target not in available_pages:
                fail(f"{path.relative_to(ROOT)} links to missing DocC page <doc:{target}>")


def main() -> None:
    paths = public_paths()
    validate_docc_links(paths)

    for path in paths:
        if not path.exists():
            fail(f"missing public doc: {path.relative_to(ROOT)}")

        source = path.read_text(encoding="utf-8")
        for pattern in BANNED_SWIFT_PATTERNS:
            if pattern in source:
                fail(f"{path.relative_to(ROOT)} contains legacy API pattern `{pattern}`")

        for match in FENCE_RE.finditer(source):
            label = match.group("label").strip().lower()
            body = match.group("body")
            if "Terra." in body or "TerraCore" in body:
                if label not in {"swift", "swift package", "bash", "sh", "shell"}:
                    fail(
                        f"{path.relative_to(ROOT)} has a Terra snippet with unlabeled fence "
                        f"near byte {match.start()}"
                    )

    print("OK: public docs, DocC links, and examples use canonical Terra references.")


if __name__ == "__main__":
    main()
