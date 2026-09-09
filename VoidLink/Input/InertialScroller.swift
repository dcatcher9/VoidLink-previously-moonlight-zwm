//
//  InertialScroller.swift
//  VoidLink
//
//  Created by True砖家 on 2025/12/5.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//

class InertialScroller {
    public var decelerationRateX: CGFloat
    public var decelerationRateY: CGFloat
    private let deliverOnMainThread: Bool

    public lazy var timer: SafeTimer? = {
        SafeTimer(interval: 1/displayLinkRate) { [weak self] in
            guard let self = self else { return }
            if self.deliverOnMainThread {
                DispatchQueue.main.async { [weak self] in self?.tick() }
            } else {
                self.tick()
            }
        }
    }()
    
    public var vector: CGVector = .zero
    public var displayLinkRate: CGFloat
    public var timerSuspendThreshold: CGFloat = 0.06
    public var handler: (() -> Void)?
    
    init(decelerationRate: CGFloat = 0.93, displayLinkRate: CGFloat = 60,
         deliverOnMainThread: Bool = false, handler: (() -> Void)? = nil) {
        self.decelerationRateX = decelerationRate
        self.decelerationRateY = decelerationRate
        self.displayLinkRate = displayLinkRate
        self.handler = handler
        self.deliverOnMainThread = deliverOnMainThread
    }

    private func tick() {
        guard let handler else { return }
        vector.dx *= decelerationRateX
        vector.dy *= decelerationRateY
        if abs(vector.dx) < timerSuspendThreshold && abs(vector.dy) < timerSuspendThreshold {
            timer?.pause()
        }
        handler()
    }
}
