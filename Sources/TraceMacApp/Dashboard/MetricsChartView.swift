import SwiftUI
import Charts
import TerraTraceKit

struct MetricsChartView: View {
    let trace: Trace
    @State private var isExpanded = false
    @State private var showGPU = true
    @State private var showMemory = true

    private var dataPoints: [HardwareTimeSeriesPoint] {
        DashboardViewModel.hardwareTimeSeries(from: trace)
    }

    var body: some View {
        let points = dataPoints
        if points.isEmpty && !isExpanded {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(hasData: !points.isEmpty)

                if isExpanded && !points.isEmpty {
                    chartContent(points: points)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(DashboardTheme.Colors.windowBackground)
            .clipShape(.rect(cornerRadius: DashboardTheme.Spacing.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DashboardTheme.Spacing.cornerRadius)
                    .strokeBorder(DashboardTheme.Colors.borderDefault, lineWidth: 1)
            )
            .onAppear {
                if !points.isEmpty {
                    isExpanded = true
                }
            }
        }
    }

    private func headerRow(hasData: Bool) -> some View {
        Button {
            guard hasData else { return }
            DashboardTheme.Animation.withAccessibleAnimation(DashboardTheme.Animation.standard) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(DashboardTheme.Colors.textTertiary)

                Text("Hardware Metrics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.Colors.textSecondary)

                Spacer()

                if isExpanded {
                    seriesToggle("GPU", color: DashboardTheme.Colors.chartGPU, isOn: $showGPU)
                    seriesToggle("Memory", color: DashboardTheme.Colors.chartMemory, isOn: $showMemory)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func seriesToggle(_ label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn.wrappedValue ? color : DashboardTheme.Colors.textQuaternary)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? DashboardTheme.Colors.textSecondary : DashboardTheme.Colors.textQuaternary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(isOn.wrappedValue ? color.opacity(0.12) : DashboardTheme.Colors.surfaceRaised)
            .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func chartContent(points: [HardwareTimeSeriesPoint]) -> some View {
        Chart {
            if showGPU {
                ForEach(points.filter { $0.gpuPercent != nil }) { point in
                    LineMark(
                        x: .value("Time", point.relativeTime),
                        y: .value("GPU %", point.gpuPercent ?? 0),
                        series: .value("Series", "GPU")
                    )
                    .foregroundStyle(DashboardTheme.Colors.chartGPU)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            if showMemory {
                ForEach(points.filter { $0.memoryMB != nil }) { point in
                    LineMark(
                        x: .value("Time", point.relativeTime),
                        y: .value("Memory MB", point.memoryMB ?? 0),
                        series: .value("Series", "Memory")
                    )
                    .foregroundStyle(DashboardTheme.Colors.chartMemory)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartXAxisLabel("Seconds", alignment: .trailing)
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DashboardTheme.Colors.borderSubtle)
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(DashboardTheme.Colors.borderSubtle)
                AxisValueLabel()
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DashboardTheme.Colors.textQuaternary)
            }
        }
        .frame(height: 140)
    }
}
