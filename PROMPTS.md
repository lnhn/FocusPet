# PROMPTS · FocusPet AI 素材生成提示词全记录

本项目所有视觉与音频素材均由 AI 生成。本文档记录全部提示词与关键参数，便于复刻或扩展（比如给宠物新增一个动作）。

## 一、序列帧图片（144 帧）

### 生成方式

每组动画让 AI 出一张 **4×2 网格大图**（8 格 = 8 帧），然后用统一裁剪框切成 `前缀_1.png ~ 前缀_8.png`。网格一次出图能保证 8 帧是同一个角色；单独生成 8 张会得到 8 只不同的宠物。

### 基础模板

```
A cute kawaii [角色], [动作描述], simple flat cartoon style, thick clean
outline, full body centered in each cell, consistent character design across
all cells, pure white background, no shadow, no watermark, no text,
4x2 grid layout with 8 equal cells, each cell shows one frame of the animation
in sequence
```

### 动作描述词（18 组共用角色模板，只换这一段）

| 前缀 | 动作描述要点 |
| --- | --- |
| `idle` | 轻轻呼吸、尾巴缓慢摆动（变化极小） |
| `walk` | 走路循环；猫加 `slow, lazy, relaxed pacing`，狗加 `bouncy, energetic, happy trotting` |
| `run` | 快速奔跑，身体拉伸 |
| `sleep` | 趴着睡觉，身体起伏 |
| `focus` | 正襟危坐、表情认真 |
| `celebrate` | 跳跃、双爪举起 |
| `wave` | 举爪招手 |
| `sad` | 垂耳低头、沮丧 |
| `eat` | 低头啃食、咀嚼 |

- 猫咪前缀：`idle` `walk` …（无前缀），狗狗全部加 `dog_` 前缀
- **角色一致性**：画第二个动作组时，上传已满意的角色图作为参考图（image reference），并加 `same character as the reference image`
- 脸朝向：素材统一脸朝左，代码里向右移动时水平翻转

### 后处理流水线

```
AI 网格大图 → 统一裁剪框切成 8 帧 → 人工逐帧抽查
→ 边缘洪水填充去白底（切勿全图删白：会删掉乳白色毛发；
  切勿用 clean_watermark 类工具：会把角色当水印抹掉）
→ 按 前缀_序号.png 命名入库
```

## 二、音效（6 个）

使用 AI 音效生成（英文描述，时长参数见下）：

| 文件 | 提示词 | 时长 |
| --- | --- | --- |
| `cat_meow_happy.mp3` | A cute kitten's short happy meow, friendly greeting, bright cheerful tone, single clear meow, no background noise | 1.5s |
| `cat_meow_beg.mp3` | Exactly one single long pitiful meow from a cute kitten, whiny hungry begging tone, one continuous meow only, absolutely no second meow, no repeats | 2.0s |
| `dog_bark_happy.mp3` | A small dog's excited happy bark, friendly yappy greeting, single crisp bark, no background noise | 1.2s |
| `dog_bark_beg.m4a` | 同 begging bark 方向；AI 倾向连吠，**按波形包络裁剪出第一声**、加淡出尾巴后转 AAC | 0.34s |
| `eat_nom.mp3` | Cartoonish cute eating sounds, happy nom nom nom munching kibble, short and playful, no background noise | 2.0s |
| `snore.mp3` | A cute gentle cartoon snore, soft rhythmic purring snore of a sleeping pet, quiet cozy, no background noise | 4.0s |

### 音效踩坑记录

- **AI 会在一条音频里重复叫声**：生成后务必检查波形包络（RMS 脉冲段数），多声的要重新生成或裁剪
- 讨食类提示词要写死 `exactly one single ... no repeats`，即便如此狗叫仍可能连吠——确定性裁剪更可靠
- 裁剪要点：跳过开头 <0.1s 的爆音（短脉冲不算有效声段）、两声之间按 0.12s 静默分割、结尾留 0.25s + 淡出

## 三、Windows 移植提示词

见仓库根目录 [prompt.txt](prompt.txt)——把本 macOS 版 1:1 移植为 C# + WPF（.NET 8）单文件 exe 的完整提示词，含全部技术坑（BitmapImage 缓存解码、透明窗口禁 DropShadowEffect、DragMove 系统级拖拽等）。
