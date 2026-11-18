import Foundation

/// One day's worth of counters.
struct DayStats: Codable, Equatable {
    var keyCounts: [String: Int] = [:]
    var totalKeys: Int = 0
    var leftClicks: Int = 0
    var rightClicks: Int = 0
    var mouseDistancePoints: Double = 0
}

/// Granularity of one trend bucket. The Today scope charts individual days,
/// All-time charts calendar weeks, so the same fourteen-bar layout covers
/// either the last fortnight or the last quarter.
enum TrendSpan {
    case day, week

    var component: Calendar.Component { self == .day ? .day : .weekOfYear }
    var dayCount: Int { self == .day ? 1 : 7 }
}

/// Which series a trend chart is plotting. Counts and travel distance share
/// one chart type, so the bucket value is a Double and each metric brings its
/// own read-out formatting.
enum TrendMetric {
    case keys, leftClicks, rightClicks, travel

    func value(_ day: DayStats) -> Double {
        switch self {
        case .keys:        return Double(day.totalKeys)
        case .leftClicks:  return Double(day.leftClicks)
        case .rightClicks: return Double(day.rightClicks)
        case .travel:      return day.mouseDistancePoints
        }
    }

    func formatted(_ value: Double) -> String {
        switch self {
        case .travel: return distanceText(points: value)
        default:      return grouped(Int(value.rounded()))
        }
    }
}

/// One bucket of a trend chart.
struct TrendPoint: Identifiable, Equatable {
    let id: Int          // 0 = oldest bucket in the window
    let start: Date
    let value: Double
    let isCurrent: Bool  // the in-progress day / week, still filling up
}

/// Central store of input statistics.
///
/// High-frequency events (especially mouse-move) mutate plain storage and only
/// flip dirty flags. A timer publishes UI snapshots a few times a second and
/// persists to disk every few seconds, so the firehose of raw events never
/// drives SwiftUI re-renders or disk writes directly. The all-time aggregate is
/// maintained incrementally rather than re-summed on every refresh.
@MainActor
final class StatsStore: ObservableObject {
    static let shared = StatsStore()

    @Published private(set) var today = DayStats()
    @Published private(set) var allTime = DayStats()
    @Published private(set) var yesterdayKeys = 0
    @Published private(set) var activeDays = 0

    /// Bars in the trend chart. Both spans use the same count so switching
    /// scope reflows the values without reflowing the layout.
    static let trendBuckets = 14

    private struct BucketSpec {
        let start: Date
        let dayKeys: [String]
    }

    private var days: [String: DayStats] = [:]
    private var allTimeCache = DayStats()
    private var daySpecs: [BucketSpec] = []
    private var weekSpecs: [BucketSpec] = []
    private var specsDay = ""
    private var dirty = false
    private var uiDirty = true
    private var lastRenderedDay = ""
    private var saveTimer: Timer?
    private var uiTimer: Timer?
    private let saveURL: URL

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Komo", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        saveURL = base.appendingPathComponent("stats.json")

        load()
        rebuildAggregate()
        recomputeSnapshots()

