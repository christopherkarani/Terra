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

private struct TimelineEventMarker: Identifiable {
    enum Kind: String {
        case promptEval
        case decode
        case tokenLifecycle
        case stall
        case recommendation
        case anomaly
        case hardware
        case unknown
    }

    let id: String
    let spanId: SpanId
    let x: CGFloat
    let y: CGFloat
    let kind: Kind
    let label: String
}

private struct TimelineMarkerCompactionResult {
    let markers: [TimelineEventMarker]
    let sourceCount: Int
    let coalescedCount: Int
    let sampledCount: Int
    let maxMarkerLimit: Int

    var aggregationLevel: String {
        if sampledCount > 0 { return "sampled" }
        if coalescedCount > 0 { return "coalesced" }
        return "none"
    }
}

private struct TimelineMarkerRenderState {
    var sourceCount: Int = 0
    var coalescedCount: Int = 0
    var sampledCount: Int = 0
    var renderedCount: Int = 0
    var targetCount: Int = 0
    var maxMarkerLimit: Int = 0
    var isRendering: Bool = false
    var aggregationLevel: String = "none"

    static let empty = TimelineMarkerRenderState()

    var statusText: String {
        guard sourceCount > 0 else {
            return "No event markers"
        }

        var parts: [String] = []
        parts.append("Markers \(renderedCount)/\(targetCount)")

        if aggregationLevel != "none" {
            parts.append("aggregation=\(aggregationLevel)")
        }
        if coalescedCount > 0 {
            parts.append("coalesced=\(coalescedCount)")
        }
        if sampledCount > 0 {
            parts.append("sampled=\(sampledCount)")
        }
        if isRendering {
            parts.append("rendering")
        }
        parts.append("limit=\(maxMarkerLimit)")
        return parts.joined(separator: " • ")
    }
}

struct TimelineMarkerDebugSample {
    let x: CGFloat
    let kind: String
    let spanHex: String
}

struct TimelineMarkerDebugStats: Equatable {
    let sourceCount: Int
    let keptCount: Int
    let coalescedCount: Int
    let sampledCount: Int
    let aggregationLevel: String
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
    var maxEventMarkers: Int

    // MARK: - State

