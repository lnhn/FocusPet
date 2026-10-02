# 11 · 统计系统：JSON 存储与快照算法

> FocusPet 零基础开发教程 · 第 11 篇
> 对应源码：`Sources/FocusPet/StatsStore.swift`（112 行）、`Sources/FocusPet/StatsView.swift`（95 行）

番茄钟跑了一周，用户自然会问：「我这周专注了多久？连续几天了？」统计系统要回答这类问题。它的架构分两层：

```
数据层：StatsStore —— 存取原始记录（JSON 文件）
            ↓ snapshot() 加工
展示层：StatsView —— 拿加工好的快照画界面
```

两层的分界线是一个关键设计：**StatsSnapshot（快照）**。视图从不直接接触原始记录数组，只消费一个算好的、扁平的统计结果。为什么这样设计？看完本章你就明白。

---

## 一、数据层：一个 JSON 文件就是数据库

### 1.1 数据模型：Codable 的魔力

一条专注记录长这样：

```swift
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
```

注意第一个词：`Codable`。它是 Swift 里一个协议组合（`Encodable` + `Decodable`），效果是——**编译器自动为你生成「对象 ↔ 数据」的双向转换**。你不需要写任何序列化代码，只要让结构体的每个成员本身可编码（`String`、`Date`、`UUID`、`Double`、数组……全都可以），整个结构体就能一键存取。

这就是 Swift 式的「约定优于配置」：换别的语言，同样的功能往往要写一堆映射代码或引入一个第三方库。

`actualMinutes` 是个**计算属性**（只有 getter）：不存数据，每次访问时现场算「从结束到开始过了几分钟」。因为「实际分钟」永远可以由起止时间推导出来，存下来反而会不一致。

### 1.2 存取三行核心代码

```swift
/// 简单的 JSON 文件存储：~/Library/Application Support/FocusPet/sessions.json
final class StatsStore {
    static let shared = StatsStore()          // 单例：全应用一个仓库

    private let url: URL                       // 数据文件地址
    private(set) var records: [SessionRecord] = []

    private init() { ... }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        records = (try? JSONDecoder().decode([SessionRecord].self, from: data)) ?? []
    }

    private func save() {
        try? JSONEncoder().encode(records).write(to: url, options: .atomic)
    }
}
```

读和写各一行核心调用，但每一行都值得咀嚼：

| 代码 | 拆解 |
| --- | --- |
| `try? Data(contentsOf: url)` | 读文件。`try?` 把「可能失败」变成「失败就返回 nil」——文件不存在？返回 nil，跳过整段。首次启动没有历史数据，这不是错误，是常态 |
| `JSONDecoder().decode([SessionRecord].self, ...)` | 把 JSON 字节翻译回对象数组。`[SessionRecord].self` 是「一个 SessionRecord 数组的类型本身」 |
| `?? []` | 解码失败（文件损坏、版本不兼容）也别崩溃，给个空数组当什么都没发生过 |
| `.write(to: url, options: .atomic)` | **原子写入**：先写到一个临时文件，写完后一次性改名为正式文件。中途断电/崩溃也不会留下半个文件 |

全链路没有一处会抛异常到用户脸上——**读不到就当空的，写失败就当没写，文件坏了就从头再来**。统计数据丢了不致命，崩溃才致命。这是「优雅降级」思想的又一次实践（第 09 章通知授权那节见过）。

### 1.3 为什么不用 UserDefaults / CoreData / SQLite

你可能会问：第 10 章的 UserDefaults 不也是存数据吗？选型逻辑是这样的：

| 方案 | 适合 | 本项目为什么没选 |
| --- | --- | --- |
| UserDefaults | 十几个扁平设置项 | 记录会无限增长，放偏好文件里会拖慢读取，也违背「偏好 ≠ 数据」的惯例 |
| CoreData / SQLite | 海量数据、复杂查询、多表关联 | 杀鸡用牛刀——我们的「查询」就是遍历数组算个和，1000 条记录的眼睛都眨一下 |
| **JSON 文件** | 结构简单的追加型记录，数据量中小 | ✅ 读写各一行，肉眼可打开检查，备份就是一个文件 |

工程选型的第一原则不是「哪个最先进」，而是「哪个刚刚好」。

### 1.4 单例的合理场景

```swift
static let shared = StatsStore()
private init() { ... }
```

