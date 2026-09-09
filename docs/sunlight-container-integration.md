# Sunlight container integration — first milestone

> Historical research: the active direction is now [host streaming only](sunlight-host-streaming.md). LiveContainer and its binaries/resources were removed on 2026-09-07. Local iPhone hosting and client conversion are deferred until iOS 27 verification.

Status: the combined app builds, signs, installs and attaches its built-in
SideStore scene on the iPhone. An imported guest has **not yet been launched
inside Sunlight on the iPhone**. Guest frame capture, depth estimation and SBS
conversion are not connected.

User-selected deployment route (September 7): **Xcode installs the combined
Sunlight app; only the built-in SideStore is used on the iPhone for signing and
renewal. Do not use external iloader.** The combined store UI is already included
in the optional build. Xcode's GUI successfully provisioned both targets, and
the real combined app was signed, installed over the paired Wi-Fi connection,
and launched on September 7. The host initialized successfully and attached
the embedded store's separate-process scene. The existing device pairing record
was transferred directly into SideStore's data directory and verified as a
regular file with mode 0600. On-device sign-in and refresh remain to be verified.

September 6 built-in SideStore test: the combined source archive, Sunlight build,
recursive ad-hoc signatures and ZIP checks passed. The first iloader attempt
rejected an AppleDouble `.___preview.dylib` metadata entry. Packaging now disables
resource forks, extended attributes and quarantine metadata; the rebuilt ZIP has
no `._*`/`__MACOSX` entries. The retry failed with **device not found**, and iloader's
refreshed USB list was empty. No combined app has been installed or launched.
The next action was reconnecting USB; the September 7 route above supersedes
the iloader retry.

## What this build does

The optional container edition adds **iPhone apps** to Sunlight's host navigation. It can import an IPA, stage and sign it, list imported apps, and request one foreground guest in LiveContainer's separate `LiveProcess` helper. The guest receives the phone's normal bounds, with a small Close app control overlaid. Sunlight continues to own its existing external-display coordinator.

During this milestone the glasses show an independent SBS calibration pattern with an advancing host counter. This is explicitly **a host-output test**, not a stereo version of the guest. Seeing the guest on the phone plus the moving host pattern in both eyes is the first hardware gate.

The developer-owned bundled fixture contains animated UIKit, touch input, a keyboard field and a Metal triangle. It does not establish YouTube, Bilibili, TikTok, Telegram or game compatibility.

## Build

From the repository root:

```sh
bash scripts/container/build.sh
```

Output: `Build/container-integration/SunlightContainer-unsigned.ipa`.

The script archives the checked-out LiveContainer fork, builds Sunlight with the container flag, embeds the helper and runtime, and includes the fixture. It fetches no mutable LiveContainer nightly or bundled SideStore release. Existing Swift package resolution is shared with the regular Sunlight build.

To include the built-in store:

```sh
bash scripts/container/build.sh --with-sidestore
```

This variant uses separate products under `Build/container-integration/bundled-sidestore` and produces `SunlightContainer-SideStore-unsigned.ipa`. Its SideStore and conversion-tool downloads are pinned by GitHub asset ID and SHA-256 in `scripts/container/sidestore-lock.json`; provenance is retained inside the app. Sunlight's imported-app library handles guest installation; the built-in store handles account provisioning and renewal, not App Store guest downloads.

This edition uses bundle ID `com.quyang.sunlight.container.dev2026`, with helper ID `com.quyang.sunlight.container.dev2026.LiveProcess`. The normal Sunlight build remains `com.quyang.voidlink3d.dev2026`; its container navigation is excluded. Build products and generated configuration stay under `Build/container-integration`.

Sunlight and LiveContainer use different OpenSSL frameworks. Packaging gives the container copy its own `LCOpenSSL.framework/LCOpenSSL` identity and updates ZSign's dependency; it retains Sunlight's existing OpenSSL. This separation still needs runtime signing and PC-streaming regression validation on the phone.

## Signing and device requirements

