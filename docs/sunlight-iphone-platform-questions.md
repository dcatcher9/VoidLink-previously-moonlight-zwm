# Apple technical questions: local screen conversion to wired glasses

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Draft only; not submitted. Prepared 2026-09-04.

## Intended user experience

A user connects a USB-C DisplayPort AR display directly to an iPhone. The phone supplies power. They explicitly start whole-display capture using the system picker. They then use another native app on the phone while our app converts permitted captured frames into stereoscopic side-by-side video and presents that processed video fullscreen on the external display. Processing stays on the phone, without a host PC or cloud service. We are prioritizing a solution on iOS 26 and separately evaluating iOS 27 APIs.

## Existing evidence and limits

On iPhone 17 Pro / iOS 26.6.1, the connected RayNeo display exposes 3840 x 1080 in its SBS mode. Foreground external presentation and physical eye separation work. App-owned external AVPlayerLayer, AVPlayerLayer without an app-owned external window, and an elevated external Metal window all revert to ordinary phone mirroring when our app backgrounds. AVPlayer's externalPlaybackActive remained false. These were output probes with no active screen-capture or PiP session. The Metal probe deliberately paused new submissions on deactivation and tested last-frame visibility.

A subsequent standalone test combined actual ReplayKit system capture, CPU-generated marked SBS frames, loopback delivery, separate phone and external AVSampleBufferDisplayLayer surfaces, and user-visible sample-buffer video PiP. With PiP active, fresh captured sequence numbers and enqueue counts advanced while the app and both scenes were backgrounded; both layers reported ready. The user nevertheless saw the ordinary phone screen split between the eyes, with PiP floating on the phone. Independent physical output therefore failed for this arrangement. This distinguishes continued capture/processing/submission from external visibility. Logs: `Build/replaykit-output-probe-device/console-first.log`; details in the probe record (retired diagnostic; source removed). Later retries included inactive/stalled capture, and a separately built idle-transport correction has no physical result yet.

No iOS 27 device result is claimed. Generic background GPU restrictions and continued-processing-task requirements are understood; we are asking about the supported combination of actual screen capture and external presentation, not unrelated keepalive techniques.

A later iOS 26 control presents native AVPlayerViewController modally using its defaults, with no app-owned external scene/window, a real-audio clip, and playback background configuration. Both 1920 x 1080 and 3840 x 1080 modes return to `mirroredScreen` on backgrounding; native readiness falls and `externalPlaybackActive` stays false. The iOS 26 preferred external participant setting did not change this in normal mode. Native PiP was enabled, but no startup callbacks occurred and the user reports no PiP button. This first build set `usesExternalPlaybackWhileExternalScreenIsActive=YES`. In an A/B build defaulting it to NO, the user confirms the native PiP button appears. After starting PiP and opening Settings, the user reports **Settings with a small floating video** in the glasses; independent fullscreen video output failed in normal 1920 x 1080 mode. The A/B activation has launcher logs only and no app-level telemetry, so this outcome relies on the physical observation. Details: native AVKit probe (retired diagnostic; source removed).

A separate long-form routing probe launched on 2026-09-04 at 23:49:05 PDT on the same iPhone 17 Pro / iOS 26.6.1, with the glasses directly connected by USB-C in normal 1920 x 1080 mode. It declared `AVInitialRouteSharingPolicy=LongFormVideo`, configured audio category `Playback`, mode `MoviePlayback`, route-sharing policy `LongFormVideo` (3), and options 0, then called `prepareRouteSelectionForPlaybackWithCompletionHandler:` before creating AVPlayer. At 23:49:27.299, the completion reported `shouldStart=1`, `selection=Local` (1), and audio output port type `HDMIOutput`. The probe followed the Local branch using native AVPlayerViewController, leaving `usesExternalPlaybackWhileExternalScreenIsActive` at its default NO. After backgrounding, logs showed the app and phone scene in background, PiP active, `externalPlaybackActive=0`, `mirroredScreen` present, and advancing playback time. The user confirmed the glasses showed **“settings with a floating window.”** This configuration therefore failed independent fullscreen output in the physical normal-mode test. The External branch was not forced or selected, and no SBS follow-up result is claimed. The diagnostic was stopped at 23:51:47. Source: long-form routing probe (retired diagnostic; source removed); log: `Build/longform-route-probe-device/console-first.log`.

