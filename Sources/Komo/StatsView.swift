import AppKit
import SwiftUI

enum Scope: String, CaseIterable, Identifiable {
    case today = "Today"
    case allTime = "All-time"
    var id: String { rawValue }
}

struct StatsView: View {
    @EnvironmentObject private var store: StatsStore
    @EnvironmentObject private var permissions: PermissionHelper
    @EnvironmentObject private var login: LoginItem
    @Environment(\.colorScheme) private var scheme
    @State private var scope: Scope = .today
    @State private var confirmingReset = false
    @State private var hoveredKey: String?

    private var data: DayStats {
        scope == .today ? store.today : store.allTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if !permissions.hasInputMonitoring { permissionBanner }
            headline
            keysSection
            mouseSection
            footer
        }
        .padding(16)
        .frame(width: 360)
        .onAppear {
            permissions.refresh()
            login.refresh()
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Label {
                Text("Komo").font(.system(size: 15, weight: .bold, design: .rounded))
            } icon: {
                Image(nsImage: MenuBarIcon.brandImage)
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Spacer()
            ScopeToggle(scope: $scope)
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(grouped(data.totalKeys))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.komoBrand)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: data.totalKeys)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("keystrokes")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(captionText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(captionColor)
        }
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                sectionHeader("KEYS")
                Spacer()
                hoverKeySummary
            }
            if data.totalKeys == 0 {
                emptyKeys
            } else {
                keyboardHeatmap
                HeatLegend(maxCount: data.keyCounts.values.max() ?? 0)
            }
        }
    }

    private var hoverKeySummary: some View {
        let key = hoveredKey ?? "Space"
        let c = hoveredKey.map { data.keyCounts[$0] ?? 0 } ?? 0
        return Text("\(key) · \(grouped(c)) press\(c == 1 ? "" : "es")")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.komoBrand)
            .monospacedDigit()
            .lineLimit(1)
            .frame(minWidth: 132, minHeight: 16, alignment: .trailing)
            .opacity(data.totalKeys > 0 && hoveredKey != nil ? 1 : 0)
            .animation(.snappy(duration: 0.12), value: hoveredKey)
    }

    private var keyboardHeatmap: some View {
        let maxCount = max(data.keyCounts.values.max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(KeyCodeMap.rows.enumerated()), id: \.offset) { idx, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        KeyCap(label: key, count: data.keyCounts[key] ?? 0, maxCount: maxCount) { hovering in
                            hoveredKey = hovering ? key : (hoveredKey == key ? nil : hoveredKey)
                        }
                    }
                }
                .padding(.leading, KeyCodeMap.rowOffsets[idx])
            }
        }
        .frame(width: KeyCodeMap.keyboardWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyKeys: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Start typing — your keys light up here.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private var mouseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("MOUSE")
            HStack(spacing: 8) {
                StatTile(icon: "cursorarrow.click", title: "Left",
                         value: abbreviated(data.leftClicks), full: grouped(data.leftClicks))
                StatTile(icon: "contextualmenu.and.cursorarrow", title: "Right",
                         value: abbreviated(data.rightClicks), full: grouped(data.rightClicks))
                StatTile(icon: "arrow.up.and.down.and.arrow.left.and.right", title: "Travel",
                         value: distanceText, full: "≈ \(distanceText) (approximate)")
            }
        }
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Grant Input Monitoring to count keystrokes", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Mouse stats already work. Open the list below, switch **Komo** on, and keystrokes start counting within a couple of seconds.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Open Input Monitoring") {
                    permissions.request()      // fires the native prompt the rare time macOS allows it
                    permissions.openSettings() // …and always lands the user on the right pane
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(scheme == .dark ? 0.08 : 0.10)))
    }

    @ViewBuilder
    private var footer: some View {
        if confirmingReset {
            resetConfirmRow
        } else {
            defaultFooterRow
        }
    }

    private var defaultFooterRow: some View {
        HStack(spacing: 10) {
            LaunchToggle(on: login.enabled) { login.toggle() }
            Spacer()
            FooterButton(title: "Reset", systemImage: "arrow.counterclockwise") {
                withAnimation(.snappy(duration: 0.15)) { confirmingReset = true }
            }
            FooterButton(title: "Quit", systemImage: "power") { NSApp.terminate(nil) }
        }
        .padding(.top, 2)
    }

    // Inline confirmation — stays inside the popover so the menu-bar window
    // never loses focus (a system .confirmationDialog would dismiss it).
    private var resetConfirmRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
            Text("Clear all stats? Can't be undone.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Button("Cancel") {
                withAnimation(.snappy(duration: 0.15)) { confirmingReset = false }
            }
            .controlSize(.small)
            Button("Reset") {
                store.resetAll()
                withAnimation(.snappy(duration: 0.15)) { confirmingReset = false }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding(.top, 2)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(1.2)
    }

    // MARK: Derived values

    private var captionText: String {
        if scope == .allTime {
            let n = store.activeDays
            return "across \(n) day\(n == 1 ? "" : "s")"
        }
        if store.yesterdayKeys == 0 { return "first day tracking" }
        let delta = store.today.totalKeys - store.yesterdayKeys
        let arrow = delta >= 0 ? "▲" : "▼"
        return "\(arrow) \(grouped(abs(delta))) vs yesterday"
    }

    private var captionColor: Color {
        if scope == .allTime || store.yesterdayKeys == 0 { return .secondary }
        return store.today.totalKeys - store.yesterdayKeys >= 0 ? .green : .orange
    }

    private var distanceText: String {
        let meters = ScreenMetric.meters(fromPoints: data.mouseDistancePoints)
        if meters < 1 { return String(format: "%.0f cm", meters * 100) }
        if meters < 1000 { return String(format: "%.1f m", meters) }
        return String(format: "%.2f km", meters / 1000)
    }
}

