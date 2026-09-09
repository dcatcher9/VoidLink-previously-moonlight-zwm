//
//  MetalVideoRenderer.m
//
//  Created by Andy Grundman.
//  Ported to VoidLink by Acaki.
//  Copyright (c) 2025 Moonlight Stream. All rights reserved.
//

#import "MetalVideoRenderer.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>
#import "ImGuiPlots.h"
#import "SunlightStereoLayout.h"

#include <Limelight.h>

#define MAX_VIDEO_PLANES 3

struct CscParams {
    vector_float3 matrix[3];
    vector_float3 offsets;
};

struct ParamBuffer {
    struct CscParams cscParams;
};

static const struct CscParams k_CscParams_Bt601Lim = {
    // CSC Matrix
    {{1.1644f, 0.0f, 1.5960f}, {1.1644f, -0.3917f, -0.8129f}, {1.1644f, 2.0172f, 0.0f}},

    // Offsets
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt601Full = {
    {
        {1.0f, 0.0f, 1.4020f},
        {1.0f, -0.3441f, -0.7141f},
        {1.0f, 1.7720f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Lim = {
    {
        {1.1644f, 0.0f, 1.7927f},
        {1.1644f, -0.2132f, -0.5329f},
        {1.1644f, 2.1124f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt709Full = {
    {
        {1.0f, 0.0f, 1.5748f},
        {1.0f, -0.1873f, -0.4681f},
        {1.0f, 1.8556f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};
static const struct CscParams k_CscParams_Bt2020Lim = {
    {
        {1.1644f, 0.0f, 1.6781f},
        {1.1644f, -0.1874f, -0.6505f},
        {1.1644f, 2.1418f, 0.0f},
    },
    {16.0f / 255.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};

static const struct CscParams k_CscParams_Bt2020Lim_10bit = {
    {
        {1.1644f, 0.0f, 1.6781f},
        {1.1644f, -0.1874f, -0.6505f},
        {1.1644f, 2.1418f, 0.0f},
    },
    {64.0f / 1023.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};

static const struct CscParams k_CscParams_Bt2020Full = {
    {
        {1.0f, 0.0f, 1.4746f},
        {1.0f, -0.1646f, -0.5714f},
        {1.0f, 1.8814f, 0.0f},
    },
    {0.0f, 128.0f / 255.0f, 128.0f / 255.0f},
};

static const struct CscParams k_CscParams_Bt2020Full_10bit = {
    {
        {1.0f, 0.0f, 1.4746f},
        {1.0f, -0.1646f, -0.5714f},
        {1.0f, 1.8814f, 0.0f},
    },
    {0.0f, 512.0f / 1023.0f, 512.0f / 1023.0f},
};

struct Vertex {
    vector_float4 position;
    vector_float2 texCoord;
};

static const NSUInteger MaxFramesInFlight = 3;

// EDR tone-mapping is possible but it's unclear how
// best to tone-map Windows content
static BOOL useEDR = YES;

// Name of the colorspace most recently applied to the layer, for the stats overlay.
// Class-level because the stats path only has access to the class; guarded by a lock
// since it is written on the render thread and read from other threads, and multiple
// renderer instances can briefly overlap during a session switch.
static NSString *__currentColorSpace;

static void setCurrentColorSpaceName(NSString *name) {
    @synchronized ([MetalVideoRenderer class]) {
        __currentColorSpace = name;
    }
}

@interface MetalVideoRenderer ()
- (BOOL)submitFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer;
@end

@implementation MetalVideoRenderer {
    dispatch_queue_t _sq;
    id<MTLDevice> _device;
    float _framerate;
    id<ConnectionCallbacks> _callbacks;
    id<MTLCommandQueue> _commandQueue;
    id<MTLLibrary> _shaderLibrary;
    id<MTLRenderPipelineState> _videoPipelineState[MAX_VIDEO_PLANES];
    MTLPixelFormat _videoPipelinePixelFormat[MAX_VIDEO_PLANES];
    MTLRenderPassDescriptor *_renderPassDescriptor;
    CVMetalTextureCacheRef _textureCache;
    CVMetalTextureRef _cvMetalTextures[MAX_VIDEO_PLANES];

    float _currentEDRHeadroom;
    int _lastColorSpace;
    BOOL _lastFullRange;
    size_t _lastFrameWidth;
    size_t _lastFrameHeight;
    size_t _lastDrawableWidth;
    size_t _lastDrawableHeight;
    SunlightStreamMode _streamMode;
    BOOL _stereoOutputEnabled;
    SunlightStreamMode _lastStreamMode;
    BOOL _lastStereoOutputEnabled;
    NSUInteger _videoRegionCount;
    id<MTLBuffer> _CscParamsBuffer;
    id<MTLBuffer> _VideoVertexBuffer;
    
    CFStringRef _nonFullHdrColorSpace;
    MTLPixelFormat _nonFullHdrPixelFormat;

    // https://developer.apple.com/documentation/metal/synchronizing-cpu-and-gpu-work?language=objc
    dispatch_semaphore_t _inFlightSemaphore;
}

@synthesize inFlightSemaphore = _inFlightSemaphore;

- (instancetype)initWithMetalDevice:(id<MTLDevice>)device drawablePixelFormat:(MTLPixelFormat)drawablePixelFormat settings:(TemporarySettings* )currentSettings {
    self = [super init];
    if (self) {
        _sq = dispatch_queue_create("com.moonlight.MetalVideoRenderer",
                                    dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, 0));
        _averageGPUTime = (1.0f / currentSettings.framerate.floatValue) / 2;
        _device = device;
        _colorPixelFormat = drawablePixelFormat;
        _framerate = currentSettings.framerate.floatValue;
        _hdrEnabled = currentSettings.enableHdr;
        _commandQueue = [_device newCommandQueue];
        _currentEDRHeadroom = 1.0f;
        _lastColorSpace = -1;
        _lastFullRange = NO;
        
        // Initialize default CSC parameters buffer with BT.601 limited range
        struct ParamBuffer defaultParamBuffer;
        defaultParamBuffer.cscParams = k_CscParams_Bt601Lim;
        MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
        _CscParamsBuffer = [_device newBufferWithBytes:(void *)&defaultParamBuffer length:sizeof(defaultParamBuffer) options:bufferOptions];
        _lastPresented = 0.0f;
        _inFlightSemaphore = dispatch_semaphore_create(MaxFramesInFlight);
        _isStopping = NO;

        CFStringRef keys[1] = {kCVMetalTextureUsage};
        NSUInteger values[1] = {MTLTextureUsageShaderRead};
        CFDictionaryRef cacheAttributes = CFDictionaryCreate(kCFAllocatorDefault, (const void **)keys, (const void **)values, 1, NULL, NULL);
        CVMetalTextureCacheCreate(kCFAllocatorDefault, cacheAttributes, _device, NULL, &_textureCache);
        CFRelease(cacheAttributes);

        _renderPassDescriptor = [MTLRenderPassDescriptor new];
        _renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
        _renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0);
        _renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
        
        if (@available(iOS 14.0, *)) _nonFullHdrColorSpace = kCGColorSpaceITUR_2100_PQ;
        else _nonFullHdrColorSpace =  kCGColorSpaceITUR_2020;
        _nonFullHdrPixelFormat = MTLPixelFormatRGBA16Float;

        // Initialize texture array to NULL
        for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
            _cvMetalTextures[i] = NULL;
        }
    }
    return self;
}

- (void)dealloc {
    Log(LOG_I, @"MetalVideoRenderer dealloc");

    if (_commandQueue) {
        _commandQueue = nil;
    }
    if (_CscParamsBuffer) {
        _CscParamsBuffer = nil;
    }
    if (_VideoVertexBuffer) {
        _VideoVertexBuffer = nil;
    }
    
    // Clean up pipeline states
    for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
        if (_videoPipelineState[i]) {
            _videoPipelineState[i] = nil;
        }
        _videoPipelinePixelFormat[i] = MTLPixelFormatInvalid;
    }
    
    // Clean up any remaining Metal textures
    for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
        if (_cvMetalTextures[i]) {
            CFRelease(_cvMetalTextures[i]);
            _cvMetalTextures[i] = NULL;
        }
    }
    
    // Properly release texture cache
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    
    if (_renderPassDescriptor) {
        _renderPassDescriptor = nil;
    }

    // Do NOT clear __currentColorSpace here: a new renderer instance may already be
    // live (session switch) and have set its own value.
}

#if !TARGET_OS_TV
- (void)reportMaxEDRHeadroom {
    if (@available(iOS 16.0, *)) {
        CGFloat maxHeadroom = [[UIScreen mainScreen] potentialEDRHeadroom];
        if (maxHeadroom > 1.0) {
            LogOnce(LOG_I, @"Display supports EDR with a max headroom of %.1f", maxHeadroom);
        } else {
            LogOnce(LOG_I, @"Display does not support EDR");
        }
    } else {
        LogOnce(LOG_I, @"Display does not support EDR (iOS < 16.0)");
    }
}

- (void)pollCurrentEDRHeadroom {
    if (@available(iOS 16.0, *)) {
        CGFloat headroom = [[UIScreen mainScreen] currentEDRHeadroom];
        if (headroom != _currentEDRHeadroom) {
            Log(LOG_I, @"EDR headroom changed to %.1f", headroom);
            _currentEDRHeadroom = (float)headroom;
        }
    }
}

- (void)setInitialEDRMetadata {
}

- (void)applyEDRFromFrame:(Frame *)frame withColorspace:(int)colorspace toLayer:(CAMetalLayer *)layer {
    // Validate input parameters
    if (!frame || !layer) {
        Log(LOG_E, @"applyEDRFromFrame called with nil frame or layer");
        return;
    }
    
    [self reportMaxEDRHeadroom];
    [self setInitialEDRMetadata];

    CFDictionaryRef ext = [frame getFormatDescExtensions];
    CFStringRef frame_trc = ext ? CFDictionaryGetValue(ext, kCVImageBufferTransferFunctionKey) : nil;

    // These can only be changed on the main thread
    void (^updateLayerBlock)(void) = ^{
        if (@available(iOS 16.0, *)) {
            layer.wantsExtendedDynamicRangeContent = YES;
        }
        layer.pixelFormat = MTLPixelFormatRGBA16Float;

        CFStringRef name;
        switch (colorspace) {
            case COLORSPACE_REC_2020:
                if (@available(iOS 12.3, *)) {
                    name = kCGColorSpaceExtendedLinearITUR_2020;
                } else {
                    name = kCGColorSpaceExtendedLinearSRGB;
                }
                break;
            case COLORSPACE_REC_601:
                name = kCGColorSpaceExtendedLinearSRGB;
                break;
            case COLORSPACE_REC_709:
            default:
                name = kCGColorSpaceExtendedLinearSRGB;
                break;
        }

        CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(name);
        layer.colorspace = colorspace;
        CGColorSpaceRelease(colorspace);

        // CAEDRMetadata is only available on iOS 16.0+
        if (@available(iOS 16.0, tvOS 16.0, *)) {
            CVPixelBufferRef imageBuffer = frame.imageBuffer;
            if (imageBuffer) {
                CFDataRef masteringDisplayColorVolume = CVBufferCopyAttachment(imageBuffer, kCVImageBufferMasteringDisplayColorVolumeKey, nil);
                CFDataRef contentLightLevel = CVBufferCopyAttachment(imageBuffer, kCVImageBufferContentLightLevelInfoKey, nil);
                
                // Configure optical output scale (100.0f is standard for HDR10)
                const float opticalOutputScale = 100.0f;
                
                if (masteringDisplayColorVolume) {
                    // This tone-mapper does receive the host's max nits in MDCV when connecting to Windows,
                    // but I think using this for tone-mapping would break apps not using system calibration (most apps).
                    layer.EDRMetadata = [CAEDRMetadata HDR10MetadataWithDisplayInfo:(__bridge NSData *)masteringDisplayColorVolume
                                                                        contentInfo:contentLightLevel ? (__bridge NSData *)contentLightLevel : nil
                                                                 opticalOutputScale:opticalOutputScale];
                    CFRelease(masteringDisplayColorVolume);
                } else {
                    layer.EDRMetadata = [CAEDRMetadata HDR10MetadataWithMinLuminance:0.005f
                                                                        maxLuminance:1000.0f
                                                                  opticalOutputScale:opticalOutputScale];
                }
                
                // Clean up contentLightLevel if it was created
                if (contentLightLevel) {
                    CFRelease(contentLightLevel);
                }
                
                LogOnce(LOG_I, @"EDRMetadata set to colorspace %@, transfer function %@, %@", 
                       layer.colorspace, 
                       frame_trc ? (__bridge NSString *)frame_trc : @"<none>", 
                       layer.EDRMetadata);
            }
        } else {
            LogOnce(LOG_I, @"EDRMetadata not available on iOS < 16.0, colorspace %@, transfer function %@", 
                   layer.colorspace, 
                   frame_trc ? (__bridge NSString *)frame_trc : @"<none>");
        }
    };
    
    // Check if we're already on the main thread
    if ([NSThread isMainThread]) {
        updateLayerBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), updateLayerBlock);
    }
}
#endif

- (int)getFrameColorspaceAndRange:(Frame *)frame isFullRange:(BOOL *)isFullRange {
    CFDictionaryRef ext = [frame getFormatDescExtensions];

    // FQLog(LOG_I, @"%@", ext);

    *isFullRange = NO;

    // Return default values if format description extensions are not available, especially during resizing
    if (!ext) {
        return COLORSPACE_REC_601;
    }

    // Full Range boolean
    CFBooleanRef fullRangeRef = CFDictionaryGetValue(ext, kCMFormatDescriptionExtension_FullRangeVideo);
    if (fullRangeRef && CFGetTypeID(fullRangeRef) == CFBooleanGetTypeID()) {
        *isFullRange = CFBooleanGetValue(fullRangeRef);
    }

    // Colorspace
    CFStringRef frame_color = CFDictionaryGetValue(ext, kCVImageBufferColorPrimariesKey);
    if (frame_color && CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_709_2)) {
        return COLORSPACE_REC_709;
    } else if (frame_color && CFEqual(frame_color, kCVImageBufferColorPrimaries_ITU_R_2020)) {
        return COLORSPACE_REC_2020;
    }
    return COLORSPACE_REC_601;
}

- (BOOL)updateColorSpaceForFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer layerDidChange:(BOOL *)layerDidChange {
    BOOL fullRange = NO;
    int colorspace = [self getFrameColorspaceAndRange:frame isFullRange:&fullRange];
    if (colorspace != _lastColorSpace || fullRange != _lastFullRange) {
        // Clean up any pending textures before colorspace change
        for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
            if (_cvMetalTextures[i]) {
                CFRelease(_cvMetalTextures[i]);
                _cvMetalTextures[i] = NULL;
            }
        }
        // Flush texture cache to avoid memory accumulation
        if (_textureCache) {
            CVMetalTextureCacheFlush(_textureCache, 0);
        }
        CGColorSpaceRef newColorSpace = nil;
        MTLPixelFormat newPixelFormat = layer.pixelFormat;
        BOOL isHDR = NO;
        struct ParamBuffer paramBuffer;

        switch (colorspace) {
            case COLORSPACE_REC_709:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceITUR_709);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt709Full : k_CscParams_Bt709Lim);
                break;
            case COLORSPACE_REC_2020: {
                // Frames without a format description (e.g. produced for the AVSB
                // backend) must not crash us here
                CFDictionaryRef ext = [frame getFormatDescExtensions];
                CFStringRef frame_trc = ext ? CFDictionaryGetValue(ext, kCVImageBufferTransferFunctionKey) : NULL;
                if (frame_trc && CFEqual(frame_trc, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)) {
                    isHDR = YES;
                    newColorSpace = CGColorSpaceCreateWithName(_nonFullHdrColorSpace);
                    newPixelFormat = _nonFullHdrPixelFormat;
                } else {
                    // SDR 2020, I'm not sure it's possible to stream this though
                    newColorSpace = CGColorSpaceCreateWithName(_nonFullHdrColorSpace);
                    newPixelFormat = _nonFullHdrPixelFormat;
                }
                if (isHDR) {
                    paramBuffer.cscParams = (fullRange ? k_CscParams_Bt2020Full_10bit : k_CscParams_Bt2020Lim_10bit);
                } else {
                    paramBuffer.cscParams = (fullRange ? k_CscParams_Bt2020Full : k_CscParams_Bt2020Lim);
                }
                break;
            }
            case COLORSPACE_REC_601:
                newColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                newPixelFormat = MTLPixelFormatBGRA8Unorm;
                paramBuffer.cscParams = (fullRange ? k_CscParams_Bt601Full : k_CscParams_Bt601Lim);
        }

        // The CAMetalLayer retains the CGColorSpace
        if (newColorSpace || newPixelFormat != layer.pixelFormat) {
            *layerDidChange = YES;
            if (newColorSpace) {
                Log(LOG_I,
                    @"Frame colorspace %@ - changing MetalLayer's colorspace to %@",
                    colorspace == COLORSPACE_REC_709        ? @"REC_709"
                        : colorspace == COLORSPACE_REC_2020 ? @"REC_2020"
                        : colorspace == COLORSPACE_REC_601  ? @"REC_601 (sRGB)"
                                                            : [NSString stringWithFormat:@"Unknown: %d", colorspace],
                    newColorSpace);
            }
            if (newPixelFormat != layer.pixelFormat) {
                Log(LOG_I,
                    @"Frame pixel format %@ - changing MetalLayer's pixel format to %@",
                    layer.pixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : layer.pixelFormat == MTLPixelFormatBGRA10_XR ? @"MTLPixelFormatBGRA10_XR"
                                                                          : [NSString stringWithFormat:@"Unknown: %lu", layer.pixelFormat],
                    newPixelFormat == MTLPixelFormatBGRA8Unorm         ? @"MTLPixelFormatBGRA8Unorm"
                        : newPixelFormat == MTLPixelFormatBGRA10_XR ? @"MTLPixelFormatBGRA10_XR"
                                                                       : [NSString stringWithFormat:@"Unknown: %lu", (unsigned long)newPixelFormat]);
            }

#if TARGET_OS_TV
            // These can only be changed on the main thread
            dispatch_sync(dispatch_get_main_queue(), ^{
                layer.colorspace = newColorSpace;
                layer.pixelFormat = newPixelFormat;
            });
#else
            BOOL canUseEDR = NO;
            if (@available(iOS 16.0, tvOS 16.0, *)) {
                canUseEDR = useEDR && [CAEDRMetadata isAvailable] && _hdrEnabled && isHDR;
            }
            if (canUseEDR) {
                [self applyEDRFromFrame:frame withColorspace:colorspace toLayer:layer];
            } else {
                // These can only be changed on the main thread
                dispatch_sync(dispatch_get_main_queue(), ^{
                    if (@available(iOS 16.0, *)) {
                        if (isHDR) {
                            layer.wantsExtendedDynamicRangeContent = YES;
                        }
                    }
                    layer.colorspace = newColorSpace;
                    layer.pixelFormat = newPixelFormat;
                });
            }
#endif
            setCurrentColorSpaceName(newColorSpace ? CFBridgingRelease(CGColorSpaceCopyName(newColorSpace)) : nil);
            CGColorSpaceRelease(newColorSpace);
        }

        // Create the new colorspace parameter buffer for our fragment shader
        MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
        id<MTLBuffer> newCscParamsBuffer = [_device newBufferWithBytes:(void *)&paramBuffer length:sizeof(paramBuffer) options:bufferOptions];
        if (!newCscParamsBuffer) {
            Log(LOG_E, @"Failed to create CSC parameters buffer");
            return NO;
        }
        
        // Replace old buffer with new one
        _CscParamsBuffer = newCscParamsBuffer;

        _lastColorSpace = colorspace;
        _lastFullRange = fullRange;
    }
    
    
    // NSLog(@"layer.pixelFormat %lu", (unsigned long)layer.pixelFormat);
    

    return YES;
}

