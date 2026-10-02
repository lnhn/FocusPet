import AppKit

/// 宠物音效：NSSound 从资源包加载一次后复用。
/// 音效文件位于 Sources/FocusPet/Sounds/（SwiftPM 资源包内）。
final class SoundManager {
    static let shared = SoundManager()

    /// 由设置注入：用户可在设置面板关闭音效
    var enabled = true

    /// 音量 0~1（宠物叫声宜轻，不打扰工作）
    var volume: Float = 0.45

    private var cache: [String: NSSound] = [:]

    private init() {}

    /// 播放指定音效（不带扩展名）；正在播放时先停再播，保证重叠触发也能立刻出声
    func play(_ name: String) {
        guard enabled else { return }
        let sound = cache[name] ?? load(name)
        guard let sound else { return }
        sound.volume = volume
        if sound.isPlaying { sound.stop() }
        sound.play()
    }

    private func load(_ name: String) -> NSSound? {
        // 优先 mp3；个别修剪过的素材是 m4a（AAC）
        let url = Bundle.module.url(
            forResource: name, withExtension: "mp3", subdirectory: "Sounds"
        ) ?? Bundle.module.url(
            forResource: name, withExtension: "m4a", subdirectory: "Sounds"
        )
        guard let url else {
            print("⚠️ 缺少音效: \(name).mp3/.m4a")
            fflush(stdout)
            return nil
        }
        let sound = NSSound(contentsOf: url, byReference: true)
        cache[name] = sound
        return sound
    }
}
