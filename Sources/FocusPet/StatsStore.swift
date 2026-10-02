import Foundation

/// 一条会话记录
struct SessionRecord: Codable {
    var id: UUID = UUID()
    var kind: String            // "focus" / "shortRest" / "longRest"
    var startedAt: Date
    var endedAt: Date
    var plannedSeconds: TimeInterval
    var completed: Bool         // 自然走完 = true；提前结束 = false

    var actualMinutes: Int {
        max(0, Int(endedAt.timeIntervalSince(startedAt) / 60))
    }
}

/// 统计快照（喂给统计窗口）
struct StatsSnapshot {
    var todayCount = 0          // 今日完成专注次数
    var todayMinutes = 0        // 今日专注分钟
    var weekMinutes = 0         // 近 7 天专注分钟
    var totalMinutes = 0        // 累计专注分钟
    var streakDays = 0          // 连续专注天数
    var last7Days: [Int] = Array(repeating: 0, count: 7)  // [0]=6天前 … [6]=今天
}

/// 简单的 JSON 文件存储：~/Library/Application Support/FocusPet/sessions.json
final class StatsStore {
    static let shared = StatsStore()

    private let url: URL
    private(set) var records: [SessionRecord] = []

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("sessions.json")
        load()
        print("[FocusPet] 已加载 \(records.count) 条历史记录: \(url.path)")
        fflush(stdout)
    }

    func add(_ record: SessionRecord) {
        records.append(record)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        records = (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    private func save() {
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
    }

    // MARK: - 统计

    func snapshot() -> StatsSnapshot {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -6, to: todayStart) else {
            return StatsSnapshot(streakDays: streakDays)
        }

        var snap = StatsSnapshot()
        snap.streakDays = streakDays

        for record in records where record.completed && record.kind == "focus" {
            let minutes = record.actualMinutes
            let day = cal.startOfDay(for: record.endedAt)

            if day == todayStart {
                snap.todayCount += 1
                snap.todayMinutes += minutes
            }
            if day >= weekAgo {
                snap.weekMinutes += minutes
                let offset = cal.dateComponents([.day], from: day, to: todayStart).day ?? -1
                if (0...6).contains(offset) {
                    snap.last7Days[6 - offset] += minutes
                }
            }
            snap.totalMinutes += minutes
        }
        return snap
    }

    /// 连续专注天数：从今天往前数（今天还没专注则从昨天起算）
    var streakDays: Int {
        let cal = Calendar.current
        let daysWithFocus = Set(
            records
                .filter { $0.completed && $0.kind == "focus" }
                .map { cal.startOfDay(for: $0.endedAt) }
        )
        var count = 0
        var day = cal.startOfDay(for: Date())
        if !daysWithFocus.contains(day),
           let yesterday = cal.date(byAdding: .day, value: -1, to: day) {
            day = yesterday
        }
        while daysWithFocus.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }
}