The host and helper must be signed together with a shared, provisioned App Group and the LiveContainer keychain groups. A signing tool must retain `LiveProcess.appex`. `Build/container-integration/Container.entitlements` describes the requested groups for this development edition. The IPA has ad-hoc signatures carrying the requested entitlements for SideStore to read. It still requires valid provisioning and re-signing and is not directly installable with `devicectl`. The package selects the sole accessible App Group at runtime so SideStore can remap its identifier.

LiveContainer's JIT-less guest signing on iOS 26 needs certificate material matching the installed host's signing team. The preview's **Signing** control imports a user-selected `.p12`, checks the team, and validates a signed test library on the device. Failed validation restores the prior signing configuration. Certificate material is stored in the runtime's shared signing preferences, following upstream behavior; it is never logged by the new UI.

The optional built-in store now has a **Signing → Open SideStore** entry and runs through the same separate-process hosting controller. It does not start a glasses test pattern. After setup, **Signing → Use SideStore certificate** reads the store's certificate directly from its shared keychain service and runs the existing team/device validation. This avoids certificate-bearing URL callbacks. Manual `.p12` import remains available.

Historical installer findings: generic iloader **Import IPA** did not transfer
the device pairing file or launch the installed app. That route is superseded by
the direct Xcode procedure below. The unsigned package's requested groups alone
are not proof that a signing tool preserves them; the direct signer validates
the actual host and helper signatures.

The store's identity hooks use Sunlight's original bundle identifier. A bundled, empty source catalog prevents the upstream LiveContainer release feed from offering to replace Sunlight. Signing refresh and travel/offline-expiry behavior still require device qualification. The combined build is not a complete travel product.

A direct Xcode provisioning attempt failed with **No Accounts** and **No profiles for com.quyang.sunlight.container.dev2026**. No container app was installed or launched. Record: `Build/container-integration/provisioning.log`. The previously cached normal Sunlight profiles do not include the required shared App Group and cannot be reused for this edition.

The September 6 recheck returned the same errors: `Build/container-integration/provisioning-bundled-recheck.log`. On September 7, direct inspection of Xcode's Apple Accounts settings found the user's account and Personal Team with one provisioned device. The old CLI error does not prove that the account is absent from Xcode. Initial deployment is now being prepared through Xcode with explicit host/helper provisioning; built-in SideStore does not inherently require iloader.

### Direct Xcode installation (September 7)

Generate a small signing-only project:

```sh
python3 scripts/container/prepare_xcode_signing.py --team J4QCH24VVD
```

Open `Build/container-integration/xcode-signing/SunlightSigningProfiles.xcodeproj`
in Xcode, select **Generate Sunlight Profiles** and the paired iPhone, then
**Build** (Command-B). Never install the generated signing fixtures. In this
session the CLI still reported No Accounts, while the GUI build succeeded.
Both real profiles grant the shared App Group and all 128 keychain groups.

Sign a separate copy of the combined app:

```sh
python3 scripts/container/sign_xcode_container.py \
  --manifest Build/container-integration/xcode-signing/signing-manifest.json \
  --prepared-app Build/container-integration/bundled-sidestore/Payload/SunlightContainer.app \
  --device-udid YOUR_DEVICE_UDID \
  --output Build/container-integration/xcode-signed-NEW_RUN
```

The signer verifies profile scope, device, expiry, shared permissions and public
signing identity before signing nested code, helper and host. It does not export
private keys. Actual installed IDs end in `.J4QCH24VVD` (host) and
`.J4QCH24VVD.LiveProcess` (helper); original IDs remain in SideStore metadata so
its later renewal can retain the installed identity. The shared group is
`group.com.SideStore.SideStore.J4QCH24VVD`.

The September 7 result is under `Build/container-integration/xcode-signed-20260907`:
`signing-report.json`, `install-result.json` and filtered live
`console-20260907.log`. Recursive signature verification passed; CoreDevice
confirmed installation and a running Sunlight process. No signing fixtures were
installed. Pairing records must be transferred only into the installed app's
data container, never bundled into an IPA.

