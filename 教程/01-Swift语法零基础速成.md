# 01 · Swift 语法零基础速成

> FocusPet 零基础开发教程 · 第 1 篇

本篇只讲读懂本项目必需的 Swift 语法，30 分钟建立感觉。Swift 由 Apple 设计，目标是「安全 + 表达力强」，很多语法和 JavaScript/Python 有相似之处。

## 1. 常量和变量

```swift
let name = "咪咪"        // let = 常量，赋值后不能改（默认优先用 let）
var age = 3              // var = 变量，可以改
age = 4

// 类型标注（一般不写，编译器自动推断）
let explicit: String = "旺财"
let count: Int = 8
let ratio: Double = 0.75
let visible: Bool = true
```

**重要习惯**：Swift 里 `let` 优先。本项目 90% 的声明都是 `let`。

## 2. 函数

```swift
// 无返回值
func greet() {
    print("你好")
}

// 有参数、有返回值
func add(_ a: Int, to b: Int) -> Int {
    return a + b
}
add(3, to: 5)   // 8。参数名前加 _ 表示调用时不写参数名

// 参数标签（Swift 特色，提高可读性）
func play(_ action: PetAction, completion: (() -> Void)? = nil) { ... }
play(.idle)                        // completion 有默认值，可省略
play(.wave) { print("播完了") }     // 尾随闭包语法
```

## 3. 可选类型（Optional）★最重要的概念

Swift 用 `?` 表示「可能没有值」，用 `!` 或 `if let` 拆包：

```swift
var petName: String? = "咪咪"   // 可能是 String，可能是 nil
petName = nil                   // 表示"没有名字"

// 安全拆包方式一：if let（推荐）
if let name = petName {
    print(name)      // 只有非 nil 才进这里，name 是普通 String
} else {
    print("没名字")
}

// 方式二：guard let（提前退出，函数里常用）
func feed(_ pet: PetController?) {
    guard let pet else { return }   // pet 为 nil 直接返回
    pet.feed()                      // 这里 pet 一定是非 nil
}

// 方式三：可选链 ?. （调用链上任何一环为 nil 就整个返回 nil，不崩溃）
window?.performDrag(with: event)

// 方式四：强制拆包 !（确定有值时用，本项目刻意几乎不用）
```

**为什么重要**：macOS API 里到处都是可选（`statusItem.button?`、`window?.frame`），读不懂 `?` 就读不懂源码。

## 4. 闭包（Closure）

就是「可以当变量传的代码块」，类似 JS 的匿名函数：

```swift
// 完整写法
let sayHi = { (name: String) -> Void in
    print("你好 \(name)")
}
sayHi("咪咪")

// 简写（项目里常见）
DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
    self.play(.idle)     // 参数是闭包时，可用尾随闭包语法放在括号外
}

// 逃逸闭包 @escaping（闭包在函数返回后才执行，必须标注）
var onComplete: (() -> Void)?    // 项目里大量这种"回调槽位"
```

**回调模式**（本项目核心通信方式）：

```swift
final class FocusEngine {
    var onTick: ((TimeInterval) -> Void)?    // 预留一个"插槽"
}
engine.onTick = { remaining in             // 使用方把代码插进去
    label.text = "\(remaining)"
}
```

类与类之间不互相引用，而是「我定义回调插槽，你往里插代码」——这是整个项目的解耦哲学。

## 5. 结构体与类

```swift
struct AnimationSpec {       // struct = 值类型，拷贝即复制（本项目的小数据都用它）
    let prefix: String
    let count: Int
    let frameDuration: Double
}

final class PetController {  // class = 引用类型，拷贝的是"指针"（管理窗口/定时器等"活物"用它）
    let species: PetSpecies  // let 属性：初始化后不可换，但对象内部状态可变
    private var timer: Timer? // private = 仅类内部可见
}
```

判断标准：**只是数据**用 struct，**有生命周期、要改别人状态**用 class。`final` 表示不许继承，项目全部加了。

## 6. 枚举与关联（项目的动作系统）

```swift
enum PetAction: String, CaseIterable {
    case idle, wave, sleep, focus, celebrate, sad, run, walk, eat
}
// 用法：play(.walk)
// CaseIterable 让枚举可以 for 循环遍历

// 带计算属性的枚举（星座篇用到）
enum Zodiac: Int, CaseIterable {
    case aries, taurus
    var name: String {
        switch self {
        case .aries: return "白羊座"
        case .taurus: return "金牛座"
        }
    }
}
```

## 7. 字典与数组

```swift
let frames: [NSImage] = [...]                    // 数组
let specs: [PetAction: AnimationSpec] = [        // 字典（键值对）
    .idle: AnimationSpec(prefix: "idle", count: 8, ...),
    .walk: AnimationSpec(prefix: "walk", count: 8, ...)
]
let walkSpec = specs[.walk]   // 返回 Optional！因为键可能不存在

// 项目里用了 force unwrap（!）的地方：species.specs[.idle]!
// 因为我们 100% 确定每个动作都配了素材，所以敢用。新手建议先用 if let。
```

## 8. 字符串插值与格式化

```swift
let name = "咪咪"
print("你好 \(name)")                    // 插值
let text = String(format: "%02d:%02d", 8, 5)   // "08:05"（倒计时用它补零）
```

## 9. 时间

```swift
let now = Date()                              // 当前时间
let timestamp = now.timeIntervalSince1970     // 时间戳（存 UserDefaults 用）
let later = Date().addingTimeInterval(3600)   // 一小时后
CACurrentMediaTime()                          // 动画专用的高精度时钟（推荐）
```

## 10. 单例与静态成员

```swift
final class StatsStore {
    static let shared = StatsStore()   // 全局唯一实例
    private init() {}                  // 私有化构造，外部只能 shared.xxx
}
// 使用：StatsStore.shared.add(record)
```

## 11. guard / switch / for 速览

```swift
guard !frames.isEmpty else { return }   // 不满足条件就滚，满足才往下走

switch Int.random(in: 0..<10) {          // 区间 0~9
case 0...4: stroll()                     // 区间匹配
case 5...6: wave()
default: break
}

for i in 0..<8 { load("frame_\(i)") }   // 0~7 循环
```

## 12. self 与弱引用 [weak self]

```swift
// 定时器/闭包会"持有" self，若 self 也持有它们 → 循环引用 → 内存泄漏
roamTimer = Timer.scheduledTimer(withTimeInterval: delay) { [weak self] _ in
    self?.performRoam()     // self 变可选，对象被销毁时自动变 nil，不会崩溃
}
```

## 最小练习

打开终端 `swift` 进入 REPL，敲：

```swift
let name = "咪咪"
print("我是\(name)")
var hungry = true
if hungry { print("喂我") }
func feed(_ n: String) -> String { "\(n)吃饱了" }
print(feed(name))
```

能跑通，本篇毕业。下一篇我们看看 macOS 应用到底是怎么启动的。
