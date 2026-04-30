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


def fail(message: str) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    for path in DOCS:
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

    print("OK: public docs snippets use canonical, labeled Terra examples.")


if __name__ == "__main__":
    main()
