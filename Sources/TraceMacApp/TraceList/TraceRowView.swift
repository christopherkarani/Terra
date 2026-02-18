import SwiftUI
import TerraTraceKit

struct TraceRowView: View {
    let trace: Trace

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(trace.hasError ? DashboardTheme.accentError : .green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(trace.displayName)
                    .font(DashboardTheme.rowTitle)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(TraceFormatter.duration(trace.duration))
                    Text(TraceFormatter.timestamp(trace.fileTimestamp))
                }
                .font(DashboardTheme.rowMeta)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
    }
}
