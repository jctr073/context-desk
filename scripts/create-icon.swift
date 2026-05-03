#!/usr/bin/env swift

import AppKit
import Foundation

let outputURL: URL
if CommandLine.arguments.count > 1 {
    outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    outputURL = URL(fileURLWithPath: ".build/app-icon.iconset")
}

try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let baseSize: CGFloat = 1024

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, in size: CGFloat) -> NSRect {
    let scale = size / baseSize
    return NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, in size: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect(x, y, width, height, in: size), xRadius: radius * size / baseSize, yRadius: radius * size / baseSize)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()

    let background = roundedRect(96, 96, 832, 832, 190, in: size)
    NSGradient(colors: [
        NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1),
        NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    ])?.draw(in: background, angle: -34)

    NSColor(calibratedWhite: 1.0, alpha: 0.32).setStroke()
    background.lineWidth = max(2, size / 120)
    background.stroke()

    let shadow = NSBezierPath(ovalIn: rect(238, 126, 548, 48, in: size))
    NSColor(calibratedWhite: 0, alpha: 0.16).setFill()
    shadow.fill()

    let page = roundedRect(248, 184, 528, 656, 58, in: size)
    NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
    page.fill()

    NSColor(calibratedWhite: 0, alpha: 0.12).setStroke()
    page.lineWidth = max(2, size / 180)
    page.stroke()

    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 636 * size / baseSize, y: 840 * size / baseSize))
    fold.line(to: NSPoint(x: 776 * size / baseSize, y: 700 * size / baseSize))
    fold.line(to: NSPoint(x: 636 * size / baseSize, y: 700 * size / baseSize))
    fold.close()
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    fold.fill()

    NSColor(calibratedWhite: 0.74, alpha: 1).setStroke()
    fold.lineWidth = max(2, size / 190)
    fold.stroke()

    let titleLine = roundedRect(326, 692, 236, 30, 15, in: size)
    NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1).setFill()
    titleLine.fill()

    for index in 0..<4 {
        let y = CGFloat(606 - index * 82)
        let lineWidth = index == 3 ? CGFloat(246) : CGFloat(388)
        let line = roundedRect(326, y, lineWidth, 24, 12, in: size)
        NSColor(calibratedWhite: 0.70, alpha: 1).setFill()
        line.fill()
    }

    let highlight = roundedRect(326, 350, 300, 30, 15, in: size)
    NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 0.34).setFill()
    highlight.fill()

    let pencil = NSBezierPath()
    pencil.move(to: NSPoint(x: 540 * size / baseSize, y: 286 * size / baseSize))
    pencil.line(to: NSPoint(x: 724 * size / baseSize, y: 470 * size / baseSize))
    pencil.line(to: NSPoint(x: 674 * size / baseSize, y: 520 * size / baseSize))
    pencil.line(to: NSPoint(x: 490 * size / baseSize, y: 336 * size / baseSize))
    pencil.close()
    NSColor(calibratedRed: 1.00, green: 0.80, blue: 0.20, alpha: 1).setFill()
    pencil.fill()

    let pencilEdge = NSBezierPath()
    pencilEdge.move(to: NSPoint(x: 490 * size / baseSize, y: 336 * size / baseSize))
    pencilEdge.line(to: NSPoint(x: 540 * size / baseSize, y: 286 * size / baseSize))
    pencilEdge.line(to: NSPoint(x: 512 * size / baseSize, y: 254 * size / baseSize))
    pencilEdge.close()
    NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
    pencilEdge.fill()

    let eraser = NSBezierPath()
    eraser.move(to: NSPoint(x: 676 * size / baseSize, y: 518 * size / baseSize))
    eraser.line(to: NSPoint(x: 724 * size / baseSize, y: 470 * size / baseSize))
    eraser.line(to: NSPoint(x: 756 * size / baseSize, y: 502 * size / baseSize))
    eraser.line(to: NSPoint(x: 708 * size / baseSize, y: 550 * size / baseSize))
    eraser.close()
    NSColor(calibratedRed: 1.00, green: 0.42, blue: 0.55, alpha: 1).setFill()
    eraser.fill()

    let sparkle = NSBezierPath()
    sparkle.move(to: NSPoint(x: 274 * size / baseSize, y: 784 * size / baseSize))
    sparkle.line(to: NSPoint(x: 294 * size / baseSize, y: 736 * size / baseSize))
    sparkle.line(to: NSPoint(x: 342 * size / baseSize, y: 716 * size / baseSize))
    sparkle.line(to: NSPoint(x: 294 * size / baseSize, y: 696 * size / baseSize))
    sparkle.line(to: NSPoint(x: 274 * size / baseSize, y: 648 * size / baseSize))
    sparkle.line(to: NSPoint(x: 254 * size / baseSize, y: 696 * size / baseSize))
    sparkle.line(to: NSPoint(x: 206 * size / baseSize, y: 716 * size / baseSize))
    sparkle.line(to: NSPoint(x: 254 * size / baseSize, y: 736 * size / baseSize))
    sparkle.close()
    NSColor.white.setFill()
    sparkle.fill()

    image.unlockFocus()
    return image
}

func writePNG(size: CGFloat, fileName: String) throws {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputURL.appendingPathComponent(fileName))
}

try writePNG(size: 16, fileName: "icon_16x16.png")
try writePNG(size: 32, fileName: "icon_16x16@2x.png")
try writePNG(size: 32, fileName: "icon_32x32.png")
try writePNG(size: 64, fileName: "icon_32x32@2x.png")
try writePNG(size: 128, fileName: "icon_128x128.png")
try writePNG(size: 256, fileName: "icon_128x128@2x.png")
try writePNG(size: 256, fileName: "icon_256x256.png")
try writePNG(size: 512, fileName: "icon_256x256@2x.png")
try writePNG(size: 512, fileName: "icon_512x512.png")
try writePNG(size: 1024, fileName: "icon_512x512@2x.png")
