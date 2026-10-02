# FocusPet

一只住在你 Mac 桌面上的专注宠物：猫咪或狗狗趴在屏幕角落陪你工作，头上的气泡显示番茄钟倒计时，专注完成时它跑到屏幕中央为你庆祝。

![FocusPet Mascot](docs/mascot.png)

## 功能

**番茄钟**

- 经典 25/5/15 分钟循环，每 N 轮一次长休（可在设置中调整）
- 全局快捷键 `⇧⌘P`：开始专注 / 暂停 / 继续
- 专注时宠物正襟危坐，休息时趴着打呼噜（每 6~10 秒一声）
- 专注完成：宠物跑到屏幕中央弹跳庆祝 + 系统通知
- 中途放弃：宠物会难过
- 菜单栏图标实时显示倒计时

**宠物**

- 猫 / 狗 二选一（状态栏菜单随时切换），可缩放 50%~150%
- 144 帧 AI 生成序列帧动画：待机 / 走路 / 奔跑 / 睡觉 / 专注 / 庆祝 / 挥手 / 难过 / 进食
- 自由行为：散步（猫慵懒踱步、狗欢快蹦跳）、随机乱窜、挥手、打盹
- 交互：拖拽（零延迟跟手）、单击投喂、双击庆祝（爱心飘出）、被抓起会挣扎挥手
- 饥饿系统：超过 2 小时没投喂会讨食；专注中饿了只发系统通知，不打扰你
- 宠物音效：叫声 / 进食 / 呼噜（可关闭）

**记录与个性化**

- 专注统计：今日次数/时长、连续天数、近 7 天柱状图、累计时长（JSON 本地存储）
- 宠物资料：名字、生日（自动算星座）、相遇纪念日（显示相伴天数）
- 星座匹配度：宠物与主人的星座配对评分
- 设置即时生效，登录自启可选

## 技术栈

- **Swift + SwiftPM**，AppKit 为主（窗口/事件/动画），SwiftUI 用于设置与统计界面
- 序列帧动画：`CVDisplayLink` 驱动 + 帧缓存 + 不变不重绘（日常 CPU 占用约 0~1%）
- 无边框透明 `NSPanel`，全桌面空间漫游，阴影关闭
- 全局快捷键：Carbon `RegisterEventHotKey`（无需辅助功能权限）
- 拖拽：`performDrag`（WindowServer 级跟手，零延迟）
- 通知：UserNotifications（仅正式 .app 环境）
- 素材：AI 生成的 144 帧序列帧 + 6 个音效（提示词见 [PROMPTS.md](PROMPTS.md)）

## 构建与运行

需要 macOS 14+ 与 Swift 5.9+ 工具链：

```bash
git clone https://github.com/lnhn/FocusPet.git
cd FocusPet
swift run            # 开发调试
swift build -c release && ./package-app.sh release   # 打包成 .app
cp -R .build/release/FocusPet.app /Applications/     # 安装
```

## 目录结构

```
FocusPet/
├── Package.swift                  # SwiftPM 构建清单
├── package-app.sh                 # 打包脚本（组装 .app）
├── PROMPTS.md                     # AI 素材生成提示词全记录
├── Sources/FocusPet/
│   ├── main.swift                 # 入口
│   ├── AppDelegate.swift          # 总指挥：装配所有模块
│   ├── PetController.swift        # 宠物窗口、行为调度、移动
│   ├── PetView.swift              # 动画渲染、气泡绘制、交互
│   ├── FocusEngine.swift          # 番茄钟状态机（纯逻辑无 UI）
│   ├── SoundManager.swift         # 音效播放
│   ├── StatusBarController.swift  # 菜单栏图标
│   ├── HotkeyManager.swift        # 全局快捷键
│   ├── SettingsModel.swift        # 设置（UserDefaults 持久化）
│   ├── SettingsView.swift         # 设置界面（SwiftUI）
│   ├── StatsStore.swift           # 统计存储（Codable + JSON）
│   ├── StatsView.swift            # 统计界面（SwiftUI）
│   ├── Zodiac.swift               # 星座计算
│   ├── Info.plist                 # 应用元数据
│   ├── PetAssets/                 # 144 帧序列帧素材
│   └── Sounds/                    # 6 个 AI 音效
├── Tests/                         # 极简测试
└── 教程/                           # 15 篇零基础开发教程（中文）
```

## 教程

`教程/` 目录下有一整套面向零基础的开发教程（15 篇 + 总索引），从 Swift 语法、应用架构、动画引擎、交互系统到打包发布，每一篇都对照本仓库真实源码讲解，并附练习。另有合并好的 [PDF 版](教程/FocusPet零基础开发教程.pdf)（78 页）。

## 配套

- `prompt.txt`：1:1 移植到 Windows（C# + WPF）的完整提示词，已有一个可用的 Windows 版
- `教程/12-AI素材生产管线.md`：素材生成的踩坑记录（网格切片、去底修洞）

## License

MIT
