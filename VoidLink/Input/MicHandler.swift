//
//  MicHandler.swift
//  VoidLink
//
//  Created by True砖家 on 2025/9/2.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.

import AVFoundation
import Collections

@objc public protocol MicHandlerDelegate: AnyObject {
    @objc optional func micHandlerDidFinishPlayback(_ handler: MicHandler)
    @objc optional func micHandler(_ handler: MicHandler, didFailWithError error: NSError)
}

@objcMembers
public class MicHandler: NSObject {

    private var notificationTokens = [NSObjectProtocol]()
    private let engine = AVAudioEngine()
    private let captureMixer = AVAudioMixerNode()
    private let mutedMixer = AVAudioMixerNode()
    private var micInputFormat: AVAudioFormat!
    // Capture buffers and recording admission are serialized on bufferQueue.
    private var isRecording = false
    private var captureClosed = false
    private let lifecycleLock = NSRecursiveLock()
    private var isCleaned = false
    private var wantsRecording = false
    private var interruptionGeneration: UInt64 = 0
    private var engineConfigured = false
    private var inputTapInstalled = false
    private var captureMixerAttached = false
    private var mutedMixerAttached = false
    private let pendingCaptureChunks = DispatchSemaphore(value: 4)
    private let sendPacket: (Data) -> Void
    private var useBuiltinMic = false
    
    private var pcm16BufferDeque = Deque<Int16>()
    private let bufferQueue = DispatchQueue(label: "pcm.buffer.queue")
    private var timer: SafeTimer?
    private static var volume: Float = 1.0
    private static let volumeLock = NSLock()

    
    private var opusEncoder: OpaquePointer?
    
    

    public weak var delegate: MicHandlerDelegate?

