# Open-source audit: keeping wired glasses output while another app runs

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

> Historical record: on 2026-09-05 the user selected [per-app 3D integration](sunlight-per-app-3d.md), with container hosting as one candidate. The background-output probes and their source projects have been removed. Previous findings and device log paths are retained as evidence; proposed experiments below are not the active implementation plan.

Research date: 2026-09-05. Target remains the current iPhone 17 Pro on iOS 26.6.1, with existing glasses directly connected over USB-C for power and video. This was source research only: no app launch, build, installation, device setting change or vendor message.

## Result

No inspected project establishes the complete required behavior on this configuration. The most useful new comparison is **Sodalite's native AVPlayer pipeline**, which has a firsthand wired fullscreen result and differs from our probes in asset delivery and audio-session activation. **Moblin** independently implements nearly our complete capture/PiP/external-window architecture, but provides no identified proof of retained fullscreen output after switching apps.

This narrows the remaining public-API question: can we first engage native AVPlayer external playback on the directly connected glasses, and does that system-managed presentation survive Home/Settings? Our prior probes observed `externalPlaybackActive=0`, so they do not establish what a successfully engaged native route would do. They do establish that the tested app-owned windows and PiP configurations returned to mirroring.

## 1. Sodalite / AetherEngine: the strongest new comparison

