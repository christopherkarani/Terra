import Foundation
import SwiftUI
import TerraTraceKit
import OpenTelemetryApi
import OpenTelemetrySdk

enum EventCategory: String, CaseIterable {
    case lifecycle
    case policy
    case hardware
    case recommendations
    case anomalies
    case uncategorized

    var displayName: String {
        rawValue.capitalized
    }

    var color: SwiftUI.Color {
        switch self {
        case .lifecycle:       return DashboardTheme.Colors.categoryLifecycle
        case .policy:          return DashboardTheme.Colors.categoryPolicy
        case .hardware:        return DashboardTheme.Colors.categoryHardware
        case .recommendations: return DashboardTheme.Colors.categoryRecommendations
        case .anomalies:       return DashboardTheme.Colors.categoryAnomalies
        case .uncategorized:   return DashboardTheme.Colors.textTertiary
        }
    }
}

struct ClassifiedEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let relativeTime: TimeInterval
    let name: String
    let category: EventCategory
    let attributes: [(String, String)]
    let spanName: String
}

@Observable
@MainActor
final class TraceEventListViewModel {
    private(set) var allEvents: [ClassifiedEvent] = []
    var selectedCategory: EventCategory? = nil
    private var currentTraceId: String?

    var filteredEvents: [ClassifiedEvent] {
        guard let category = selectedCategory else {
            return allEvents
        }
        return allEvents.filter { $0.category == category }
    }

    var categoryCounts: [EventCategory: Int] {
        var counts: [EventCategory: Int] = [:]
        for event in allEvents {
            counts[event.category, default: 0] += 1
        }
        return counts
    }

    func update(trace: Trace) {
        guard trace.id != currentTraceId else { return }
        currentTraceId = trace.id

        var events: [ClassifiedEvent] = []
        let traceStart = trace.startTime

        for span in trace.orderedSpans {
            for event in span.events {
                let category = classify(name: event.name, attributes: event.attributes)
                let attrs = event.attributes.sorted(by: { $0.key < $1.key }).map {
                    ($0.key, $0.value.description)
                }
                events.append(ClassifiedEvent(
                    timestamp: event.timestamp,
                    relativeTime: event.timestamp.timeIntervalSince(traceStart),
                    name: event.name,
                    category: category,
                    attributes: attrs,
                    spanName: span.name
                ))
            }
        }

        allEvents = events.sorted { $0.timestamp < $1.timestamp }
    }

    private func classify(
        name: String,
        attributes: [String: OpenTelemetryApi.AttributeValue]
    ) -> EventCategory {
        if TerraTelemetryClassifier.isAnomalyEvent(name: name, attributes: attributes) {
            return .anomalies
        }
        if TerraTelemetryClassifier.isRecommendationEvent(name: name, attributes: attributes) {
            return .recommendations
        }
        if TerraTelemetryClassifier.isHardwareEvent(name: name, attributes: attributes) {
            return .hardware
        }
        if TerraTelemetryClassifier.isPolicyEvent(name: name, attributes: attributes) {
            return .policy
        }
        if TerraTelemetryClassifier.isLifecycleEvent(name: name, attributes: attributes) {
            return .lifecycle
        }
        return .uncategorized
    }
}
