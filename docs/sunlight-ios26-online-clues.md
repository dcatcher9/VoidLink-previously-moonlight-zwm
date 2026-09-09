# iOS 26: online clues and the floating-dot proposal

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Research and follow-up test date: 2026-09-04. This continues the direct iPhone → USB-C glasses investigation after the native AVKit/PiP output controls failed. The glasses must stay directly attached for video and power. Another installed native app being foreground remains the requirement; foreground browser/player content is only a partial alternative. The subsequent authorized long-form routing device test is recorded below. No third-party app was installed.

## Tested public-API lead: prepare the long-form route

Apple's WWDC19 routing session explicitly includes wired external screens among destinations that route preparation can select. The associated Apple sample first registers long-form video, then requests route selection **before** constructing playback UI. That combination was absent from our earlier probes. It justified a materially different experiment; the 2019 material does not establish iOS 26 USB-C behavior after switching apps. [Apple session](https://developer.apple.com/videos/play/wwdc2019/501/), [Apple sample](https://developer.apple.com/documentation/avfoundation/integrating-airplay-for-long-form-video-apps).

The installed SDK 26.5 and Apple's sample, inspected read-only, provide this recipe:

```xml
<key>AVInitialRouteSharingPolicy</key>
<string>LongFormVideo</string>
```

```objc
AVAudioSession *session = AVAudioSession.sharedInstance;
[session setCategory:AVAudioSessionCategoryPlayback
                mode:AVAudioSessionModeMoviePlayback
  routeSharingPolicy:AVAudioSessionRouteSharingPolicyLongFormVideo
             options:0
               error:&error];
[session prepareRouteSelectionForPlaybackWithCompletionHandler:
    ^(BOOL shouldStartPlayback, AVAudioSessionRouteSelection selection) {
        // Return to the main queue, honor cancellation, then construct playback UI.
    }];
```

