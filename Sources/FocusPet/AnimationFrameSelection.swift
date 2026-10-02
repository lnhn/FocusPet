/// 选择序列动画本次需要绘制的唯一帧。
enum AnimationFrameSelection {
    /// 默认直接切帧；返回 nil 表示当前下标无效。
    static func currentIndex(_ currentIndex: Int, frameCount: Int) -> Int? {
        guard currentIndex >= 0, currentIndex < frameCount else { return nil }
        return currentIndex
    }
}
