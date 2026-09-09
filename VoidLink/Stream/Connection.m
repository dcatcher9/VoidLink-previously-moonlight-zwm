//
//  Connection.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/19/14.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2025.9
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//

#import "Connection.h"
#import "Plot.h"
#import "Utils.h"
#import "DataManager.h"
#import "ConnectionLifecycle.h"
#import "SunlightPlatform.h"

#import <VideoToolbox/VideoToolbox.h>

#define SDL_MAIN_HANDLED
#import <SDL.h>

#include "Limelight.h"
#include "opus_multistream.h"
#include <stdatomic.h>
#include "VoidLink-Swift.h"

@implementation Connection {
    SERVER_INFORMATION _serverInfo;
    STREAM_CONFIGURATION _streamConfig;
    CONNECTION_LISTENER_CALLBACKS _clCallbacks;
    DECODER_RENDERER_CALLBACKS _drCallbacks;
    AUDIO_RENDERER_CALLBACKS _arCallbacks;
    char _hostString[256];
    char _appVersionString[32];
    char _gfeVersionString[32];
    char _rtspSessionUrl[128];
    ConnectionLifecycle *_lifecycle;
    VideoDecoderRenderer *_sessionRenderer;
    id<ConnectionCallbacks> _sessionCallbacks;
    BOOL _sessionFullColorRange;
    BOOL _session10BitCodec;
    BOOL _sessionAuthoredHaptics;
    float _sessionVolume;
}

static OpusMSDecoder* opusDecoder;
static id<ConnectionCallbacks> _callbacks;
static int lastFrameNumber;
static int activeVideoFormat;
static video_stats_t currentVideoStats;
static video_stats_t lastVideoStats;
static NSLock* videoStatsLock;
static uint64_t lastRenderedInterpolatedFrameCount;

static SDL_AudioDeviceID audioDevice;
static OPUS_MULTISTREAM_CONFIGURATION audioConfig;
static void* audioBuffer;
static float volume = 1.0;
static int audioFrameSize;
// Only the lifecycle owner resets this before entering C. Stop is observable
// even if SDL's output device has stalled and its queue can no longer drain.
static atomic_bool audioRendererStopping = true;

static bool useSystemAudioEngine;
static bool audioSessionInterrupted;
static AVAudioEngine *audioEngine;
static AVAudioPlayerNode *audioPlayerNode;
static AVAudioPCMBuffer *pcmBuffer;
static AVAudioFormat *audioFormat;

static bool muteInBackground;
static bool fullColorRange;
static bool request10BitCodec;
static bool useDualSenseAuthoredPCM = false;

static VideoDecoderRenderer* renderer;

static BandwidthTracker *bwTracker;

int DrDecoderSetup(int videoFormat, int width, int height, int redrawRate, void* context, int drFlags)
{
    [renderer setupWithVideoFormat:videoFormat width:width height:height frameRate:redrawRate fullRange:fullColorRange request10BitCodec:request10BitCodec];
    lastFrameNumber = 0;
    activeVideoFormat = videoFormat;
    Log(LOG_I, @"Active video format: 0x%x", activeVideoFormat);
    [videoStatsLock lock];
    currentVideoStats = (video_stats_t){0};
    lastVideoStats = (video_stats_t){0};
    [videoStatsLock unlock];
    lastRenderedInterpolatedFrameCount = [renderer renderedInterpolatedFrameCount];
    bwTracker = [[BandwidthTracker alloc] initWithWindowSeconds:10 bucketIntervalMs:250];
    return 0;
}

void DrCleanup(void)
{
    [ConnectionLifecycle cleanupActiveDecoder];
}

void DrStop(void)
{
    [renderer stop];
}

-(BandwidthTracker *) getBwTracker
{
    return bwTracker;
}

-(BOOL) getVideoStats:(video_stats_t*)stats
{
    if (stats == NULL) return NO;
    __block BOOL available = NO;
    [_lifecycle performIfCurrentOwner:^{
        // Keep both the completed window and its renderer in the same session.
        // Typed assignment retains/releases the struct's ARC-owned NSString.
        [videoStatsLock lock];
        if (lastVideoStats.endTime != 0) {
            *stats = lastVideoStats;
            available = YES;
        }
        [videoStatsLock unlock];
        if (available) [self->_sessionRenderer getAllStats:stats];
    }];
    return available;
}

