# Task: CI — Toolchain Pinning

Prompt:
Pin the CI Swift toolchain (and related runner dependencies) to explicit versions to ensure reproducible builds.

Goal:
Remove floating CI toolchain configuration so builds are deterministic and stable.

Task Breakdown:
- Inspect `.github/workflows/` for Swift setup steps or toolchain usage.
- Pin Swift toolchain versions explicitly (and any related setup actions) per repo requirements.
- Avoid changing CI behavior beyond pinning.

Expected Output:
- CI workflow updates with explicit Swift toolchain pinning.
- Brief note listing pinned versions.
