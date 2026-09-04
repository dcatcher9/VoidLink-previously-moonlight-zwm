#!/usr/bin/env swift
// Resize the approved master into the existing iOS catalog without redesigning it.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["--apply"] || arguments == ["--check"] else {
    fputs("Usage: swift design/sunlight3d-icon/apply-icons.swift --apply|--check\n", stderr)
    exit(2)
}
let design = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repo = design.deletingLastPathComponent().deletingLastPathComponent()
let catalog = repo.appendingPathComponent("VoidLink/Images.xcassets")
let appIcon = catalog.appendingPathComponent("AppIcon.appiconset")
let masterURL = design.appendingPathComponent("sunlight3d-ios-1024.png")
guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil),
      master.width == 1024, master.height == 1024,
      [.none, .noneSkipFirst, .noneSkipLast].contains(master.alphaInfo) else {
    fatalError("The approved master must be an opaque 1024 x 1024 image.")
}

struct Catalog: Decodable {
    struct Image: Decodable {
        let filename: String
        let size: String
        let scale: String
    }
    let images: [Image]
}
let manifest = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: appIcon.appendingPathComponent("Contents.json")))
var targets: [(URL, Int)] = []
for image in manifest.images {
    let size = image.size.split(separator: "x")
    guard size.count == 2, size[0] == size[1],
          let points = Double(size[0]),
          image.scale.hasSuffix("x"), let scale = Double(image.scale.dropLast()),
          points > 0, scale > 0, points * scale <= 1024,
          (points * scale).rounded() == points * scale,
          (image.filename as NSString).lastPathComponent == image.filename else {
        fatalError("Invalid icon slot: \(image.filename)")
    }
    targets.append((appIcon.appendingPathComponent(image.filename), Int(points * scale)))
}
// AboutView uses this independent image rather than the launcher catalog.
targets.append((catalog.appendingPathComponent("AppIconMedium.imageset/AppIconMedium.png"), 360))
guard Set(targets.map { $0.0.path }).count == targets.count,
      targets.allSatisfy({ FileManager.default.fileExists(atPath: $0.0.path) }) else {
    fatalError("Expected unique, existing catalog assets; no files were changed.")
}

func png(size: Int) -> Data {
    if size == 1024 { return try! Data(contentsOf: masterURL) }
    let context = CGContext(data: nil, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
    context.interpolationQuality = .high
    context.draw(master, in: CGRect(x: 0, y: 0, width: size, height: size))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "PNG encoding failed")
    return data as Data
}

// Encode every output before writing any files.
let outputs = targets.map { (url: $0.0, size: $0.1, data: png(size: $0.1)) }
for output in outputs {
    if arguments == ["--apply"] {
        try output.data.write(to: output.url, options: .atomic)
    }
    guard try Data(contentsOf: output.url) == output.data,
          let source = CGImageSourceCreateWithURL(output.url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == output.size, image.height == output.size,
          [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) else {
        fatalError("Icon does not match the approved master: \(output.url.path)")
    }
}
print("Verified \(manifest.images.count) launcher/store assets and the About icon against the approved master.")