## Immediate iOS 26 question

Is there a supported AVPlayer/AVKit configuration that keeps application-generated video fullscreen on a directly attached USB-C DisplayPort display when another native app becomes foreground? Does `usesExternalPlaybackWhileExternalScreenIsActive` affect native PiP eligibility on that route, and is simultaneous native PiP plus independent fullscreen external video supported? The `AVRoutingPlaybackArbiter` documentation specifically names AirPlay and Lightning adapters; does its preferred external participant have any effect on USB-C DisplayPort? We can provide the minimal standalone native-player reproduction and logs without live screen capture or ML.

For the long-form reproduction above, should `prepareRouteSelectionForPlaybackWithCompletionHandler:` classify a directly connected USB-C DisplayPort display as `External` when `AVInitialRouteSharingPolicy` and the audio session both specify `LongFormVideo`? Apple's long-form routing presentation discusses wired external screens, but this device returns `Local` while reporting `HDMIOutput`. Is that expected for USB-C DisplayPort, and does any supported configuration allow system-managed independent fullscreen video on that display to remain visible while another native app is foreground? If so, what route selection, audio-session settings, and player presentation are required? We can provide the standalone route-preparation reproduction and live console capture separately from the screen-capture prototype.

## Questions

1. With an active iOS 27 ScreenCaptureKit full-display stream and the `screen-capture` background mode, is continuous independent output through `UISceneAccessory.externalNonInteractive` supported while a different native iPhone app is foreground? If supported, what lifecycle/configuration is required to prevent the external output reverting to phone mirroring? Does a presented-but-backgrounded owner view controller remain eligible?

2. Does a legitimate active capture session permit offscreen Metal preprocessing or presentation work? If not, can that same session perform repeated Core ML predictions with the new Background Inference entitlement and `cpuAndNeuralEngine`, without a separate finite `BGContinuedProcessingTask`? Which runtime resource checks and distribution/signing conditions apply?

3. Is there a public system-managed video presentation path accepting application-generated `CMSampleBuffer`/`CVPixelBuffer` frames that continues fullscreen on a USB-C DisplayPort display while the phone foreground belongs to another app? In particular, is there a supported configuration using AVSampleBufferDisplayLayer, AVPlayer/AVPlayerViewController, or PiP? We need the processed fullscreen external image, not a floating PiP image within normal mirrored phone output.

4. Can iOS 27 `AVCaptureBroadcastVideoOutput` accept ScreenCaptureKit output or application-generated processed video using a public capture input or transformation API? Its current public API appears tied to camera capture formats and does not expose an enqueue operation. If camera-only, is a corresponding general DisplayPort video-output API available? Can it negotiate 3840 x 1080, and what foreground/background requirements apply?

5. What is the supported capture scope for nonprotected video in other apps, including their AVPlayer or PiP layers, while a wired external display is active? Are simultaneous capture and wired output subject to restrictions beyond content protection and system capture consent?

## Proposed minimal reproduction

Use the system picker for built-in-display capture. Apply a cheap CPU-generated diagnostic mark and duplicate each captured frame into two eye regions. Present to the physical external display using the new scene-accessory registration. Log capture/presentation frame IDs, scene state, app state, external mode, mirroredScreen, and renderer errors. Switch Home -> another nonprotected native app -> our app repeatedly and verify the physical glasses output.

Start without ML or direct Metal submission so external ownership can be measured separately. Then add a tiny Metal operation or a small Neural Engine model. Compare normal external output with supported video PiP as a distinct variant. Validate without an attached debugger, with redacted console output. A ten-minute pass is the initial proposed acceptance check; longer thermal and interruption testing follows separately.

## Primary documentation reviewed

- [Integrating AirPlay for long-form video apps](https://developer.apple.com/documentation/avfoundation/integrating-airplay-for-long-form-video-apps)
- [WWDC19: Advances in AirPlay 2](https://developer.apple.com/videos/play/wwdc2019/501/)
- [iOS ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
- [Connected-display scenes and accessories](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display)
- [Background Inference entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference)
- [Background GPU guidance](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background)
- [Direct capture broadcast output](https://developer.apple.com/documentation/avfoundation/avcapturebroadcastvideooutput)
