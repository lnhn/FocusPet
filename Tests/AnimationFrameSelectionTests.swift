@main
struct AnimationFrameSelectionTests {
    static func main() {
        precondition(AnimationFrameSelection.currentIndex(3, frameCount: 8) == 3)
        precondition(AnimationFrameSelection.currentIndex(-1, frameCount: 8) == nil)
        precondition(AnimationFrameSelection.currentIndex(8, frameCount: 8) == nil)
        print("AnimationFrameSelection tests passed")
    }
}