- (SunlightStreamMode)streamMode {
    @synchronized (self) {
        return _streamMode;
    }
}

- (void)setStreamMode:(SunlightStreamMode)streamMode {
    @synchronized (self) {
        _streamMode = streamMode;
    }
}

- (BOOL)stereoOutputEnabled {
    @synchronized (self) {
        return _stereoOutputEnabled;
    }
}

- (void)setStereoOutputEnabled:(BOOL)stereoOutputEnabled {
    @synchronized (self) {
        _stereoOutputEnabled = stereoOutputEnabled;
    }
}

- (BOOL)updateVideoRegionSizeForFrame:(Frame *)frame drawableSize:(CGSize)drawableSize {
    CGSize sourceSize = CGSizeMake(frame.width, frame.height);
    if (!isfinite(sourceSize.width) || !isfinite(sourceSize.height) ||
        !isfinite(drawableSize.width) || !isfinite(drawableSize.height) ||
        sourceSize.width < 1 || sourceSize.height < 1 ||
        drawableSize.width < 1 || drawableSize.height < 1) {
        return NO;
    }
    SunlightStreamMode streamMode;
    BOOL stereoOutput;
    @synchronized (self) {
        streamMode = _streamMode;
        stereoOutput = _stereoOutputEnabled;
    }

    // Check if anything has changed since the last vertex buffer upload
    if (_VideoVertexBuffer && sourceSize.width == _lastFrameWidth && sourceSize.height == _lastFrameHeight &&
        drawableSize.width == _lastDrawableWidth && drawableSize.height == _lastDrawableHeight &&
        streamMode == _lastStreamMode && stereoOutput == _lastStereoOutputEnabled) {
        return YES;
    }

    SunlightEyeRegion regions[2];
    NSUInteger regionCount = 1;
    BOOL rawStream = streamMode == SunlightStreamModeRawFullSBS || streamMode == SunlightStreamModeRawHalfSBS;
    if (stereoOutput && rawStream) {
        if (!SunlightRawPassthroughRegion(sourceSize, drawableSize, &regions[0])) return NO;
    } else if (stereoOutput && streamMode == SunlightStreamModeHost3D) {
        if (!SunlightStereoRegions(sourceSize, drawableSize, false, regions)) {
            return NO;
        }
        regionCount = 2;
    } else if (stereoOutput && streamMode == SunlightStreamMode2D) {
        if (!SunlightMonoRegions(sourceSize, drawableSize, regions)) return NO;
        regionCount = 2;
    } else if (streamMode == SunlightStreamModeHost3D) {
        if (sourceSize.width < 2) return NO;
        // Host 3D input retains the logical desktop's touch coordinates. Show
        // one full-aspect eye on the phone rather than the double-width pack.
        regions[0].destination = SunlightFitVideo(CGSizeMake(sourceSize.width / 2, sourceSize.height),
                                                 (CGRect){CGPointZero, drawableSize});
        CGFloat inset = 0.5 / sourceSize.width;
        regions[0].texture = CGRectMake(inset, 0, 0.5 - 2 * inset, 1);
    } else {
        // Raw SBS previews retain the complete packed desktop for absolute
        // touch mapping. The glasses route above requires exact passthrough.
        regions[0].destination = SunlightFitVideo(sourceSize, (CGRect){CGPointZero, drawableSize});
        regions[0].texture = CGRectMake(0, 0, 1, 1);
    }

    struct Vertex verts[8];
    for (NSUInteger eye = 0; eye < regionCount; eye++) {
        CGRect destination = regions[eye].destination;
        CGRect texture = regions[eye].texture;
        if (CGRectIsEmpty(destination)) return NO;
        float x0 = (float)(2 * CGRectGetMinX(destination) / drawableSize.width - 1);
        float x1 = (float)(2 * CGRectGetMaxX(destination) / drawableSize.width - 1);
        float y0 = (float)(1 - 2 * CGRectGetMaxY(destination) / drawableSize.height);
        float y1 = (float)(1 - 2 * CGRectGetMinY(destination) / drawableSize.height);
        float u0 = (float)CGRectGetMinX(texture), u1 = (float)CGRectGetMaxX(texture);
        float v0 = (float)CGRectGetMinY(texture), v1 = (float)CGRectGetMaxY(texture);
        NSUInteger offset = eye * 4;
        verts[offset]     = (struct Vertex){{x0, y0, 0, 1}, {u0, v1}};
        verts[offset + 1] = (struct Vertex){{x0, y1, 0, 1}, {u0, v0}};
        verts[offset + 2] = (struct Vertex){{x1, y0, 0, 1}, {u1, v1}};
        verts[offset + 3] = (struct Vertex){{x1, y1, 0, 1}, {u1, v0}};
    }

    MTLResourceOptions bufferOptions = MTLResourceStorageModeShared;
    id<MTLBuffer> newVideoVertexBuffer = [_device newBufferWithBytes:verts
                                                          length:sizeof(struct Vertex) * regionCount * 4
                                                         options:bufferOptions];
    if (!newVideoVertexBuffer) {
        Log(LOG_E, @"Failed to create video vertex buffer");
        return NO;
    }
    
    // Replace old buffer with new one
    _VideoVertexBuffer = newVideoVertexBuffer;
    _videoRegionCount = regionCount;

    _lastFrameWidth = sourceSize.width;
    _lastFrameHeight = sourceSize.height;
    _lastDrawableWidth = drawableSize.width;
    _lastDrawableHeight = drawableSize.height;
    _lastStreamMode = streamMode;
    _lastStereoOutputEnabled = stereoOutput;
    Log(LOG_I, @"Sunlight presentation: mode=%ld, decoded=%.0fx%.0f, output=%.0fx%.0f, stereoOutput=%d, regions=%lu",
        (long)streamMode, sourceSize.width, sourceSize.height, drawableSize.width, drawableSize.height,
        stereoOutput, (unsigned long)regionCount);

    return YES;
}

