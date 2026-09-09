# Sunlight3D for iOS

Sunlight3D is the iPhone/iPad client based on VoidLink and Moonlight.
It streams from a PC to the device or USB-C glasses. The current picture modes
are **2D**, **Host3D**, and **RawSBS**. Client3D remains disabled pending platform
and hardware verification; local iPhone-screen hosting is outside this base.

Picture quality belongs to each app/mode. PC controls, sound and connection
settings are shared per machine, with one set of global defaults. Native uses
the phone/tablet's full landscape pixels; Raw uses the exact glasses canvas.

## Start here

- [Architecture and review](docs/sunlight-ios-review.md)
- [Current streaming contract](docs/sunlight-host-streaming-contract.md)
- [Settings and streaming UI](docs/sunlight-in-stream-controls.md)
- [Shared common-C integration](docs/shared-common-core-ios-handoff.md)
- [Regression checks](tests/README.md)
- [Workspace boundaries and device logging](AGENTS.md)

Open `VoidLink.xcodeproj` and select the `VoidLink` scheme. Its display name is
Sunlight3D. The iOS target uses the checked-in dependency pins; shared common-C
must remain unmodified. The sibling host and Android checkouts are read-only.
A generic compilation without device signing is:

```sh
xcodebuild -project VoidLink.xcodeproj -scheme VoidLink -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The project retains its inherited deployment setting and some availability and
deprecation warnings. That setting is not evidence of physical qualification on
every OS. See the review's validation limits before release.

## Credits and license

This work builds on VoidLink by True砖家 (True Zhuanjia), the Moonlight iOS
contributors and the contributors listed in the [upstream README](docs/archive/voidlink-upstream-readme.md).
The original attribution and App Store distribution information remain there.
Source licensing is in [LICENSE.txt](LICENSE.txt); dependency licenses remain
with their respective sources.
