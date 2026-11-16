import AppKit

func ink(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: alpha)
}

func panel(_ rect: CGRect, radius: CGFloat, colors: [UInt32], angle: CGFloat = 90) {
    let outline = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(colors: colors.map { ink($0) })!.draw(in: outline, angle: angle)
}

func line(_ from: CGPoint, _ to: CGPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: from)
    path.line(to: to)
    path.lineWidth = width
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}

func export(_ width: Int, _ height: Int, _ name: String, draw: (CGContext) -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw(context)
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
}

func icon(_ context: CGContext) {
    let tile = CGRect(x: 76, y: 76, width: 872, height: 872)
    let edge = NSBezierPath(roundedRect: tile, xRadius: 205, yRadius: 205)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -17), blur: 31, color: ink(0x10191C, 0.3).cgColor)
    ink(0x17272A).setFill()
    edge.fill()
    context.restoreGState()

    context.saveGState()
    edge.addClip()
    panel(tile, radius: 205, colors: [0x101E22, 0x254348, 0x496769], angle: 72)
    ink(0x86A0A0, 0.45).setStroke()
    edge.lineWidth = 5
    edge.stroke()

    let card = CGRect(x: 316, y: 221, width: 392, height: 383)
    context.saveGState()
    context.translateBy(x: 512, y: 525)
    context.rotate(by: -0.095)
    context.translateBy(x: -512, y: -525)
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 31, color: ink(0x071518, 0.63).cgColor)
    ink(0xE5E5D8).setFill()
    NSBezierPath(roundedRect: card, xRadius: 45, yRadius: 45).fill()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    panel(card, radius: 45, colors: [0xA8B5AF, 0xDBE1D7, 0xF7F5E9], angle: 104)
    panel(CGRect(x: 350, y: 271, width: 324, height: 259), radius: 22,
          colors: [0x45676A, 0x7E9E9C, 0xAFC0AE], angle: 78)
    let landscape = NSBezierPath()
    landscape.move(to: CGPoint(x: 350, y: 306))
    landscape.line(to: CGPoint(x: 450, y: 428))
    landscape.curve(to: CGPoint(x: 553, y: 350), controlPoint1: CGPoint(x: 469, y: 451),
                    controlPoint2: CGPoint(x: 509, y: 376))
    landscape.line(to: CGPoint(x: 620, y: 395))
    landscape.line(to: CGPoint(x: 674, y: 343))
    landscape.line(to: CGPoint(x: 674, y: 271))
    landscape.line(to: CGPoint(x: 350, y: 271))
    landscape.close()
    context.saveGState()
    NSBezierPath(roundedRect: CGRect(x: 350, y: 271, width: 324, height: 259), xRadius: 22, yRadius: 22).addClip()
    ink(0x244A4E).setFill()
    landscape.fill()
    ink(0xF7CE8A).setFill()
    NSBezierPath(ovalIn: CGRect(x: 568, y: 434, width: 49, height: 49)).fill()
    context.restoreGState()
    context.restoreGState()

    let wire = NSBezierPath()
    wire.move(to: CGPoint(x: 70, y: 685))
    wire.curve(to: CGPoint(x: 954, y: 685), controlPoint1: CGPoint(x: 350, y: 565),
               controlPoint2: CGPoint(x: 674, y: 565))
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -5), blur: 7, color: ink(0x061217, 0.82).cgColor)
    wire.lineWidth = 19
    ink(0x52382C).setStroke()
    wire.stroke()
    context.restoreGState()
    wire.lineWidth = 11
    ink(0xD5A16F).setStroke()
    wire.stroke()
    wire.lineWidth = 3
    ink(0xF5D0A4).setStroke()
    wire.stroke()

    context.saveGState()
    context.translateBy(x: 512, y: 617)
    context.rotate(by: -0.095)
    context.translateBy(x: -512, y: -617)
    let clip = CGRect(x: 444, y: 519, width: 136, height: 259)
    let shell = NSBezierPath(roundedRect: clip, xRadius: 48, yRadius: 48)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -11), blur: 15, color: ink(0x161512, 0.6).cgColor)
    ink(0x683A28).setFill()
    shell.fill()
    context.restoreGState()
    panel(clip, radius: 48, colors: [0x713923, 0xBA673F, 0xECA36E, 0xFFCC94], angle: 41)
    shell.lineWidth = 4
    ink(0xFED2A7, 0.75).setStroke()
    shell.stroke()
    line(CGPoint(x: 477, y: 710), CGPoint(x: 477, y: 743), width: 8, color: ink(0xFFF0D5, 0.8))
    panel(CGRect(x: 472, y: 622, width: 80, height: 29), radius: 14,
          colors: [0x472A22, 0x9C5131], angle: 90)
    line(CGPoint(x: 486, y: 627), CGPoint(x: 540, y: 627), width: 3, color: ink(0xEFB585))
    context.restoreGState()
    context.restoreGState()
}

let output = CommandLine.arguments[1]
try export(1024, 1024, output + "/PeSarma-Simbol.png", draw: icon)
try export(1560, 560, output + "/PeSarma-Logotip.png") { context in
    panel(CGRect(x: 0, y: 0, width: 1560, height: 560), radius: 36,
          colors: [0xE8ECE6, 0xF7F5ED], angle: 70)
    context.saveGState()
    context.translateBy(x: 62, y: 50)
    context.scaleBy(x: 0.45, y: 0.45)
    icon(context)
    context.restoreGState()
    let font = NSFont(name: "AvenirNext-DemiBold", size: 146) ?? .systemFont(ofSize: 146, weight: .semibold)
    let wordmark = NSAttributedString(string: "Pe sârmă", attributes: [
        .font: font, .foregroundColor: ink(0x142D30), .kern: -5
    ])
    wordmark.draw(at: CGPoint(x: 580, y: (560 - wordmark.size().height) / 2))
}
