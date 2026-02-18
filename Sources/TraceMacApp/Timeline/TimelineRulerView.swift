import SwiftUI
import TerraTraceKit

// MARK: - TimelineRulerView

/// A horizontal ruler bar displaying time markers above the timeline canvas.
///
/// The ruler computes evenly-spaced time labels across the trace duration
/// and renders tick marks with formatted labels. It matches the horizontal
/// width and zoom of the companion `TraceTimelineCanvasView`.
struct TimelineRulerView: View {

    // MARK: - Properties

    /// The trace whose time range defines the ruler bounds.
    let trace: Trace

    /// Current zoom scale, kept in sync with the timeline canvas.
    let zoomScale: CGFloat

    // MARK: - Layout Constants

    private let rulerHeight: CGFloat = 28
    private let leftPadding: CGFloat = 16
    private let rightPadding: CGFloat = 16
    private let tickHeight: CGFloat = 6
    private let minimumCanvasWidth: CGFloat = 600
    private let preferredTickCount: Int = 10

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            let totalWidth = max(proxy.size.width, minimumCanvasWidth) * zoomScale
            let availableWidth = totalWidth - leftPadding - rightPadding
            let traceDuration = max(trace.duration, 0.001)
            let ticks = computeTicks(
                traceDuration: traceDuration,
                availableWidth: availableWidth
            )

            Canvas { context, size in
                // Bottom border line
                let borderPath = Path { path in
                    path.move(to: CGPoint(x: 0, y: size.height - 0.5))
                    path.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
                }
                context.stroke(borderPath, with: .color(.gray.opacity(0.2)), lineWidth: 1)

                // Tick marks and labels
                for tick in ticks {
                    let x = leftPadding + (tick.time / traceDuration) * availableWidth

                    // Tick mark
                    let tickPath = Path { path in
                        path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(tickPath, with: .color(.gray.opacity(0.35)), lineWidth: 1)

                    // Label
                    let resolvedText = context.resolve(
                        Text(tick.label)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    )
                    let textSize = resolvedText.measure(in: size)
                    let labelX = x - textSize.width / 2
                    let labelY = size.height - tickHeight - textSize.height - 2
                    context.draw(
                        resolvedText,
                        at: CGPoint(x: labelX + textSize.width / 2, y: labelY + textSize.height / 2)
                    )
                }
            }
            .frame(width: totalWidth, height: rulerHeight)
        }
        .frame(height: rulerHeight)
        .accessibilityLabel("Timeline ruler")
    }

    // MARK: - Tick Computation

    /// A single tick mark on the ruler.
    private struct Tick {
        /// Time offset from trace start in seconds.
        let time: TimeInterval
        /// Formatted label string.
        let label: String
    }

    /// Computes evenly-spaced tick positions across the trace duration.
    private func computeTicks(
        traceDuration: TimeInterval,
        availableWidth: CGFloat
    ) -> [Tick] {
        let count = max(2, preferredTickCount)
        let interval = traceDuration / TimeInterval(count)

        return (0...count).map { index in
            let time = TimeInterval(index) * interval
            let label = TraceFormatter.duration(time)
            return Tick(time: time, label: label)
        }
    }
}
