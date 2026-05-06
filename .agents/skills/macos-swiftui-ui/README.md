# macOS SwiftUI UI — SaaS-Clean Design System

TraceMacApp follows a Swiss-industrial, SaaS-grade design language. Every surface is flat, every color earns its place, and density serves clarity.

## Core Principles

- **White canvas, near-black type.** Color is reserved for status and node-kind accents — never decoration.
- **No gradients, no vibrancy, no blur.** Flat opaque surfaces, 1px borders, subtle drop shadows.
- **Density over decoration.** Information-rich without clutter. Every pixel justifies itself.
- **Status drives color.** Green = healthy/completed, red = error, yellow = slow/pending, blue = active/running.

## DashboardTheme Tokens

### Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `windowBackground` | #FFFFFF | Main canvas |
| `sidebarBackground` | #FAFAFA | Left sidebar |
| `surfaceRaised` | #F7F7F7 | Cards, pill backgrounds |
| `surfaceHover` | #F2F2F2 | Hover states |
| `surfaceActive` | #EDEDED | Active/pressed states |
| `borderDefault` | #E5E5E5 | Card borders, dividers |
| `borderStrong` | #D1D1D1 | Hover borders |
| `textPrimary` | #0A0A0A | Headings, values |
| `textSecondary` | #555555 | Body text |
| `textTertiary` | #8A8A8A | Labels, meta |
| `textQuaternary` | #B5B5B5 | Separators, placeholders |

### Semantic Accents

| Token | Purpose |
|-------|---------|
| `accentSuccess` (green) | Completed, healthy |
| `accentError` (red) | Error, failed, anomaly |
| `accentWarning` (yellow) | Slow, pending |
| `accentActive` (blue) | Running, selected, live |

### Node-Kind Accents (only vivid colors in the UI)

| Token | Color | Kind |
|-------|-------|------|
| `nodeAgent` | Purple #7C3AED | Agent spans |
| `nodeInference` | Blue #2563EB | Inference/chat |
| `nodeTool` | Orange #EA580C | Tool calls |
| `nodeStage` | Gray #6B7280 | Stages (prompt_eval, decode) |
| `nodeEmbedding` | Teal #0891B2 | Embeddings |
| `nodeSafety` | Green #16A34A | Safety checks |

### Fonts

| Token | Spec | Usage |
|-------|------|-------|
| `sectionHeader` | 11pt semibold small-caps | Section labels ("TRACES", "MODEL") |
| `rowTitle` | 13pt medium | Trace/span names |
| `rowMeta` | 11pt monospaced-digit | Timestamps, counts |
| `kpiValue` | 20pt semibold | Dashboard KPI numbers |
| `codeLarge` | 11pt monospaced | Code/attribute values |
| `badge` | 10pt medium | Pill labels |

### Spacing (4px base grid)

| Token | Value |
|-------|-------|
| `sm` | 4px |
| `md` | 8px |
| `lg` | 12px |
| `xl` | 16px |
| `xxl` | 24px |
| `cardPadding` | 12px |
| `cornerRadius` | 6px |
| `cornerRadiusSmall` | 4px |

### Shadows

| Level | Spec |
|-------|------|
| `sm` | black 4%, radius 2, y 1 |
| `md` | black 6%, radius 4, y 2 |

### Animations

| Token | Spec | Usage |
|-------|------|-------|
| `micro` | 0.10s ease-out | Hover states |
| `standard` | 0.2s ease-in-out | Tab switches, panel reveals |
| `smooth` | spring(0.35, 0.85) | Layout shifts |
| `entrance` | spring(0.5, 0.75) | Staggered node reveals |
| `pulse` | 1.2s ease-in-out repeat | Running status dot |

## Component Patterns

### Pills
Colored dot (6px) + label + count. `surfaceRaised` background, `cornerRadius` clip. Selected state: `accentActive` at 8% opacity background + 30% opacity border.

### Cards
`.dashboardCard()` modifier or manual: `windowBackground` bg, 1px `borderDefault` border, `cornerRadius` clip, `sm` shadow.

### Status Dots
6-8px circle. Color by `FlowNodeStatus`: green completed, blue+pulse running, red error, yellow pending.

### Duration Pills
Colored capsule: green `<100ms`, yellow `<1s`, red `>1s`. 9pt monospaced medium, `durationColor.opacity(0.08)` background.

### Accent Stripes
3px left edge on node rows, colored by `FlowNodeKind`. Agent nodes additionally get a 3px top crown stripe.

### Chips
8pt medium text, tinted `opacity(0.08)` background, capsule clip. Used for latency, hardware, event counts.

### Section Headers
9pt semibold with 0.8pt tracking, uppercase, `textTertiary` color, 56px fixed width for label alignment.

## SwiftUI-on-AppKit Conventions

- `@Observable` + `@MainActor` for view models. No `@StateObject` or `@ObservedObject` on view models.
- `@Environment(AppState.self)` injection. Use `@Bindable var appState = appState` inside `body` for bindings.
- `.onKeyPress()` for keyboard shortcuts (macOS 14+).
- `.onHover` with `NSCursor.pointingHand.push()/pop()` for interactive elements.
- `FlowGraphNode` is `ObservableObject` with `@Published status` — use `@ObservedObject` only for these.

## Animation Rules

- `.contentTransition(.numericText())` for changing numbers.
- `.matchedGeometryEffect` for tab indicator sliding.
- `spring(0.3, 0.85)` for expand/collapse.
- Completion cascade: glow flash (0.08s ease-in, 0.2s ease-out) + status dot scale pop (1.3 to 1.0).
- Streaming node entrance: `.opacity.combined(with: .scale(scale: 0.95))`.
- Drill transitions: `.asymmetric(insertion: .push(from: .trailing), removal: .push(from: .leading))`.
