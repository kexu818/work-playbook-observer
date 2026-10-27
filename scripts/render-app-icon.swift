import AppKit

// macOS displays custom runtime icons as supplied. Normalize the approved
// full-bleed artwork to an icon canvas, with transparent padding and corners.
guard CommandLine.arguments.count == 3,
      let source = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Expected source artwork and destination PNG paths")
}
bitmap.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill(using: .copy)
let face = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: face, xRadius: 184, yRadius: 184)
shape.addClip()
source.draw(in: face, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode application icon")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