An iPhone 15 / iOS 26.5 issue reports fullscreen playback on both a Dolby Vision TV and SDR monitor after the player enabled native external playback. The maintainer explains that wired HDMI must retain the local stream URL and HLS master playlist; their earlier code mistakenly treated wired output like a wireless AirPlay receiver. The user confirms fullscreen playback and display-mode matching. **Neither report establishes behavior after Home or another native app opens.** The hardware included a USB-C-to-HDMI adapter, unlike our direct DisplayPort glasses. [Issue and device details](https://github.com/superuser404notfound/Sodalite/issues/34), [maintainer's routing explanation](https://github.com/superuser404notfound/Sodalite/issues/34#issuecomment-4899656052), [physical result](https://github.com/superuser404notfound/Sodalite/issues/34#issuecomment-4909000223).

The source supplies a reproducible configuration:

- Native AVPlayer receives locally generated HLS with fragmented MP4 media and enables `allowsExternalPlayback` and `usesExternalPlaybackWhileExternalScreenIsActive`. [Player setup](https://github.com/superuser404notfound/Sodalite/blob/2934437739498a8623c7315bbd8ed5d5b2d14684/Sodalite/Player/PlayerHostController.swift#L159-L188).
- AetherEngine declares playback/moviePlayback/default audio policy but deliberately leaves native-path activation to AVPlayerViewController. Its motivating activation bug concerns **tvOS multichannel audio**, so an effect on iPhone video routing remains a hypothesis. The wired HDMI branch retains `127.0.0.1` and the master playlist. Playing native sessions are left running during background transitions, without an identified special wired-display assertion. [Audio-session setup](https://github.com/superuser404notfound/AetherEngine/blob/33c38166e54ed4c9d2675ca3058074caa4b71123/Sources/AetherEngine/AetherEngine.swift#L3025-L3060), [wired routing](https://github.com/superuser404notfound/AetherEngine/blob/33c38166e54ed4c9d2675ca3058074caa4b71123/Sources/AetherEngine/AetherEngine.swift#L5444-L5467), [background policy](https://github.com/superuser404notfound/AetherEngine/blob/33c38166e54ed4c9d2675ca3058074caa4b71123/Sources/AetherEngine/AetherEngine.swift#L828-L908).
- Its alternate subtitle path disables native external playback and creates an app-owned external window. Exclude that path from a native-route comparison; it reintroduces the ownership mechanism already tested. [Subtitle window source](https://github.com/superuser404notfound/Sodalite/blob/2934437739498a8623c7315bbd8ed5d5b2d14684/Sodalite/Platforms/iOS/ExternalSubtitleWindowController.swift#L5-L17).

Our native AVKit probe explicitly calls `setActive:YES` before playback and uses bundled MP4 files. The long-form probe also explicitly activates audio and plays bundled MP4 after route selection. Neither reproduces local HLS with AVKit-owned activation. The long-form `Local` result happened before asset creation, so it must not be attributed to MP4; this proposed comparison tests actual playback-route engagement separately.

## 2. Moblin: almost the same architecture, no demonstrated ownership escape

Moblin captures video/app audio through a ReplayKit broadcast extension. Its clean external output is a `UIWindow(windowScene:)` containing a preview. PiP uses a sample-buffer display layer. Its pipeline continues attempting external-display enqueues independently of whether phone preview is enabled; background handling disables the phone preview without PiP. This is an intentional background-processing-plus-external-submission implementation, not proof that iOS physically presents its external frames after Home. [Capture extension](https://github.com/eerimoq/moblin/blob/b136654b635d5f6b4fea699a93090e98d129671c/Moblin%20Screen%20Recording/SampleHandler.swift#L18), [external window](https://github.com/eerimoq/moblin/blob/b136654b635d5f6b4fea699a93090e98d129671c/Moblin/Various/Model/Model.swift#L1588), [PiP source](https://github.com/eerimoq/moblin/blob/b136654b635d5f6b4fea699a93090e98d129671c/Moblin/Various/Model/ModelPictureInPicture.swift#L5), [external enqueues](https://github.com/eerimoq/moblin/blob/b136654b635d5f6b4fea699a93090e98d129671c/Moblin/Media/HaishinKit/Media/Video/VideoUnit.swift#L939).

An issue confirms broadcasting a screen while browsing a website, but does not address HDMI. It corroborates capture/broadcast capability rather than the missing output behavior. [Issue #242](https://github.com/eerimoq/moblin/issues/242). A physical Moblin comparison could be informative, but source inspection found no distinct display-ownership mechanism to transplant.

## 3. Other source leads and their limits

| Project | Source finding | Implication |
| --- | --- | --- |
| Swiftfin | [PR #1863](https://github.com/jellyfin/Swiftfin/pull/1863/files) adds `usesExternalPlaybackWhileExternalScreenIsActive=true`; [issue #1860](https://github.com/jellyfin/Swiftfin/issues/1860) reports foreground wired mirroring. | Supports native-route engagement as a real issue, but the property was already tried in our MP4 probe. No cross-app proof. |
| WebKit | [iOS external-playback selection](https://github.com/WebKit/WebKit/blob/7ab124eb02518a622a79a6a7c9476bd7d7c1e538/Source/WebCore/platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm#L3596-L3604) uses the same AVPlayer property for fullscreen/standby. The nearby explicit [AVOutputContext assignment](https://github.com/WebKit/WebKit/blob/7ab124eb02518a622a79a6a7c9476bd7d7c1e538/Source/WebCore/platform/graphics/avfoundation/objc/MediaPlayerPrivateAVFoundationObjC.mm#L3566-L3581) is compiled outside iOS-family platforms. | These inspected functions do not supply an iPhone private output-context bypass. This is not an audit of every WebKit/platform SPI. |
| MPVKit | [iOS demo background handler](https://github.com/mpvkit/MPVKit/blob/2103893078c5e339073b11737b86f7f22b9c4491/Demo/Demo-iOS/Demo-iOS/Player/Metal/MPVMetalViewController.swift#L96-L109) pauses playback and disables video. | No hidden background Metal output solution in that implementation. |
| UTM | [External scene](https://github.com/utmapp/UTM/blob/b6f7475be54f9cb542c46b131319454b83489ced/Platform/iOS/UTMExternalSceneDelegate.swift#L20) uses an ordinary scene/window. | External-screen support alone is not background-ownership evidence. |
| Flutter external_display | [Implementation](https://github.com/GavinFu7/external_display/blob/83a56ae58752e24c9cf266a5d16944adc640e719/ios/Classes/ExternalDisplayPlugin.swift) uses legacy UIScreen/window management. | A scene-less lifecycle control remains untested locally, but no positive Home/Settings result justifies ranking it above the native-player comparison. |
| Google Navigation | [CarPlay fix #740](https://github.com/googlemaps/flutter-navigation-sdk/pull/740) binds rendering to the CarPlay screen to fix animation after phone lock. | Useful for a frozen retained surface; it does not resolve our observed return to phone mirroring. Direct glasses are not a CarPlay scene. |

The promising-sounding `preventsAutomaticBackgroundingDuringVideoPlayback` name is also not an answer: Apple explicitly distinguishes automatic backgrounding from the user choosing to background an app. Its existence does not grant simultaneous foreground app ownership. [Apple documentation](https://developer.apple.com/documentation/avfoundation/avplayer/preventsautomaticbackgroundingduringvideoplayback).

The previously investigated private system-windowing projects remain separate: [compatibility and privilege audit](sunlight-experimental-iphone-windowing.md). This source pass found no new evidence that they support the current phone/OS combination.

## Next experiment, not yet implemented or run

Reproduce Sodalite's **native** output configuration in a minimal diagnostic before adding conversion:

1. Serve a known-good marked H.264/AAC HLS fixture from a loopback-only server on the phone. Use a master/media playlist and fragmented MP4. Keep the glasses directly connected; no wireless receiver or internet dependency.
2. Use playback/moviePlayback/default, leave session activation to AVKit, enable both external-playback properties, and present native AVPlayerViewController. Create no app-owned external output window and no subtitle takeover.
3. Log the actual URL/requests, `externalPlaybackActive`, layer readiness, external-screen mirroring and lifecycle. First seek a physically verified native wired picture with external playback active. If it never engages, record that failure instead of treating foreground fullscreen alone as the desired route.
4. Open Home and Settings and verify the moving marked video remains fullscreen in the glasses. Test PiP state explicitly; lock-only playback does not pass. Physical visibility is the decisive result, not successful buffer submission or advancing playback time.
5. Only after this passes, test SBS mode and a competing native video app. Then connect ReplayKit → processing → encoder → local HLS, measure end-to-end delay, and separately prove sustained background depth inference. Encoding and player buffering may make a playback solution unsuitable for interactive games.

This is a source-backed configuration comparison, not a claim that HLS or deferred audio activation grants background display ownership. If it succeeds, subsequent controls should isolate which difference mattered. If it fails, it adds a precise negative result without repeating the previous PiP/window experiment under a new name.
