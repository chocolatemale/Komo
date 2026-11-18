import SwiftUI

/// Keystroke volume over time, sitting directly under the headline number it
/// puts in context. Fourteen buckets wide in either mode — days for Today,
/// calendar weeks for All-time — so switching scope changes the reach of the
/// chart without changing its footprint.
///
/// Bar height is the only value encoding; colour is reserved for *where you
/// are* (the in-progress bucket, and whatever the pointer is on), which keeps
/// the chart from competing with the heat-map below it.
struct TrendChart: View {
    let points: [TrendPoint]
    let span: TrendSpan
    let metric: TrendMetric
    var plotHeight: Double = 40

    @State private var hovered: Int?

    private var peak: Double { points.map(\.value).max() ?? 0 }
    private var hoveredPoint: TrendPoint? { points.first { $0.id == hovered } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            bars
            caption
        }
        .onChange(of: span) { _, _ in hovered = nil }
    }

    private var bars: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(points) { point in
                    TrendBar(point: point, peak: peak, height: plotHeight, hovered: hovered == point.id)
                        .onHover { hovering in
                            hovered = hovering ? point.id : (hovered == point.id ? nil : hovered)
                        }
                }
            }
            .frame(height: plotHeight)
            // A baseline is enough structure; drawing a track behind every bar
            // turned the chart into a second row of keycaps.
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }

    /// Doubles as the axis label and the hover read-out, so inspecting a bucket
    /// costs no extra height and nothing in the popover shifts.
    private var caption: some View {
        HStack(spacing: 8) {
            Text(hoveredPoint.map(readout) ?? windowLabel)
                .foregroundStyle(hoveredPoint == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.komoBrand))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("peak \(metric.formatted(peak))")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .layoutPriority(1)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .monospacedDigit()
        .frame(minHeight: 13)
        .animation(.snappy(duration: 0.12), value: hovered)
    }

    private var windowLabel: String {
        span == .day
            ? "last \(points.count) days"
            : "last \(points.count) weeks"
    }

    private func readout(_ point: TrendPoint) -> String {
        "\(bucketName(point)) · \(metric.formatted(point.value))"
    }

    private func bucketName(_ point: TrendPoint) -> String {
        switch span {
        case .day:
            if point.isCurrent { return "Today" }
            return point.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week:
            if point.isCurrent { return "This week" }
            return "Week of " + point.start.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct TrendBar: View {
    @Environment(\.colorScheme) private var scheme
    let point: TrendPoint
    let peak: Double
    let height: Double
    let hovered: Bool

    var body: some View {
        // A hairline of a bar still beats none: an active-but-quiet bucket
        // should never be indistinguishable from a silent one.
        let fraction = peak > 0 ? point.value / peak : 0
        let filled = point.value > 0 ? max(3, height * fraction) : 0

        return ZStack(alignment: .bottom) {
            // Only surfaces under the pointer, so the chart stays quiet at rest
            // but a bucket with no activity is still hoverable.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(hovered ? (scheme == .dark ? 0.06 : 0.04) : 0))
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .fill(barColor)
                .frame(height: filled)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .contentShape(Rectangle())   // the whole column is the hover target
        .animation(.snappy(duration: 0.25), value: filled)
        .animation(.snappy(duration: 0.12), value: hovered)
    }

    private var barColor: Color {
        guard !(point.isCurrent || hovered) else { return .komoBrand }
        // Dark backgrounds swallow low-alpha fills, so the resting bars need a
        // little more of the brand colour there to stay clearly blue.
        return Color.komoBrand.opacity(scheme == .dark ? 0.55 : 0.45)
    }
}
