#!/usr/bin/env swift
// A vector-native proposal. Does not modify the app catalog or either reference repo.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let midnight = "#0B1020"
let gold = "#E0B020"
let moonBlue = "#2563EB"
let farBlue = "#D7E5FF"
let nearBlue = "#8AB4F8"

func color(_ hex: String) -> CGColor {
    let n = UInt32(hex.dropFirst(), radix: 16)!
    return CGColor(srgbRed: CGFloat((n >> 16) & 255) / 255,
                   green: CGFloat((n >> 8) & 255) / 255,
                   blue: CGFloat(n & 255) / 255, alpha: 1)
}

let rays: [(CGPoint, CGPoint)] = [
    (.init(x: 512, y: 160), .init(x: 512, y: 236)),
    (.init(x: 286, y: 222), .init(x: 344, y: 280)),
    (.init(x: 738, y: 222), .init(x: 680, y: 280)),
    (.init(x: 170, y: 414), .init(x: 250, y: 414)),
    (.init(x: 854, y: 414), .init(x: 774, y: 414))
]
let disc = CGRect(x: 332, y: 244, width: 360, height: 360)
// Offset circular cutout: a broad Moonlight-blue crescent within the gold sun.
let cutout = CGRect(x: 420, y: 182, width: 320, height: 320)
let planes: [(CGPoint, CGPoint, CGPoint, CGPoint, CGFloat, String)] = [
    (.init(x: 188, y: 704), .init(x: 342, y: 582),
     .init(x: 682, y: 582), .init(x: 836, y: 704), 104, farBlue),
    (.init(x: 164, y: 810), .init(x: 338, y: 650),
     .init(x: 686, y: 650), .init(x: 860, y: 810), 112, nearBlue)
]

func drawMark(_ ctx: CGContext) {
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(gold))
    ctx.setLineWidth(52)
    for (a, b) in rays {
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    }
    ctx.setFillColor(color(gold))
    ctx.fillEllipse(in: disc)
    ctx.saveGState()
    ctx.addEllipse(in: disc); ctx.clip()
    ctx.setFillColor(color(moonBlue))
    ctx.addEllipse(in: disc); ctx.addEllipse(in: cutout)
    ctx.drawPath(using: .eoFill)
    ctx.restoreGState()
    for (a, b, c, d, width, hex) in planes {
        ctx.setStrokeColor(color(hex)); ctx.setLineWidth(width)
        ctx.move(to: a); ctx.addCurve(to: d, control1: b, control2: c)
        ctx.strokePath()
    }
}

func render(_ filename: String, width: Int, height: Int,
            opaque: Bool = true, draw: (CGContext) -> Void) throws {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: alpha.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true)
    draw(ctx)
    let image = ctx.makeImage()!
    let destination = CGImageDestinationCreateWithURL(
        output.appendingPathComponent(filename) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "SunlightIcon", code: 1)
    }
}

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat,
          hex: String, weight: NSFont.Weight = .regular, ctx: CGContext) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor(cgColor: color(hex))!
    ])
    NSGraphicsContext.restoreGraphicsState()
}

func drawPNG(_ path: String, in rect: CGRect, ctx: CGContext) {
    let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY); ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

func icon(in rect: CGRect, masked: Bool, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY)
    ctx.scaleBy(x: rect.width / 1024, y: rect.height / 1024)
    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    if masked {
        // Illustrative preview only. The production icon is full-bleed square.
        ctx.addPath(CGPath(roundedRect: bounds, cornerWidth: 220, cornerHeight: 220, transform: nil))
        ctx.clip()
    }
    ctx.setFillColor(color(midnight)); ctx.fill(bounds)
    drawMark(ctx)
    ctx.restoreGState()
}

