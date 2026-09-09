# iPhone conversion: reassessment after LiveContainer

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

Research date: 2026-09-07. This records the latest user clarification and a
read-only feasibility investigation. It does not claim a working replacement.

## Current requirements

- Conversion must happen on the iPhone. The user rejects XREAL's onboard
  conversion quality; recommending it again does not satisfy this goal.
- Different glasses are acceptable if setup is simple. This changes the earlier
  requirement to retain RayNeo, but does **not** move conversion off the phone.
- Preserve normal installed native apps and their familiar interfaces. Avoid
  importing and maintaining a separate copy of every app in LiveContainer.
- Keep a direct USB-C connection and an easy travel experience. An additional
  receiver, computer, modified phone, or wireless video transport has not been
  accepted as a replacement for this requirement.
- Native games and video remain relevant. A custom player, web replacements,
  downloaded videos, and a publisher SDK were previously rejected.

## Present finding

**No verified implementation currently meets the combined requirements on the
recorded iPhone 17 Pro / iOS 26.6.1 setup.** This is a bounded finding, not proof
that every future implementation is impossible.

The earlier [physical tests](sunlight-iphone-screen-feasibility.md) distinguish
capture from presentation: even when captured frames and CPU composition kept
advancing, iOS replaced the processed external picture with phone mirroring
after another app opened. More inference work does not repair that failure.

[LiveContainer hosting](sunlight-container-integration.md) changes scene
ownership by running imported guests. It does not adopt arbitrary existing App
Store installations, their data, or their updates. Improving signing and import
screens therefore cannot eliminate the coverage problem. The combined app's
installed SideStore scene is not evidence that guest capture and 3D work.

## New transport lead: send already-converted video as USB data

The architectural alternative is:

```text
Existing iPhone app
  -> consented system screen capture
  -> depth estimation and stereo synthesis on iPhone
  -> encode the completed stereo frames on iPhone
  -> direct USB-C network connection
  -> glasses receive, decode, and display those frames
```

The glasses perform ordinary video decoding, not depth estimation or 2D-to-3D
conversion. A receiver independent of iOS's DisplayPort scene would avoid the
specific external-window ownership failure. This remains a proposed design.

