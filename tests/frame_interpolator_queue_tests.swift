import Foundation

// The runner inserts the actual admission, pause, reset, HUD dispatch, and
// processing-reset branch. Only frame storage and GPU completion are controlled.
final class Frame: NSObject {
    let number: Int
    init(_ number: Int) { self.number = number }
}
final class WeakFrame {
    weak var frame: Frame?
    init(_ frame: Frame) { self.frame = frame }
}
final class FrameInterpolator {
    typealias Completion = (NSArray) -> Void
    private struct PendingFrame { let frame: Frame; let completion: Completion }
    private let queue = DispatchQueue(label: "interpolation-admission-tests")
    // SUNLIGHT_ACTUAL_PENDING_LIMIT
    private var pendingFrames: [PendingFrame] = []
    private var isProcessing = false
    private var isPaused = false
    private var resetRequested = false
    private var resetResolutionTierRequested = false
    private var overlayGeneration = 0
    var transientHUDHandler: ((String?) -> Void)?
    private var active: PendingFrame?
    private(set) var largestPendingCount = 0

    // SUNLIGHT_ACTUAL_INTERPOLATOR_METHODS

    private func drainPendingFrames() {
        largestPendingCount = max(largestPendingCount, pendingFrames.count)
        guard !isProcessing, !pendingFrames.isEmpty else { return }
        active = pendingFrames.removeFirst()
        isProcessing = true // Hold a real strong input until the fake GPU completes.
    }
    private func resetLocked(resetResolutionTier: Bool = false) {
        _ = resetResolutionTier
        isProcessing = false
        resetRequested = false
        resetResolutionTierRequested = false
        pendingFrames.removeAll()
    }
    func completeGPU() {
        queue.sync {
            guard let pending = self.active else { fatalError("No in-flight operation") }
            self.active = nil
            let completion = pending.completion
            self.isProcessing = false
            // SUNLIGHT_ACTUAL_PROCESSING_RESET_BRANCH
            completion([pending.frame])
            self.drainPendingFrames()
        }
    }
    func drainAdmissions() { queue.sync {} }
    var waitingNumbers: [Int] { queue.sync { pendingFrames.map { $0.frame.number } } }
    func resetForTest() { queue.sync { requestResetLocked() } }
    func showHUD(_ text: String) { queue.sync { showTransientHUDText(text) } }
}

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else { fatalError("FAIL: \(message)") }
}
func spinMain(until condition: () -> Bool, timeout: TimeInterval = 1) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
}

func testStalledGPU() {
    let interpolator = FrameInterpolator()
    var weakFrames: [WeakFrame] = []
    var displayed: [Int] = []
    var drops = 0
    for number in 1...1000 {
        let frame = Frame(number)
        weakFrames.append(WeakFrame(frame))
        interpolator.processFrame(frame) { outputs in
            if outputs.count == 0 { drops += 1 }
            for case let frame as Frame in outputs { displayed.append(frame.number) }
        }
    }
    interpolator.drainAdmissions()
    check(interpolator.waitingNumbers == [999, 1000], "stalled GPU retains only the two latest waiting images")
    check(interpolator.largestPendingCount == 2, "waiting decoded image bound holds throughout the burst")
    check(weakFrames.filter { $0.frame != nil }.count == 3, "dropped buffers release while exactly one GPU input and two waiting images remain")
    check(drops == 997 && displayed.isEmpty, "overflow reports drops without publishing newer images ahead of GPU work")
    interpolator.completeGPU()
    check(displayed == [1] && interpolator.waitingNumbers == [1000], "GPU completion preserves chronological output and starts the latest retained work")
    interpolator.completeGPU()
    interpolator.completeGPU()
    check(displayed == [1, 999, 1000] && drops == 997, "all accepted images finish in original timestamp order")
    check(weakFrames.allSatisfy { $0.frame == nil }, "completion releases every retained input image")
}

func testPauseAndResetOrdering() {
    let paused = FrameInterpolator()
    var displayed: [Int] = []
    var drops = 0
    let completion: FrameInterpolator.Completion = { outputs in
        if outputs.count == 0 { drops += 1 }
        for case let frame as Frame in outputs { displayed.append(frame.number) }
    }
    paused.processFrame(Frame(1), completion: completion)
    paused.processFrame(Frame(2), completion: completion)
    paused.drainAdmissions()
    paused.setPaused(true)
    paused.drainAdmissions()
    check(paused.waitingNumbers.isEmpty && drops == 1, "pausing retires waiting images without out-of-order publication")
    paused.processFrame(Frame(3), completion: completion)
    paused.drainAdmissions()
    check(displayed == [3], "paused interpolation preserves ordinary passthrough")
    paused.completeGPU()
    check(displayed == [3] && drops == 2, "old GPU result is dropped after newer paused passthrough")
    paused.setPaused(false)
    paused.processFrame(Frame(4), completion: completion)
    paused.drainAdmissions()
    paused.completeGPU()
    check(displayed == [3, 4], "resuming accepts a fresh ordered image")

    let reset = FrameInterpolator()
    reset.processFrame(Frame(5), completion: completion)
    reset.drainAdmissions()
    reset.resetForTest()
    reset.processFrame(Frame(6), completion: completion)
    reset.drainAdmissions()
    reset.completeGPU()
    check(displayed == [3, 4, 6] && drops == 3, "explicit reset cannot return an older GPU image after fresh passthrough")
}

func testOriginalHUDSink() {
    let interpolator = FrameInterpolator()
    var first: [String?] = []
    var successor: [String?] = []
    interpolator.transientHUDHandler = { first.append($0) }
    interpolator.showHUD("Original")
    interpolator.transientHUDHandler = { successor.append($0) }
    spinMain(until: { first.count == 1 })
    check(first == ["Original"] && successor.isEmpty, "queued HUD captures the original sink before main-thread dispatch")
    interpolator.resetForTest()
    spinMain(until: { first.count > 1 || !successor.isEmpty }, timeout: 5.2)
    check(first == ["Original"] && successor.isEmpty, "reset invalidates delayed HUD clearing without resolving a later sink")
}

testStalledGPU()
testPauseAndResetOrdering()
testOriginalHUDSink()
print("FRAME_INTERPOLATOR_QUEUE_TESTS_RESULT: PASS (\(checks) checks)")
