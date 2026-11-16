// Draws the Pe sârmă app icon: a copper wire sagging across a dark tile,
// with two cards pinned to it by wooden clips. Original artwork for this
// edition, drawn entirely in code. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift out.png\n".utf8)); exit(2)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

// Tile: the usual macOS grid, an 824 pt rounded square centred in 1024.
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x000000, 0.45).cgColor)
color(0x1A1D22).setFill(); tilePath.fill()
ctx.restoreGState()
tilePath.addClip()
NSGradient(colors: [color(0x2B3038), color(0x14161A)])!.draw(in: tile, angle: -90)

// Wire: a gentle catenary from the left edge to the right edge.
func wireY(_ x: CGFloat) -> CGFloat {
    let t = (x - tile.minX) / tile.width          // 0...1
    return 700 - 90 * (1 - pow(2 * t - 1, 2))      // sags by 90 pt in the middle
}
let wire = NSBezierPath()
wire.move(to: NSPoint(x: tile.minX - 10, y: wireY(tile.minX)))
for x in stride(from: tile.minX, through: tile.maxX + 10, by: 8) { wire.line(to: NSPoint(x: x, y: wireY(x))) }
wire.lineWidth = 14; wire.lineCapStyle = .round
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 10, color: color(0x000000, 0.5).cgColor)
color(0xC77D3A).setStroke(); wire.stroke()
ctx.restoreGState()
color(0xEBA866, 0.9).setStroke(); wire.lineWidth = 4
wire.transform(using: AffineTransform(translationByX: 0, byY: 3)); wire.stroke()

// A card hung on the wire at x, tilted by degrees.
func card(x: CGFloat, width: CGFloat, height: CGFloat, degrees: CGFloat, fill: [UInt32], lines: Int) {
    let top = wireY(x) - 6
    ctx.saveGState()
    ctx.translateBy(x: x, y: top)
    ctx.rotate(by: degrees * .pi / 180)
    let rect = NSRect(x: -width / 2, y: -height, width: width, height: height)
    let body = NSBezierPath(roundedRect: rect, xRadius: 34, yRadius: 34)
    ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 26, color: color(0x000000, 0.55).cgColor)
    color(fill[0]).setFill(); body.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    NSGradient(colors: [color(fill[0]), color(fill[1])])!.draw(in: body, angle: -90)
    color(0xFFFFFF, 0.35).setStroke(); body.lineWidth = 3; body.stroke()
    // Text lines on the card.
    for i in 0..<lines {
        let y = rect.maxY - 92 - CGFloat(i) * 46
        let w = rect.width - 90 - (i == lines - 1 ? 70 : 0)
        let line = NSBezierPath(roundedRect: NSRect(x: rect.minX + 45, y: y, width: w, height: 16), xRadius: 8, yRadius: 8)
        color(0x2B3038, 0.55).setFill(); line.fill()
    }
    // Wooden clip across the top edge.
    let clip = NSBezierPath(roundedRect: NSRect(x: -30, y: -24, width: 60, height: 70), xRadius: 14, yRadius: 14)
    color(0xB98B5A).setFill(); clip.fill()
    color(0x6E4A27).setStroke(); clip.lineWidth = 4; clip.stroke()
    let slit = NSBezierPath(); slit.move(to: NSPoint(x: 0, y: -24)); slit.line(to: NSPoint(x: 0, y: 34))
    slit.lineWidth = 4; color(0x6E4A27).setStroke(); slit.stroke()
    ctx.restoreGState()
}
card(x: 400, width: 300, height: 380, degrees: 6, fill: [0xF3E6D0, 0xDDC9A8], lines: 4)
card(x: 640, width: 270, height: 330, degrees: -5, fill: [0xE08E4A, 0xB8672A], lines: 3)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