- (void)renderFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    // waitToRenderTo: handed this call one frame slot. A missing drawable during
    // window reparenting (or another pre-submission failure) must return it here.
    // Submitted work returns its slot from the GPU completion handler instead.
    if (![self submitFrame:frame toLayer:layer]) {
        dispatch_semaphore_signal(_inFlightSemaphore);
    }
}

- (BOOL)submitFrame:(Frame *)frame toLayer:(CAMetalLayer *)layer {
    @autoreleasepool {
        if (self.isStopping) {
            Log(LOG_I, @"[MetalVideoRenderer] isStopping");
            return NO;
        }

        // Handle changes to the frame's colorspace from last time we rendered
        BOOL layerDidChange = NO;
        if (![self updateColorSpaceForFrame:frame toLayer:layer layerDidChange:&layerDidChange]) {
            return NO;
        }

        FQLog(LOG_I, @"[%d / %.3f ms] Metal frame rendering", frame.frameNumber, frame.pts);

        CVPixelBufferRef imageBuffer = frame.imageBuffer;
        if (!imageBuffer) {
            Log(LOG_W, @"Frame imageBuffer is NULL, skipping render");
            return NO;
        }

        size_t planes = CVPixelBufferGetPlaneCount(imageBuffer);

        // For packed formats like BGRA, plane count is 0 but we treat it as 1 plane
        OSType pixelFormatType = CVPixelBufferGetPixelFormatType(imageBuffer);
        BOOL isPackedFormat = (pixelFormatType == kCVPixelFormatType_32BGRA ||
                               pixelFormatType == kCVPixelFormatType_32ARGB);
        if (isPackedFormat) {
            planes = 1;  // Treat packed formats as single plane
        }

        if (planes == 0 || planes > MAX_VIDEO_PLANES) {
            Log(LOG_E, @"Unsupported video plane count: %zu", planes);
            return NO;
        }
        size_t pipelineIndex = planes - 1;

        if (layerDidChange && frame.frameNumber > 1) {
            Log(LOG_I, @"Metal frame changed layer's colorspace and/or pixel format");
            // Invalidate all pipeline states since pixel format affects all of them
            for (int i = 0; i < MAX_VIDEO_PLANES; i++) {
                if (_videoPipelineState[i]) {
                    _videoPipelineState[i] = nil;
                }
                _videoPipelinePixelFormat[i] = MTLPixelFormatInvalid;
            }
        }

        // Get the next drawable early to get its pixel format
        id<CAMetalDrawable> drawable = [layer nextDrawable];
        if (!drawable) {
            Log(LOG_E, @"Failed to get nextDrawable");
            return NO;
        }

        // Use this drawable's actual pixels, including during screen mode changes.
        // Raw mismatches are withheld instead of scaling an incorrect eye layout.
        CGSize drawableSize = CGSizeMake(drawable.texture.width, drawable.texture.height);
        if (![self updateVideoRegionSizeForFrame:frame drawableSize:drawableSize]) return NO;

        // Get the framebuffer pixel format for pipeline creation
        MTLPixelFormat framebufferPixelFormat = drawable.texture.pixelFormat;

        // Check if we need to recreate pipeline state due to pixel format change
        if (!_videoPipelineState[pipelineIndex] || _videoPipelinePixelFormat[pipelineIndex] != framebufferPixelFormat) {
            if (_videoPipelineState[pipelineIndex]) {
                Log(LOG_I, @"Recreating pipeline state for %zu planes due to pixel format change: %lu -> %lu",
                    planes, (unsigned long)_videoPipelinePixelFormat[pipelineIndex], (unsigned long)framebufferPixelFormat);
            }
            MTLRenderPipelineDescriptor *pipelineDesc = [MTLRenderPipelineDescriptor new];
            id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

            // RGB shaders
            id<MTLFunction> vertexVsDraw = [defaultLibrary newFunctionWithName:@"vs_draw"];

            // linear shaders
            id<MTLFunction> yuvToLinear = [defaultLibrary newFunctionWithName:@"yuvToLinear"];

            // Determine if this is 10-bit based on the input CVPixelBuffer format, not the output framebuffer format
            // pixelFormatType is already declared above
            BOOL is10BitInput = (pixelFormatType == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange ||
                                 pixelFormatType == kCVPixelFormatType_444YpCbCr10BiPlanarFullRange ||
                                 pixelFormatType == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange ||
                                 pixelFormatType == kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange);

            NSString *fragmentShaderName;
            if (isPackedFormat) {
                // BGRA/ARGB packed formats don't need color space conversion
                fragmentShaderName = @"ps_draw_bgra";
            } else if (planes == 2) {
                fragmentShaderName = is10BitInput ? @"ps_draw_biplanar_10bit" : @"ps_draw_biplanar_8bit";
            } else {
                fragmentShaderName = is10BitInput ? @"ps_draw_triplanar_10bit" : @"ps_draw_triplanar_8bit";
            }

            Log(LOG_I, @"DEBUG: CVPixelBuffer format: 0x%X, planes: %zu, is10BitInput: %d, shader: %@, framebuffer format: %lu",
                pixelFormatType, planes, is10BitInput, fragmentShaderName, (unsigned long)framebufferPixelFormat);

            pipelineDesc.colorAttachments[0].pixelFormat = framebufferPixelFormat;
            pipelineDesc.vertexBuffers[0].mutability = MTLMutabilityImmutable;
            
            Log(LOG_I, @"Creating Metal pipeline state for %zu planes with pixel format %lu",
                planes, (unsigned long)framebufferPixelFormat);

            if (framebufferPixelFormat == MTLPixelFormatRGBA16Float) {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB -> linear float
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = yuvToLinear;
            } else {
                // 4:2:0 or 4:4:4 YUV -> BT.2020 RGB
                pipelineDesc.vertexFunction = vertexVsDraw;
                pipelineDesc.fragmentFunction = [defaultLibrary newFunctionWithName:fragmentShaderName];
            }

            NSError *error = nil;
            _videoPipelineState[pipelineIndex] = [_device newRenderPipelineStateWithDescriptor:pipelineDesc error:&error];
            if (!_videoPipelineState[pipelineIndex]) {
                Log(LOG_E, @"Failed to create video pipeline state: %@", error);
                return NO;
            }

            // Store the pixel format this pipeline state was created for
            _videoPipelinePixelFormat[pipelineIndex] = framebufferPixelFormat;
        }

        if (isPackedFormat) {
            // Handle packed BGRA format - iOS/macOS uses BGRA internally
            // Check if the pixel buffer has IOSurface backing
            CFTypeRef ioSurface = CVPixelBufferGetIOSurface(imageBuffer);
            if (!ioSurface) {
                Log(LOG_E, @"CVPixelBuffer does not have IOSurface backing - cannot create Metal texture");
                return NO;
            }

            CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                     _textureCache,
                                                                     imageBuffer,
                                                                     NULL,
                                                                     MTLPixelFormatBGRA8Unorm,
                                                                     CVPixelBufferGetWidth(imageBuffer),
                                                                     CVPixelBufferGetHeight(imageBuffer),
                                                                     0,  // planeIndex must be 0 for non-planar
                                                                     &_cvMetalTextures[0]);
            if (err != kCVReturnSuccess) {
                Log(LOG_E, @"CVMetalTextureCacheCreateTextureFromImage() failed for BGRA: %d", err);
                Log(LOG_E, @"PixelBuffer info - format: 0x%X, width: %zu, height: %zu, IOSurface: %p",
                    pixelFormatType,
                    CVPixelBufferGetWidth(imageBuffer),
                    CVPixelBufferGetHeight(imageBuffer),
                    ioSurface);
                return NO;
            } else {
                FQLog(LOG_I, @"Created BGRA texture: format=%lu, width=%zu, height=%zu",
                    (unsigned long)MTLPixelFormatBGRA8Unorm,
                    CVPixelBufferGetWidth(imageBuffer),
                    CVPixelBufferGetHeight(imageBuffer));
            }
        } else {
            // Handle planar YUV formats
            size_t actualPlanes = CVPixelBufferGetPlaneCount(imageBuffer);
            for (size_t i = 0; i < actualPlanes; i++) {
                MTLPixelFormat fmt;

                switch (CVPixelBufferGetPixelFormatType(imageBuffer)) {
                    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
                    case kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange:
                    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
                    case kCVPixelFormatType_444YpCbCr8BiPlanarFullRange:
                        fmt = (i == 0) ? MTLPixelFormatR8Unorm : MTLPixelFormatRG8Unorm;
                        break;

                    case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
                    case kCVPixelFormatType_444YpCbCr10BiPlanarFullRange:
                    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
                    case kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange:
                        fmt = (i == 0) ? MTLPixelFormatR16Unorm : MTLPixelFormatRG16Unorm;
                        break;

                    default:
                        Log(LOG_E, @"Unknown pixel format: 0x%08X", (unsigned int)CVPixelBufferGetPixelFormatType(imageBuffer));
                        return NO;
                }

                CVReturn err = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                         _textureCache,
                                                                         imageBuffer,
                                                                         NULL,
                                                                         fmt,
                                                                         CVPixelBufferGetWidthOfPlane(imageBuffer, i),
                                                                         CVPixelBufferGetHeightOfPlane(imageBuffer, i),
                                                                         i,
                                                                         &_cvMetalTextures[i]);
                if (err != kCVReturnSuccess) {
                    Log(LOG_E, @"CVMetalTextureCacheCreateTextureFromImage() failed: %d", err);
                    return NO;
                }
            }
        }

        _renderPassDescriptor.colorAttachments[0].texture = drawable.texture;

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:_renderPassDescriptor];
        if (!commandBuffer || !renderEncoder) {
            Log(LOG_E, @"Failed to create Metal command buffer or render encoder");
            return NO;
        }

        [renderEncoder setRenderPipelineState:_videoPipelineState[pipelineIndex]];

        if (isPackedFormat) {
            // For packed formats, we only have one texture
            [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(_cvMetalTextures[0]) atIndex:0];
        } else {
            // For planar formats, set multiple textures
            size_t actualPlanes = CVPixelBufferGetPlaneCount(imageBuffer);
            for (size_t i = 0; i < actualPlanes; i++) {
                [renderEncoder setFragmentTexture:CVMetalTextureGetTexture(_cvMetalTextures[i]) atIndex:i];
            }
        }

        [renderEncoder setVertexBuffer:_VideoVertexBuffer offset:0 atIndex:0];

        // Only set CSC params buffer for YUV formats that need color space conversion
        if (!isPackedFormat) {
            [renderEncoder setFragmentBuffer:_CscParamsBuffer offset:0 atIndex:0];
        }