-(NSString*) getActiveCodecName
{
    switch (activeVideoFormat)
    {
        case VIDEO_FORMAT_H264:
            return @"H.264";
        case VIDEO_FORMAT_H264_HIGH8_444:
            return @"H.264 YUV444";
        case VIDEO_FORMAT_H265:
            return @"HEVC";
        case VIDEO_FORMAT_H265_REXT8_444:
            return @"HEVC YUV444";
        case VIDEO_FORMAT_H265_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 HDR";
            }
            else {
                return @"HEVC Main 10 SDR";
            }
        case VIDEO_FORMAT_H265_REXT10_444:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"HEVC Main 10 YUV444 HDR";
            }
            else {
                return @"HEVC Main 10 YUV444 SDR";
            }
        case VIDEO_FORMAT_AV1_MAIN8:
            return @"AV1";
        case VIDEO_FORMAT_AV1_HIGH8_444:
            return @"AV1 YUV444";
        case VIDEO_FORMAT_AV1_MAIN10:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"AV1 10-bit HDR";
            }
            else {
                return @"AV1 10-bit SDR";
            }
        case VIDEO_FORMAT_AV1_HIGH10_444:
            if (LiGetCurrentHostDisplayHdrMode()) {
                return @"AV1 10-bit YUV444 HDR";
            }
            else {
                return @"AV1 10-bit YUV444 SDR";
            }
        default:
            return @"UNKNOWN";
    }
}

