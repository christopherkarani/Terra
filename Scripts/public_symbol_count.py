#!/usr/bin/env python3
from __future__ import annotations

import argparse
import glob
import json
import os
import subprocess
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Baseline:
    terra: int
    terra_core: int


DEFAULT_BASELINE = Baseline(terra=92, terra_core=48)


def _run_dump_symbol_graph(pretty: bool) -> None:
    cmd = ["swift", "package", "dump-symbol-graph", "--skip-synthesized-members"]
    if pretty:
        cmd.append("--pretty-print")
    subprocess.run(cmd, check=True)


def _find_symbolgraph_dir() -> str:
    candidates = sorted(
        set(glob.glob(".build/**/symbolgraph", recursive=True)),
        key=lambda p: (len(p.split(os.sep)), p),
    )
    if not candidates:
        raise RuntimeError("No symbolgraph directories found under .build. Run `swift package dump-symbol-graph`.")

    def score(path: str) -> tuple[int, int]:
        terra = os.path.join(path, "Terra@TerraCore.symbols.json")
        terra_core = os.path.join(path, "TerraCore.symbols.json")
        return (int(os.path.exists(terra)) + int(os.path.exists(terra_core)), -len(path))

    best = max(candidates, key=score)
    return best


def _read_unique_symbols_by_module(symbolgraph_dir: str) -> dict[str, set[str]]:
    modules: dict[str, set[str]] = {}
    for path in glob.glob(os.path.join(symbolgraph_dir, "*.symbols.json")):
        with open(path, "r", encoding="utf-8") as f:
            graph = json.load(f)
        module_name = graph.get("module", {}).get("name")
        if not module_name:
            continue
        precise_ids = {s["identifier"]["precise"] for s in graph.get("symbols", [])}
        modules.setdefault(module_name, set()).update(precise_ids)
    return modules


def _pct_change(current: int, baseline: int) -> float:
    if baseline == 0:
        return 0.0
    return (current - baseline) / baseline * 100.0


def main() -> int:
    parser = argparse.ArgumentParser(description="Count unique public symbols per module from Swift symbolgraphs.")
    parser.add_argument("--no-dump", action="store_true", help="Skip `swift package dump-symbol-graph` step.")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON symbolgraphs (slower, larger).")
    parser.add_argument("--symbolgraph-dir", default=None, help="Explicit symbolgraph directory (defaults to .build/**/symbolgraph).")
    parser.add_argument("--baseline-terra", type=int, default=DEFAULT_BASELINE.terra)
    parser.add_argument("--baseline-terra-core", type=int, default=DEFAULT_BASELINE.terra_core)
    parser.add_argument("--format", choices=["text", "json"], default="text")
    args = parser.parse_args()

    baseline = Baseline(terra=args.baseline_terra, terra_core=args.baseline_terra_core)

    if not args.no_dump:
        _run_dump_symbol_graph(pretty=args.pretty)

    symbolgraph_dir = args.symbolgraph_dir or _find_symbolgraph_dir()
    modules = _read_unique_symbols_by_module(symbolgraph_dir)

    terra_count = len(modules.get("Terra", set()))
    terra_core_count = len(modules.get("TerraCore", set()))

    payload = {
        "symbolgraphDir": symbolgraph_dir,
        "baseline": {"Terra": baseline.terra, "TerraCore": baseline.terra_core},
        "current": {"Terra": terra_count, "TerraCore": terra_core_count},
        "delta": {
            "Terra": terra_count - baseline.terra,
            "TerraCore": terra_core_count - baseline.terra_core,
        },
        "pctChange": {
            "Terra": _pct_change(terra_count, baseline.terra),
            "TerraCore": _pct_change(terra_core_count, baseline.terra_core),
        },
    }

    if args.format == "json":
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return 0

    print(f"Symbolgraphs: {symbolgraph_dir}")
    print("")
    print("Module     Baseline  Current  Δ    %")
    print("---------  --------  -------  ---  --------")
    print(
        f"Terra      {baseline.terra:8d}  {terra_count:7d}  {terra_count - baseline.terra:3d}  {payload['pctChange']['Terra']:7.2f}%"
    )
    print(
        f"TerraCore  {baseline.terra_core:8d}  {terra_core_count:7d}  {terra_core_count - baseline.terra_core:3d}  {payload['pctChange']['TerraCore']:7.2f}%"
    )

    missing = [m for m in ("Terra", "TerraCore") if m not in modules]
    if missing:
        print("")
        print(f"Warning: missing modules in symbolgraphs: {', '.join(missing)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

