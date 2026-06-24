import AppKit
import CoreGraphics
import Foundation

// 渲染 RimeDou 图标设计为 PNG 预览。
// 用法: swift make-icon.swift <dou|dou-mic> <输出.png>

let args = CommandLine.arguments
let design = args.count > 1 ? args[1] : "mono-light"
let outPath = args.count > 2 ? args[2] : "icon.png"
let pixels = (args.count > 3 ? Int(args[3]) : nil) ?? 1024
let S = CGFloat(pixels)

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// 圆角方形（macOS squircle 近似半径 0.2237）
let radius = S * 0.2237
let bgRect = CGRect(x: 0, y: 0, width: S, height: S)
let clip = CGMutablePath()
clip.addRoundedRect(in: bgRect, cornerWidth: radius, cornerHeight: radius)
ctx.addPath(clip)
ctx.clip()

// 配色：经典单色 tile（深/浅两种），无复杂色彩，亮暗模式皆宜
let bgColors: [CGColor]
let glyphColor: NSColor
switch design {
case "mono-light":
    bgColors = [
        CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0),
        CGColor(red: 0.86, green: 0.86, blue: 0.87, alpha: 1.0),
    ]
    glyphColor = NSColor(white: 0.11, alpha: 1.0)
default: // mono-dark 经典深色 tile
    bgColors = [
        CGColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1.0),
        CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1.0),
    ]
    glyphColor = NSColor(white: 0.96, alpha: 1.0)
}
let space = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: space, colors: bgColors as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// 白色“豆”字（dou-mic 时用更小字号并上移让位，避免与右下麦克风重叠）
let beanFontSize = (design == "dou-mic") ? S * 0.46 : S * 0.60
let beanFont = NSFont(name: "PingFangSC-Semibold", size: beanFontSize)
    ?? NSFont.systemFont(ofSize: beanFontSize, weight: .semibold)
let bean = NSAttributedString(string: "豆", attributes: [
    .font: beanFont,
    .foregroundColor: glyphColor,
])
let bs = bean.size()
var beanOriginX = (S - bs.width) / 2
var beanOriginY = (S - bs.height) / 2 - S * 0.02
if design == "dou-mic" {
    beanOriginX -= S * 0.06
    beanOriginY += S * 0.08
}
let beanRect = CGRect(x: beanOriginX, y: beanOriginY, width: bs.width, height: bs.height)
bean.draw(in: beanRect)

// 右下角小麦克风（仅 dou-mic）
if design == "dou-mic" {
    drawMic(in: CGRect(x: S * 0.62, y: S * 0.10, width: S * 0.26, height: S * 0.26))
}

NSGraphicsContext.restoreGraphicsState()

func drawMic(in box: CGRect) {
    let g = NSGraphicsContext.current!
    NSGraphicsContext.saveGraphicsState()
    // 切到 bitmap 上下文绘制（独立函数需在 restore 前调用，这里复用当前 ctx）
    _ = g
    let c = NSGraphicsContext.current!.cgContext
    c.setLineWidth(box.width * 0.12)
    c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    c.setLineCap(.round)
    c.setLineJoin(.round)

    // 头部胶囊
    let headW = box.width * 0.46
    let headH = box.height * 0.52
    let headRect = CGRect(
        x: box.midX - headW / 2,
        y: box.maxY - headH - box.height * 0.04,
        width: headW,
        height: headH
    )
    c.addPath(CGPath(roundedRect: headRect, cornerWidth: headW / 2, cornerHeight: headW / 2, transform: nil))
    c.fillPath()

    // 支架弧（下方托杯，绘制圆的下半弧）
    let arcCenter = CGPoint(x: box.midX, y: box.minY + box.height * 0.40)
    c.addArc(center: arcCenter, radius: box.width * 0.40, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
    c.strokePath()

    // 立柱
    c.move(to: CGPoint(x: box.midX, y: arcCenter.y))
    c.addLine(to: CGPoint(x: box.midX, y: box.minY + box.height * 0.12))
    c.strokePath()

    // 底座
    c.move(to: CGPoint(x: box.midX - box.width * 0.26, y: box.minY + box.height * 0.12))
    c.addLine(to: CGPoint(x: box.midX + box.width * 0.26, y: box.minY + box.height * 0.12))
    c.strokePath()

    NSGraphicsContext.restoreGraphicsState()
}

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to encode png\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print(outPath)