int DrSubmitDecodeUnit(PDECODE_UNIT decodeUnit)
{
    int offset = 0;
    int ret;
    CFTimeInterval decodeStartTime = CACurrentMediaTime();

    unsigned char* data = (unsigned char*) malloc(decodeUnit->fullLength);
    if (data == NULL) {
        // A frame was lost due to OOM condition
        return DR_NEED_IDR;
    }
    
    CFTimeInterval now = CACurrentMediaTime();
    if (!lastFrameNumber) {
        currentVideoStats.startTime = now;
        lastFrameNumber = decodeUnit->frameNumber;
    }
    else {
        // Flip stats roughly every second
        if (now - currentVideoStats.startTime >= 1.0f) {
            currentVideoStats.endTime = now;
            uint64_t renderedInterpolatedFrameCount = [renderer renderedInterpolatedFrameCount];
            currentVideoStats.interpolatedFrames = (int)(renderedInterpolatedFrameCount - lastRenderedInterpolatedFrameCount);
            lastRenderedInterpolatedFrameCount = renderedInterpolatedFrameCount;
            
            [videoStatsLock lock];
            lastVideoStats = currentVideoStats;
            [videoStatsLock unlock];
            
            currentVideoStats = (video_stats_t){0};
            currentVideoStats.startTime = now;
        }
        
        // Any frame number greater than m_LastFrameNumber + 1 represents a dropped frame
        int droppedFrames = decodeUnit->frameNumber - (lastFrameNumber + 1);
        if (droppedFrames > 0) {
            currentVideoStats.networkDroppedFrames += droppedFrames;
            currentVideoStats.totalFrames += droppedFrames;

            Log(LOG_W, @"Network dropped %d frame(s): %d - %d", droppedFrames, lastFrameNumber + 1, decodeUnit->frameNumber - 1);
        }
        lastFrameNumber = decodeUnit->frameNumber;
    }
    
    if (decodeUnit->frameHostProcessingLatency != 0) {
        if (currentVideoStats.minHostProcessingLatency == 0 || decodeUnit->frameHostProcessingLatency < currentVideoStats.minHostProcessingLatency) {
            currentVideoStats.minHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        if (decodeUnit->frameHostProcessingLatency > currentVideoStats.maxHostProcessingLatency) {
            currentVideoStats.maxHostProcessingLatency = decodeUnit->frameHostProcessingLatency;
        }
        
        currentVideoStats.framesWithHostProcessingLatency++;
        currentVideoStats.totalHostProcessingLatency += decodeUnit->frameHostProcessingLatency;
    }
    
    currentVideoStats.receivedFrames++;
    currentVideoStats.totalFrames++;

    [bwTracker addBytes:decodeUnit->fullLength];

    PLENTRY entry = decodeUnit->bufferList;
    while (entry != NULL) {
        // Submit parameter set NALUs directly since no copy is required by the decoder
        if (entry->bufferType != BUFFER_TYPE_PICDATA) {
            ret = [renderer submitDecodeBuffer:(unsigned char*)entry->data
                                        length:entry->length
                                    bufferType:entry->bufferType
                                    decodeUnit:decodeUnit
                               decodeStartTime:decodeStartTime];
            if (ret != DR_OK) {
                free(data);
                return ret;
            }
        }
        else {
            memcpy(&data[offset], entry->data, entry->length);
            offset += entry->length;
        }

        entry = entry->next;
    }

    // This function will take our picture data buffer
    return [renderer submitDecodeBuffer:data
                                 length:offset
                             bufferType:BUFFER_TYPE_PICDATA
                             decodeUnit:decodeUnit
                        decodeStartTime:decodeStartTime];
}

static void PrepareAudioPlayback(void) {
    atomic_store_explicit(&audioRendererStopping, false, memory_order_release);
}

static void ArStop(void) {
    atomic_store_explicit(&audioRendererStopping, true, memory_order_release);
}

static BOOL WaitForSdlAudioQueueCapacity(void) {
    // Device/buffer storage remains owned until common joins the audio callback.
    if (audioDevice == 0 || audioFrameSize <= 0) return NO;
    while (!atomic_load_explicit(&audioRendererStopping, memory_order_acquire)) {
        if (SDL_GetQueuedAudioSize(audioDevice) / audioFrameSize <= 10) {
            return !atomic_load_explicit(&audioRendererStopping, memory_order_acquire);
        }
        [NSThread sleepForTimeInterval:0.001f];
    }
    return NO;
}

int ArInit(int audioConfiguration, POPUS_MULTISTREAM_CONFIGURATION opusConfig, void* context, int flags)
{
    int err;
    SDL_AudioSpec want, have;
    
    if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
        Log(LOG_E, @"Failed to initialize audio subsystem: %s\n", SDL_GetError());
        return -1;
    }
        
    SDL_zero(want);
    want.freq = opusConfig->sampleRate;
    want.format = AUDIO_F32;
    want.channels = opusConfig->channelCount;
    want.samples = opusConfig->samplesPerFrame;

    audioDevice = SDL_OpenAudioDevice(NULL, 0, &want, &have, 0);
    if (audioDevice == 0) {
        Log(LOG_E, @"Failed to open audio device: %s\n", SDL_GetError());
        ArCleanup();
        return -1;
    }
    
    audioConfig = *opusConfig;
    audioFrameSize = opusConfig->samplesPerFrame * sizeof(float) * opusConfig->channelCount;
    audioBuffer = SDL_malloc(audioFrameSize);
    if (audioBuffer == NULL) {
        Log(LOG_E, @"Failed to allocate audio frame buffer");
        ArCleanup();
        return -1;
    }
    
    opusDecoder = opus_multistream_decoder_create(opusConfig->sampleRate,
                                                  opusConfig->channelCount,
                                                  opusConfig->streams,
                                                  opusConfig->coupledStreams,
                                                  opusConfig->mapping,
                                                  &err);
    if (opusDecoder == NULL) {
        Log(LOG_E, @"Failed to create Opus decoder");
        ArCleanup();
        return -1;
    }
    
    // Start playback
    SDL_PauseAudioDevice(audioDevice, 0);
    
    // [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];

    // return 0;
    
    // System audio engine initialization
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* tempSettings = [dataMan getSettings];
    bool useBluetoothD2P = tempSettings.useBuiltinMic || !tempSettings.redirectMic;
    AVAudioSessionCategoryOptions bluetoothAudioOption = useBluetoothD2P ? AVAudioSessionCategoryOptionAllowBluetoothA2DP : AVAudioSessionCategoryOptionAllowBluetooth;
    AVAudioSessionCategoryOptions volumeMixOption = tempSettings.duckOtherApps ? AVAudioSessionCategoryOptionDuckOthers : AVAudioSessionCategoryOptionMixWithOthers;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:tempSettings.redirectMic ? AVAudioSessionCategoryPlayAndRecord : AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:volumeMixOption|bluetoothAudioOption
                   error:nil];
    if(tempSettings.redirectMic) if(@available(iOS 13.0, *)) [session setAllowHapticsAndSystemSoundsDuringRecording:YES error:nil];
    [session setActive:YES error:nil];
    audioSessionInterrupted = false;

    AudioEngineInit(audioConfig.sampleRate, audioConfig.channelCount);

    return 0;
}

