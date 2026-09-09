import Foundation

// Production start/stop/clean/send/interruption methods are inserted by the
// runner. Fake audio/Opus endpoints make their ordering deterministic without
// requesting desktop recording permission or accessing audio hardware.
var checks = 0
var encoderCalls = 0
var encoderResult: Int32 = 8
var destroyedEncoders = 0
func require(_ okay: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !okay() { fatalError(message) }
}
func wait(_ semaphore: DispatchSemaphore) {
    require(semaphore.wait(timeout: .now() + 3) == .success, "lifecycle boundary timed out")
}
func opus_encode(_ encoder: OpaquePointer, _ samples: [Int16], _ frames: Int32,
                 _ bytes: inout [UInt8], _ capacity: Int32) -> Int32 {
    precondition(frames == 960 && samples.count == 960, "encoder must receive one mono20ms frame")
    encoderCalls += 1
    if encoderResult > 0 { for i in 0..<Int(encoderResult) { bytes[i] = UInt8(i) } }
    return encoderResult
}
func opus_encoder_destroy(_ encoder: OpaquePointer) { destroyedEncoders += 1 }
let AVAudioSessionInterruptionTypeKey = "interruptionType"
enum AVAudioSession {
    enum InterruptionType: UInt { case ended = 0, began = 1 }
}
enum FixtureScheduler {
    static var pending: [() -> Void] = []
    static func after(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
    static func run() { let callbacks = pending; pending.removeAll(); callbacks.forEach { $0() } }
}
class FakeNode: NSObject {
    var stopped = 0, tapsRemoved = 0
    func stop() { stopped += 1 }
    func removeTap(onBus: Int) { tapsRemoved += 1 }
}
class FakeEngine {
    var isRunning = false, starts = 0, stops = 0, detaches = 0
    func start() throws { isRunning = true; starts += 1 }
    func stop() { isRunning = false; stops += 1 }
    func detach(_ node: FakeNode) { detaches += 1 }
}
class FakeTimer {
    var starts = 0, pauses = 0, cleans = 0
    func start() { starts += 1 }
    func pause() { pauses += 1 }
    func clean() { cleans += 1 }
}
class Capture: NSObject {
    var isRecording = false, captureClosed = false, isCleaned = false, wantsRecording = false
    let lifecycleLock = NSRecursiveLock()
    var interruptionGeneration: UInt64 = 0
    var engineConfigured = false, inputTapInstalled = false
    var captureMixerAttached = false, mutedMixerAttached = false
    let engine = FakeEngine(), captureMixer = FakeNode(), mutedMixer = FakeNode()
    var pcm16BufferDeque: [Int16] = []
    let bufferQueue = DispatchQueue(label: "test.microphone.capture")
    var timer: FakeTimer? = FakeTimer()
    var notificationTokens: [NSObjectProtocol] = []
    var opusEncoder: OpaquePointer?
    var sendPacket: (Data) -> Void = { _ in }
    var configurations = 0
    func configureEngine() throws {
        configurations += 1; engineConfigured = true
        captureMixerAttached = true; mutedMixerAttached = true; inputTapInstalled = true
        opusEncoder = OpaquePointer(bitPattern: 1)
    }
    func notify(_ error: Error) { fatalError("unexpected fake engine failure") }
    func fill() { bufferQueue.sync { pcm16BufferDeque = Array(repeating: 5, count: 960) } }
    func interrupt(_ type: AVAudioSession.InterruptionType) {
        handleInterruption(Notification(name: Notification.Name("test"), userInfo: [AVAudioSessionInterruptionTypeKey: type.rawValue]))
    }
    // PRODUCTION_METHODS
}

let normal = Capture()
var received: [Data] = []
normal.sendPacket = { received.append($0) }
normal.fill(); normal.sendOpusFrameFromDequeBuffer()
require(encoderCalls == 0, "unstarted capture cannot encode")
normal.startTapping(); normal.fill(); normal.sendOpusFrameFromDequeBuffer()
require(received == [Data(0..<8)], "encoded bytes copied with exact returned length")
require(normal.configurations == 1, "capture configures once")
normal.stopTapping(stopEngine: false); normal.fill(); normal.sendOpusFrameFromDequeBuffer()
require(received.count == 1, "paused timer work cannot send")
normal.startTapping(); normal.fill(); encoderResult = -1; normal.sendOpusFrameFromDequeBuffer()
require(received.count == 1, "encoder failure cannot forward invalid length")
encoderResult = 8
normal.interrupt(.began); normal.interrupt(.ended)
require(FixtureScheduler.pending.count == 1, "interruption schedules requested resume")
normal.stopTapping(stopEngine: false); FixtureScheduler.run()
require(!normal.isRecording, "manual pause invalidates queued interruption resume")
normal.startTapping(); normal.interrupt(.began); normal.interrupt(.ended); FixtureScheduler.run()
require(normal.isRecording && normal.configurations == 1, "interruption resumes existing graph without duplicate capture")
normal.interrupt(.began); normal.interrupt(.ended)
let retiredTimer = normal.timer!
normal.clean(); FixtureScheduler.run(); normal.startTapping(); normal.fill(); normal.sendOpusFrameFromDequeBuffer()
require(normal.isCleaned && normal.captureClosed && !normal.isRecording, "retired capture cannot restart")
require(retiredTimer.cleans == 1 && normal.engine.detaches == 2, "timer and attached graph release once")
require(destroyedEncoders == 1, "Active Opus encoder released")
normal.clean(); require(retiredTimer.cleans == 1 && destroyedEncoders == 1, "cleanup is idempotent")

let concurrent = Capture(), entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
let cleanupEntered = DispatchSemaphore(value: 0), cleanupDone = DispatchSemaphore(value: 0)
concurrent.startTapping(); concurrent.fill()
concurrent.sendPacket = { _ in entered.signal(); _ = release.wait(timeout: .now() + 3) }
DispatchQueue.global().async { concurrent.sendOpusFrameFromDequeBuffer() }
wait(entered)
DispatchQueue.global().async { cleanupEntered.signal(); concurrent.clean(); cleanupDone.signal() }
wait(cleanupEntered)
require(cleanupDone.wait(timeout: .now() + 0.03) == .timedOut, "cleanup must wait for admitted send")
release.signal(); wait(cleanupDone)
let finalCalls = encoderCalls
concurrent.fill(); concurrent.sendOpusFrameFromDequeBuffer(); concurrent.startTapping()
require(encoderCalls == finalCalls && !concurrent.isRecording, "late queued work after drained cleanup cannot send")
require(destroyedEncoders == 2, "concurrent cleanup releases each encoder exactly once")
print("PASS microphone capture lifecycle: \(checks) checks")
