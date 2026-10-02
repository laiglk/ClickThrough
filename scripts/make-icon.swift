import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var chunks = Data()
func bigEndian(_ value: Int) -> Data {
    var integer = UInt32(value).bigEndian
    return withUnsafeBytes(of: &integer) { Data($0) }
}
let types = [16: ["icp4", "ic11"], 32: ["icp5", "ic12"],
             128: ["ic07", "ic13"], 256: ["ic08", "ic14"], 512: ["ic09", "ic10"]]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let size = CGFloat(pixels)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let inset = size * 0.08
        let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.18, yRadius: size * 0.18).fill()
        if let symbol = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [.white])) {
            symbol.draw(in: NSRect(x: size * 0.24, y: size * 0.24, width: size * 0.52, height: size * 0.52))
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let file = destination.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: file)
        chunks.append(Data(types[points]![scale - 1].utf8))
        chunks.append(bigEndian(png.count + 8))
        chunks.append(png)
    }
}
// ICNS supports PNG payloads; write the container directly so the build does not
// depend on iconutil's system image-conversion services being available.
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