void ArCleanup(void)
{
    ArStop();
    if (opusDecoder != NULL) {
        opus_multistream_decoder_destroy(opusDecoder);
        opusDecoder = NULL;
    }
    
    if (audioDevice != 0) {
        SDL_CloseAudioDevice(audioDevice);
        audioDevice = 0;
    }
    
    if (audioBuffer != NULL) {
        SDL_free(audioBuffer);
        audioBuffer = NULL;
    }
    
    SDL_QuitSubSystem(SDL_INIT_AUDIO);
}

+ (void)setVolume:(float)linearVolume{
    if (linearVolume <= 0.0f) linearVolume = 0.0f;
    if (linearVolume >= 1.0f) linearVolume = 1.0f;
    CGFloat exponent = 2.5;
    volume = powf(linearVolume, exponent);
}

+ (void)setMuteInBackground:(bool)mute {
    muteInBackground = mute;
}

+ (void)setUseSystemAudioEngine:(bool)useSysAudioEngine{
    useSystemAudioEngine = useSysAudioEngine;
}

+ (bool)useDualSenseAuthoredPCM {
    return useDualSenseAuthoredPCM;
}

+ (void)setuseDualSenseAuthoredPCM:(bool)use {
    useDualSenseAuthoredPCM = use;
}

void AudioEngineInit(int sampleRate, int channelCount) {
    
    audioEngine = [[AVAudioEngine alloc] init];
    audioPlayerNode = [[AVAudioPlayerNode alloc] init];
    
    [audioEngine attachNode:audioPlayerNode];
        
    AVAudioChannelLayout *layout;
    
    switch (channelCount) {
        case 2:
        default:
            audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                           sampleRate:sampleRate
                                                             channels:channelCount
                                                          interleaved:NO];
            break;
        case 6:
            layout =
                [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_MPEG_5_1_A];
            audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                           sampleRate:sampleRate
                                                          interleaved:NO
                                                        channelLayout:layout];
            break;
        case 8:
            layout =
                [[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_MPEG_7_1_A];
            audioFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32
                                                           sampleRate:sampleRate
                                                          interleaved:NO
                                                        channelLayout:layout];
            break;
    }
    
    if(!audioFormat) return;
    
    AVAudioFormat *mixerFormat = [audioEngine.mainMixerNode outputFormatForBus:0];
    AVAudioFormat *outputFormat = [audioEngine.outputNode inputFormatForBus:0];
    NSLog(@"Mixer: %dch, Output: %dch",
          (int)mixerFormat.channelCount,
          (int)outputFormat.channelCount);
    
    [audioEngine connect:audioPlayerNode to:audioEngine.mainMixerNode format:audioFormat];
    
    NSError *err = nil;
    if (![audioEngine startAndReturnError:&err]) {
        NSLog(@"AudioEngine start error: %@", err);
    }
    
    [audioPlayerNode play];
}

+ (void)resetSysAudioPlayback {
    Connection *connection = [ConnectionLifecycle activeContext];
    if (!connection) return;
    [connection->_lifecycle performIfCurrentOwner:^{
        audioSessionInterrupted = true;
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0),
                   dispatch_get_main_queue(), ^{
        [connection->_lifecycle performIfCurrentOwner:^{
            @try {
                if (audioPlayerNode) {
                    [audioPlayerNode stop];
                }

                if (audioEngine) {
                    [audioEngine stop];
                    [audioEngine reset];

                    if (audioPlayerNode) {
                        [audioEngine disconnectNodeInput:audioPlayerNode];
                        [audioEngine disconnectNodeOutput:audioPlayerNode];
                        [audioEngine detachNode:audioPlayerNode];
                    }
                }

                audioEngine = nil;
                audioPlayerNode = nil;

                AudioEngineInit(audioConfig.sampleRate, audioConfig.channelCount);
            }
            @catch (NSException *exception) {
                NSLog(@"resetSysAudioPlayback failed: %@, reason: %@",
                      exception.name,
                      exception.reason);
            }
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [connection->_lifecycle performIfCurrentOwner:^{
                audioSessionInterrupted = false;
            }];
        });
    });
}