#if !TARGET_OS_TV
        if (layer.pixelFormat == MTLPixelFormatRGBA16Float) {
            [self pollCurrentEDRHeadroom];
            [renderEncoder setFragmentBytes:&_currentEDRHeadroom length:sizeof(float) atIndex:1];
        }
#endif
        for (NSUInteger eye = 0; eye < _videoRegionCount; eye++) {
            [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:eye * 4 vertexCount:4];
        }
        [renderEncoder endEncoding];

        __block MetalVideoRenderer *strongSelf = self;
#if !TARGET_OS_SIMULATOR
        [drawable addPresentedHandler:^(id<MTLDrawable> d) {
            if (strongSelf.lastPresented > 0.0f) {
                CFTimeInterval frametime = d.presentedTime - strongSelf.lastPresented;
                [[ImGuiPlots sharedInstance] observeFloat:PLOT_FRAMETIME value:(frametime * 1000.0)];
            }
            strongSelf.lastPresented = d.presentedTime;
        }];
#endif

        // signal semaphore, compute GPU time average, and clear textures
        __block dispatch_semaphore_t block_semaphore = _inFlightSemaphore;
        __block size_t texturesToClean = isPackedFormat ? 1 : CVPixelBufferGetPlaneCount(imageBuffer);
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> cb) {
            dispatch_semaphore_signal(block_semaphore);

            const CFTimeInterval GPUTime = cb.GPUEndTime - cb.GPUStartTime;
            const double alpha = 0.25f;
            self.averageGPUTime = (GPUTime * alpha) + (self.averageGPUTime * (1.0 - alpha));

            // Free textures after completion of rendering
            for (size_t i = 0; i < texturesToClean; i++) {
                if (self->_cvMetalTextures[i]) {
                    CFRelease(self->_cvMetalTextures[i]);
                    self->_cvMetalTextures[i] = NULL;
                }
            }

            CVMetalTextureCacheFlush(self->_textureCache, 0);
        }];