        uiTimer = makeTimer(interval: 0.3) { [weak self] in
            guard let self else { return }
            if Self.todayKey != self.lastRenderedDay { self.uiDirty = true }
            guard self.uiDirty else { return }
            self.recomputeSnapshots()
            self.uiDirty = false
        }
        saveTimer = makeTimer(interval: 5) { [weak self] in self?.flush() }
    }

    /// Timers scheduled in `.common` mode keep firing while menus/popovers track.
    private func makeTimer(interval: TimeInterval, _ body: @escaping () -> Void) -> Timer {
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
        RunLoop.main.add(t, forMode: .common)
        return t
    }

    static var todayKey: String { dayKey(for: Date()) }
    static var yesterdayKey: String {
        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return dayKey(for: date)
    }
    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: Recording

    func recordKey(label: String?) {
        guard let label else { return }
        mutateToday { d in
            d.totalKeys += 1
            d.keyCounts[label, default: 0] += 1
        }
        allTimeCache.totalKeys += 1
        allTimeCache.keyCounts[label, default: 0] += 1
    }

    func recordLeftClick() {
        mutateToday { $0.leftClicks += 1 }
        allTimeCache.leftClicks += 1
    }

    func recordRightClick() {
        mutateToday { $0.rightClicks += 1 }
        allTimeCache.rightClicks += 1
    }

    func recordMouseMove(points: Double) {
        guard points.isFinite, points > 0 else { return }
        mutateToday { $0.mouseDistancePoints += points }
        allTimeCache.mouseDistancePoints += points
    }

    func resetAll() {
        days = [:]
        allTimeCache = DayStats()
        dirty = true
        uiDirty = true
        recomputeSnapshots()
        flush()
    }

    /// Synchronous save, used on quit / power-off so nothing is lost.
    func flushNow() { flush() }

    /// Seeds representative data for offscreen UI snapshots. Not persisted.
    func loadDemoData() {
        var d = DayStats()
        d.keyCounts = [
            "E": 820, "T": 610, "A": 540, "O": 510, "I": 480, "N": 470, "S": 450,
            "R": 430, "H": 390, "L": 300, "D": 290, "C": 250, "U": 230, "M": 200,
            "W": 180, "F": 170, "G": 160, "Y": 150, "P": 140, "B": 120, "V": 80,
            "K": 70, "J": 24, "X": 18, "Q": 15, "Z": 12,
            "1": 90, "2": 60, "3": 50, "4": 40, "5": 35,
            "6": 30, "7": 28, "8": 44, "9": 25, "0": 80,
            "Space": 760
        ]
        d.totalKeys = d.keyCounts.values.reduce(0, +)
        d.leftClicks = 3120
        d.rightClicks = 240
        d.mouseDistancePoints = 1_850_000

        // A quarter of plausible history so the trend chart has something to
        // draw in both spans: a weekday/weekend rhythm plus a slow swell,
        // shaped deterministically so successive snapshots stay comparable.
        var seeded: [String: DayStats] = [Self.todayKey: d]
        let cal = Calendar.current
        for back in 1...110 {
            guard let date = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let weekday = cal.component(.weekday, from: date)
            let base = (weekday == 1 || weekday == 7) ? 0.28 : 1.0
            let swell = 0.6 + 0.4 * sin(Double(back) / 11)
            let jitter = 0.75 + 0.5 * abs(sin(Double(back) * 2.7))
            seeded[Self.dayKey(for: date)] = Self.scaled(d, by: base * swell * jitter)
        }
        days = seeded
        rebuildAggregate()
        recomputeSnapshots()
        dirty = false
    }

    /// Proportionally rescales a day so seeded history keeps the same key
    /// distribution as the sample day, and the All-time heat-map stays honest.
    private static func scaled(_ day: DayStats, by factor: Double) -> DayStats {
        var out = DayStats()
        out.keyCounts = day.keyCounts.mapValues { Int(Double($0) * factor) }
        out.totalKeys = out.keyCounts.values.reduce(0, +)
        out.leftClicks = Int(Double(day.leftClicks) * factor)
        out.rightClicks = Int(Double(day.rightClicks) * factor)
        out.mouseDistancePoints = day.mouseDistancePoints * factor
        return out
    }

    // MARK: Internals

    private func mutateToday(_ body: (inout DayStats) -> Void) {
        let key = Self.todayKey
        var d = days[key] ?? DayStats()
        body(&d)
        days[key] = d
        dirty = true
        uiDirty = true
    }

    private func rebuildAggregate() {
        var agg = DayStats()
        for (_, d) in days {
            agg.totalKeys += d.totalKeys
            agg.leftClicks += d.leftClicks
            agg.rightClicks += d.rightClicks
            agg.mouseDistancePoints += d.mouseDistancePoints
            for (k, v) in d.keyCounts { agg.keyCounts[k, default: 0] += v }
        }
        allTimeCache = agg
    }

    private func recomputeSnapshots() {
        today = days[Self.todayKey] ?? DayStats()
        allTime = allTimeCache
        yesterdayKeys = days[Self.yesterdayKey]?.totalKeys ?? 0
        activeDays = days.count
        lastRenderedDay = Self.todayKey
        refreshBucketSpecs()
    }

    // MARK: Trend

    /// Buckets for one series. Derived on read rather than published: a chart
    /// re-renders whenever the store publishes anyway, and summing fourteen
    /// buckets is cheaper than keeping every metric/span combination live.
    func trend(_ metric: TrendMetric, span: TrendSpan) -> [TrendPoint] {
        let specs = span == .day ? daySpecs : weekSpecs
        return specs.enumerated().map { index, spec in
            TrendPoint(
                id: index,
                start: spec.start,
                value: spec.dayKeys.reduce(0) { $0 + (days[$1].map(metric.value) ?? 0) },
                isCurrent: index == specs.count - 1
            )
        }
    }

    /// Which calendar days land in which bucket only changes at midnight, so
    /// the key strings are built once a day and the 0.3 s UI refresh is left
    /// with nothing but dictionary lookups.
    private func refreshBucketSpecs() {
        let key = Self.todayKey
        guard specsDay != key else { return }
        specsDay = key
        daySpecs = Self.buildBucketSpecs(span: .day)
        weekSpecs = Self.buildBucketSpecs(span: .week)
    }

    private static func buildBucketSpecs(span: TrendSpan) -> [BucketSpec] {
        let cal = Calendar.current
        let now = Date()
        let currentStart: Date
        switch span {
        case .day:
            currentStart = cal.startOfDay(for: now)
        case .week:
            // Honours the user's first weekday rather than assuming Monday.
            currentStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        }

        return (0..<trendBuckets).map { index in
            let back = index - (trendBuckets - 1)
            let start = cal.date(byAdding: span.component, value: back, to: currentStart) ?? currentStart
            let dayKeys = (0..<span.dayCount)
                .compactMap { cal.date(byAdding: .day, value: $0, to: start) }
                .map(dayKey(for:))
            return BucketSpec(start: start, dayKeys: dayKeys)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        do {
            days = try JSONDecoder().decode([String: DayStats].self, from: data)
        } catch {
            // Preserve the unreadable file instead of silently overwriting it.
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = saveURL.deletingLastPathComponent()
                .appendingPathComponent("stats.corrupt-\(stamp).json")
            try? FileManager.default.moveItem(at: saveURL, to: backup)
            NSLog("Komo: stats.json unreadable, backed up to \(backup.lastPathComponent)")
            days = [:]
        }
    }

    private func flush() {
        guard dirty else { return }
        do {
            let data = try JSONEncoder().encode(days)
            try data.write(to: saveURL, options: .atomic)
            dirty = false
        } catch {
            NSLog("Komo: failed to save stats: \(error)")
        }
    }
}
