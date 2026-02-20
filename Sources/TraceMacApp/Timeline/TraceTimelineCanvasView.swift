import SwiftUI
import TerraTraceKit
import OpenTelemetrySdk
import OpenTelemetryApi

// MARK: - SpanLayout

/// Cached layout geometry for a single span bar in the timeline.
private struct SpanLayout: Identifiable {
    let id: String
    let span: SpanData
    let rect: CGRect
    let isError: Bool
    let isCritical: Bool
}

// MARK: - TraceTimelineCanvasView

/// A high-performance waterfall timeline rendered using `Canvas`.
///
/// Displays span bars arranged in non-overlapping lanes with color coding for
/// normal, error, and critical spans. Supports zoom, hover highlights,
/// and span selection through gesture overlays.
struct TraceTimelineCanvasView: View {

    // MARK: - Properties

    /// The timeline view model providing lane and span data.
    let viewModel: TimelineViewModel

    /// The currently selected span identifier.
    var selectedSpanId: SpanId?

    /// Callback invoked when a span is tapped.
    var onSelectSpan: ((SpanData) -> Void)?

    // MARK: - State

    @Binding var zoomScale: CGFloat
    @State private var hoveredSpanId: SpanId?
    @State private var layouts: [SpanLayout] = []
    @State private var contentSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0

    // MARK: - Layout Constants

