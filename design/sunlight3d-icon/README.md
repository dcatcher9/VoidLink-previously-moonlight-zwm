# Sunlight 3D app icon

Status: approved and applied to the iOS `AppIcon` catalog and the About screen's
`AppIconMedium` image. Rebuild and install the app to update a device.

The gold sun carries the Sunshine 3D host identity. A broad blue crescent inset
adds the Moonlight 3D client identity. Both sit above the family's original two
curved depth planes. The combined mark represents Sunlight 3D's intended dual
client/host role without adding small text, device silhouettes, or arrows.

## Deliverables

- `family-comparison.png`: side-by-side reference comparison and small-size checks.
- `sunlight3d-ios-1024.png`: approved opaque, full-bleed square iOS icon master, sRGB.
- `sunlight3d-ios-{180,120,60,32}.png`: small-size exports.
- `sunlight3d-ios.svg`: scalable icon including its opaque background.
- `sunlight3d.svg` / `sunlight3d-mark-1024.png`: transparent brand mark.
- `generate.swift`: reproducible native vector/raster rendering; run with `swift design/sunlight3d-icon/generate.swift` from the repo root.
- `apply-icons.swift`: resize the approved PNG into all 18 existing launcher/store
  slots and the 360px About icon, preserving the catalog and project settings.
  Run `swift design/sunlight3d-icon/apply-icons.swift --apply` to update them, or
  `swift design/sunlight3d-icon/apply-icons.swift --check` to verify their contents,
  dimensions, and lack of alpha without changing files. This script does not
  require either reference repository.

Rounded corners on the comparison board are illustrative, not baked into the
production PNG. The operating system applies the actual icon mask.

## Source references (read-only)

- `/Volumes/Data/repos/Apollo-3D/sunshine3d.svg` and `sunshine3d.png`.
- `/Volumes/Data/repos/moonlight-android/moonlight3d.svg` and `app/src/main/ic_launcher-web.png`.
- Android adaptive background: `app/src/main/res/values/ic_launcher_background.xml`.

Retained exactly: the two Bézier depth paths, their 104/112-unit widths, five
52-unit rounded sun rays, and the gold `#E0B020`, moon blue `#2563EB`, far blue
`#D7E5FF`, near blue `#8AB4F8`, and midnight `#0B1020` palette. The checked-in
Moonlight icon is blue; its older generator does not reflect that color update.

## Design brief and method

“Design a coherent Sunlight 3D iOS app icon in the Sunshine 3D / Moonlight 3D
family: retain their two curved depth planes and flat, rounded geometry; combine
the gold sun with a broad blue crescent inset; use the existing midnight
background. Keep it legible at launcher sizes, with no lettering, gradients,
extra device illustrations, or baked-in corner mask.”

Method: native vector construction, not AI image generation or API fallback.
The image-generation skill directs established vector icon families toward
editable native assets so their geometry stays exact. Reference repositories
were only read, never modified or built.
