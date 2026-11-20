// Renders the app icon: a dark macOS squircle with the menu bar pill in the brand color.
// Usage: swift scripts/make-icon.swift <hex color> <SF Symbol name> <out.png>
// scripts/make-icon.sh turns the 1024 px PNG into Resources/AppIcon.icns.
import AppKit

let args = CommandLine.arguments
guard args.count == 4, let hex = UInt32(args[1], radix: 16) else {
    print("usage: make-icon.swift <hex> <symbol> <out.png>"); exit(1)
}
func color(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: a)
}
let brand = color(hex)
let amber = color(0xEF9F27)
let size: CGFloat = 1024

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Apple icon grid: 824 px body inset 100 px, corner radius ~185 px.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Drop shadow under the body.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor.black.setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

// Body: near-black gradient with a faint brand glow at the top.
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(starting: color(0x26272B), ending: color(0x0B0B0D))!.draw(in: body, angle: -90)
NSGradient(colors: [brand.withAlphaComponent(0.35), brand.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 512, y: 700), radius: 0, toCenter: NSPoint(x: 512, y: 700), radius: 520, options: [])
NSGraphicsContext.restoreGraphicsState()

// Inner hairline.
color(0xFFFFFF, 0.08).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
rim.lineWidth = 4
rim.stroke()

// The pill: black capsule with a brand stroke and soft glow.
let pill = NSRect(x: 182, y: 412, width: 660, height: 236)
let capsule = NSBezierPath(roundedRect: pill, xRadius: 118, yRadius: 118)
NSGraphicsContext.saveGraphicsState()
let glow = NSShadow()
glow.shadowColor = brand.withAlphaComponent(0.75)
glow.shadowBlurRadius = 60
glow.set()
NSColor.black.setFill()
capsule.fill()
NSGraphicsContext.restoreGraphicsState()
brand.setStroke()
capsule.lineWidth = 16
capsule.stroke()

// Brand symbol on the left of the pill.
let config = NSImage.SymbolConfiguration(pointSize: 220, weight: .bold)
    .applying(.init(paletteColors: [brand]))
if let symbol = NSImage(systemSymbolName: args[2], accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    let scale = min(190 / s.width, 170 / s.height)
    let w = s.width * scale, h = s.height * scale
    symbol.draw(in: NSRect(x: 320 - w / 2, y: pill.midY - h / 2, width: w, height: h))
}

// Status dot with a halo: "the agent is waiting for you".
let dotCenter = NSPoint(x: 620, y: pill.midY)
amber.withAlphaComponent(0.25).setFill()
NSBezierPath(ovalIn: NSRect(x: dotCenter.x - 78, y: dotCenter.y - 78, width: 156, height: 156)).fill()
amber.setFill()
NSBezierPath(ovalIn: NSRect(x: dotCenter.x - 50, y: dotCenter.y - 50, width: 100, height: 100)).fill()

// Two "status text" bars under the pill.
color(0xFFFFFF, 0.16).setFill()
NSBezierPath(roundedRect: NSRect(x: 262, y: 300, width: 500, height: 34), xRadius: 17, yRadius: 17).fill()
color(0xFFFFFF, 0.09).setFill()
NSBezierPath(roundedRect: NSRect(x: 342, y: 240, width: 340, height: 30), xRadius: 15, yRadius: 15).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
print("Wrote \(args[3])")
