//
//  TouchPadGestureHandler.swift
//  VoidLink
//
//  Created by True砖家 on 2025/11/5.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//

import UIKit

@objc class TouchPadGestureHandler: NSObject {
    
    @objc public static var ctrlDown:Bool = false
    @objc public static var enablePinch:Bool = true
    @objc public static var ctrlDownForPinch:Bool = true
    @objc public static var enableHorizontalScroll:Bool = true
    @objc public static var scrollSensitivity:CGFloat = 1.0
    @objc public static var pinchSensitivity:CGFloat = 1.0
    @objc public static var displayLinkRate:CGFloat = 60

    private static weak var inputView: StreamView?
    private static var inputGeneration: UInt = 0

    private static var inertialScroller: InertialScroller = InertialScroller(decelerationRate: displayLinkRate > 110 ? 0.96 : 0.9, displayLinkRate: displayLinkRate, deliverOnMainThread: true) {
        guard let view = inputView else { return }
        view.performHostInput(generation: inputGeneration) {
            if ctrlDown { return }
            LiSendHighResScrollEvent(Int16(inertialScroller.vector.dy*7*scrollSensitivity))
            if enableHorizontalScroll { LiSendHighResHScrollEvent(Int16(-inertialScroller.vector.dx*7*scrollSensitivity)) }
        }
    }
    
    @objc public static func startInertialScroll(){
        guard let view = inputView, view.hostTouchInputAllowed,
              view.hostInputGeneration == inputGeneration else { return }
        inertialScroller.timer?.restart()
    }
    
    @objc public static func handleGesture(in view: UIView, with event: UIEvent) {
        guard let stream = view as? StreamView, stream.hostTouchInputAllowed else { return }
        inputView = stream
        inputGeneration = stream.hostInputGeneration
        inertialScroller.timer?.pause()

        let currentTouches = UITouchUtil.touches(in: view, from: event)
        guard currentTouches.count == 2 else { return }
        
        stream.performHostInput(generation: inputGeneration) {
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_LEFT)
            LiSendMouseButtonEvent(CChar(BUTTON_ACTION_RELEASE), BUTTON_RIGHT)

            guard let touch1 = currentTouches.first else { return }
            var mutable = Array(currentTouches)
            mutable.removeAll { $0 == touch1 }
            guard let touch2 = mutable.first else { return }

            let currentDistance = UITouchUtil.distance(between: touch1, and: touch2, in: view)
            let previousDistance = UITouchUtil.previousDistance(between: touch1, and: touch2, in: view)

            let midPointVector = UITouchUtil.midPointVector(between: touch1, and: touch2, in: view)
            let midPointDeltaX = midPointVector.dx
            let midPointDeltaY = midPointVector.dy

            let sendHorizontalScroll = abs(midPointDeltaX) > 1.2*abs(midPointDeltaY)

            inertialScroller.vector = CGVector(dx: sendHorizontalScroll ? midPointDeltaX : 0, dy: midPointDeltaY)

            let originalPinchDelta = currentDistance-previousDistance;
            let pinchDelta = enablePinch ? originalPinchDelta*7*pinchSensitivity : 0;
            LiSendHighResScrollEvent(Int16(pinchDelta + midPointDeltaY*7*scrollSensitivity))
            if enableHorizontalScroll, sendHorizontalScroll {LiSendHighResHScrollEvent(Int16(-midPointDeltaX*7*scrollSensitivity))}

            if enablePinch, ctrlDownForPinch {
                let midPointDelta = hypot(midPointDeltaX, midPointDeltaY)
                if abs(originalPinchDelta) > midPointDelta*1.3, midPointDelta < 2 {
                    LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_DOWN), 0)
                    ctrlDown = true
                } else {
                    LiSendKeyboardEvent(CommandManager.keyboardButtonMappings["CTRL"]!, CChar(KEY_ACTION_UP), 0)
                    ctrlDown = false
                }
            }
        }
    }
    @objc(cancelHostGesturesIn:)
    public static func cancelHostGestures(in view: StreamView) {
        guard inputView == nil || inputView === view else { return }
        inertialScroller.timer?.pause()
        inputView = nil
        inputGeneration = 0
        inertialScroller.vector = .zero
        if ctrlDown { LiSendKeyboardEvent(0x11, CChar(KEY_ACTION_UP), 0) }
        ctrlDown = false
    }
}
