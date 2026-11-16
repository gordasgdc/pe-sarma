import AppKit

// Menu bar symbol: the approved silhouette (wire, copper clip, photo) reduced to
// one colour, drawn as a template image. Usage: swift MenuSymbol.swift <out-dir>
func render(_ px: Int, _ path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let c = NSGraphicsContext.current!.cgContext
    c.clear(CGRect(x: 0, y: 0, width: px, height: px))
    let s = CGFloat(px) / 36            // design grid: 36 x 36
    c.scaleBy(x: s, y: s)
    NSColor.black.setFill(); NSColor.black.setStroke()
    // photo, tilted, hanging from the wire
    c.saveGState()
    c.translateBy(x: 18, y: 16); c.rotate(by: -0.095); c.translateBy(x: -18, y: -16)
    let card = NSBezierPath(roundedRect: CGRect(x: 8.5, y: 3, width: 19, height: 17), xRadius: 3, yRadius: 3)
    card.fill()
    // landscape cut out of the photo
    c.setBlendMode(.clear)
    let hill = NSBezierPath()
    hill.move(to: CGPoint(x: 11, y: 5.5)); hill.line(to: CGPoint(x: 15, y: 11))
    hill.line(to: CGPoint(x: 18.5, y: 8.5)); hill.line(to: CGPoint(x: 21, y: 10.5))
    hill.line(to: CGPoint(x: 25, y: 7)); hill.line(to: CGPoint(x: 25, y: 5.5)); hill.close()
    hill.fill()
    NSBezierPath(ovalIn: CGRect(x: 21, y: 13, width: 3, height: 3)).fill()
    c.setBlendMode(.normal)
    c.restoreGState()
    // wire
    let wire = NSBezierPath()
    wire.move(to: CGPoint(x: 1, y: 27)); wire.curve(to: CGPoint(x: 35, y: 27),
        controlPoint1: CGPoint(x: 12, y: 22.5), controlPoint2: CGPoint(x: 24, y: 22.5))
    wire.lineWidth = 2; wire.lineCapStyle = .round; wire.stroke()
    // clip, with a gap around it so it reads against the photo
    c.saveGState()
    c.translateBy(x: 18, y: 22.5); c.rotate(by: -0.095); c.translateBy(x: -18, y: -22.5)
    c.setBlendMode(.clear)
    NSBezierPath(roundedRect: CGRect(x: 13.3, y: 15, width: 9.4, height: 17), xRadius: 4.7, yRadius: 4.7).fill()
    c.setBlendMode(.normal)
    NSBezierPath(roundedRect: CGRect(x: 14.6, y: 16.3, width: 6.8, height: 14.4), xRadius: 3.4, yRadius: 3.4).fill()
    c.restoreGState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
let out = CommandLine.arguments[1]
try render(36, out + "/StatusIcon@2x.png")
try render(18, out + "/StatusIcon.png")
try render(72, out + "/StatusIcon-preview.png")