let defs = """
  <defs>
    <mask id="crescent" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <rect width="1024" height="1024" fill="black"/>
      <circle cx="512" cy="424" r="180" fill="white"/>
      <circle cx="580" cy="342" r="160" fill="black"/>
    </mask>
  </defs>
"""
var geometry = "  <g fill=\"none\" stroke=\"\(gold)\" stroke-width=\"52\" stroke-linecap=\"round\">\n"
for (a, b) in rays {
    geometry += "    <path d=\"M\(Int(a.x)) \(Int(a.y))L\(Int(b.x)) \(Int(b.y))\"/>\n"
}
geometry += "  </g>\n  <circle cx=\"512\" cy=\"424\" r=\"180\" fill=\"\(gold)\"/>\n"
geometry += "  <rect width=\"1024\" height=\"1024\" fill=\"\(moonBlue)\" mask=\"url(#crescent)\"/>\n"
for (a, b, c, d, width, hex) in planes {
    geometry += "  <path d=\"M\(Int(a.x)) \(Int(a.y))C\(Int(b.x)) \(Int(b.y)) \(Int(c.x)) \(Int(c.y)) \(Int(d.x)) \(Int(d.y))\" fill=\"none\" stroke=\"\(hex)\" stroke-width=\"\(Int(width))\" stroke-linecap=\"round\"/>\n"
}
for (filename, background) in [("sunlight3d.svg", false), ("sunlight3d-ios.svg", true)] {
    let svg = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-labelledby="title description">
      <title id="title">Sunlight 3D</title>
      <desc id="description">A gold sun with a blue crescent inset above two curved depth planes.</desc>
    \(defs)
    \(background ? "  <rect width=\"1024\" height=\"1024\" fill=\"\(midnight)\"/>\n" : "")\(geometry)</svg>

    """
    try svg.write(to: output.appendingPathComponent(filename), atomically: true, encoding: .utf8)
}

for size in [1024, 180, 120, 60, 32] {
    try render("sunlight3d-ios-\(size).png", width: size, height: size) { ctx in
        icon(in: CGRect(x: 0, y: 0, width: size, height: size), masked: false, ctx: ctx)
    }
}
try render("sunlight3d-mark-1024.png", width: 1024, height: 1024, opaque: false, draw: drawMark)

try render("family-comparison.png", width: 1320, height: 740) { ctx in
    ctx.setFillColor(color("#F1F4FA")); ctx.fill(CGRect(x: 0, y: 0, width: 1320, height: 740))
    text("Sunlight 3D", x: 88, y: 45, size: 32, hex: midnight, weight: .semibold, ctx: ctx)
    text("ICON FAMILY / PROPOSAL 01", x: 88, y: 90, size: 13, hex: "#60708B", weight: .medium, ctx: ctx)
    let columns: [(CGFloat, String, String, String?)] = [
        (88, "Sunshine 3D", "PC host · existing", "/Volumes/Data/repos/Apollo-3D/sunshine3d.png"),
        (500, "Sunlight 3D", "iPhone client + host · proposed", nil),
        (912, "Moonlight 3D", "Android client · existing", "/Volumes/Data/repos/moonlight-android/app/src/main/ic_launcher-web.png")
    ]
    for (x, title, role, path) in columns {
        let rect = CGRect(x: x, y: 155, width: 320, height: 320)
        if let path = path {
            ctx.setFillColor(color(midnight))
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 68.75, cornerHeight: 68.75, transform: nil))
            ctx.fillPath()
            // Source rasters crop the 1024 grid to a 920-unit viewBox.
            let inset: CGFloat = 320 * 52 / 1024
            drawPNG(path, in: rect.insetBy(dx: inset, dy: inset), ctx: ctx)
        } else {
            icon(in: rect, masked: true, ctx: ctx)
        }
        text(title, x: x, y: 496, size: 24, hex: midnight, weight: .semibold, ctx: ctx)
        text(role, x: x, y: 534, size: 16, hex: "#60708B", ctx: ctx)
    }
    ctx.setFillColor(color("#D9E1EC")); ctx.fill(CGRect(x: 88, y: 590, width: 1144, height: 1))
    icon(in: CGRect(x: 88, y: 627, width: 60, height: 60), masked: true, ctx: ctx)
    icon(in: CGRect(x: 164, y: 641, width: 32, height: 32), masked: true, ctx: ctx)
    text("60 px / 32 px", x: 218, y: 648, size: 15, hex: "#60708B", ctx: ctx)
    text("Shared depth layers. Sun + moon identity.", x: 500, y: 631, size: 20, hex: midnight, weight: .medium, ctx: ctx)
    text("Original palette · flat vector geometry · no lettering inside the icon", x: 500, y: 666, size: 15, hex: "#60708B", ctx: ctx)
}
print("Saved Sunlight 3D proposal to \(output.path)")
