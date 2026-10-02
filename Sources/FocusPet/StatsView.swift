import SwiftUI

/// 专注统计窗口内容
struct StatsView: View {
    let stats: StatsSnapshot

    /// 宠物名片：名字、生日、相遇日（可选）
    var petName: String?
    var petBirthday: Date?
    var adoptionDate: Date?

    var body: some View {
        VStack(spacing: 18) {
            if let petName {
                VStack(spacing: 4) {
                    Text(petName).font(.title2.bold())
                    HStack(spacing: 12) {
                        if let petBirthday {
                            let z = Zodiac.of(petBirthday)
                            Text("\(z.emoji) \(z.name)")
                        }
                        if let adoptionDate {
                            let days = max(1, Calendar.current.dateComponents([.day], from: adoptionDate, to: Date()).day ?? 1)
                            Text("相伴 \(days) 天 💞")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                StatBox(title: "今日专注", value: "\(stats.todayCount) 次")
                StatBox(title: "今日时长", value: "\(stats.todayMinutes) 分")
                StatBox(title: "连续天数", value: "\(stats.streakDays) 天")
            }
            HStack(spacing: 12) {
                StatBox(title: "近 7 天", value: "\(stats.weekMinutes) 分")
                StatBox(title: "累计时长", value: "\(stats.totalMinutes) 分")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("近 7 天专注分钟数").font(.headline)
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(0..<stats.last7Days.count, id: \.self) { i in
                        let minutes = stats.last7Days[i]
                        VStack(spacing: 4) {
                            Text("\(minutes)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 6 ? Color.orange : Color.gray.opacity(0.45))
                                .frame(
                                    width: 26,
                                    height: max(4, CGFloat(minutes) / CGFloat(max(1, stats.last7Days.max() ?? 1)) * 90)
                                )
                            Text(Self.dayLabel(daysAgo: 6 - i))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    static func dayLabel(daysAgo: Int) -> String {
        guard let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else {
            return "?"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: date)
    }
}

private struct StatBox: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.12))
        )
    }
}