These APIs exist on iOS 13+. The prepare method is declared in `AVKit/AVPlaybackRouteSelecting.h`. The long-form policy requires the playback category and options zero; do not combine it with `MixWithOthers`. The SDK also documents that all long-form video apps share an audiovisual destination. Therefore a Settings success would still need a competing native video app test. The separately named `Independent` policy is not an app-settable workaround: the SDK explicitly tells apps not to set it directly. [Route policy documentation](https://developer.apple.com/documentation/avfaudio/avaudiosession/routesharingpolicy-swift.enum).

Apple's sample handles the callback in two materially different ways: Local presents AVPlayerViewController; External creates a bare AVPlayer with phone remote controls, without a local player layer or native player controller. Our previous system-only control still attached a local player layer, and our native control always presented AVPlayerViewController. The sample uses HLS, so compatibility with a local marked MP4 also needs observation. [Sample source archive](https://docs-assets.developer.apple.com/published/a687ba227f31/IntegratingAirPlayForLongFormVideoApps.zip).

Bounded test procedure:

1. Register the policy from launch; present a video-prioritized route picker and explicit Play control.
2. Keep glasses directly connected. Request route preparation, log its actual selection, audio route and external display. Do not select a wireless receiver or treat AirPlay success as USB-C proof.
3. If External is returned, follow the sample's bare-player/remote-controls branch. If Local is returned, log that result and use the local branch; do not manufacture an External result.
4. Test normal 1920 x 1080, Home and Settings with a moving marked clip. If independent output survives, test actual 3840 x 1080 SBS, another native video app, and repeated switches.
5. Only a physical output pass warrants attaching ReplayKit plus an encoded local stream. Then evaluate delay, capture exclusions, processing and thermal limits separately.

The user subsequently authorized a standalone long-form route prototype (retired diagnostic; source removed), which was built, installed in the previous AVKit diagnostic's bundle slot, and freshly launched with live logs at 23:49:05 PDT on iOS 26.6.1. With directly connected glasses at 1920 x 1080, long-form policy active and `HDMIOutput` audio, route preparation returned `shouldStart=1 selection=Local(1)` at 23:49:27.299 before player creation. The Local native-player branch ran. While backgrounded, video time advanced with PiP active, `external=0` and `mirrored=yes`. The user confirmed **Settings with a floating window** in the glasses. This configuration therefore failed independent fullscreen background output. No External selection, SBS follow-up or combined live-conversion result is claimed. The diagnostic was stopped at 23:51:47. Log: `Build/longform-route-probe-device/console-first.log`.

## Existing-app evidence

| Source | What it establishes | What it does not establish |
| --- | --- | --- |
| [Outplayer direct-glasses user report](https://www.reddit.com/r/Xreal/comments/1uokki8/how_to_turn_iphone_display_off_while_watching/) | A firsthand report of fullscreen wired video surviving phone lock, with explicit failure on Home. Useful but unverified on our hardware. | Cross-app independent output. The same report distinguishes it from lock-only playback. |
| [Outplayer's own release history](https://apps.apple.com/us/app/outplayer/id1449923287) | Maintained PiP, external-display and background-resume functionality. | No vendor promise of the required Home/Settings behavior. |
| [VLC external scene source](https://github.com/videolan/vlc-ios/blob/master/Sources/App/iOS/VLCNonInteractiveWindowSceneDelegate.m#L30-L37) and [playback lifecycle](https://github.com/videolan/vlc-ios/blob/master/Sources/Playback/Control/VLCPlaybackService.m#L1965-L2015) | Ordinary external UIWindow plus a decision not to pause simply because an external display is attached. | A privileged display path or proof that the window stays visible after another app foregrounds. Chromecast-specific dummy audio is unrelated to USB-C. |
| [VITURE browser Immersive 3D](https://www.viture.com/academy/immersive-3d/mobile#browser) | Current iOS guide describes Screen Recording consent, conversion of its browser content including webpages/web game streams, direct glasses and SBS switching. | The implementation is unpublished; consent alone does not establish how capture runs or whether another native app can foreground. |
| [RayNeo XR iOS](https://apps.apple.com/us/app/rayneo-xr/id6504473085) | Vendor implementation of photo/video 2D-to-3D playback on compatible Air glasses. | Whole-phone capture or background ownership. |
| [XREAL SDK release notes](https://developer.xreal.com/download/) | Documented dual-screen mode that preserves glasses AR while another 2D phone app is foreground. | The cited NRSDK mode is Android/Nebula, not an iPhone capability. |

SpaceWalker is the closest commercial iOS behavior to compare. An informative vendor-app test would confirm its browser 3D output, then switch to Settings with the same direct cable. Its documentation does not promise that transition will pass. Outplayer remains a playback benchmark with a specific firsthand Home failure; it does not provide positive evidence for the required cross-app output.

## Floating dot over the real iPhone Home Screen

The proposed UX is: shrink Sunlight to a small always-visible dot, let touches reach Home/other native apps, and keep Sunlight eligible for rendering and external presentation.

The missing piece is a supported **foreground scene**, not a visible pixel. UIKit's ordinary windows belong to the app's scenes. A transparent window, small frame or higher window level does not establish a public cross-app overlay and foreground-execution exemption. Hit testing within an app does not grant touch delivery to arbitrary other apps under it. [UIWindow](https://developer.apple.com/documentation/uikit/uiwindow), [app and scene lifecycle](https://developer.apple.com/documentation/uikit/managing-your-app-s-life-cycle).

PiP supplies a system-managed floating video; a user can move it partly offscreen. That does not keep the main app foreground. Our live ReplayKit/PiP run already logged both app and scenes in background while capture and CPU composition continued, yet the glasses returned to mirroring. The native PiP test independently produced Settings plus floating video in the glasses. Changing that floating UI to a smaller visual control does not address the measured output behavior. [Apple PiP user guide](https://support.apple.com/en-sg/guide/iphone/iphcc3587b5d/ios).

AssistiveTouch is an OS accessibility UI. Live Activities/Dynamic Island expose bounded system presentations and interactions rather than hosting the app's full UI/execution context. Neither supplies an established external-display ownership route for this design. Do not implement a fake transparent Home Screen or claim that a visible dot keeps Sunlight foreground.

## A different foreground design: host content inside Sunlight

An App Store-compatible scope can keep Sunlight's own browser, player, emulator or integrated content on the phone, add a dot over that content, and retain the foreground external renderer. VITURE's browser conversion is product evidence for part of this design. This changes source coverage: it cannot automatically host arbitrary installed native games and video apps. XeOS, another external-display desktop app, explicitly distinguishes its own browser/built-in environment from installed native apps. [XeOS developer FAQ](https://externaldisplayiphone.com/).

A more experimental clue is [LiveContainer](https://github.com/LiveContainer/LiveContainer). It demonstrates running supplied iOS app packages in a host environment with virtual windows and PiP on iOS 16+, distributed through sideloading. Its developer describes private FrontBoard/RunningBoard/UIKit scene-hosting APIs. That suggests a research architecture where Sunlight remains the foreground host while supported guest content is processed. It is not evidence that our external SBS path works, nor an App Store-ready way to use every already-installed app. Compatibility, supplied app packages, signing and app services impose major limits; no installation or execution is proposed here. [Developer's architecture notes](https://gist.github.com/khanhduytran0/504b16d86a2091e676c412bd0a517306).

## Decision

The 2026-09-05 [open-source output audit](sunlight-open-source-output-audit.md) found a source-backed native-player comparison in Sodalite/AetherEngine: local HLS with AVKit-owned audio activation and a firsthand wired fullscreen result, but no reported Home/Settings test. Moblin independently combines ReplayKit, PiP and external-window submission without identified proof that fullscreen output survives another foreground app. The audit records exact sources and an unrun native-route experiment; neither project establishes the complete requirement.

The user's subsequent request to search beyond the public windowing model produced [experimental iPhone system-windowing leads](sunlight-experimental-iphone-windowing.md) on 2026-09-05. These include real installed-app scene hosting and iPad-style windowing implementations, with explicit OS/chip/privilege limits. None is established on the current iPhone 17 Pro / iOS 26.6.1, and no complete glasses pipeline was tested. Keep this separate from LiveContainer's imported-app scope and from the measured public-API output failures.

The explicit long-form route-selection control has now failed the physical output gate on the tested iOS 26 device. The remaining immediate platform question is whether USB-C DisplayPort should qualify as an External selection and whether a supported configuration can retain fullscreen output after another app foregrounds; preserve the minimal reproduction for Apple. A future experiment needs a distinct mechanism or new platform evidence. Retain the dot as a possible control surface if a supported output path passes. Preserve the content-host alternative as a separate product-scope decision; it does not complete arbitrary native-app capture.