#if TARGET_OS_SIMULATOR
        [commandBuffer presentDrawable:drawable];
#else
        // present for a minimum duration for best frame pacing
        [commandBuffer presentDrawable:drawable afterMinimumDuration:1.0f / _framerate];
#endif

        [commandBuffer commit];
        [commandBuffer waitUntilCompleted];
        return YES;
    }
}

- (BOOL)waitToRenderTo:(nonnull CAMetalLayer *)layer {
    // Wait to ensure only `MaxFramesInFlight` number of frames are getting processed
    // by any stage in the Metal pipeline (CPU, GPU, Metal, Drivers, etc.).
    if (self.isStopping) {
        return NO;
    }

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1f * NSEC_PER_SEC));  // 100ms
    if (dispatch_semaphore_wait(_inFlightSemaphore, timeout) != 0) {
        Log(LOG_W, @"Timed out waiting for in-flight frame buffer.");
        return NO;
    }

    return YES;
}

- (void)shutdown {
    self.isStopping = YES;
    // Shutdown runs on main while a frame can still be submitting or completing.
    // Never release the worker's texture refs or pipelines here. The active
    // wait/render pair and GPU callbacks retain this renderer until they finish;
    // dealloc then releases its resources without racing those users.
    Log(LOG_I, @"[MetalVideoRenderer] shutdown requested");
}

/// Responds to the drawable's size or orientation changes.
- (void)drawableResize:(CGSize)drawableSize {
    [self resize:drawableSize];
}

- (void)resize:(CGSize)size {
}

+ (NSString *)currentColorSpace {
    @synchronized ([MetalVideoRenderer class]) {
        return __currentColorSpace;
    }
}

@end
