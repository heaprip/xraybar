// Draws XrayBar's app icon (its mark, white on a black rounded square, macOS icon grid) into an
// .iconset folder for `iconutil`. Run by make-app.sh, so the repository holds no binary images.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

/// The mark's petal, as `Mark.petal` in 8-Menu.swift (a narrower gap: the icon is drawn large).
func petal(_ i: Int, in r: NSRect) -> NSBezierPath {
    let radius = r.width / 2, inner = radius * 0.07, w = radius * 0.30, m = radius * 0.34
    let p = NSBezierPath()
    p.move(to: NSPoint(x: 0, y: inner))
    p.line(to: NSPoint(x: w, y: m))
    p.curve(to: NSPoint(x: 0, y: radius), controlPoint1: NSPoint(x: w * 0.45, y: m + (radius - m) * 0.3),
            controlPoint2: NSPoint(x: w * 0.12, y: radius * 0.8))
    p.curve(to: NSPoint(x: -w, y: m), controlPoint1: NSPoint(x: -w * 0.12, y: radius * 0.8),
            controlPoint2: NSPoint(x: -w * 0.45, y: m + (radius - m) * 0.3))
    p.close()
    var t = AffineTransform(translationByX: r.midX, byY: r.midY)
    t.rotate(byDegrees: CGFloat(-90 * i))
    p.transform(using: t)
    return p
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels)
    // Apple's grid: the shape is 80% of the canvas, corner radius ~22.5% of the shape.
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18).fill()
    NSColor.white.setFill()
    for i in 0..<4 { petal(i, in: tile.insetBy(dx: s * 0.13, dy: s * 0.13)).fill() }
    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