void ArDecodeAndPlaySample(char* sampleData, int sampleLength)
{
    if (atomic_load_explicit(&audioRendererStopping, memory_order_acquire)) return;
    if(appDidEnterBackgroundWithoutPip && muteInBackground) return;
    
    int decodeLen;
    
    // Don't queue if there's already more than 30 ms of audio data waiting
    // in Moonlight's audio queue.
    if (LiGetPendingAudioDuration() > 30) {
        return;
    }

    decodeLen = opus_multistream_decode_float(opusDecoder,
                                              (unsigned char*)sampleData,
                                              sampleLength,
                                              (float*)audioBuffer,
                                              audioConfig.samplesPerFrame,
                                              0);
    
    if (decodeLen > 0) {
        // Provide backpressure on the queue to ensure too many frames don't build up
        // in SDL's audio queue.
        
        float* fbuf = (float*)audioBuffer;
        
        if(useSystemAudioEngine){
            // 创建 AVAudioPCMBuffer
            AVAudioFrameCount frameCount = decodeLen;
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:audioFormat frameCapacity:frameCount];
            buffer.frameLength = frameCount;
            
            // 拷贝数据到 buffer
            for (int ch = 0; ch < audioConfig.channelCount; ch++) {
                float *dst = buffer.floatChannelData[ch];
                for (int i = 0; i < decodeLen; i++) {
                    dst[i] = fbuf[i * audioConfig.channelCount + ch] * volume; // 非交错数据
                }
            }
            // 播放
            if(!audioSessionInterrupted) [audioPlayerNode scheduleBuffer:buffer completionHandler:nil];
        }
        
        else{
            if(volume != 1.0){
                int totalSamples = decodeLen * audioConfig.channelCount;
                for (int i = 0; i < totalSamples; i++) {
                    fbuf[i] *= volume;
                }
            }
            
            if (!WaitForSdlAudioQueueCapacity()) return;
            
            if (SDL_QueueAudio(audioDevice,
                               audioBuffer,
                               sizeof(float) * decodeLen * audioConfig.channelCount) < 0) {
                Log(LOG_E, @"Failed to queue audio sample: %s\n", SDL_GetError());
            }
        }
        
    }
}

void ClStageStarting(int stage)
{
    // C resets its interrupt flag before this first callback. Cancellation that
    // arrived between the final caller check and that reset must be reasserted.
    if ([ConnectionLifecycle reassertActiveCancellation]) return;
    [_callbacks stageStarting:LiGetStageName(stage)];
}

void ClStageComplete(int stage)
{
    if ([ConnectionLifecycle reassertActiveCancellation]) return;
    [_callbacks stageComplete:LiGetStageName(stage)];
}

void ClStageFailed(int stage, int errorCode)
{
    if ([ConnectionLifecycle reassertActiveCancellation]) return;
    [_callbacks stageFailed:LiGetStageName(stage) withError:errorCode portTestFlags:LiGetPortFlagsFromStage(stage)];
}

void ClConnectionStarted(void)
{
    if ([ConnectionLifecycle reassertActiveCancellation]) return;
    [_callbacks connectionStarted];
}

void ClConnectionTerminatedWithSession(int errorCode, uint64_t sessionToken)
{
    __block Connection *connection;
    __block id<ConnectionCallbacks> callbacks;
    if (![ConnectionLifecycle claimTerminationForSessionToken:sessionToken capture:^(id context) {
        connection = context;
        callbacks = connection->_sessionCallbacks;
    }]) return;
    // Both references belong to the captured instance. A delayed detached C
    // callback must never read a successor's process-wide callback globals.
    [callbacks connectionTerminated:errorCode];
    [connection terminate];
}

void ClLogMessage(const char* format, ...)
{
    va_list va;
    va_start(va, format);
    vfprintf(stderr, format, va);
    va_end(va);
}

