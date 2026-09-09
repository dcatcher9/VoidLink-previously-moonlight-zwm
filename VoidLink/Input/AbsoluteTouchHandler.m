//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved
//

#import "AbsoluteTouchHandler.h"
#import "VoidLink-Swift.h"

#include <Limelight.h>
#import "SunlightInputDispatch.h"

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.02f

// How long the double tap deadzone stays in effect between touch up and touch down
#define DOUBLE_TAP_DEAD_ZONE_DELAY 0.250f

// How far the finger can move before it can override the double tap deadzone
#define DOUBLE_TAP_DEAD_ZONE_DELTA 0.025f

static int mouseButtonForCursorMove = BUTTON_LEFT;

@implementation AbsoluteTouchHandler {
    __weak StreamView* streamView;
    
    bool multiTouchesDetected;
    bool passthroughGestures;
    
    NSTimer* longPressTimer;
    UITouch* lastTouchDown;
    CGPoint lastTouchDownLocation;
    UITouch* lastTouchUp;
    CGPoint lastTouchUpLocation;
    
    UITouch* capturedTouch;
    
    CGPoint touchBeganLocation;
    CGPoint movingTouchLocation;

    NSTimeInterval touchBeganTimeStamp;
    NSTimeInterval leftClickTimeThreshold;
    
    // upper screen edge check
    
    bool _delayMouseLeftClick;
    NSTimeInterval leftClickDelay;
    
    bool dragButtonDown;
    UInt8 currentTouchesCount;
    
    bool rightButtonClicked;
}

- (id)initWithView:(StreamView*)view andSettings:(TemporarySettings*)settings {
    self = [self init];
    self->streamView = view;
    
    multiTouchesDetected = false;
    passthroughGestures = settings.passthroughGestures;
    
    _delayMouseLeftClick = settings.delayLeftClick;
    // _delayMouseLeftClick = true;
    dragButtonDown = false;
    
    leftClickTimeThreshold = 0.1;
    
    // upper screen check
        
    leftClickDelay = ((CGFloat)settings.leftClickDelayMs.intValue)/1000;
    
    return self;
}

- (void)onLongPressStart:(NSTimer*)timer {
    // Raise the left click and start a right click
    if(multiTouchesDetected) return;
    
    if([self touchDidntMoveOnScreen:movingTouchLocation]){
        if(_delayMouseLeftClick){
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); });
            if(mouseButtonForCursorMove!=BUTTON_LEFT) SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, mouseButtonForCursorMove); });
        }
        SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT); });
        dispatch_time_t delayShort = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC));
        SunlightDispatchHostInputAfter(streamView, delayShort, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT); });
            self->rightButtonClicked = true;
        });
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    rightButtonClicked = false;

    if([UITouchUtil touchesIn:streamView from:event].count>=2){
        multiTouchesDetected = true;
        [longPressTimer invalidate];
        longPressTimer = nil;
        return;
    }
    
    

    // Ignore touch down events with more than one finger
    /*
    if ([[event allTouches] count] > 1) {
        return;
    }*/
    
    capturedTouch = [touches anyObject];
    CGPoint touchLocation = [capturedTouch locationInView:streamView];
    
    touchBeganTimeStamp = capturedTouch.timestamp;
    
    // Don't reposition for finger down events within the deadzone. This makes double-clicking easier.
    if (capturedTouch.timestamp - lastTouchUp.timestamp > DOUBLE_TAP_DEAD_ZONE_DELAY ||
        sqrt(pow((touchLocation.x / streamView.bounds.size.width) - (lastTouchUpLocation.x / streamView.bounds.size.width), 2) +
             pow((touchLocation.y / streamView.bounds.size.height) - (lastTouchUpLocation.y / streamView.bounds.size.height), 2)) > DOUBLE_TAP_DEAD_ZONE_DELTA) {
       if(!multiTouchesDetected) [streamView updateCursorLocation:touchLocation isMouse:NO];
    }
    
    // Press the left button down
    if(!_delayMouseLeftClick){
        SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT); }); //deprecated
    }
    
    // Start the long press timer
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                      target:self
                                                    selector:@selector(onLongPressStart:)
                                                    userInfo:nil
                                                     repeats:NO];
    
    lastTouchDown = capturedTouch;
    lastTouchDownLocation = touchLocation;
    movingTouchLocation = touchLocation;
    touchBeganLocation = touchLocation;
    currentTouchesCount = [UITouchUtil touchesIn:streamView from:event].count;
}

