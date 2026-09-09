# Direct iPhone to AR glasses: 2D-to-3D decision and implementation gates

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Research date: 2026-09-04. This document includes the subsequent authorized live ReplayKit/PiP device test and its physical result, in addition to the initial research and earlier output probes.

## Required experience

- The glasses stay plugged **directly into the iPhone** for both DisplayPort video and power throughout use.
- The user operates other iPhone apps while Sunlight is minimized or hidden.
- Ideally Sunlight captures those apps, generates stereoscopic views on the phone, and presents full SBS to the glasses.
- A separate receiver/processor that the glasses plug into does not meet the direct-connection requirement.
- An in-app local-file video player was previously rejected; it is not a substitute for whole-phone capture.

## Decision

Product direction clarified after the platform comparison: **iPhone remains the primary target**. The travel product must work with one phone and directly connected glasses, with no PC, receiver, second phone, or mandatory network for conversion. Native games and video are equally important. Android's technical feasibility does not replace this iPhone objective.

The complete Sunlight-generated path is **not established on the tested iPhone 17 Pro / iOS 26.6.1 / RayNeo setup**. Three initial output experiments reverted to phone mirroring after Home. A subsequent live ReplayKit capture plus sample-buffer PiP experiment also failed independent physical output: the user saw the ordinary phone screen divided between the eyes, with floating PiP. Capture and CPU composition continued during a logged background interval, but did not establish visible independent output.

An iOS 27 feasibility prototype is justified by newly documented background capture support. It must prove external presentation and computation separately before full 2D-to-3D implementation. An OS upgrade alone is not a solution.

If the existing glasses must be retained, foreground Sunlight is the strongest implementation fallback, with an explicit content limitation: the source must be available inside Sunlight, such as the existing PC stream. It does not provide simultaneous use of arbitrary other iPhone apps.

If replacement glasses are acceptable, conversion performed inside compatible glasses is the strongest documented alternative architecture preserving direct iPhone cabling and ordinary cross-app phone use. It changes where conversion happens and does not produce a Sunlight-generated SBS stream on the cable.

## Existing evidence

| Experiment | Physical result | Interpretation |
| --- | --- | --- |
| Full-SBS calibration | Correct eye labels, geometry, eye swap, reconnect recovery and Stop were verified at 3840 x 1080. | The current foreground output and stereo packing foundation works. |
| AVPlayer in an external window | Foreground video worked; Home returned the glasses to phone mirroring. System external playback stayed inactive. | Attached views and an advancing playback clock do not prove visible independent output. |
| AVPlayer without an app-owned external window | Home again returned to ordinary phone mirroring. | Removing the external window did not enable a system-managed takeover. |
| Raised Metal output window | Foreground texture-to-SBS rendering succeeded; Home still reverted to mirroring. | Window level does not establish persistent external ownership. The test deliberately paused new GPU work on deactivation. |
| Live ReplayKit + CPU SBS + sample-buffer PiP | The user saw half the ordinary phone screen in each eye and PiP floating on the phone. | Fresh processed frames reached both layers during a background interval, but independent physical glasses output failed. |

Evidence and preserved console paths: [feasibility record](sunlight-iphone-screen-feasibility.md), [device validation](sunlight-ar-glasses-validation.md), AVPlayer probe (retired diagnostic; source removed), direct Metal probe (retired diagnostic; source removed).

The three original output probes implemented neither live capture nor a depth estimator. The later ReplayKit probe (retired diagnostic; source removed) implements live capture and CPU formatting, with no depth estimator. Identical images placed side by side validate packing, not inferred depth.

## What current Apple documentation supports