void ClRumble(unsigned short controllerNumber, unsigned short lowFreqMotor, unsigned short highFreqMotor)
{
    [_callbacks rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}

void ClConnectionStatusUpdate(int status)
{
    [_callbacks connectionStatusUpdate:status];
}

void ClSetHdrMode(bool enabled)
{
    [renderer setHdrMode:enabled];
    [_callbacks setHdrMode:enabled];
}

void ClRumbleTriggers(uint16_t controllerNumber, uint16_t leftTriggerMotor, uint16_t rightTriggerMotor)
{
    [_callbacks rumbleTriggers:controllerNumber leftTrigger:leftTriggerMotor rightTrigger:rightTriggerMotor];
}

void ClSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz)
{
    [_callbacks setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}

void ClSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b)
{
    [_callbacks setControllerLed:controllerNumber r:r g:g b:b];
}

void ClSetAdaptiveTriggers(uint16_t controllerNumber, uint8_t eventFlags,
                           uint8_t typeLeft, uint8_t typeRight,
                           uint8_t* left, uint8_t* right)
{
    [_callbacks setAdaptiveTriggers:controllerNumber
                         eventFlags:eventFlags
                           typeLeft:typeLeft
                          typeRight:typeRight
                               left:left
                              right:right];
}

void ClDs5HapticsPcm(const LI_DS5_HAPTICS_PCM_FRAME* frame)
{
    if (frame == NULL || frame->pcmData == NULL) {
        return;
    }

    // common-c owns pcmData only for this callback, so copy before returning.
    NSData* pcmData = [NSData dataWithBytes:frame->pcmData length:frame->pcmDataLength];
    [ControllerUtil enqueueDualSenseHapticsPCMWithControllerNumber:frame->controllerNumber
                                                             flags:frame->flags
                                                    sequenceNumber:frame->sequenceNumber
                                                presentationTimeUs:frame->presentationTimeUs
                                                        frameCount:frame->frameCount
                                                           pcmData:pcmData];
}

void ClDs5HapticsIrV2(const LI_DS5_HAPTICS_IR_FRAME_V2* frame)
{
    if (frame == NULL) {
        return;
    }

    [ControllerUtil enqueueDualSenseHapticsIRV2WithControllerNumber:frame->controllerNumber
                                                              flags:frame->flags
                                               sourceSequenceNumber:frame->sourceSequenceNumber
                                                        timestampUs:frame->timestampUs
                                                   sourceFrameCount:frame->sourceFrameCount
                                                            leftRms:frame->lanes[0].rmsAmplitude
                                                           leftPeak:frame->lanes[0].peakAmplitude
                                                      leftTransient:frame->lanes[0].transientStrength
                                                       leftLowRatio:frame->lanes[0].lowBandRatio
                                                    leftZeroCrossHz:frame->lanes[0].zeroCrossingRateHz
                                                           rightRms:frame->lanes[1].rmsAmplitude
                                                          rightPeak:frame->lanes[1].peakAmplitude
                                                     rightTransient:frame->lanes[1].transientStrength
                                                      rightLowRatio:frame->lanes[1].lowBandRatio
                                                   rightZeroCrossHz:frame->lanes[1].zeroCrossingRateHz
                                                    laneCorrelation:frame->laneCorrelation];
}

-(void) terminate
{
    [self cancel];
}

- (void)terminateWithCompletion:(dispatch_block_t)completion {
    [super cancel];
    [_lifecycle cancelWithCompletion:completion];
}

- (void)cancel {
    [super cancel];
    [_lifecycle cancel];
}

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    NSDictionary *info = notification.userInfo;
    AVAudioSessionInterruptionType type =
        [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    
    [_lifecycle performIfCurrentOwner:^{
        switch (type) {
            case AVAudioSessionInterruptionTypeBegan: {
                audioSessionInterrupted = true;
                [audioPlayerNode stop];
                [audioEngine stop];
                break;
            }
            case AVAudioSessionInterruptionTypeEnded: {
                AudioEngineInit(audioConfig.sampleRate, audioConfig.channelCount);
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [self->_lifecycle performIfCurrentOwner:^{
                        audioSessionInterrupted = false;
                    }];
                });
                break;
            }
            default:
                break;
        }
    }];
}