Apple DTS confirms that an accessory can expose USB NCM/Ethernet directly to an
iPhone, with no separate hub or router. Standard network APIs and link-local
addressing are supported; this network transport itself does not use an
MFi-licensed technology. It does not grant background execution or prove a video
receiver exists. [Apple DTS explanation](https://developer.apple.com/forums/thread/772812).

The missing hardware capability is **incoming encoded stereo video that drives
the glasses' displays independently of DisplayPort**. USB sensor, camera, mode
switching, or firmware interfaces do not establish that capability. For example,
an inspected XREAL One-family implementation exposes USB Ethernet, but its
documented video flow is Eye camera output from the glasses, alongside DP
controls; it does not document a stereo-video sink.
[Protocol implementation](https://github.com/taowen/ar-glass-lib).

This is a manufacturer integration lead, not a glasses purchase recommendation.
No reviewed retail model has a verified complete USB receiver path for this
purpose. INMO Air3's documented iPhone mirroring uses Wi-Fi; its USB file/debug
support does not establish USB video receiving. RayNeo X3 Pro development support
likewise does not establish such a transport.

The [INMO guide](https://support.inmoxr.com/air3/) and
[Unity SDK](https://github.com/INMOXR/air3-unity-sdk) establish development and
mirroring capabilities, not the complete stereo receiver. A concrete
[RayDesk receiver](https://github.com/Quad-Labs/RayDesk) targets RayNeo X3 Pro,
but its Wi-Fi transport and unresolved stereo viewport behavior do not meet this
single-cable requirement. Installing one receiver on programmable glasses would
be different from importing every iPhone app; it still needs real transport,
eye-separation, image-quality, and setup validation before recommendation.

## Phone-side execution remains a separate gate

Apple's iOS 27 ScreenCaptureKit sample explicitly supports full-display capture
while another app is frontmost through the `screen-capture` background mode.
The Background Inference entitlement is separately required for background
Neural Engine use. These are useful ingredients for an iPhone conversion
service, not a measured quality, latency, thermal, or battery result.
[Capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios),
[Background Inference](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.inference).

On the current iOS 26 path, do not assume a ReplayKit extension can use the
Neural Engine simply because the model selects it. Background inference,
extension memory, encoding, and sustained throughput need separate verification.
Apple recommends CPU-only compute for background Core ML execution.
[Compute units](https://developer.apple.com/documentation/coreml/mlcomputeunits).

For ordinary DisplayPort glasses, iOS 27's new external-scene accessory is still
the unresolved software lead. Apple ties it to a registered view controller and
system availability; the guide does not explicitly guarantee that another
foreground iPhone app leaves the external picture visible.
[Connected-display guide](https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display).

The installed toolchain remains Xcode 26.6 with iPhoneOS SDK 26.5. No iOS 27
prototype or physical result is claimed. A test must first retain a visibly
changing marked stereo picture through Home and Settings, then through another
video app, before adding depth inference. An advancing log counter is not a pass.

### Official sample and additional prerequisite

A subsequent direct device query confirmed that the available paired iPhone is
still running iOS 26.6.1 (23G83). The official downloadable capture sample was
then inspected. Its README requires a **physical iOS 27 device** and says this
capture API is unavailable in Simulator. Its signed target requests
`com.apple.developer.screen-recording = true`, in addition to its background
modes. This is a separate prerequisite from the Background Inference entitlement.

The sample's signing instructions express an intention to provision this
capability; they do not prove that the current user's team can obtain it. No
standalone authoritative entitlement page or managed-capability approval policy
was established in this check. Do not strip the entitlement or assume it is
granted. The first test must build/sign the unchanged official sample and verify
its actual provisioning and screen-capture behavior before adding external
presentation.

The source archive was staged locally, excluding its embedded Git history and
archive metadata. No sample code was executed or installed. It is a reference
capture app, **not an external-display or 3D prototype**.

- [Official archive](https://docs-assets.developer.apple.com/published/91f0562d72a9/CapturingScreenContentInIOS.zip)
- SHA-256: `d6d3f4068458490d9ddb5771636c135bcff98025d1ae38fa4a1b0fbb37a229a1`
- Local project: `Build/iphone-output-research/apple-ios27-sample/iOSSCKSample.xcodeproj`
- Local provenance: `Build/iphone-output-research/apple-ios27-sample/provenance.json`

The user has been asked whether a separate iOS 27 test phone is available. A
missing reply does not authorize upgrading the current phone. The necessary
runtime/signing and physical-output tests remain unperformed.

## Decisions justified by the evidence

1. Do not invest further in container onboarding as the answer to broad native
   app coverage. Keep the existing experimental work intact.
2. Do not buy different DisplayPort-only glasses expecting a different iOS
   lifecycle result. A vendor must demonstrate the distinct input capability.
3. Qualify either the iOS 27 external-output combination or an actual USB video
   receiver before selecting a production architecture. Neither is established.
4. Keep content protection and app-specific capture exclusions explicit; even a
   successful output path would not prove literally every app can be converted.

The [Sodalite HLS comparison](sunlight-open-source-output-audit.md) was also
rechecked against the current issue comments and source. There is still no
reported direct-glasses or Home/app-switch pass. The original report concerns
wired HDMI foreground playback. Its playback-oriented buffering also gives no
evidence of acceptable game latency. This remains a low-confidence diagnostic,
not a newly established workaround.
[Sodalite report](https://github.com/superuser404notfound/Sodalite/issues/34).

No app source changed, no device launched or restarted, no OS or firmware
changed, and no vendor or Apple message was sent during this reassessment.

## Android branch: hardware the user already owns

The user subsequently asked whether development should move to Android and
reported a Xiaomi phone, a Samsung tablet, and a HONOR MagicPad3 Pro. Their
follow-up identifies the Samsung as "tablet 7 plus pro" and Xiaomi as "latest
model this year." Treat Galaxy Tab S7+ as a provisional interpretation; the
Xiaomi model and installed Android versions remain unconfirmed. Android remains
an alternative product path, not a completed solution for iPhone apps.

- Samsung explicitly lists Tab S7/S7+ for DeX dual-display operation. If this is
  the user's tablet, it is a useful first capture/output test device. Its
  Snapdragon 865+ is confirmed by Samsung's datasheet; depth-inference frame
  rate has not been measured.
  [DeX developer guide](https://developer.samsung.com/samsung-dex/how-it-works.html),
  [Tab S7/S7+ datasheet](https://image-us.samsung.com/SamsungUS/samsungbusiness/pdfs/datasheet/Galaxy_Tab_S7_S7plus_Datasheet.pdf).
- Xiaomi's official FAQs explicitly document DisplayPort Alt Mode: DP1.2 on
  Xiaomi 17 and DP1.4 on Xiaomi 17 Ultra. These are conditional candidates;
  "latest" alone does not establish which phone the user owns or its port.
  [Xiaomi 17 FAQ](https://www.mi.com/global/support/faq/details/KA-667475/),
  [Xiaomi 17 Ultra FAQ](https://www.mi.com/global/support/faq/details/KA-667490/).
- The exact MagicPad3 Pro variant and its wired-display capability need to be
  distinguished. HONOR lists separate 13.3-inch and 12.3-inch versions. A USB
  speed, PC-style tablet interface, or reverse-charging specification does not
  by itself prove DisplayPort output. HONOR's wired-projection guide omits both
  Pro variants from its applicable-model list. The 12.3-inch product page
  advertises external-monitor use without establishing the transport. Keep
  the required USB-C output unverified for the user's exact device.
  [Wired-projection guide](https://www.honor.com/cn/support/content/zh-cn15857832/),
  [12.3-inch product page](https://www.honor.com/cn/tablets/honor-magicpad-3-pro-12-3/).

The proposed first software gate is intentionally independent of depth
inference: consent to whole-display MediaProjection, process captured frames
into a visibly marked left/right output, and keep that output moving in the
glasses while opening Home, Settings, and another native app on the Android
device. Confirm eye separation, the actual negotiated stereo display mode, and
reconnection physically. Ordinary mirroring or DeX support alone is not a pass.

Android documents whole-display capture and a mediaProjection foreground
service, with consent required for each session. That capture capability does
not independently prove OEM external-display lifecycle behavior. Protected
content remains excluded. Only after the physical output gate passes should
the existing Android GPU depth/stereo work be integrated and benchmarked.
[MediaProjection](https://developer.android.com/media/grow/media-projection).

No Android source was edited or built. The sibling moonlight-android repository
remains a read-only reference under this workspace's project boundaries.

### Compute evidence and its limits

The user's subsequent concern is whether the owned devices have enough GPU
power. No complete pipeline benchmark exists for their Xiaomi, Samsung tablet,
or MagicPad in the inspected reference records. Tab S7+ remains provisionally
identified and uses Snapdragon 865+ / Adreno 650. Xiaomi 17 and 17 Ultra use
Snapdragon 8 Elite Gen 5; the 13.3-inch MagicPad3 Pro also advertises that chip
and Adreno 840. Do not apply those specifications to an unidentified Xiaomi or
the separate 12.3-inch HONOR variant.

Qualcomm's current Depth Anything V2 Small model card lists 518x518 inference on
Snapdragon 8 Elite Gen 5 at 18.775 ms with ONNX float and 12.525 ms with ONNX
w8a16, both using the NPU. These are model-only measurements on vendor test
hardware, not GPU measurements or sustained results on the user's devices.
Runtime selection matters: the same card's QNN_DLC w8a16 entry is 83.512 ms.
Do not quote the fastest configuration as a generic phone performance promise.
[Qualcomm model card](https://huggingface.co/qualcomm/Depth-Anything-V2).

The Android reference's `docs/client-sbs-evaluation.md` records controlled
Galaxy XR GPU medians of 16.532 ms for DA-V2 322x182 and 10.293 ms for MiDaS
352x192 (complete OpenCL FP16 delegation, 20 warmups, 100 measurements).
These exclude capture and full-resolution stereo rendering. Historical live
experiments showed substantially longer inference calls under contention and
throttling; those are not current end-to-end FPS measurements. Current output
uses exact color/depth pairs, so a high display refresh rate must not be reported
as an equally high fresh 3D frame rate.

The newer flagship hardware is a credible performance target, subject to exact
model identification and sustained measurement. A phone NPU depth backend plus
GPU stereo rendering is worth comparing with the existing GPU implementation;
it is not implemented or validated for these devices. The first quality and
performance decision needs the full live pipeline, including a GPU-heavy native
game, rather than only an isolated model test.