    @objc public init(useBuiltinMic: Bool, sendPacket: @escaping (Data) -> Void) {
        self.sendPacket = sendPacket
        super.init()
        
        let token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        notificationTokens.append(token)

        self.useBuiltinMic = useBuiltinMic
        do {
            try configureSession()
            try configureEngine()
        } catch {
            notify(error)
        }
    }
    
    
    /* ----------- Mic permission -------------*/
    /// 请求麦克风权限
    /// - Parameter completion: 可选 block，如果为 nil 且未授权，会弹窗提示跳转系统设置
    @objc static func requestPermission(_ completion: ((Bool) -> Void)? = nil) {
        let permission = AVAudioSession.sharedInstance().recordPermission
        switch permission {
        case .granted:
            completion?(true)
        case .denied:
            if let callback = completion {
                callback(false)
            } else {
                showSettingsAlert()
            }
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        completion?(true)
                    } else {
                        if let callback = completion {
                            callback(false)
                        } else {
                            showSettingsAlert()
                        }
                    }
                }
            }
        @unknown default:
            if let callback = completion {
                callback(false)
            } else {
                showSettingsAlert()
            }
        }
    }
        
    /// 弹窗提示用户跳转系统设置（英文版）
    private static func showSettingsAlert() {
        guard let topVC = topViewController() else { return }
        let alert = UIAlertController(
            title:  LocalizationHelper.localizedString(forKey: "Microphone Permission") ,
            message: LocalizationHelper.localizedString(forKey: "micPermissionTip"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: LocalizationHelper.localizedString(forKey: "Go to Settings") , style: .default, handler: { _ in
            openSettings()
        }))
        topVC.present(alert, animated: true, completion: nil)
    }
    
    /// 打开系统设置
    @objc static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
    
    /// 检查麦克风权限状态（返回 Int，OC 可用）
    @objc static func permissionGranted() -> Bool {
        return AVAudioSession.sharedInstance().recordPermission == AVAudioSession.RecordPermission.granted
    }
    
    /// 获取最顶层 UIViewController
    private static func topViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
    /* ----------------------------------------*/

    
    /* ----------- Audio Session -------------*/
    
    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !isCleaned else { return }
        switch type {
        case .began:
            let shouldResume = wantsRecording
            stopTapping(stopEngine: true)
            wantsRecording = shouldResume
        case .ended:
            guard wantsRecording else { return }
            let generation = interruptionGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.lifecycleLock.lock()
                defer { self.lifecycleLock.unlock() }
                guard !self.isCleaned, self.wantsRecording,
                      generation == self.interruptionGeneration else { return }
                self.startTapping()
            }
        @unknown default:
            break
        }
    }

    private func configureOpus(sampleRate: Int32, channels: Int) throws {
        var err: Int32 = 0
        guard let enc = opus_encoder_create(sampleRate, Int32(channels), OPUS_APPLICATION_VOIP, &err), err == OPUS_OK else {
            throw NSError(domain: "Opus", code: Int(err), userInfo: nil)
        }

        opusEncoder = enc

        // Optional: But defaults are fine. Only change when needed:
        opus_encoder_ctl_wrapper(enc, Int32(OPUS_SET_BITRATE_REQUEST), opus_int32(64000))      // Set bitrate
        opus_encoder_ctl_wrapper(enc, Int32(OPUS_SET_COMPLEXITY_REQUEST), opus_int32(5))         // Set complexity
        opus_encoder_ctl_wrapper(enc, Int32(OPUS_SET_SIGNAL_REQUEST), OPUS_SIGNAL_VOICE)      // Set signal type
    }

    @objc public func startTapping() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !isCleaned else { return }
        do {
            if !engineConfigured { try configureEngine() }
            if !engine.isRunning { try engine.start() }
        } catch {
            notify(error)
            return
        }
        wantsRecording = true
        bufferQueue.sync { isRecording = true }
        timer?.start()
    }

    @objc public func stopTapping(stopEngine: Bool) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        wantsRecording = false
        interruptionGeneration &+= 1
        // Wait for any admitted packet to finish, then reject queued timer work.
        bufferQueue.sync {
            isRecording = false
            pcm16BufferDeque.removeAll()
        }
        timer?.pause()
        if stopEngine {
            engine.stop()
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Connection owns AVAudioSession configuration; this capture only selects its input.

        // 列出所有可用输入
        if self.useBuiltinMic, let inputs = session.availableInputs {
            for port in inputs {
                if port.portType == .builtInMic {
                    try session.setPreferredInput(port)
                    print("Set preferred input to built-in mic")
                    break
                }
            }
        }
    }
    
    private func sendOpusFrameFromDequeBuffer() {
        bufferQueue.sync {
            guard isRecording, !captureClosed else { return }
            if pcm16BufferDeque.count >= 960 {
                let chunk = Array(pcm16BufferDeque.prefix(960))
                var packet = [UInt8](repeating: 0, count: 4000)
                guard let enc = self.opusEncoder else {return}
                let outBytes = opus_encode(enc, chunk, 960, &packet, Int32(packet.count))
                if outBytes > 0 { sendPacket(Data(packet.prefix(Int(outBytes)))) }
                let removeCount = min(960, pcm16BufferDeque.count)
                if removeCount > 0 {
                    pcm16BufferDeque.removeFirst(removeCount)
                }
            }
        }
    }
    
    @objc public static func setVolume(_ linearVolume: Float) {
        let clamped = max(0.0, min(1.5, linearVolume))
        let exponent: Float = 1.7
        volumeLock.lock()
        MicHandler.volume = powf(clamped, exponent)
        volumeLock.unlock()
    }

    private static func captureVolume() -> Float {
        volumeLock.lock()
        defer { volumeLock.unlock() }
        return volume
    }
    
    private func configureEngine() throws {
        guard !isCleaned, !engineConfigured else { return }
        let input = engine.inputNode
        micInputFormat = input.inputFormat(forBus: 0)
        
        // The host microphone sink consumes 48 kHz mono. Let the audio engine
        // resample/downmix the hardware route before buffering 960-frame Opus
        // packets, including stereo built-in inputs and lower-rate Bluetooth.
        guard micInputFormat.sampleRate > 0, micInputFormat.channelCount > 0,
              let captureFormat = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) else {
            throw NSError(domain: "Microphone", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No usable microphone input format."])
        }
        try self.configureOpus(sampleRate: 48_000, channels: 1)
        engine.attach(captureMixer)
        captureMixerAttached = true
        engine.connect(input, to: captureMixer, format: micInputFormat)
        // A mixer tap supports format conversion. AVAudioSinkNode requires the
        // hardware sample rate, so it cannot provide this fixed-rate contract.
        engine.attach(mutedMixer)
        mutedMixerAttached = true
        mutedMixer.outputVolume = 0
        engine.connect(captureMixer, to: mutedMixer, format: captureFormat)
        engine.connect(mutedMixer, to: engine.mainMixerNode, format: captureFormat)
        captureMixer.installTap(onBus: 0, bufferSize: 960, format: captureFormat) { [weak self] buffer, _ in
            guard let self = self, let samples = buffer.floatChannelData?[0],
                  self.pendingCaptureChunks.wait(timeout: .now()) == .success else { return }
            // Bound both queued work and captured audio. The realtime tap never
            // waits for encoding or the network; congestion drops older audio.
            let sampleCount = min(Int(buffer.frameLength), 4_800)
            let offset = Int(buffer.frameLength) - sampleCount
            let gain = MicHandler.captureVolume()
            var chunk = [Int16](repeating: 0, count: sampleCount)
            for i in 0..<sampleCount {
                let clamped = max(min(samples[offset + i] * gain, 1.0), -1.0)
                chunk[i] = Int16(clamped * Float(Int16.max))
            }
            let capturedChunk = chunk
            self.bufferQueue.async { [weak self] in
                guard let self = self else { return }
                defer { self.pendingCaptureChunks.signal() }
                guard self.isRecording, !self.captureClosed else { return }
                let overflow = self.pcm16BufferDeque.count + capturedChunk.count - 4_800
                if overflow > 0 { self.pcm16BufferDeque.removeFirst(overflow) }
                self.pcm16BufferDeque.append(contentsOf: capturedChunk)
            }
        }
        inputTapInstalled = true
        timer = SafeTimer(interval: 0.02, delay: 0.05) { [weak self] in
            self?.sendOpusFrameFromDequeBuffer()
        }

        engineConfigured = true
        engine.prepare()
        try engine.start()
    }
    
    @objc public func clean() {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        guard !isCleaned else { return }
        isCleaned = true
        wantsRecording = false
        interruptionGeneration &+= 1
        bufferQueue.sync {
            captureClosed = true
            isRecording = false
            pcm16BufferDeque.removeAll()
        }
        // SafeTimer.clean drains an in-flight handler before returning.
        timer?.clean()
        timer = nil
        engine.stop()
        if inputTapInstalled { captureMixer.removeTap(onBus: 0) }
        if captureMixerAttached { engine.detach(captureMixer); captureMixerAttached = false }
        if mutedMixerAttached { engine.detach(mutedMixer); mutedMixerAttached = false }
        bufferQueue.sync {
            if let encoder = opusEncoder { opus_encoder_destroy(encoder) }
            opusEncoder = nil
        }
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
    }

    deinit { clean() }

    private func notify(_ error: Error) {
        delegate?.micHandler?(self, didFailWithError: error as NSError)
    }

}