-(id) initWithConfig:(StreamConfiguration*)config renderer:(VideoDecoderRenderer*)myRenderer connectionCallbacks:(id<ConnectionCallbacks>)callbacks
{
    self = [super init];

    static dispatch_once_t statsOnce;
    dispatch_once(&statsOnce, ^{
        videoStatsLock = [[NSLock alloc] init];
    });
    _sessionRenderer = myRenderer;
    _sessionCallbacks = callbacks;
    _lifecycle = [[ConnectionLifecycle alloc] initWithCleanup:^{
        [myRenderer cleanup];
    } interrupt:^{
        // Wake a blocked audio callback before C stop attempts to join it.
        // The lifecycle invokes this only while this Connection owns C state.
        ArStop();
        LiInterruptConnection();
    }];
    
    NSString *rawAddress = [Utils addressPortStringToAddress:config.host];
    strncpy(_hostString,
            [rawAddress cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_hostString) - 1);
    strncpy(_appVersionString,
            [config.appVersion cStringUsingEncoding:NSUTF8StringEncoding],
            sizeof(_appVersionString) - 1);
    if (config.gfeVersion != nil) {
        strncpy(_gfeVersionString,
                [config.gfeVersion cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_gfeVersionString) - 1);
    }
    if (config.rtspSessionUrl != nil) {
        strncpy(_rtspSessionUrl,
                [config.rtspSessionUrl cStringUsingEncoding:NSUTF8StringEncoding],
                sizeof(_rtspSessionUrl) - 1);
    }

    LiInitializeServerInformation(&_serverInfo);
    _serverInfo.address = _hostString;
    _serverInfo.serverInfoAppVersion = _appVersionString;
    if (config.gfeVersion != nil) {
        _serverInfo.serverInfoGfeVersion = _gfeVersionString;
    }
    if (config.rtspSessionUrl != nil) {
        _serverInfo.rtspSessionUrl = _rtspSessionUrl;
    }
    _serverInfo.serverCodecModeSupport = config.serverCodecModeSupport;

    LiInitializeStreamConfiguration(&_streamConfig);
    _streamConfig.colorRange = config.fullColorRange ? 1 : 0;
    _sessionFullColorRange = config.fullColorRange;
    _session10BitCodec = config.enableHdr;
    _streamConfig.width = config.width;
    _streamConfig.height = config.height;
    _streamConfig.fps = config.frameRate;
    _streamConfig.bitrate = config.bitRate;
    _streamConfig.supportedVideoFormats = config.supportedVideoFormats;
    _streamConfig.audioConfiguration = config.audioConfiguration;
    _streamConfig.redirectMic = config.redirectMic && [MicHandler permissionGranted];
    _sessionVolume = config.localVolume;
    
    // Since we require iOS 12 or above, we're guaranteed to be running
    // on a 64-bit device with ARMv8 crypto instructions, so we don't
    // need to check for that here.
    _streamConfig.encryptionFlags = ENCFLG_ALL;
    
    if ([Utils isActiveNetworkVPN]) {
        // Force remote streaming mode when a VPN is connected
        _streamConfig.streamingRemotely = STREAM_CFG_REMOTE;
        _streamConfig.packetSize = 1024;
    }
    else {
        // Detect remote streaming automatically based on the IP address of the target
        _streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        _streamConfig.packetSize = 1392;
    }

    memcpy(_streamConfig.remoteInputAesKey, [config.riKey bytes], [config.riKey length]);
    memset(_streamConfig.remoteInputAesIv, 0, 16);
    int riKeyId = htonl(config.riKeyId);
    memcpy(_streamConfig.remoteInputAesIv, &riKeyId, sizeof(riKeyId));

    LiInitializeVideoCallbacks(&_drCallbacks);
    _drCallbacks.setup = DrDecoderSetup;
    _drCallbacks.cleanup = DrCleanup;
    _drCallbacks.stop = DrStop;
    // Use pull renderer for legacy and off frame pacing, direct submit for queue-based frame pacing
    TemporarySettings *presentation = config.presentationSettings ?: [[[DataManager alloc] init] getSettings];
    // Stereo is consumed by Metal, which waits for decoded frames in FrameQueue.
    // Legacy pull mode requires an AVSB display link to poll incoming frames.
    FramePacingMode framePacingMode = config.requiresMetalPresentation ? FramePacingModeQueue :
        presentation.framePacingMode.integerValue;
    if (framePacingMode == FramePacingModeLegacy || framePacingMode == FramePacingModeOff) {
        _drCallbacks.capabilities = CAPABILITY_PULL_RENDERER |
                                    CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC |
                                    CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1;
        _drCallbacks.submitDecodeUnit = NULL;
    } else {
        _drCallbacks.capabilities = CAPABILITY_DIRECT_SUBMIT |
                                    CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC |
                                    CAPABILITY_REFERENCE_FRAME_INVALIDATION_AV1;
        _drCallbacks.submitDecodeUnit = DrSubmitDecodeUnit;
    }

    LiInitializeAudioCallbacks(&_arCallbacks);
    _arCallbacks.init = ArInit;
    _arCallbacks.cleanup = ArCleanup;
    _arCallbacks.stop = ArStop;
    _arCallbacks.decodeAndPlaySample = ArDecodeAndPlaySample;
    _arCallbacks.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;

    LiInitializeConnectionCallbacks(&_clCallbacks);
    _clCallbacks.stageStarting = ClStageStarting;
    _clCallbacks.stageComplete = ClStageComplete;
    _clCallbacks.stageFailed = ClStageFailed;
    _clCallbacks.connectionStarted = ClConnectionStarted;
    _clCallbacks.connectionTerminatedWithSession = ClConnectionTerminatedWithSession;
    _clCallbacks.connectionSessionId = _lifecycle.sessionToken;
#ifdef DEBUG
    _clCallbacks.logMessage = ClLogMessage;
#endif
    _clCallbacks.rumble = ClRumble;
    _clCallbacks.connectionStatusUpdate = ClConnectionStatusUpdate;
    _clCallbacks.setHdrMode = ClSetHdrMode;
    _clCallbacks.rumbleTriggers = ClRumbleTriggers;
    _clCallbacks.setMotionEventState = ClSetMotionEventState;
    _clCallbacks.setControllerLED = ClSetControllerLED;
    _clCallbacks.setAdaptiveTriggers = ClSetAdaptiveTriggers;
    // The shared core negotiates compatible authored-haptics capabilities with
    // each host, including Sunshine 3D's nonconflicting SBS capability profile.
    _sessionAuthoredHaptics =
        ((config.emulatedControllerType == ControllerEmulationPsEnhancedHaptic
          && ControllerUtil.hasDualSenseController) || config.hapticEngine == RumbleDevice);
    if (_sessionAuthoredHaptics) {
        _clCallbacks.ds5HapticsPcm = ClDs5HapticsPcm;
        // _clCallbacks.ds5HapticsIrV2 = ClDs5HapticsIrV2;
    }

    return self;
}