- (void)pauseLeftButtonDrag{
    if(dragButtonDown){
        SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); });
        dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC));
        SunlightDispatchHostInputAfter(streamView, delay, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, mouseButtonForCursorMove); });
        });
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    
    // Ignore touch move events with more than one finger
    /*
    if ([[event allTouches] count] > 1) {
        return;
    }*/
    
    NSSet* currentTouches = [UITouchUtil touchesIn:streamView from:event];
    currentTouchesCount = currentTouches.count;
    
    if(currentTouchesCount == 2){
        if(mouseButtonForCursorMove!=BUTTON_LEFT) SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, mouseButtonForCursorMove); });
        if(passthroughGestures) [TouchPadGestureHandler handleGestureIn:streamView with:event];
    }
     
    if(currentTouchesCount > 1) return;
    
    if(![currentTouches containsObject:capturedTouch]) return;
    
    movingTouchLocation = [capturedTouch locationInView:streamView];
    
    if (sqrt(pow((movingTouchLocation.x / streamView.bounds.size.width) - (lastTouchDownLocation.x / streamView.bounds.size.width), 2) +
             pow((movingTouchLocation.y / streamView.bounds.size.height) - (lastTouchDownLocation.y / streamView.bounds.size.height), 2)) > LONG_PRESS_ACTIVATION_DELTA) {
        // Moved too far since touch down. Cancel the long press timer.
        [longPressTimer invalidate];
        longPressTimer = nil;
        
        NSTimeInterval dragDelay = mouseButtonForCursorMove == BUTTON_LEFT ? leftClickTimeThreshold : 0;
        
        if(_delayMouseLeftClick && (CACurrentMediaTime()-touchBeganTimeStamp>dragDelay) && !dragButtonDown){
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, mouseButtonForCursorMove); });
            dragButtonDown = true;
        }
    }
    
   if(!rightButtonClicked) [streamView updateCursorLocation:movingTouchLocation isMouse:NO];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    [longPressTimer invalidate];
    longPressTimer = nil;
    
    if(TouchPadGestureHandler.ctrlDown) SunlightHostInput(streamView, ^int{ return LiSendKeyboardEvent(CommandManager.keyboardButtonMappings[@"CTRL"].shortValue,KEY_ACTION_UP,0); });
    
    
    if(multiTouchesDetected) {
        if([UITouchUtil touchesIn:streamView from:event].count == touches.count) multiTouchesDetected = false;
        return;
    };
    
    if([UITouchUtil touchesIn:streamView from:event].count == touches.count) multiTouchesDetected = false;
    
    // Only fire this logic if all touches have ended
    if ([touches containsObject:capturedTouch]) {
        // Cancel the long press timer
        [longPressTimer invalidate];
        longPressTimer = nil;
        
        // Remember this last touch for touch-down deadzoning
        CGPoint touchEndLocation = [capturedTouch locationInView:streamView];
        
        if(_delayMouseLeftClick){
            if(CACurrentMediaTime()-touchBeganTimeStamp<leftClickTimeThreshold) {
                if(CACurrentMediaTime()-lastTouchUp.timestamp<0.15
                   && ![self isAdjacentPoints:touchEndLocation from:lastTouchUpLocation tolerance:30]) [streamView updateCursorLocation:touchEndLocation isMouse:NO];
                if([self touchDidntMoveOnScreen:touchEndLocation] && !rightButtonClicked) [self sendShortMouseLeftButtonClickEvent];
            }
            else if(!rightButtonClicked){
                    SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); });
                    if(mouseButtonForCursorMove!=BUTTON_LEFT) SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, mouseButtonForCursorMove); });
                    SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT); });
            }
        }
        else{
            // Left button up on finger up
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); });

            // Raise right button too in case we triggered a long press gesture
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT); });
        }
                
        lastTouchUp = [touches anyObject];
        lastTouchUpLocation = [lastTouchUp locationInView:streamView];
        
        dragButtonDown = false;
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [self cancelHostTouches];
}

- (void)sendShortMouseLeftButtonClickEvent{
    dispatch_time_t delayShort = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(leftClickDelay * NSEC_PER_SEC));
    dispatch_time_t delayLong = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.03 * NSEC_PER_SEC));
    SunlightDispatchHostInputAfter(streamView, delayShort, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT); });
        SunlightDispatchHostInputAfter(streamView, delayLong, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT); });
            SunlightHostInput(streamView, ^int{ return LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT); });
        });
    });
}

- (bool)touchDidntMoveOnScreen:(CGPoint)touchLocation{
    return [self isAdjacentPoints:touchLocation from:touchBeganLocation tolerance:3];
}

- (BOOL)isAdjacentPoints:(CGPoint)currentPoint from:(CGPoint)originalPoint tolerance:(CGFloat)tolerance {
    bool isAdjacent = hypotf(originalPoint.x - currentPoint.x, originalPoint.y - currentPoint.y) <= hypot(tolerance, tolerance);
    return isAdjacent;
}

+ (int)mouseButtonForCursorMove {
    return mouseButtonForCursorMove;
}

+ (void)setMouseButtonForCursorMove:(int)button {
    mouseButtonForCursorMove = button;
}

- (void)cancelHostTouches {
    [longPressTimer invalidate];
    longPressTimer = nil;
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    if (mouseButtonForCursorMove != BUTTON_LEFT && mouseButtonForCursorMove != BUTTON_RIGHT)
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, mouseButtonForCursorMove);
    capturedTouch = nil;
    lastTouchDown = nil;
    lastTouchUp = nil;
    multiTouchesDetected = false;
    dragButtonDown = false;
    rightButtonClicked = false;
}

@end