`static let shared` + `private init` 是单例的标准写法：全局唯一实例，外部无法另行创建。第 05 篇提过单例容易藏耦合，为什么这里敢用？因为仓库**天生就该唯一**——两份各自为政的 records 数组意味着数据分裂，那才是真正的灾难。判断单例是否合理的试金石：**这个事物的「唯一性」是需求本身，还是偷懒图方便？** StatsStore 属于前者。

---

## 二、加工层：snapshot() 把数组翻译成答案

StatsView 需要六个数字（今日次数、今日分钟、近 7 天分钟、累计分钟、连续天数、近 7 天分布）。`snapshot()` 的工作就是把原始记录数组**一次性算出这六个数字**，打包成快照：

```swift
struct StatsSnapshot {
    var todayCount = 0
    var todayMinutes = 0
    var weekMinutes = 0
    var totalMinutes = 0
    var streakDays = 0
    var last7Days: [Int] = Array(repeating: 0, count: 7)  // [0]=6天前 … [6]=今天
}
```

### 2.1 核心循环：一次遍历，四个统计

```swift
for record in records where record.completed && record.kind == "focus" {
    let minutes = record.actualMinutes
    let day = cal.startOfDay(for: record.endedAt)   // 该记录归属哪一天（按结束时刻）

    if day == todayStart {
        snap.todayCount += 1
        snap.todayMinutes += minutes
    }
    if day >= weekAgo {
        snap.weekMinutes += minutes
        let offset = cal.dateComponents([.day], from: day, to: todayStart).day ?? -1
        if (0...6).contains(offset) {
            snap.last7Days[6 - offset] += minutes    // 落进对应的天槽
        }
    }
    snap.totalMinutes += minutes
}
```

三个值得学的点：

1. **`for ... where` 条件过滤**：只统计「完成且是专注」的记录。中断的专注（`completed == false`）和休息都不计入——产品规则一行声明式表达。
2. **`Calendar.current.startOfDay`**：把任意时刻归一到「那天的 0 点」。日期比较必须先归一，否则「今天 23:59 结束」和「今天 00:01 开始」会被当作不同的时间点而无法参与相等比较。这是所有日历类编程的第一课：**别比较时刻，比较「天」**。
3. **offset → 槽位映射**：`dateComponents([.day], from: day, to: todayStart)` 算出「那天距今天几天」，然后 `last7Days[6 - offset]` 落位——6 天前偏移 6，放槽 0；今天偏移 0，放槽 6。数组索引和「天前数」方向相反，这个换算容易绕晕，画个表就清楚了：

| 槽位 | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 含义 | 6 天前 | 5 天前 | 4 天前 | 3 天前 | 前天 | 昨天 | 今天 |
| offset（距今天） | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
| 索引公式 | 6−6 | 6−5 | … | … | 6−2 | 6−1 | 6−0 |

### 2.2 连续天数算法：今天没专注，从昨天起算

「连续专注 N 天」最常见的纠结：**今天还没专注， streak 要不要清零？** 合理的体验是：不清零，今天只是还没开始，昨天的记录仍然算数。streakDays 的算法体现了这个体贴：

```swift
var streakDays: Int {
    let cal = Calendar.current
    // 第一步：收集所有「完成过专注」的日期，去重成集合
    let daysWithFocus = Set(
        records
            .filter { $0.completed && $0.kind == "focus" }
            .map { cal.startOfDay(for: $0.endedAt) }
    )
    var count = 0
    var day = cal.startOfDay(for: Date())
    // 今天还没专注 → 起点挪到昨天（今天中断不算断签）
    if !daysWithFocus.contains(day),
       let yesterday = cal.date(byAdding: .day, value: -1, to: day) {
        day = yesterday
    }
    // 从今天（或昨天）开始往前一天一天数
    while daysWithFocus.contains(day) {
        count += 1
        guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
        day = prev
    }
    return count
}
```

三个技巧：

- **`Set` 去重**：同一天专注 5 次，集合里只有 1 个元素。连续天数数的是「天数」不是「次数」。
- **起点修正**：今天不在集合里，起点先挪到昨天。`if` 后面跟 `,` 再接一个 `let` 是 Swift 的「可选绑定 + 条件复合」语法——两个条件都满足才进分支。
- **回溯循环**：从起点逐日往前查集合，断了就停。循环次数 = streak 天数，天然高效。

