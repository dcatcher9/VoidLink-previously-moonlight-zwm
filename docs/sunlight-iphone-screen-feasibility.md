# iPhone screen source and background output

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Date: 2026-09-04. This is a required product path, not a feature supplied by the local-file player.

## Required behavior

When glasses connect, the phone offers **PC** or **iPhone screen** as the source. PC mode receives Sunshine/Apollo content. iPhone-screen mode captures the phone's current screen, including other apps after Sunlight is minimized, and supplies frames to Sunlight's own external presentation surface. That surface must stay visible and update continuously so a later 2D-to-3D stage can generate left/right images before USB-C output.

The required pipeline is:

`Selected screen source → capture/decode → 2D-to-3D processing → SBS compositor → glasses`

The user explicitly rejected a local video player inside Sunlight; that implementation was removed. Native iOS screen mirroring also does not provide Sunlight with a programmable processing stage.

## Verified platform facts

- Current test phone: iPhone 17 Pro, iOS 26.6.1. Installed Xcode has iPhoneOS SDK 26.5.
- The local iOS SDK contains ReplayKit, including `RPBroadcastSampleHandler`, and does not contain ScreenCaptureKit. ReplayKit system broadcasts support continuous capture across the Home Screen and other apps; captured video/audio buffers arrive in an extension process. This capture capability does not require iOS 27. [Apple WWDC18, slide 11](https://devstreaming-cdn.apple.com/videos/wwdc/2018/601nz4m863hyf0/601/601_live_screen_broadcast_with_replaykit.pdf), [broadcast sample handler](https://developer.apple.com/documentation/replaykit/rpbroadcastsamplehandler).
- Apple's new ScreenCaptureKit iOS sample requires **iOS 27 or later**. It documents full-display capture with a system content-sharing picker and the `screen-capture` background mode to continue capture when the app is not frontmost. This is not an API available in the installed iOS 26.5 SDK. [Apple iOS capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios).
- Noninteractive external scenes present app-owned content. Their existence does not establish indefinite background execution or visibility while another app is frontmost. The user observed the readiness page disappearing when Sunlight was minimized. iOS 27 also changes external-scene registration to scene accessories. [Apple external-display guide](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display).
- Background GPU processing has separate runtime capability and entitlement requirements. It does not by itself establish permission for persistent external-screen presentation. The code now logs the supported-resource value without submitting a background task or requesting an entitlement. [Apple DTS guidance](https://developer.apple.com/forums/thread/794072).

## Engineering decision

Do not label the file player or OS mirroring as processed iPhone-screen mode. Do not treat adding `audio` or `screen-capture` to the existing app as a fix for its current iOS 26 runtime.

Before delivering the PC/iPhone source switch as a complete workflow, a physical feasibility test must establish all of the following together:

1. The user starts system screen capture through Apple's visible system control.
2. Capture continues while the phone shows another app.
3. Sunlight's custom external surface stays visible and can consume fresh frames in that state.
4. The processing stage can run within the target OS/device's execution and resource limits.
5. Returning to Sunlight, stopping capture, and reconnecting the glasses cleanly release or restore the source without stale frames or a recursive capture of the output.

On iOS 26, ReplayKit's broadcast extension is the candidate capture component; the background external presentation component is not established. On iOS 27, ScreenCaptureKit is a documented candidate for capture in the main app, but background external presentation and processing still need the same hardware proof. No OS upgrade or new background-compute entitlement has been applied. The later user-started ReplayKit diagnostic and its physical result are recorded below.

## Immediate output feasibility test

ReplayKit upload extensions have no documented API for acquiring an app-owned external window scene. A separate possible output mechanism is AVPlayer's system-managed external playback, with `usesExternalPlaybackWhileExternalScreenIsActive` and the legitimate audiovisual background playback policy. Its behavior on this direct USB-C connection must be measured. [Apple external playback](https://developer.apple.com/documentation/avfoundation/avplayer/usesexternalplaybackwhileexternalscreenisactive), [background policy](https://developer.apple.com/documentation/avfoundation/avplayer/audiovisualbackgroundplaybackpolicy).

An internal Debug-only probe has been built and installed to display a short moving pattern, log actual external playback and scene state, and ask the user to switch to another app. It is activated only by the explicit `--sunlight-background-output-probe` diagnostic launch argument; it adds no local-video playback feature. Release excludes the probe source and media. Only a successful background-output result warrants connecting ReplayKit's encoded live capture to this route. A moving pattern in the foreground or advancing playback time alone is insufficient: the glasses must visibly continue updating while another app is frontmost.

The signed Debug build passed and was installed over the local network at 10:06 on 2026-09-04. The post-build device query initially reported only the built-in LCD. Build, installation, and display-query records are in `Build/background-output-probe-device/`, with the final build in `build-final.log`.

At 10:09, after the user connected and enabled 3D, a device query confirmed TVOut at 3840 × 1080 and scale 1. The first diagnostic launch was rejected because the iPhone was locked, before the app started. That attempt is recorded in `Build/background-output-probe-device/console-20260904-1009.log`.

After the user unlocked the phone, the retry launched at 10:11:08 with redacted live capture in `Build/background-output-probe-device/console-20260904-retry.log`. Foreground logs show the requested view attached to the 3840 × 1080 output, `layerReady=1`, and advancing playback at rate 1. `externalPlayback` remains 0. At 10:11:30–31 both scenes entered background and `layerReady` changed to 0, while the playback clock continued advancing. Coordinator `presented=1` means that its view is still attached; it does not prove the screen remains visible. The user confirmed the glasses switched to mirroring the phone. This is a **failed background-output result for the app-owned-window probe**. Playback also paused at the next clip boundary. Runtime background GPU capability was reported as 0; no background task was requested. This probe contains no live screen capture.

One control comparison places the player layer in the phone window and declines to attach any external window, using the separate Debug-only `--sunlight-system-output-probe` launch argument. This isolates app window ownership from system external playback. Apple's documentation does not establish that window ownership caused the first failure; this is an experiment, not a proposed fix. The installed AVPlayer header and AVRouting documentation name AirPlay and Lightning adapters for external playback but do not establish USB-C DisplayPort support. [Apple external playback arbitration](https://developer.apple.com/documentation/avrouting/avroutingplaybackarbiter/preferredparticipantforexternalplayback), [scene migration guidance](https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle).

The control build succeeded, installed over Wi-Fi, and launched at 10:17:03. Artifacts: `Build/background-output-probe-device/build-system-control.log`, `install-system-control.log`, and redacted `console-system-control.log`. The launch log confirms no app-owned external window, a phone-owned player layer, observed mode 3840 × 1080, `mirroredScreen=phone`, and `externalPlayback=0`. The user saw the phone-controls panel in the glasses and confirmed that the glasses followed the phone again on Home/app switch. Both scenes entered background, the phone player layer's readiness fell to 0, and system external playback remained inactive. This is a **failed independent/background-output result for the system-only control**. Removing the app's external window did not enable video takeover on this connection.

## Current conclusion

The physical tests establish that neither tested custom-layer AVPlayer arrangement supplies the required persistent processed output on this iPhone 17 Pro / iOS 26.6.1 / direct USB-C RayNeo connection. The subsequent live ReplayKit plus sample-buffer PiP test also failed independent physical output. The native fullscreen AVKit investigation, including an automatic-external-playback-off control that restored native PiP, likewise ended with the user seeing mirrored Settings and a small floating video. These outcomes do not prove that every conceivable implementation or later OS version is incapable of it. There is currently no verified public-API architecture for the requested whole-phone capture → processing → glasses path while another app is frontmost. ReplayKit capture and CPU composition now have device evidence; independent external output remains unresolved.

Do not implement a source selector that promises working iPhone-screen 3D, or a broadcast extension presented as a complete solution, until a supported output mechanism is established. Do not substitute an in-app file player, treat native mirroring as programmable SBS output, or suggest an OS upgrade as a verified fix. Foreground readiness, SBS calibration, and the existing PC renderer routing remain available. No source switch, live capture, or 2D-to-3D implementation is claimed by either diagnostic.

## Windows architecture and requested direct-render experiment

The user asked to try the local Sunshine 3D host architecture after its implementation was verified in the read-only `Apollo-3D` checkout at `e827a6fc`. That host creates a SudoVDA 1920 × 1080 virtual **2D source desktop**, captures it, produces a 3840 × 1080 SBS GPU image, and presents it using a borderless topmost Win32 window on the distinct physical glasses display. The virtual desktop itself does not contain the generated SBS output. Source anchors: `ar_glasses.cpp:2658`, `display_vram.cpp:7143`, `display_vram.cpp:7220`, and `display_vram.cpp:7637` under `src/platform/windows/`.

The public iPhone mapping has these limits:

| Windows component | iPhone component and limitation |
| --- | --- |
| SudoVDA virtual desktop receiving application windows | An offscreen texture can hold an app's pixels, but it is not a system monitor that other apps can target. UIKit provides existing hardware screens; apps do not create them. |
| Display driver | DriverKit supports macOS and M-series iPadOS devices; it is not an iPhone driver installation path. |
| Direct SBS GPU processing | Metal can render to offscreen textures and an external drawable while execution is permitted. |
| Always-on-top presenter | A separate external `UIWindow` can have a higher level than Sunlight's other windows, but remains attached to an iOS-managed scene. No background-visibility exemption is documented. |

Primary references: [UIScreen](https://developer.apple.com/documentation/uikit/uiscreen), [DriverKit](https://developer.apple.com/documentation/driverkit), [window levels](https://developer.apple.com/documentation/uikit/uiwindow/windowlevel), [background scenes](https://developer.apple.com/documentation/uikit/uiscene/activationstate-swift.enum/background), and [Metal background handling](https://developer.apple.com/documentation/metal/preparing-your-metal-app-to-run-in-the-background).

A separate Debug-only `--sunlight-direct-output-probe` implements the user's requested rendering experiment. It uses a synthetic 1920 × 1080 offscreen GPU canvas, packs identical source images into two 1920 × 1080 eye regions, and presents directly in a separate raised-level external window. It contains no AVPlayer, file playback, screen capture, or depth estimator. This is a direct-rendering experiment, not a claim to have created a system virtual monitor or mirrored another app.

On deactivation it must stop submitting new GPU work, retain the last rendered frame for the visibility observation, and log that pause explicitly. If the last frame disappears when another app becomes frontmost, the raised window has not supplied persistent output. A retained frame would establish visibility only; continuous background capture/processing would remain a separate unresolved requirement. Do not use denied GPU submissions, artificial audio, or forced foreground activation to evade lifecycle limits.

The signed direct-output build passed and was installed over Wi-Fi at 10:34. Artifacts are `Build/direct-output-probe-device/build-final.log` and `install.log`. The initial launch was rejected because the phone locked before it began; the redacted attempt is `Build/direct-output-probe-device/console.log`.

After the user unlocked, the retry launched at 10:36:06 with redacted capture in `Build/direct-output-probe-device/console-retry.log`. Runtime shader compilation succeeded. The raised window reports level 2001; at 6.2 seconds, 87 commands were submitted and completed, with 86 drawable presentation callbacks and no missing drawables. The source is 1920 × 1080 and the drawable is 3840 × 1080. This validates foreground GPU execution and presentation submission. The user then reported that the glasses followed the phone to the desktop on Home. The raised-window direct-render path therefore **failed persistent independent output**, as the AVPlayer arrangements did.

No background GPU commands were needed to establish that result: the prototype deliberately paused new submissions on deactivation and asked whether the last rendered image remained visible. Raising the window and using an offscreen texture did not keep the image over native mirroring. The experiment does not supply live phone capture or 2D-to-3D depth processing. It remains a reusable foreground rendering diagnostic.

The run exposed a small foreground recovery issue in the diagnostic: after returning, iOS can leave the noninteractive external scene foregroundInactive while the phone scene is active. The source now permits that visible foreground state while continuing to pause background/unattached output. Timeout wording also now states that cleanup of a retained frame waits for execution if the app is suspended. These changes do not alter the negative Home-transition finding.

## Live ReplayKit plus PiP result

A standalone diagnostic, Sunlight Capture Test (retired diagnostic; source removed), was built, signed, installed, and launched with live redacted console capture on 2026-09-04 at 21:22:50. Its broadcast extension performs CPU orientation/resize and duplicates captured pixels into 1280 x 360 SBS, baking in L/R labels and frame IDs. Frames travel through loopback to separate phone/PiP and external AVSampleBufferDisplayLayer surfaces. The glasses negotiated 3840 x 1080. No AI model, remote receiver, saved captured frames, or direct Metal submissions were used.

With PiP off, foreground recovery after switching apps produced interruption errors on both video layers. With PiP on, at 21:25:40–54, captured sequence IDs 324–344 and both enqueue counts advanced while the app and both scenes were backgrounded. Layer readiness stayed true. This provides evidence of background capture, CPU composition, delivery, and presentation submission during that interval, but no sustained-performance guarantee.

The user subsequently reported seeing the ordinary iPhone screen cut in half between the eyes, with PiP floating on the phone screen. This is a failed independent/fullscreen glasses-output result, consistent with ordinary mirroring being interpreted by the glasses as SBS. Layer readiness and enqueue counts did not establish physical visibility. Later retries included inactive/stalled capture and must not be treated as additional successful capture evidence.

Preserved log: `Build/replaykit-output-probe-device/console-first.log`. The receiver was stopped at 21:29:22, capture and PiP were later inactive, and the app terminated normally. A separately built transport idle-timeout correction has not been physically tested and does not itself address external-display ownership.

## iOS 26 native fullscreen AVKit control

The user requested checking iOS 26 before pursuing iOS 27. One material presentation difference remains: the previous system-only test used a custom AVPlayerLayer; it did not present native AVPlayerViewController. Apple's guidance recommends its default modal fullscreen presentation, allowing AVKit to manage presentation and display behavior. This does not establish a separate background-output permission. [Apple AVKit guidance](https://developer.apple.com/videos/play/wwdc2019/503/).

A separate native AVKit diagnostic (retired diagnostic; source removed) has been built for iOS 26 with no app-owned external scene or window. It compares normal 2D and SBS clips, native PiP on/off, and the iOS 26 routing preference. The routing documentation names AirPlay and Lightning adapters; USB-C support is a hypothesis to test. `appliesPreferredDisplayCriteriaAutomatically` is unavailable on iOS in the installed SDK and is not part of this implementation.

The native app launched with live logs at 21:50:26. SBS at 3840 x 1080, normal video at 1920 x 1080, and normal video with iOS 26 routing preference enabled all reported a return to mirroring on backgrounding; native controller readiness subsequently fell. `externalPlayback` stayed zero. No native PiP-start callbacks occurred despite PiP being enabled. When asked to start it manually, the user confirmed there was no PiP button. That establishes a missing native control in this configuration, not a universal lack of iPhone PiP support. Detailed timestamps are in the diagnostic README; redacted capture is `Build/native-avkit-output-probe-device/console-first.log`.

A second build isolates `usesExternalPlaybackWhileExternalScreenIsActive`, allowing it to be disabled while `allowsExternalPlayback` remains enabled. The user confirmed that the native PiP button appears with this build's default configuration. After starting PiP and opening Settings, the user reported **Settings with a small floating video** in the glasses. Independent fullscreen output therefore failed in this normal 1920 x 1080 comparison. The activation's console pipeline captured launcher messages only, so no app-level runtime or PiP-start telemetry is claimed for this comparison; the physical report establishes the output failure. Restoring the PiP control is an availability finding, not a solution to simultaneous PiP and fullscreen USB-C output. This automatic-off configuration was not separately tested in SBS mode.

If the complete moving SBS video remains in the glasses while Settings is foreground, the next experiment is ReplayKit capture feeding an encoded local stream to this same native player. That later combination must independently establish live delivery, capture/playback coexistence, and acceptable delay before adding depth inference. A failed physical clip control does not justify building the encoded pipeline on speculation.

The native-player control did not pass that gate. Keep its findings and minimal reproduction available for the specific iOS 26 USB-C routing question to Apple; further work needs a materially different supported output mechanism or new platform evidence.

## iOS 26 long-form route-preparation result

Following Apple's long-form routing sample, a separate route-preparation probe (retired diagnostic; source removed) registers `AVInitialRouteSharingPolicy=LongFormVideo` from launch, configures Playback/MoviePlayback with long-form policy and options zero, and requests route selection before constructing playback UI. The callback controls whether it uses the sample's bare-player External branch or native AVPlayerViewController Local branch. No app-owned external window, live capture or depth processing is included.

The user-authorized fresh launch at 23:49:05 PDT on 2026-09-04 captured actual startup and runtime output in `Build/longform-route-probe-device/console-first.log`. With iOS 26.6.1 and directly connected glasses at 1920 x 1080, audio port type was `HDMIOutput`. At 23:49:27.299, route preparation returned `shouldStart=1 selection=Local(1)` before player creation. During background playback the logs reported `app=2 scene=2`, `pip=1`, `external=0` and `mirrored=yes`, with advancing playback time. The user confirmed **Settings with a floating window** in the glasses. This configuration therefore also failed independent fullscreen external output.

The API never selected External, and the test did not force that branch or proceed to SBS/live conversion. Changing the clip format would not explain the initial Local classification because route preparation precedes asset creation. The diagnostic process was terminated at 23:51:47 after the physical report. Preserve these observations for the specific question of whether direct USB-C DisplayPort is eligible for this route-selection mechanism and cross-app fullscreen video presentation.