1. **Cross-app input:** ReplayKit broadcast extensions receive video/audio samples independently of the containing app. This is a candidate capture/sender architecture for iOS 26; it is not an external-window entitlement. [Apple ReplayKit security](https://support.apple.com/guide/security/replaykit-security-seca5fc039dd/web).
2. **New capture route:** Apple's iOS 27 ScreenCaptureKit sample explicitly supports full-display capture while the app is not frontmost using the `screen-capture` background mode. The installed iOS 26.5 SDK cannot implement this API. [Apple iOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).
3. **External presentation:** Apple's connected-display guide introduces `UISceneAccessory.externalNonInteractive` registration for iOS 27. It describes app-owned external scenes but does not explicitly guarantee their continued visibility while another iPhone app is foreground. [Apple connected-display guide](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display).
4. **Computation:** The general Metal background rule prevents new background GPU submissions. Background processing tasks have separate resource/entitlement requirements and completion/cancellation semantics. Neither establishes an indefinite custom display service. An active capture session's actual GPU behavior needs verification. [Metal background guidance](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background), [continued processing tasks](https://developer.apple.com/documentation/backgroundtasks/performing-long-running-tasks-on-ios-and-ipados).
5. **PiP:** Supported PiP content can continue in a floating system window. This does not document fullscreen ownership of USB-C glasses. Existing app PiP support is not evidence for the proposed capture/conversion/output chain. [Apple PiP content sources](https://developer.apple.com/documentation/avkit/avpictureinpicturecontroller/contentsource-swift.class).

## Bounded software investigation

Do not start by integrating a depth model. Prove the three required capabilities in a small diagnostic build, with separate counters and pass/fail evidence.

### iPhone-first research update: capture plus Neural Engine

The product requires local 2D-to-3D computation; it does not inherently require every stage to execute on the GPU. Apple's iOS 27 **Background Inference** entitlement is a material new candidate. Its documentation says the entitlement is required for any Neural Engine access while an app is backgrounded, including when it is not running a continued-processing task. This is broader than the finite-task-only interpretation previously considered for inference. It does not itself keep the process running, guarantee performance, or grant external-display ownership. Pair it with the legitimate ScreenCaptureKit background capture session, then verify runtime support and signing on the selected device. [Background Inference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference).

Candidate computation path: ScreenCaptureKit frame -> Core ML depth using `cpuAndNeuralEngine` -> CPU/Accelerate stereo warp and SBS packing -> `CVPixelBuffer` / video sample buffer -> AVFoundation presentation. The compute-unit setting permits CPU and Neural Engine while excluding GPU; it does not guarantee that all model operations execute on the Neural Engine. CPU composition is a fallback to benchmark at reduced resolution/cadence, not a claimed high-performance result. Existing Metal composition remains preferable if supported in the actual capture/display execution state. [Core ML compute units](https://developer.apple.com/documentation/coreml/mlcomputeunits/cpuandneuralengine).

The original three output probes ran without screen capture or active PiP. The subsequent iOS 26 ReplayKit/sample-buffer test added both: background receipt and enqueueing were observed with PiP active, while the physical result still failed independent output. An active capture session and continued process execution must not be confused with keeping the external scene visible. The iOS 27 lifecycle combination remains untested.

Use a small A/B matrix: (1) capture plus external sample-buffer presentation, (2) the same with supported, user-visible video PiP, and (3) if warranted, system player presentation under the same active-capture conditions. Verify actual output in the glasses and source/presented frame IDs. PiP success on the handset alone is a failure. Capture must target the built-in screen; investigate feedback from any PiP overlay explicitly. Run final lifecycle measurements without an attached debugger, while retaining live redacted console capture.

Another new API, `AVCaptureBroadcastVideoOutput`, explicitly describes direct USB-C DisplayPort output. Its public documentation currently connects it to supported camera capture formats, and `videoSettings` is read-only and reports camera/destination-negotiated output. No public input path for app-generated or ScreenCaptureKit sample buffers was established in this review. It is a precise question for Apple, not a ready replacement for the output window. [Broadcast output](https://developer.apple.com/documentation/avfoundation/avcapturebroadcastvideooutput), [negotiated settings](https://developer.apple.com/documentation/avfoundation/avcapturebroadcastvideooutput/videosettings).

The local toolchain was rechecked: Xcode 26.6 / iPhoneOS SDK 26.5. No iOS 27 probe was built or tested. Testing the newer API combination requires an iOS 27 SDK and an appropriate test phone. The current phone was not upgraded. Questions for Apple are drafted in [iPhone platform questions](sunlight-iphone-platform-questions.md).

### A. Current-OS ReplayKit/PiP control: failed physical output

The user authorized and performed the live capture/PiP test on iOS 26.6.1. It used real captured video, CPU-generated SBS labels and pixels, and separate phone/PiP and external layers. The user observed ordinary phone content split between the eyes and a floating PiP image on the phone. This fails the required independent, full-size SBS presentation while another app is foreground. No fake call or silent-audio keepalive was used.

The background capture/CPU processing evidence is useful, but this tested PiP arrangement is not a product solution. The separately built idle-transport fix addresses frame-delivery gaps, not the observed mirroring takeover. Further device experiments need a material change to the output mechanism or a supported lifecycle configuration; merely repeating these variants adds no evidence. See the probe record (retired diagnostic; source removed) for timing, limitations, and preserved console output.

### B. iOS 27 capture and output gate

Prerequisite: an appropriate SDK and an explicitly selected iOS 27 test device. Do not upgrade or restart the user's current phone as part of planning.

1. Use the system capture picker and `screen-capture` mode. Show increasing capture frame IDs while Home and a nonprotected test app are foreground.
2. Register the new external scene accessory. Present a cheap, changing SBS test pattern before adding inference. Verify physical output while switching apps.
3. Combine the two: display live captured frames with a diagnostic mark and frame ID in both eyes. Confirm the glasses show the marked output rather than ordinary mirrored phone content. Test for at least ten minutes and through multiple app switches. This duration is a proposed acceptance test, not an observed capability.
4. Probe computation in the same state: first a minimal Metal operation, and independently a small Core ML model configured for CPU and Neural Engine with the Background Inference entitlement. If Metal is unavailable, benchmark CPU stereo composition before selecting the ANE/CPU route. Integrate a full depth model only after external output and at least one viable computation route pass.

Use live, redacted console capture for every future launch; preserve the capture path. Record scene states, source frame IDs, presented frame IDs, output dimensions, command errors and physical observations. Device lock is a separate case from switching apps and needs its own expectation/test. System capture permission, content exclusions and interruption behavior remain part of acceptance.

**Stop condition:** if iOS replaces Sunlight's output with mirroring, or the required computation cannot continue, do not integrate the full model on that path. Keep iPhone-screen 3D marked unsupported for that configuration. Escalating window levels or adding unrelated background modes is not an implementation plan.

## Conversion implementation after the gate passes

```text
System-approved iPhone capture
  -> orientation/color normalization
  -> compact depth estimator
  -> temporal depth stabilization
  -> left/right view synthesis and disocclusion handling
  -> full-SBS compositor
  -> external coordinator with supported Metal or sample-buffer presentation
  -> direct USB-C video + power
  -> glasses in verified SBS mode
```

Reuse the current coordinator, external scene lifecycle handling, calibration geometry, eye swap and reconnect behavior. Keep source, processing and presentation as separate components so a failing capability does not look like a working capture mode.

Start with SDR and a low-cost depth model. Treat 30 source frames per second and 60 Hz display output as provisional profiling targets, not performance promises. Benchmark model size, compute backend, inference cadence, thermal behavior and battery drain on the actual phone. Hold only a small number of recent frames and discard stale work rather than accumulate latency. Keep RGB and depth frame association explicit; stabilize depth to reduce flicker and constrain disparity to preserve readable UI.

Validate inferred depth on moving objects, thin edges, scene cuts and text. Preserve portrait aspect ratio independently within each eye. Use 3840 x 1080 only for the currently verified RayNeo mode; future hardware must negotiate and validate its own output geometry. Protected or unavailable source content must be handled without promising universal app coverage.

## Alternatives preserving the direct cable

### Foreground Sunlight with existing glasses

Sunlight remains active and unlocked. A dark, minimal phone control surface accompanies dedicated SBS output to the glasses. Source frames come from content Sunlight already owns, initially its existing PC stream. Decode once, optionally run local depth conversion for a 2D stream, and present through the existing external route. A host-generated SBS stream can use passthrough. This remains a development path; physical PC streaming and full conversion performance are not established by calibration alone.

This preserves the direct cable and Sunlight-generated presentation, but cannot represent other native iPhone apps while they are foreground. Dimming the phone is different from locking it or backgrounding Sunlight. It is not a completion of the original cross-app requirement.

### Conversion inside replacement glasses

```text
Any ordinary iPhone app that supports external output
  -> iOS 2D mirroring
  -> direct USB-C video + power
  -> compatible glasses perform 2D-to-3D internally
  -> left/right eye displays
```

XREAL's official 1S page explicitly describes glasses-side conversion without source software. Its One Series REAL 3D tutorial describes real-time conversion of ordinary 2D input, configurable in the glasses' menu. Its connection guide lists direct iPhone 15/16/17 compatibility and power supplied by the connected device. Together, these document an alternative consistent with the direct-cable constraint. Confirm exact model, firmware and desired apps in a demonstration before a purchase; this project has not physically tested it. [XREAL 1S](https://www.xreal.com/1s), [REAL 3D guide](https://tutorials.xreal.com/docs/glasses/one-series/osd/real-3d/), [connection and power guide](https://tutorials.xreal.com/docs/glasses/one-series/first-use/connect-device/).

The iPhone sends ordinary 2D in this design. Sunlight does not generate SBS, and there is no established Sunlight control API for the glasses' internal conversion. Manufacturer guidance also notes weaker suitability for text and possible distortion, heat and frame drops at stronger effects. Assess image quality separately from connectivity.

Do not assume the current RayNeo glasses can do this. Their exact model/firmware remains unrecorded. RayNeo's Air 4 Pro FAQ describes conversion through its companion app; it does not establish conversion of arbitrary mirrored input inside the glasses. [RayNeo FAQ](https://www.rayneo.com/en-ca/products/rayneo-air-4-pro-ar-smart-glasses).

## Recommended next decision

Keep iPhone as the primary target. The user's latest priority is iOS 26: the native fullscreen AVKit control (retired diagnostic; source removed) has now been physically evaluated. Both hardware resolutions and the normal-mode iOS 26 routing-preference comparison report a return to mirroring on backgrounding. The original configuration did not start native PiP or expose its button. In a second build with the automatic external-video request disabled, the user confirms the PiP button appears, but after starting it the glasses show **Settings with a small floating video**. This fails independent fullscreen output. The second activation has no app-level console telemetry, and its physical comparison used normal 1920 x 1080 mode. Only a physical output pass warrants connecting live ReplayKit through an encoded local stream and measuring the combined pipeline.

The control failed, and a subsequent broader online search found a materially different public-API lead: Apple's long-form route preparation and sample's bare-player External branch. A standalone implementation (retired diagnostic; source removed) registers `AVInitialRouteSharingPolicy=LongFormVideo`, requests `prepareRouteSelectionForPlayback` before creating playback UI, and follows the actual Local/External result. The authorized device run at 23:49 PDT on 2026-09-04 returned `Local(1)` with a directly connected 1920 x 1080 display and `HDMIOutput` audio. Background playback continued with PiP, `external=0` and `mirrored=yes`; the user confirmed **Settings with a floating window** in the glasses. This long-form configuration therefore also failed independent fullscreen output. The system never selected its External branch, and no SBS or live-conversion follow-up is claimed. See [online clues and the floating-dot proposal](sunlight-ios26-online-clues.md) for exact APIs and evidence.

The floating-dot proposal does not itself supply a foreground scene or external ownership while real Home/other apps are interactive. A foreground content-host design changes supported source coverage; sideloaded app containers are a separate experimental architecture with significant compatibility/distribution limitations. With the long-form control also failing, the specific USB-C routing/lifecycle questions remain suitable for Apple, supported by the minimal reproduction and live logs. No verified iOS 26 implementation currently meets the full original requirement. The iOS 27 capture/output prototype remains a later investigation, not an assumed fix or an instruction to upgrade the current phone. Background capture plus inference and continuous independent external output have separate feasibility gates.