// MARK: - Components

private struct ScopeToggle: View {
    @Binding var scope: Scope
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Scope.allCases) { option in
                let selected = option == scope
                Text(option.rawValue)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if selected {
                            Capsule().fill(Color.komoBrand)
                                .matchedGeometryEffect(id: "scopeSeg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.snappy(duration: 0.2)) { scope = option } }
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

private struct KeyCap: View {
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false
    let label: String
    let count: Int
    let maxCount: Int
    let onHover: (Bool) -> Void

    private var intensity: Double { maxCount > 0 ? Double(count) / Double(maxCount) : 0 }
    private var width: Double { label == "Space" ? 128 : 28 }

    var body: some View {
        let pressed = count > 0
        let i = pressed ? max(intensity, HeatColor.floor) : 0
        return Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(width: width, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(pressed
                          ? HeatColor.fill(intensity: i)
                          : Color.primary.opacity(scheme == .dark ? 0.07 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(hover ? Color.primary.opacity(0.5) : Color.primary.opacity(0.06),
                                  lineWidth: hover ? 1.5 : 1)
            )
            .foregroundStyle(pressed ? HeatColor.label(intensity: i) : Color.secondary)
            .scaleEffect(hover ? 1.08 : 1)
            .animation(.snappy(duration: 0.12), value: hover)
            .onHover { h in
                hover = h
                onHover(h)
            }
    }
}

private struct HeatLegend: View {
    let maxCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("0").font(.system(size: 9)).foregroundStyle(.tertiary)
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(gradient: HeatColor.gradient, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            Text(grouped(maxCount)).font(.system(size: 9)).foregroundStyle(.tertiary).monospacedDigit()
        }
        .padding(.top, 2)
    }
}

private struct StatTile: View {
    let icon: String
    let title: String
    let value: String
    var full: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.komoBrand)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .help(full ?? value)
    }
}

private struct LaunchToggle: View {
    let on: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Color.komoBrand : Color.secondary)
                Text("Launch at login")
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.06 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
    }
}

private struct FooterButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hover = $0 }
    }
}

// MARK: - Formatting

private func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

private func abbreviated(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.2fM", Double(n) / 1_000_000)
    case 100_000...:   return String(format: "%.0fk", Double(n) / 1_000)
    case 10_000...:    return String(format: "%.1fk", Double(n) / 1_000)
    default:           return grouped(n)
    }
}
