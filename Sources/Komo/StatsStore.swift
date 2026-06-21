import Foundation

/// One day's worth of counters.
struct DayStats: Codable, Equatable {
    var keyCounts: [String: Int] = [:]
    var totalKeys: Int = 0
    var leftClicks: Int = 0
    var rightClicks: Int = 0
    var mouseDistancePoints: Double = 0
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

    private var days: [String: DayStats] = [:]
    private var allTimeCache = DayStats()
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
        days = [Self.todayKey: d, Self.yesterdayKey: DayStats(totalKeys: 7887)]
        rebuildAggregate()
        recomputeSnapshots()
        dirty = false
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
