# Sunlight container reliability and alternatives

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

Research and proposed design, 2026-09-05. The user likes container hosting and wants it to be more reliable. The target remains native games and video apps, all conversion on iPhone, and existing unmodified USB-C glasses connected directly for power and SBS video. No jailbreak or publisher SDK integration. Package import, account persistence and update friction remain concerns; accepting containers does not mean those are solved.

## Other third-party containers

| Project | What the primary source establishes | Relevance to Sunlight |
| --- | --- | --- |
| [VibeContainers](https://github.com/GenericCoding/VibeContainers) | Experimental iPhone/iPad shell embedding LiveContainer 3.8.0. | Useful integration reference, not an independent runtime or demonstrated reliability improvement. Open reports concern [TikTok launch](https://github.com/GenericCoding/VibeContainers/issues/2) and the [IPA install button](https://github.com/GenericCoding/VibeContainers/issues/3); these reports do not establish universal failure. |
| [MultiAppIOS](https://github.com/vinhnv2507/MultiAppIOS) | Describes itself as based on LiveContainer; retains its guest loader and architecture. | Another derivative, with no reviewed evidence of better target-app reliability or the complete Sunlight pipeline. |
| [CherryFlavoredBleach/LiveContainer](https://github.com/CherryFlavoredBleach/LiveContainer) | Unofficial fork documenting fixes tested on iOS 27 beta 1 and a broken SDK-spoofing option. | A version-specific fork, not evidence of a stronger current runtime. Upstream subsequently added iOS 27 beta support. |
| [Crane](https://havoc.app/package/crane) | App data-container manager; the current listing explicitly requires jailbreak. | Outside the user's requirements; data switching also does not establish scene hosting inside Sunlight. |

No independently maintained, more reliable native-app hosting engine for the current non-jailbroken iPhone was established by this search. This is a bounded research result, not a claim that no other implementation exists. None of the reviewed alternatives demonstrates adoption of an existing App Store installation with its original credentials in place.

## Recommended foundation

Use upstream LiveContainer as the runtime reference and keep Sunlight's integration small. The latest stable release is [3.8.0](https://github.com/LiveContainer/LiveContainer/releases/tag/3.8.0), commit `e370a92dfc03ce109ebce00ed4a7cfc64ad1c801`. The September 5 build `8ca6ea52485ed33e795e70ce6d3cf42872771f0e` is a nightly. Select a baseline only after testing it, and record the exact SHA plus any reviewed fixes. Neither a release label nor a newer nightly certifies compatibility.

Upstream has concrete reliability work to retain: 3.8.0 includes keyboard, scene and video-freeze fixes. A later [lifecycle fix](https://github.com/LiveContainer/LiveContainer/commit/5727a3b366) addresses duplicate resign-active notifications. The [YouTube termination issue](https://github.com/LiveContainer/LiveContainer/issues/1491) also records confusion about which branch actually contained a fix. Treat a maintainer's fix report as a candidate for qualification, not a successful device test.

## Packaging with built-in SideStore

The user's fork is [dcatcher9/LiveContainer](https://github.com/dcatcher9/LiveContainer). It is checked out at `third_party/LiveContainer` as a Sunlight Git submodule, initially pinned to `8ca6ea52485ed33e795e70ce6d3cf42872771f0e`. Its local working branch is `codex/sunlight-integration`; `origin` is the user's fork and `upstream` is the official repository. This revision is a candidate baseline, not a qualified runtime release. For a fresh Sunlight checkout, initialize it with `git submodule update --init --recursive third_party/LiveContainer`.

The user highlighted that LiveContainer already bundles SideStore. Prefer evaluating that existing integration for the container-enabled Sunlight build rather than implementing a new signing/refresh service. Proposed responsibilities: Sunlight supplies the library, conversion and glasses output; LiveContainer supplies guest execution; bundled SideStore supplies host installation/refresh and the signing identity used by the guest runtime. This packaging has not yet been integrated or validated in Sunlight.

At the pinned revision, the base Xcode scheme is `LiveContainer`. The combined SideStore IPA is produced later by [upstream's packaging script](https://github.com/dcatcher9/LiveContainer/blob/8ca6ea52485ed33e795e70ce6d3cf42872771f0e/.github/build_github.sh), which downloads a mutable SideStore nightly and additional tooling. A reproducible Sunlight combined build must pin those artifacts and use isolated staging. The initial dependency checkout does not execute that packaging script.

The official [LiveContainer + SideStore guide](https://livecontainer.github.io/docs/installation/lc_sidestore) documents a combined app occupying one free app slot, certificate import, on-device refresh through LocalDevVPN, and an auto-refresh shortcut. Initial installation and setup are still required. Travel qualification must verify actual refresh and subsequent launch on the selected OS; bundling does not guarantee successful automatic renewal.

Keep signature refresh separate from guest-version updates. LiveContainer's [Sources feature](https://livecontainer.github.io/docs/guides/sources) installs packages supplied by a feed; it does not adopt the user's existing App Store installation or synchronize its credentials. SideStore integration reduces setup friction, but guest package availability, compatibility testing and recoverable updates remain necessary.

## Dependency checkout verification

The initial fork checkout and both nested dependencies are complete. OpenSSL is pinned to `623c84da314e85363236507ca38a4bde65df21c3`; litehook is pinned to `8025e0c8ebdf5cdd1d2a4f45025813234bf9dc55`. The fork's stale `fishhook` entry has no Git submodule entry in the index at this revision, so no fishhook checkout was required.

An unsigned `LiveContainer` Release archive **passed** on Xcode 26.6 (`17F113`), iPhoneOS SDK 26.5, generic iOS/arm64. [Build log](../Build/livecontainer-baseline/console.log); archive: `Build/livecontainer-baseline/LiveContainer.xcarchive`. The LiveContainer source tree remained clean after the build.

Reproduce from the Sunlight repository root:

```sh
xcodebuild archive \
  -project third_party/LiveContainer/LiveContainer.xcodeproj \
  -scheme LiveContainer \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath Build/livecontainer-baseline/DerivedData \
  -archivePath Build/livecontainer-baseline/LiveContainer.xcarchive \
  ARCHS=arm64 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=''
```

This validates source compilation and linkage only. It does not validate signing, bundled SideStore packaging/refresh, guest execution, readable guest pixels or USB-C output. No iPhone app was installed or launched. No commit or push was made during this setup.

## Proposed stabilization work

1. **One guest process.** Keep Sunlight's UI, conversion and glasses renderer in the host; run one guest through LiveProcess. Stop the prior guest before launching another. Minimizing other windows is not the same as enforcing one running guest. This is process separation for recovery, not a security-isolation guarantee.
2. **Normal phone geometry from launch.** Present one full-size hosted scene. Defer floating windows, arbitrary resizing and multiple data profiles. Qualify rotation separately. This reduces lifecycle and layout combinations while retaining the native app's own feed, keyboard and controls.
3. **Per-app compatibility records.** Record the package identity/hash, app version, runtime SHA, configuration, signing setup, phone and exact iOS build. Support requires launch, login, input, playback/gameplay, frame capture, USB-C output and recovery results. A launch-only pass cannot earn a 3D-supported status.
4. **Independent recovery.** On guest exit, invalidate its frame-session generation and discard queued frames. Keep the host and output coordinator alive where possible, present a readable recovery screen to both eyes, and offer to relaunch without deleting guest data. Avoid restart loops. An AI failure should preserve guest interaction; a proposed 2D fallback must duplicate the image correctly within the current SBS layout rather than display a phone mirror split across the eyes.
5. **Preserve identity through updates.** Keep the guest's data UUID, App Group mapping and keychain assignment stable. Stage and validate a replacement package; stop the guest before switching bundles; record the update transaction so interruption can be recovered. Retain the working bundle and a consistent recoverable data snapshot where possible. File backup alone cannot promise recovery of keychain mutations, server state or incompatible database migrations. Never clear data/keychain automatically as a generic repair.
6. **Qualify signing and travel behavior.** Validate the host and helper signatures, matching identity, required extensions and an actual cold guest launch after refresh. Include reboot, temporary loss of connectivity and certificate-expiry handling in qualification. Network access is still required for online content. Do not equate a scheduled refresh with verified launchability.
7. **Bound resource use.** Start with one in-flight conversion and a replaceable latest-frame slot. Measure frame age, input delay, A/V sync, drops, memory and sustained thermal behavior. Lower conversion workload when needed without changing the guest's phone layout. No latency or reliability percentage is claimed before measurement.

These are proposed changes, not implemented features. Upstream provides [guest interruption callbacks](https://github.com/LiveContainer/LiveContainer/blob/8ca6ea52485ed33e795e70ce6d3cf42872771f0e/MultitaskSupport/AppSceneViewController.m#L95) and [termination cleanup](https://github.com/LiveContainer/LiveContainer/blob/8ca6ea52485ed33e795e70ce6d3cf42872771f0e/MultitaskSupport/AppSceneViewController.m#L341) to investigate for recovery. These hooks do not guarantee that the OS preserves the host after a guest failure.

Upstream's [data-management guide](https://livecontainer.github.io/docs/guides/data-management) distinguishes data files, App Groups and keychain cleanup. Its [JIT-less diagnostic guide](https://livecontainer.github.io/docs/faq/jit-less-mode-setup) checks signing identity, groups, validity and executable launch, and documents unsupported distribution-profile configurations. These are deployment constraints that a polished interface cannot erase.

## Implementation gates

| Gate | Evidence required before proceeding |
| --- | --- |
| Host ownership | A usable hosted guest on the phone while an independent moving Sunlight pattern remains visible in the glasses. |
| Real pixels | Fresh hosted video and Metal frames, with frame identifiers, reach the glasses. A hosted remote UIView or a moving playback clock is insufficient. |
| Native workflows | The selected app's sign-in, browsing, keyboard and playback/gameplay work without replacing its interface. Start with the named YouTube target and a developer-owned Metal fixture; game titles still need selection. |
| Fault recovery | Guest termination, host relaunch and glasses reconnect preserve recoverable user data and restore correctly packed output. |
| Update recovery | Interrupted staging leaves the old version launchable; any data migration has a documented recovery boundary. |
| Sustained 3D | Measured capture, depth inference, stereo synthesis and presentation under a representative extended session. |

LiveContainer's [architecture](https://livecontainer.github.io/docs/development/architecture) uses private loading/hosting mechanisms. Guest entitlements, permissions, extensions and data separation differ from normal installed apps. Stabilization can reduce defects for qualified combinations; it cannot guarantee every native app or future iOS release works.

The existing Sunlight external-display coordinator remains the output foundation. The optional container edition now links the runtime and embeds LiveProcess. See [the implementation record](sunlight-container-integration.md) for build and test evidence. No hosted-app or physical glasses compatibility pass is claimed by this source integration.

## Implementation started

The optional container edition now builds. See [Sunlight container integration](sunlight-container-integration.md) for the exact implemented behavior, signing requirements, test evidence and remaining hardware gates.