-(void) main
{
    [_lifecycle runWithContext:self prepare:^{
        // Publish process-wide callback state only after the previous C session
        // has completely stopped. Merely constructing a successor changes none.
        PrepareAudioPlayback();
        [self->_sessionRenderer activateForStreaming];
        renderer = self->_sessionRenderer;
        _callbacks = self->_sessionCallbacks;
        fullColorRange = self->_sessionFullColorRange;
        request10BitCodec = self->_session10BitCodec;
        useDualSenseAuthoredPCM = self->_sessionAuthoredHaptics;
        [Connection setVolume:self->_sessionVolume];
        [[NSNotificationCenter defaultCenter] addObserver:self
               selector:@selector(handleAudioSessionInterruption:)
                   name:AVAudioSessionInterruptionNotification object:nil];
    } start:^int{
        return LiStartConnection(&self->_serverInfo,
                                 &self->_streamConfig,
                                 &self->_clCallbacks,
                                 &self->_drCallbacks,
                                 &self->_arCallbacks,
                                 NULL, 0,
                                 NULL, 0);
    } stop:^{
        LiStopConnection();
        [audioPlayerNode stop];
        [audioEngine stop];
        [ControllerUtil stopAllDualSenseHaptics];
    } teardown:^{
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        renderer = nil;
        _callbacks = nil;
        self->_sessionRenderer = nil;
        self->_sessionCallbacks = nil;
    }];
}

- (void)performMicrophoneInput:(dispatch_block_t)action {
    [_lifecycle performIfCurrentOwner:action];
}

@end
