//
//  MetalViewController.h
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import "FrameQueue.h"
#import "ImGuiRenderer.h"
#import "MetalVideoRenderer.h"
#import "MetalView.h"
#import "TemporarySettings.h"

@interface MetalViewController : UIViewController <MetalViewDelegate>

@property (nonatomic) CGRect bounds;
// May be configured before the view loads. Output is enabled only for a
// compatible external SBS canvas; the phone remains an interactive preview.
@property (atomic) SunlightStreamMode streamMode;
@property (atomic) BOOL stereoOutputEnabled;

- (nonnull instancetype)initWithFrame:(CGRect)bounds framerate:(float)framerate settings:(TemporarySettings* _Nonnull )settings metricsHandler:(MetricsHandler _Nonnull)metricsHandler;


- (void)pauseRendering;
- (void)resumeRendering;

// Idempotent teardown: stops the render thread, display link and renderer.
// Must be called when the stream session ends. Moving the view between display
// windows or changing controller appearance does not end the renderer session.
- (void)shutdown;

@end