    private let rowHeight: CGFloat = 20
    private let rowSpacing: CGFloat = 8
    private let topPadding: CGFloat = 16
    private let leftPadding: CGFloat = 16
    private let rightPadding: CGFloat = 16
    private let minimumCanvasWidth: CGFloat = 600
    private let minimumBarWidth: CGFloat = 2
    private let labelMinimumWidth: CGFloat = 52
    private let barCornerRadius: CGFloat = 5
    private let laneCornerRadius: CGFloat = 6
    private let zoomMinimum: CGFloat = 0.5
    private let zoomMaximum: CGFloat = 5.0
    private let zoomStep: CGFloat = 1.25

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                timelineCanvas
                    .frame(
                        width: max(contentSize.width, 1),
                        height: max(contentSize.height, 1)
                    )
            }
            .onChange(of: proxy.size.width) { _, newWidth in
                containerWidth = newWidth
                rebuildLayouts()
            }
            .onAppear {
                containerWidth = proxy.size.width
                rebuildLayouts()
            }
        }
        .onChange(of: zoomScale) {
            rebuildLayouts()
        }
    }

    // MARK: - Canvas

    private var timelineCanvas: some View {
        ZStack {
            Canvas { context, size in
                drawLaneBackgrounds(context: &context, size: size)
                drawConnectorLines(context: &context, size: size)
                drawSpanBars(context: &context, size: size)
            }
            .accessibilityHidden(true)

            ForEach(layouts) { layout in
                Color.clear
                    .frame(width: layout.rect.width, height: layout.rect.height)
                    .position(x: layout.rect.midX, y: layout.rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(accessibilityLabel(for: layout))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction {
                        onSelectSpan?(layout.span)
                    }
            }
        }
        .overlay {
            hitTestOverlay
        }
        .gesture(zoomGesture)
        .accessibilityLabel("Trace timeline")
        .accessibilityHint("Displays span bars in a waterfall layout. Use VoiceOver to navigate individual spans.")
    }

    // MARK: - Drawing

    private func drawLaneBackgrounds(context: inout GraphicsContext, size: CGSize) {
        let availableWidth = size.width - leftPadding - rightPadding
        let lanes = viewModel.lanes

        for laneIndex in lanes.indices {
            let y = topPadding + CGFloat(laneIndex) * (rowHeight + rowSpacing)
            let laneRect = CGRect(
                x: leftPadding,
                y: y - 2,
                width: availableWidth,
                height: rowHeight + 4
            )
            guard laneRect.intersects(CGRect(origin: .zero, size: size)) else { continue }
            let lanePath = RoundedRectangle(cornerRadius: laneCornerRadius)
                .path(in: laneRect)
            context.fill(lanePath, with: .color(.gray.opacity(0.08)))
        }
    }

    private func drawConnectorLines(context: inout GraphicsContext, size: CGSize) {
        var layoutBySpanId: [String: SpanLayout] = [:]
        for layout in layouts {
            layoutBySpanId[layout.span.spanId.hexString] = layout
        }

        let visibleRect = CGRect(origin: .zero, size: size)
        for layout in layouts {
            guard let parentId = layout.span.parentSpanId else { continue }
            guard let parentLayout = layoutBySpanId[parentId.hexString] else { continue }
            guard layout.rect.intersects(visibleRect) else { continue }

            let startX = parentLayout.rect.midX
            let startY = parentLayout.rect.maxY
            let endX = layout.rect.minX
            let endY = layout.rect.midY

            var path = Path()
            path.move(to: CGPoint(x: startX, y: startY))
            path.addLine(to: CGPoint(x: startX, y: endY))
            path.addLine(to: CGPoint(x: endX, y: endY))

            context.stroke(
                path,
                with: .color(DashboardTheme.textTertiary.opacity(0.5)),
                style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
            )
        }
    }

    private func drawSpanBars(context: inout GraphicsContext, size: CGSize) {
        for layout in layouts where layout.rect.intersects(CGRect(origin: .zero, size: size)) {
            let fillColor = barColor(for: layout)
            let barPath = RoundedRectangle(cornerRadius: barCornerRadius)
                .path(in: layout.rect)

            // Fill
            context.fill(barPath, with: .color(fillColor.opacity(0.88)))

            // 1px stroke border
            context.stroke(
                barPath,
                with: .color(.gray.opacity(0.25)),
                lineWidth: 1
            )

            // Hover highlight
            if layout.span.spanId == hoveredSpanId, hoveredSpanId != selectedSpanId {
                context.fill(barPath, with: .color(.white.opacity(0.18)))
            }

            // Selection ring
            if layout.span.spanId == selectedSpanId {
                let selectionRect = layout.rect.insetBy(dx: -1, dy: -1)
                let selectionPath = RoundedRectangle(cornerRadius: barCornerRadius - 1)
                    .path(in: selectionRect)
                context.stroke(
                    selectionPath,
                    with: .color(DashboardTheme.accentNormal),
                    lineWidth: 2
                )
            }

            // Label
            drawLabel(layout.span.name, in: layout.rect, context: &context)
        }
    }

    private func drawLabel(
        _ text: String,
        in rect: CGRect,
        context: inout GraphicsContext
    ) {
        guard rect.width > labelMinimumWidth else { return }

        let truncated: String
        if text.count > 26 {
            truncated = String(text.prefix(25)) + "\u{2026}"
        } else {
            truncated = text
        }

        let insetRect = rect.insetBy(dx: 4, dy: 2)
        let resolvedText = context.resolve(
            Text(truncated)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
        )
        context.draw(resolvedText, in: insetRect)
    }

    // MARK: - Hit Test Overlay

    private var hitTestOverlay: some View {
        Color.clear
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let hit = layouts.first { $0.rect.contains(location) }
                    hoveredSpanId = hit?.span.spanId
                case .ended:
                    hoveredSpanId = nil
                }
            }
            .gesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if let hit = layouts.first(where: { $0.rect.contains(value.location) }) {
                            onSelectSpan?(hit.span)
                        }
                    }
            )
            .onKeyPress(characters: .init(charactersIn: "=+")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                zoomIn()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "-")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                zoomOut()
                return .handled
            }
            .onKeyPress(characters: .init(charactersIn: "0")) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                resetZoom()
                return .handled
            }
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = zoomScale * value.magnification
                zoomScale = min(max(proposed, zoomMinimum), zoomMaximum)
            }
    }

    // MARK: - Zoom Actions

    private func zoomIn() {
        zoomScale = min(zoomScale * zoomStep, zoomMaximum)
    }

    private func zoomOut() {
        zoomScale = max(zoomScale / zoomStep, zoomMinimum)
    }

    private func resetZoom() {
        zoomScale = 1.0
    }

    // MARK: - Layout Computation

    /// Rebuilds the cached span layout rects from the view model lanes,
    /// the stored `containerWidth`, and the current `zoomScale`.
    private func rebuildLayouts() {
        let lanes = viewModel.lanes
        guard !lanes.isEmpty else {
            layouts = []
            contentSize = .zero
            return
        }

        let totalHeight = topPadding
            + CGFloat(lanes.count) * rowHeight
            + CGFloat(max(0, lanes.count - 1)) * rowSpacing
            + topPadding

        let totalWidth = max(containerWidth, minimumCanvasWidth) * zoomScale
        let availableWidth = totalWidth - leftPadding - rightPadding
        let traceDuration = max(viewModel.trace.duration, 0.001)

        var newLayouts: [SpanLayout] = []
        newLayouts.reserveCapacity(lanes.reduce(0) { $0 + $1.items.count })

        for (laneIndex, lane) in lanes.enumerated() {
            let y = topPadding + CGFloat(laneIndex) * (rowHeight + rowSpacing)
            for item in lane.items {
                let startOffset = item.start.timeIntervalSince(viewModel.trace.startTime)
                let duration = max(item.duration, 0.001)
                let x = leftPadding + (startOffset / traceDuration) * availableWidth
                let width = max(minimumBarWidth, (duration / traceDuration) * availableWidth)
                let rect = CGRect(x: x, y: y, width: width, height: rowHeight)
                newLayouts.append(
                    SpanLayout(
                        id: item.span.spanId.hexString,
                        span: item.span,
                        rect: rect,
                        isError: item.isError,
                        isCritical: item.isCritical
                    )
                )
            }
        }

        layouts = newLayouts
        contentSize = CGSize(width: totalWidth, height: totalHeight)
    }

    // MARK: - Helpers

    private func barColor(for layout: SpanLayout) -> Color {
        if layout.isError {
            return DashboardTheme.accentError
        } else if layout.isCritical {
            return DashboardTheme.accentWarning
        } else {
            return DashboardTheme.Colors.serviceColor(for: layout.span.name)
        }
    }

    private func accessibilityLabel(for layout: SpanLayout) -> String {
        var label = layout.span.name
        let duration = TraceFormatter.duration(
            layout.span.endTime.timeIntervalSince(layout.span.startTime)
        )
        label += ", \(duration)"
        if layout.isError { label += ", error" }
        if layout.isCritical { label += ", slow" }
        return label
    }
}