---

## 三、展示层：纯 SwiftUI 的统计页

StatsView 是项目里第二处 SwiftUI（第一处是设置面板），它展示了一种典型的函数式视图风格——**只读输入，无副作用**：

```swift
struct StatsView: View {
    let stats: StatsSnapshot        // 只读！没有 @ObservedObject，没有 @State
```

视图拿到的只是一个快照值。数据从哪来、什么时候刷新，视图一概不管——每次打开统计窗口，AppDelegate 现场调一次 `snapshot()`、现场构建一个 StatsView。窗口关闭，视图销毁。没有订阅、没有同步、没有状态管理，**生命周期最简单的界面反而最不容易出 bug**。

### 3.1 柱状图：SwiftUI 画图表的朴素之道

界面最下面的近 7 天柱状图没有引用任何图表库，纯基础控件拼装：

```swift
HStack(alignment: .bottom, spacing: 10) {   // 底对齐 → 柱子底部在一条线上
    ForEach(0..<stats.last7Days.count, id: \.self) { i in
        let minutes = stats.last7Days[i]
        VStack(spacing: 4) {
            Text("\(minutes)")                        // 柱顶数字
            RoundedRectangle(cornerRadius: 3)          // 柱子本体
                .fill(i == 6 ? Color.orange : Color.gray.opacity(0.45))  // 今天橙色高亮
                .frame(width: 26,
                      height: max(4, CGFloat(minutes) / CGFloat(max(1, stats.last7Days.max() ?? 1)) * 90))
            Text(Self.dayLabel(daysAgo: 6 - i))       // 柱底日期
        }
    }
}
```

柱子高度的归一化公式值得单独看一眼：

```
height = minutes / max(1, 近7天最大值) × 90
```

- 最高的柱子永远是 90 点（满分柱），其余按与最大值的比例缩放——不管数据是 5 分钟还是 500 分钟，图都能看。
- 外面再包一层 `max(4, ...)`：0 分钟的柱子也有 4 点高，不至于「消失」导致对不齐。
- `max(1, ...)` 防除零：如果一周全没专注，最大值是 0，直接除会崩。

SwiftUI 画图的哲学和 Canvas 手绘（第 05 篇的气泡）不同：**用声明式布局控件当积木**，HStack 管横排、VStack 管纵排、`alignment: .bottom` 一摆，柱状图自己就立起来了。适合条形类简单图表；折线图、饼图再考虑图表库。

### 3.2 复用小视图：StatBox

```swift
private struct StatBox: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)      // 在 HStack 里均分宽度
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.12)))
    }
}
```

一个大数字 + 一个小标题的统计卡片，在界面里用了 5 次。抽成独立的小视图后，5 次使用变成 5 行调用——这就是「组件化」的最小实践。`private` 修饰表示它是 StatsView 的私有小帮手，外界不需要知道它存在。

---

## 四、为什么是「快照」而不是「视图自己算」

最后回到开头的架构问题，现在可以给出完整答案了：

| 方案 | 问题 |
| --- | --- |
| StatsView 直接持有 records 数组自己算 | 视图里塞满日期计算和过滤逻辑，界面代码被业务逻辑污染；换界面（比如菜单栏显示今日分钟）要重抄一遍算法 |
| **snapshot() 一次算好** | 算法集中在 StatsStore（数据的家）；StatsView 只画数字；以后任何新界面消费同一个快照即可 |

这条原则叫「**单一数据真相源**」（Single Source of Truth）：原始记录只有一个家（StatsStore），所有派生数字都从它那里算，绝不另起炉灶存第二份。

---

## 练习

1. 在 Playground 里造 10 条假记录（跨 5 天，含一次中断），跑 `snapshot()`，手算一遍期望值再对答案。
2. 给 StatsSnapshot 加一个 `averageMinutesPerFocus`（累计分钟 ÷ 累计完成专注数），分母为 0 时返回 0。想好这个除法该怎么防崩。
3. 把柱状图的最高柱从 90 改成 60，再把今天的颜色从橙色改成粉色——体会「改视图不改逻辑」的清爽。
4. 思考题：如果记录增长到 10 万条，`snapshot()` 每次全量遍历会不会慢？（提示：算一下 10 万次简单比较需要多少毫秒，再想想什么时候才值得优化。）
