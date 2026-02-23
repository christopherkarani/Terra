# Extract TerraViewer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract TraceMacApp and TerraCLI into a new `TerraViewer` repository, keeping TerraTraceKit in the Terra SDK repo as a remote SPM dependency.

**Architecture:** Two-phase extraction — first create the new TerraViewer repo with all app/CLI sources and a Package.swift that depends on Terra for TerraTraceKit, then clean up the Terra repo by removing extracted targets and updating CI.

**Tech Stack:** Swift 5.9, SPM, macOS 14+, OpenTelemetry, GitHub Actions

---

### Task 1: Create TerraViewer repo structure

**Files:**
- Create: `/Users/chriskarani/CodingProjects/TerraViewer/Package.swift`
- Create: `/Users/chriskarani/CodingProjects/TerraViewer/.gitignore`

**Step 1: Create the repo directory and initialize git**

```bash
mkdir -p /Users/chriskarani/CodingProjects/TerraViewer
cd /Users/chriskarani/CodingProjects/TerraViewer
git init
```

**Step 2: Create .gitignore**

```
.DS_Store
/.build
/Packages
xcuserdata/
DerivedData/
.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata
.netrc
```

**Step 3: Create Package.swift**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TerraViewer",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "TraceMacAppUI", targets: ["TraceMacAppUI"]),
    .executable(name: "TraceMacApp", targets: ["TraceMacApp"]),
    .executable(name: "terra", targets: ["TerraCLI"])
  ],
  dependencies: [
    .package(url: "https://github.com/christopherkarani/Terra.git", branch: "main"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.3.0"),
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.99.0"),
  ],
  targets: [
    .target(
      name: "TraceMacAppUI",
      dependencies: [
        .product(name: "TerraTraceKit", package: "Terra"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
      ],
      path: "Sources/TraceMacApp"
    ),
    .executableTarget(
      name: "TraceMacApp",
      dependencies: [
        "TraceMacAppUI",
        .product(name: "TerraTraceKit", package: "Terra"),
      ],
      path: "Sources/TraceMacAppExecutable"
    ),
    .executableTarget(
      name: "TerraCLI",
      dependencies: [
        .product(name: "TerraTraceKit", package: "Terra"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/TerraCLI"
    ),
    .testTarget(
      name: "TraceMacAppTests",
      dependencies: [
        "TraceMacAppUI",
        .product(name: "TerraTraceKit", package: "Terra"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TraceMacAppTests"
    ),
    .testTarget(
      name: "TraceMacAppUITests",
      dependencies: [
        "TraceMacAppUI",
        .product(name: "TerraTraceKit", package: "Terra"),
        .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        .product(name: "Testing", package: "swift-testing"),
      ],
      path: "Tests/TraceMacAppUITests"
    ),
  ]
)
```

**Step 4: Commit**

```bash
git add Package.swift .gitignore
git commit -m "chore: initialize TerraViewer with Package.swift"
```

---

### Task 2: Copy source files to TerraViewer

**Files:**
- Copy: `Terra/Sources/TraceMacApp/` → `TerraViewer/Sources/TraceMacApp/`
- Copy: `Terra/Sources/TraceMacAppExecutable/` → `TerraViewer/Sources/TraceMacAppExecutable/`
- Copy: `Terra/Sources/terra-cli/` → `TerraViewer/Sources/TerraCLI/`
- Copy: `Terra/Tests/TraceMacAppTests/` → `TerraViewer/Tests/TraceMacAppTests/`
- Copy: `Terra/Tests/TraceMacAppUITests/` → `TerraViewer/Tests/TraceMacAppUITests/`
- Copy: `Terra/Apps/TraceMacApp/` → `TerraViewer/Apps/TraceMacApp/`

**Step 1: Copy all source directories**

```bash
TERRA=/Users/chriskarani/CodingProjects/Terra
VIEWER=/Users/chriskarani/CodingProjects/TerraViewer

# App UI sources
cp -R "$TERRA/Sources/TraceMacApp" "$VIEWER/Sources/TraceMacApp"

# App entry point
cp -R "$TERRA/Sources/TraceMacAppExecutable" "$VIEWER/Sources/TraceMacAppExecutable"

# CLI (rename directory from terra-cli to TerraCLI to match Package.swift path)
cp -R "$TERRA/Sources/terra-cli" "$VIEWER/Sources/TerraCLI"

# Tests
cp -R "$TERRA/Tests/TraceMacAppTests" "$VIEWER/Tests/TraceMacAppTests"
cp -R "$TERRA/Tests/TraceMacAppUITests" "$VIEWER/Tests/TraceMacAppUITests"

# Xcode project + assets
cp -R "$TERRA/Apps" "$VIEWER/Apps"
```

**Step 2: Commit**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
git add Sources/ Tests/ Apps/
git commit -m "feat: copy TraceMacApp, TerraCLI, and tests from Terra repo"
```

---

### Task 3: Verify TerraViewer builds

**Step 1: Resolve packages and build TraceMacApp**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
swift build --target TraceMacApp
```

Expected: BUILD SUCCEEDED

**Step 2: Build TerraCLI**

```bash
swift build --target TerraCLI
```

Expected: BUILD SUCCEEDED

**Step 3: Run tests**

```bash
swift test
```

Expected: All tests pass (TraceMacAppTests + TraceMacAppUITests)

**Step 4: Fix any issues**

If builds fail due to import paths or missing dependencies, fix them in the TerraViewer Package.swift or source files. Common issues:
- The CLI path changed from `Sources/terra-cli` to `Sources/TerraCLI` — no source changes needed since SPM uses directory path, not name
- If any test file imports a target that no longer exists in this package, update the import

**Step 5: Commit fixes if any**

```bash
git add -A
git commit -m "fix: resolve build issues after extraction"
```

---

### Task 4: Clean up Terra repo — remove extracted targets from Package.swift

**Files:**
- Modify: `/Users/chriskarani/CodingProjects/Terra/Package.swift`

**Step 1: Remove these products from the `products` array**

```swift
// REMOVE these 3 lines:
.library(name: "TraceMacAppUI", targets: ["TraceMacAppUI"]),
.executable(name: "TraceMacApp", targets: ["TraceMacApp"]),
.executable(name: "terra", targets: ["TerraCLI"])
```

**Step 2: Remove `swift-argument-parser` from `dependencies` array**

```swift
// REMOVE this line:
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
```

**Step 3: Remove these targets from the `targets` array**

Remove the following target declarations:
- `TraceMacAppUI` target (lines 174-182)
- `TraceMacAppTests` test target (lines 284-294)
- `TraceMacAppUITests` test target (lines 295-305)
- `TerraCLI` executable target (lines 314-321)
- `TraceMacApp` executable target (lines 322-329)

Also remove the `// MARK: - TraceMacApp UI` comment.

**Step 4: Verify Terra still builds**

```bash
cd /Users/chriskarani/CodingProjects/Terra
swift build
```

Expected: BUILD SUCCEEDED (SDK targets only)

**Step 5: Run Terra tests**

```bash
swift test
```

Expected: All remaining SDK tests pass (TerraTests, TerraTraceKitTests, etc.)

**Step 6: Commit**

```bash
git add Package.swift
git commit -m "chore: remove TraceMacApp, TerraCLI targets from Package.swift"
```

---

### Task 5: Clean up Terra repo — delete extracted source files

**Files:**
- Delete: `Sources/TraceMacApp/` (92 files)
- Delete: `Sources/TraceMacAppExecutable/` (1 file)
- Delete: `Sources/terra-cli/` (5 files)
- Delete: `Tests/TraceMacAppTests/` (11 files)
- Delete: `Tests/TraceMacAppUITests/` (13 files)
- Delete: `Apps/TraceMacApp/` (xcodeproj, entitlements, plist)

**Step 1: Delete directories**

```bash
cd /Users/chriskarani/CodingProjects/Terra
rm -rf Sources/TraceMacApp
rm -rf Sources/TraceMacAppExecutable
rm -rf Sources/terra-cli
rm -rf Tests/TraceMacAppTests
rm -rf Tests/TraceMacAppUITests
rm -rf Apps/TraceMacApp
```

**Step 2: Remove empty Apps/ dir if nothing else is in it**

```bash
rmdir Apps 2>/dev/null || true
```

**Step 3: Verify build still works**

```bash
swift build
swift test
```

Expected: Both succeed with no errors.

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: delete extracted TraceMacApp and TerraCLI source files"
```

---

### Task 6: Update Terra CI workflow

**Files:**
- Modify: `/Users/chriskarani/CodingProjects/Terra/.github/workflows/ci.yml`

**Step 1: Remove the TraceMacApp Xcode build step**

Remove the "TraceMacApp (unsigned) build" step from the `swift` job (lines 43-53):

```yaml
# REMOVE this entire step:
      - name: TraceMacApp (unsigned) build
        run: |
          ...
```

**Step 2: Remove TraceMacApp from API breaking changes check**

In the "API breaking changes" step (line 40), remove:
```yaml
swift package diagnose-api-breaking-changes Terra
# KEEP only the above, remove this line since it references SDK:
```

Wait — `TerraTraceKit` API check should stay since it's still in the repo. Only `TraceMacApp` was extracted. The existing lines check `Terra` (the umbrella SDK target) and `TerraTraceKit`, both of which stay. No change needed here.

**Step 3: Update RC hardening references**

The rc-hardening job references `tracemacapp-performance-gate.json` and `.txt` in the required artifacts list. These performance gates likely run TraceMacApp tests. Either:
- Remove the TraceMacApp performance gate entries from the required list, OR
- Update the rc_hardening.sh script if it references TraceMacApp targets

Check `Scripts/rc_hardening.sh` and remove TraceMacApp-related gates.

**Step 4: Update job name**

```yaml
# Change:
name: SwiftPM + TraceMacApp build
# To:
name: SwiftPM build + test
```

**Step 5: Verify CI config is valid**

```bash
cd /Users/chriskarani/CodingProjects/Terra
# Dry-run YAML validation
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))" 2>/dev/null || echo "check yaml manually"
```

**Step 6: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: remove TraceMacApp build steps from CI"
```

---

### Task 7: Update Terra CLAUDE.md

**Files:**
- Modify: `/Users/chriskarani/CodingProjects/Terra/CLAUDE.md`

**Step 1: Remove TraceMacApp sections**

Remove or update these sections:
- "Build Commands" — remove `swift build --target TraceMacApp` and Xcode build commands
- "Module Dependency Graph" — remove TraceMacApp, TraceMacAppUI, TerraCLI entries
- "TraceMacApp" architecture section
- "TerraCLI" architecture section
- "Dual Build System" section (no longer relevant — Xcode project moved)
- Test targets list — remove TraceMacAppTests, TraceMacAppUITests
- CI section — remove TraceMacApp build reference

**Step 2: Add note about TerraViewer**

Add a brief note that TraceMacApp and TerraCLI have been extracted to the `TerraViewer` repository.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md after TraceMacApp extraction"
```

---

### Task 8: Create TerraViewer CLAUDE.md

**Files:**
- Create: `/Users/chriskarani/CodingProjects/TerraViewer/CLAUDE.md`

**Step 1: Write CLAUDE.md**

Adapt the TraceMacApp-relevant sections from the Terra CLAUDE.md into a standalone project guide covering:
- Project overview (TerraViewer = Mac trace viewer + CLI for Terra SDK)
- Build commands (swift build, swift test, xcodebuild)
- Architecture (TraceMacAppUI, TerraTraceKit dependency, TerraCLI)
- Key conventions
- External dependencies

**Step 2: Commit**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md for TerraViewer"
```

---

### Task 9: Create TerraViewer GitHub repo and push

**Step 1: Create GitHub repo**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
gh repo create christopherkarani/TerraViewer --public --source=. --push
```

Or if private:
```bash
gh repo create christopherkarani/TerraViewer --private --source=. --push
```

**Step 2: Verify remote**

```bash
git remote -v
git log --oneline
```

Expected: All commits pushed, remote set.

---

### Task 10: Final verification — both repos build independently

**Step 1: Verify Terra SDK builds and tests pass**

```bash
cd /Users/chriskarani/CodingProjects/Terra
swift build
swift test
```

Expected: BUILD SUCCEEDED, all SDK tests pass.

**Step 2: Verify TerraViewer builds and tests pass**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
swift package resolve
swift build --target TraceMacApp
swift build --target TerraCLI
swift test
```

Expected: All targets build, all tests pass.

**Step 3: Verify the app launches**

```bash
cd /Users/chriskarani/CodingProjects/TerraViewer
swift build --target TraceMacApp && open .build/arm64-apple-macosx/debug/TraceMacApp
```

Expected: TraceMacApp window opens normally.
