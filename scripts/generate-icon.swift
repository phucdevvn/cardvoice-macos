import AppKit
import Foundation

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : ".build/AppIcon-Source.png"

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
defer { image.unlockFocus() }

let bounds = NSRect(origin: .zero, size: size)
NSColor.clear.setFill()
bounds.fill()

let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 210, yRadius: 210)
background.addClip()
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.10, green: 0.33, blue: 0.86, alpha: 1.0),
    NSColor(calibratedRed: 0.32, green: 0.18, blue: 0.72, alpha: 1.0)
])!
gradient.draw(in: bounds, angle: -90)

let glow = NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.clear)!
glow.draw(in: NSRect(x: 160, y: 540, width: 700, height: 330), relativeCenterPosition: NSPoint(x: 0.0, y: 0.1))

NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
shadow.shadowBlurRadius = 28
shadow.shadowOffset = NSSize(width: 0, height: -18)
shadow.set()

let bubbleRect = NSRect(x: 205, y: 275, width: 620, height: 470)
let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 120, yRadius: 120)
NSColor.white.setFill()
bubble.fill()

let tail = NSBezierPath()
tail.move(to: NSPoint(x: 300, y: 318))
tail.line(to: NSPoint(x: 222, y: 230))
tail.line(to: NSPoint(x: 380, y: 292))
tail.close()
NSColor.white.setFill()
tail.fill()
NSGraphicsContext.current?.restoreGraphicsState()

let barHeights: [CGFloat] = [120, 220, 320, 260, 180, 110]
let barColors: [NSColor] = [
    NSColor(calibratedRed: 0.55, green: 0.28, blue: 0.95, alpha: 1),
    NSColor(calibratedRed: 0.42, green: 0.34, blue: 0.96, alpha: 1),
    NSColor(calibratedRed: 0.26, green: 0.45, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.15, green: 0.58, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.94, alpha: 1),
    NSColor(calibratedRed: 0.12, green: 0.82, blue: 0.90, alpha: 1)
]

let barWidth: CGFloat = 44
let spacing: CGFloat = 28
let totalWidth = CGFloat(barHeights.count) * barWidth + CGFloat(barHeights.count - 1) * spacing
var x = (1024 - totalWidth) / 2
let centerY: CGFloat = 505

for (height, color) in zip(barHeights, barColors) {
    let rect = NSRect(x: x, y: centerY - height / 2, width: barWidth, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
    color.setFill()
    path.fill()
    x += barWidth + spacing
}

NSGraphicsContext.current?.saveGraphicsState()
let boltShadow = NSShadow()
boltShadow.shadowColor = NSColor.orange.withAlphaComponent(0.35)
boltShadow.shadowBlurRadius = 20
boltShadow.shadowOffset = NSSize(width: 0, height: -6)
boltShadow.set()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 700, y: 420))
bolt.line(to: NSPoint(x: 790, y: 420))
bolt.line(to: NSPoint(x: 748, y: 320))
bolt.line(to: NSPoint(x: 840, y: 320))
bolt.line(to: NSPoint(x: 690, y: 150))
bolt.line(to: NSPoint(x: 724, y: 285))
bolt.line(to: NSPoint(x: 648, y: 285))
bolt.close()

let boltGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.0, green: 0.84, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.08, alpha: 1)
])!
boltGradient.draw(in: bolt, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: url)
print("Generated icon: \(url.path)")