    @Binding var zoomScale: CGFloat
    @State private var hoveredSpanId: SpanId?
    @State private var layouts: [SpanLayout] = []
    @State private var contentSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var eventMarkers: [TimelineEventMarker] = []
    @State private var markerRenderState: TimelineMarkerRenderState = .empty
    @State private var markerRenderGeneration: UInt64 = 0
    @State private var markerRenderTask: Task<Void, Never>?

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
    private let zoomMinimum: CGFloat = CGFloat(AppSettings.timelineZoomScaleRange.lowerBound)
    private let zoomMaximum: CGFloat = CGFloat(AppSettings.timelineZoomScaleRange.upperBound)
    private let zoomStep: CGFloat = 1.25
    private let markerCoalesceBucketWidth: CGFloat = 2.0
    private let markerProgressiveBatchSize: Int = 256

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
        .onChange(of: maxEventMarkers) {
            rebuildLayouts()
        }
        .onDisappear {
            markerRenderTask?.cancel()
            markerRenderTask = nil
        }
    }

    // MARK: - Canvas

    private var timelineCanvas: some View {
        ZStack {
            Canvas { context, size in
                drawLaneBackgrounds(context: &context, size: size)
                drawConnectorLines(context: &context, size: size)
                drawSpanBars(context: &context, size: size)
                drawEventMarkers(context: &context, size: size)
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
        .overlay(alignment: .bottomTrailing) {
            markerStatusOverlay
                .padding(10)
        }
        .gesture(zoomGesture)
        .accessibilityLabel("Trace timeline")
        .accessibilityHint("Displays span bars in a waterfall layout. Use VoiceOver to navigate individual spans.")
    }

    @ViewBuilder
    private var markerStatusOverlay: some View {
        if markerRenderState.sourceCount > 0 {
            Text(markerRenderState.statusText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(.secondary)
                .background(.ultraThinMaterial, in: Capsule())
                .accessibilityLabel("Timeline marker status")
                .accessibilityValue(markerRenderState.statusText)
        }
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

    private func drawEventMarkers(context: inout GraphicsContext, size: CGSize) {
        guard !eventMarkers.isEmpty else { return }

        for marker in eventMarkers {
            let color = markerColor(marker.kind)
            let center = CGPoint(x: marker.x, y: marker.y)

            switch marker.kind {
            case .stall:
                var path = Path()
                path.move(to: CGPoint(x: center.x, y: center.y - 8))
                path.addLine(to: CGPoint(x: center.x - 7, y: center.y + 5))
                path.addLine(to: CGPoint(x: center.x + 7, y: center.y + 5))
                path.closeSubpath()
                context.fill(path, with: .color(color))

            case .promptEval, .decode, .tokenLifecycle, .recommendation, .anomaly, .hardware, .unknown:
                let markerPath = Path(ellipseIn: CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7))
                context.fill(markerPath, with: .color(color))
            }

            if marker.kind == .stall || marker.kind == .anomaly {
                let label = marker.label
                let renderedText = context.resolve(
                    Text(label)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                )
                context.draw(
                    renderedText,
                    at: CGPoint(x: center.x + 8, y: center.y - 4)
                )
            }
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
        zoomScale = CGFloat(AppSettings.defaultTimelineZoomScale)
    }

    // MARK: - Layout Computation

    /// Rebuilds the cached span layout rects from the view model lanes,
    /// the stored `containerWidth`, and the current `zoomScale`.
    private func rebuildLayouts() {
        let lanes = viewModel.lanes
        guard !lanes.isEmpty else {
            layouts = []
            contentSize = .zero
            eventMarkers = []
            markerRenderState = .empty
            markerRenderTask?.cancel()
            markerRenderTask = nil
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
        let markerCompaction = buildTimelineEventMarkers(
            layouts: newLayouts,
            totalWidth: totalWidth,
            availableWidth: availableWidth
        )
        renderEventMarkersProgressively(using: markerCompaction)
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

    private func buildTimelineEventMarkers(
        layouts: [SpanLayout],
        totalWidth: CGFloat,
        availableWidth: CGFloat
    ) -> TimelineMarkerCompactionResult {
        let effectiveWidth = max(totalWidth, minimumCanvasWidth)
        let effectiveAvailableWidth = availableWidth > 0 ? availableWidth : (effectiveWidth - leftPadding - rightPadding)
        let traceDuration = max(viewModel.trace.duration, 0.001)

        var markers: [TimelineEventMarker] = []
        markers.reserveCapacity(1024)

        for layout in layouts {
            for event in layout.span.events {
                guard let mapped = eventLayoutMarker(
                    event: event,
                    traceStart: viewModel.trace.startTime,
                    spanLayout: layout,
                    traceDuration: traceDuration,
                    availableWidth: effectiveAvailableWidth
                ) else { continue }

                markers.append(mapped)
            }
        }

        return compactedMarkers(markers)
    }

    private func compactedMarkers(_ markers: [TimelineEventMarker]) -> TimelineMarkerCompactionResult {
        let resolvedLimit = max(1, maxEventMarkers)
        guard !markers.isEmpty else {
            return TimelineMarkerCompactionResult(
                markers: [],
                sourceCount: 0,
                coalescedCount: 0,
                sampledCount: 0,
                maxMarkerLimit: resolvedLimit
            )
        }

        var buckets: [String: TimelineEventMarker] = [:]
        buckets.reserveCapacity(markers.count)
        var orderedBucketKeys: [String] = []
        orderedBucketKeys.reserveCapacity(markers.count)

        for marker in markers {
            let bucket = Int((marker.x / markerCoalesceBucketWidth).rounded(.down))
            let key = "\(bucket)|\(marker.kind.rawValue)|\(marker.spanId.hexString)"
            if buckets[key] == nil {
                orderedBucketKeys.append(key)
                buckets[key] = marker
            }
        }

        let coalesced = orderedBucketKeys.compactMap { buckets[$0] }
        let coalescedCount = max(0, markers.count - coalesced.count)

        guard coalesced.count > resolvedLimit else {
            return TimelineMarkerCompactionResult(
                markers: coalesced,
                sourceCount: markers.count,
                coalescedCount: coalescedCount,
                sampledCount: 0,
                maxMarkerLimit: resolvedLimit
            )
        }

        let step = Int(ceil(Double(coalesced.count) / Double(resolvedLimit)))
        let sampled = stride(from: 0, to: coalesced.count, by: step).map { coalesced[$0] }
        let sampledCount = max(0, coalesced.count - sampled.count)
        return TimelineMarkerCompactionResult(
            markers: sampled,
            sourceCount: markers.count,
            coalescedCount: coalescedCount,
            sampledCount: sampledCount,
            maxMarkerLimit: resolvedLimit
        )
    }

    private func renderEventMarkersProgressively(using compaction: TimelineMarkerCompactionResult) {
        markerRenderTask?.cancel()
        markerRenderTask = nil
        markerRenderGeneration &+= 1
        let generation = markerRenderGeneration

        let targetMarkers = compaction.markers
        markerRenderState = TimelineMarkerRenderState(
            sourceCount: compaction.sourceCount,
            coalescedCount: compaction.coalescedCount,
            sampledCount: compaction.sampledCount,
            renderedCount: 0,
            targetCount: targetMarkers.count,
            maxMarkerLimit: compaction.maxMarkerLimit,
            isRendering: false,
            aggregationLevel: compaction.aggregationLevel
        )

        guard !targetMarkers.isEmpty else {
            eventMarkers = []
            return
        }

        if targetMarkers.count <= markerProgressiveBatchSize {
            eventMarkers = targetMarkers
            markerRenderState.renderedCount = targetMarkers.count
            return
        }

        eventMarkers = Array(targetMarkers.prefix(markerProgressiveBatchSize))
        markerRenderState.renderedCount = eventMarkers.count
        markerRenderState.isRendering = true

        markerRenderTask = Task { @MainActor in
            var index = markerProgressiveBatchSize
            while index < targetMarkers.count {
                if Task.isCancelled {
                    return
                }
                try? await Task.sleep(nanoseconds: 8_000_000)
                if generation != markerRenderGeneration {
                    return
                }

                let nextIndex = min(targetMarkers.count, index + markerProgressiveBatchSize)
                eventMarkers.append(contentsOf: targetMarkers[index..<nextIndex])
                markerRenderState.renderedCount = eventMarkers.count
                index = nextIndex
            }
            markerRenderState.isRendering = false
        }
    }

    private func eventLayoutMarker(
        event: SpanData.Event,
        traceStart: Date,
        spanLayout: SpanLayout,
        traceDuration: TimeInterval,
        availableWidth: CGFloat
    ) -> TimelineEventMarker? {
        let offset = event.timestamp.timeIntervalSince(traceStart)
        guard offset >= 0 else { return nil }
        let normalized = offset / traceDuration
        guard normalized <= 1.02 else { return nil }

        let x = leftPadding + CGFloat(normalized) * availableWidth
        let y = spanLayout.rect.midY
        guard let kind = eventKind(for: event) else { return nil }

        let label = markerLabel(for: event, kind: kind)
        return TimelineEventMarker(
            id: "\(spanLayout.span.spanId.hexString)|\(event.timestamp.timeIntervalSinceReferenceDate)|\(event.name)",
            spanId: spanLayout.span.spanId,
            x: x,
            y: y,
            kind: kind,
            label: label
        )
    }

    private func eventKind(for event: SpanData.Event) -> TimelineEventMarker.Kind? {
        let kindName = Self.markerKindName(
            eventName: event.name,
            attributes: event.attributes
        )
        return TimelineEventMarker.Kind(rawValue: kindName) ?? .unknown
    }

    private func markerLabel(for event: SpanData.Event, kind: TimelineEventMarker.Kind) -> String {
        switch kind {
        case .promptEval:
            return "P"
        case .decode:
            return "D"
        case .tokenLifecycle:
            return "T"
        case .stall:
            return "!"
        case .recommendation:
            return "R"
        case .anomaly:
            return "A"
        case .hardware:
            return "H"
        case .unknown:
            return event.name
        }
    }

    private func markerColor(_ kind: TimelineEventMarker.Kind) -> Color {
        switch kind {
        case .promptEval:
            return .purple
        case .decode:
            return .blue
        case .tokenLifecycle:
            return .mint
        case .stall:
            return .red
        case .recommendation:
            return .green
        case .anomaly:
            return .orange
        case .hardware:
            return DashboardTheme.Colors.accentWarning
        case .unknown:
            return .secondary
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

    static func markerKindName(
        eventName: String,
        attributes: [String: OpenTelemetryApi.AttributeValue]
    ) -> String {
        let normalizedName = eventName.lowercased()
        if normalizedName.contains("stalled") && normalizedName.contains("token") {
            return TimelineEventMarker.Kind.stall.rawValue
        }
        if normalizedName.contains("prompt_eval") || normalizedName.contains("prompt-eval") {
            return TimelineEventMarker.Kind.promptEval.rawValue
        }
        if normalizedName == "terra.stage.decode" || normalizedName.contains("decode") {
            return TimelineEventMarker.Kind.decode.rawValue
        }
        if TerraTelemetryClassifier.isLifecycleEvent(name: eventName, attributes: attributes) {
            return TimelineEventMarker.Kind.tokenLifecycle.rawValue
        }
        if TerraTelemetryClassifier.isHardwareEvent(name: eventName, attributes: attributes) {
            return TimelineEventMarker.Kind.hardware.rawValue
        }
        if TerraTelemetryClassifier.isRecommendationEvent(name: eventName, attributes: attributes) {
            return TimelineEventMarker.Kind.recommendation.rawValue
        }
        if TerraTelemetryClassifier.isAnomalyEvent(name: eventName, attributes: attributes) {
            return TimelineEventMarker.Kind.anomaly.rawValue
        }

        return TimelineEventMarker.Kind.unknown.rawValue
    }

    static func markerCompactionStats(
        samples: [TimelineMarkerDebugSample],
        maxEventMarkers: Int,
        bucketWidth: CGFloat = 2.0
    ) -> TimelineMarkerDebugStats {
        let resolvedLimit = max(1, maxEventMarkers)
        guard !samples.isEmpty else {
            return TimelineMarkerDebugStats(
                sourceCount: 0,
                keptCount: 0,
                coalescedCount: 0,
                sampledCount: 0,
                aggregationLevel: "none"
            )
        }

        let safeBucketWidth = max(0.01, bucketWidth)
        var seen: Set<String> = []
        var coalescedKeys: [String] = []
        coalescedKeys.reserveCapacity(samples.count)

        for sample in samples {
            let bucket = Int((sample.x / safeBucketWidth).rounded(.down))
            let key = "\(bucket)|\(sample.kind)|\(sample.spanHex)"
            if seen.insert(key).inserted {
                coalescedKeys.append(key)
            }
        }

        let coalescedCount = max(0, samples.count - coalescedKeys.count)
        if coalescedKeys.count <= resolvedLimit {
            return TimelineMarkerDebugStats(
                sourceCount: samples.count,
                keptCount: coalescedKeys.count,
                coalescedCount: coalescedCount,
                sampledCount: 0,
                aggregationLevel: coalescedCount > 0 ? "coalesced" : "none"
            )
        }

        let step = Int(ceil(Double(coalescedKeys.count) / Double(resolvedLimit)))
        let keptCount = Array(stride(from: 0, to: coalescedKeys.count, by: step)).count
        let sampledCount = max(0, coalescedKeys.count - keptCount)
        return TimelineMarkerDebugStats(
            sourceCount: samples.count,
            keptCount: keptCount,
            coalescedCount: coalescedCount,
            sampledCount: sampledCount,
            aggregationLevel: "sampled"
        )
    }
}