The follow-up build is installed from
`Build/container-integration/xcode-signed-20260907-refresh-fix`. It corrects
SideStore's extension lookup to the containing host and changes only the exact
self-entry's `useMainProfile` flag during its normal database save. This makes
the separately provisioned LiveProcess helper eligible for its own profile
renewal. An in-memory CoreData test passed for an existing self-entry, persistence,
unrelated identities and repeated saves. The source archive, combined app build,
real recursive signature validation, device update and relaunch passed. The
pairing file survived the update with mode 0600. The latest live capture is
`xcode-signed-20260907-refresh-fix/console-20260907.log`; Apple Account sign-in and
actual in-app renewal are awaiting the on-phone test.

After opening the built-in store once to create its data directory, transfer the
existing trusted-device pairing directly from this Mac:

```sh
python3 scripts/container/install_pairing_record.py \
  --udid YOUR_DEVICE_UDID \
  --bundle-id com.quyang.sunlight.container.dev2026.J4QCH24VVD
```

This reads only the exact requested device's record from local usbmuxd, validates
the bounded response, and copies only
`Documents/SideStore/Documents/ALTPairingFile.mobiledevicepairing` through
`devicectl`. Temporary material is protected and deleted; credentials and raw
transfer output are never printed. The September 7 transfer succeeded and the
on-device file's mode was verified as 0600. This proves file setup, not SideStore
network connectivity or a successful signing renewal.

## Reliability changes

- `LCInitializeEmbeddedHost` initializes existing runtime globals without invoking `LiveContainerMain`, replacing Sunlight's home/bundle, or starting another UIApplication in the host process.
- The remote scene is created only after its controller attaches to the phone window. Cancellation, callback delivery, queued layout updates and teardown are serialized on main; late launch completion cannot restore a cancelled guest.
- The importer rejects unsafe paths, links, duplicate entries and oversized archives. Incoming LiveContainer recovery metadata is cleared before upstream processing. A separate structural Mach-O preflight checks bounded headers, commands, file ranges and embedded executable names before entering upstream patching; this does not guarantee runtime compatibility.
- Updates sign in staging before atomic promotion and retain the previous bundle. Guest data remains outside the bundle, with the existing container UUID and keychain identity. This is bundle recovery, not a guarantee that app database migrations or server sessions can be rolled back.
- Signing refresh also uses a staged copy. A currently valid executable takes the direct launch path, avoiding a full app copy on every launch.
- Only one guest can be opened from the modal library. An active glasses stream or calibration must be stopped before it can own output.

## Verification and hardware gates

Completed at the first build:

- LiveContainer archive with embedded-host API: passed on Xcode 26.6 / iPhoneOS SDK 26.5.
- Sunlight container build and IPA packaging: passed with ad-hoc entitlement signatures; ZIP integrity and nested signature consistency passed. Host and helper each declare the same App Group and 128 keychain groups.
- Normal Sunlight Debug build: passed with fresh build products (`normal-app-build-clean.log`); the first attempt hit an obsolete precompiled-header cache.
- Existing external-display regression suite: 21 passed, zero failures.
- Package extraction/promotion and Mach-O preflight tests on macOS: 268 checks passed, zero failures across 40 input archives, including malformed binaries, metadata sanitization, replacement backup and unrelated guest-data preservation. See `tests/container_package_tests/README.md` for the suite.
- Fixture build: arm64 IPA, warnings treated as errors; no device launch.

Logs: `Build/container-integration/{runtime-build.log,app-build.log,fixture-build.log}`. Existing display regression artifacts: `Build/external-display-tests/20260905-230604-79963`.

Next hardware sequence, with live console capture filtered through `scripts/container/capture_console.py` before saving to disk. That filter retains only known container lifecycle diagnostics so account details, certificate callbacks and guest content are not captured:

1. Install the separately signed container edition and set up its matching certificate.
2. Tap iPhone apps → Install test app, then open the fixture.
3. Confirm animated UIKit and Metal, touch/keyboard, and the independent host counter in both glasses eyes.
4. Close/reopen the guest, rotate the phone and reconnect the glasses. Confirm Sunlight survives a guest exit.
5. Only after this passes, obtain real moving guest pixels and feed them into the external renderer. A remote-scene UIView is not a pixel-buffer export; snapshots may omit Metal or video layers.
6. Connect depth estimation and SBS rendering, measure latency and sustained temperature/power, then qualify exact real app versions.

Runtime/private API compatibility, signing availability and capture are separate gates. A successful build proves none of those by itself.
