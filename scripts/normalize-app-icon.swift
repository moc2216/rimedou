import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 || arguments.count == 4 else {
    fputs("usage: normalize-app-icon.swift <input.png> <output.png> [canvas-scale]\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let canvasScale = arguments.count == 4 ? (Double(arguments[3]) ?? 0.88) : 0.88
let outputSize = 1024
let bytesPerPixel = 4
let bytesPerRow = outputSize * bytesPerPixel
var finalPixels = [UInt8](repeating: 0, count: outputSize * bytesPerRow)

guard canvasScale > 0, canvasScale <= 1 else {
    fputs("canvas-scale must be greater than 0 and less than or equal to 1\n", stderr)
    exit(2)
}

guard let image = NSImage(contentsOf: inputURL),
      let finalContext = CGContext(
        data: &finalPixels,
        width: outputSize,
        height: outputSize,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fputs("failed to prepare icon normalization\n", stderr)
    exit(1)
}

let scaledSize = Double(outputSize) * canvasScale
let inset = (Double(outputSize) - scaledSize) / 2
finalContext.interpolationQuality = .high
finalContext.clear(CGRect(x: 0, y: 0, width: outputSize, height: outputSize))
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: finalContext, flipped: false)
image.draw(
    in: NSRect(x: inset, y: inset, width: scaledSize, height: scaledSize),
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high]
)
NSGraphicsContext.restoreGraphicsState()

guard let outputImage = finalContext.makeImage() else {
    fputs("failed to render normalized icon\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("failed to finalize normalized icon\n", stderr)
    exit(1)
}
