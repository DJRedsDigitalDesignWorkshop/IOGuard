#!/usr/bin/env swift
// IOGuard icon artwork, drawn with Core Graphics so every size stays crisp.
// Run from the project root after compiling with:
// swiftc -module-cache-path /private/tmp/ioguard-icon-cache scripts/make-icon.swift -o /private/tmp/make-ioguard-icon
// /private/tmp/make-ioguard-icon
// On some macOS hosts, iconutil must run outside a sandboxed shell to write the ICNS file.

import AppKit
import CoreGraphics
import Foundation
import ImageIO

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red, green: green, blue: blue, alpha: alpha)
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    )!
}

private func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

private func fillRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, _ fill: CGColor) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setFillColor(fill)
    context.fillPath()
}

private func strokeRounded(_ context: CGContext, _ rect: CGRect, radius: CGFloat, width: CGFloat, _ stroke: CGColor) {
    context.addPath(roundedPath(rect, radius: radius))
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.strokePath()
}

private func fillEllipse(_ context: CGContext, center: CGPoint, radius: CGFloat, _ fill: CGColor) {
    context.setFillColor(fill)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

private func strokeEllipse(_ context: CGContext, center: CGPoint, radius: CGFloat, width: CGFloat, _ stroke: CGColor) {
    context.setStrokeColor(stroke)
    context.setLineWidth(width)
    context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

private func drawRadial(_ context: CGContext, center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat, colors: [CGColor]) {
    context.drawRadialGradient(
        gradient(colors, locations: [0, 1]),
        startCenter: center,
        startRadius: innerRadius,
        endCenter: center,
        endRadius: outerRadius,
        options: []
    )
}

private func drawSpeaker(_ context: CGContext, x: CGFloat) {
    let cabinet = CGRect(x: x, y: 204, width: 350, height: 612)
    let cabinetPath = roundedPath(cabinet, radius: 42)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -16), blur: 30, color: color(0.015, 0.08, 0.10, 0.42))
    context.addPath(cabinetPath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.12, 0.28, 0.34), color(0.035, 0.12, 0.17)], locations: [0, 1]),
        start: CGPoint(x: x, y: 816),
        end: CGPoint(x: x + 350, y: 204),
        options: []
    )
    context.restoreGState()

    context.addPath(cabinetPath)
    context.setStrokeColor(color(0.49, 0.80, 0.80, 0.30))
    context.setLineWidth(3)
    context.strokePath()

    // Slim inset rails make the pair read as individual speaker cabinets.
    context.setFillColor(color(0.66, 0.94, 0.89, 0.09))
    context.fill(CGRect(x: x + 22, y: 250, width: 4, height: 515))
    context.fill(CGRect(x: x + 324, y: 250, width: 4, height: 515))
    strokeRounded(context, CGRect(x: x + 28, y: 765, width: 294, height: 2), radius: 1, width: 2, color(0.70, 0.95, 0.89, 0.14))

    let tweeter = CGPoint(x: x + 175, y: 700)
    fillEllipse(context, center: tweeter, radius: 45, color(0.018, 0.075, 0.093))
    strokeEllipse(context, center: tweeter, radius: 41, width: 5, color(0.40, 0.72, 0.72, 0.56))
    drawRadial(context, center: tweeter, innerRadius: 2, outerRadius: 34, colors: [color(0.31, 0.53, 0.57), color(0.055, 0.16, 0.20)])
    fillEllipse(context, center: tweeter, radius: 12, color(0.62, 0.86, 0.81, 0.48))
    fillEllipse(context, center: CGPoint(x: tweeter.x - 4, y: tweeter.y + 5), radius: 3.8, color(0.87, 0.99, 0.94, 0.56))

    let woofer = CGPoint(x: x + 175, y: 520)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0.005, 0.035, 0.05, 0.66))
    fillEllipse(context, center: woofer, radius: 128, color(0.018, 0.065, 0.082))
    context.restoreGState()
    strokeEllipse(context, center: woofer, radius: 122, width: 9, color(0.48, 0.75, 0.74, 0.78))
    drawRadial(context, center: woofer, innerRadius: 30, outerRadius: 112, colors: [color(0.28, 0.48, 0.51), color(0.06, 0.16, 0.20)])
    strokeEllipse(context, center: woofer, radius: 92, width: 7, color(0.63, 0.88, 0.83, 0.32))
    drawRadial(context, center: woofer, innerRadius: 3, outerRadius: 83, colors: [color(0.28, 0.43, 0.47), color(0.035, 0.105, 0.13)])
    strokeEllipse(context, center: woofer, radius: 76, width: 3, color(0.77, 0.95, 0.89, 0.16))
    drawRadial(context, center: CGPoint(x: woofer.x - 4, y: woofer.y + 5), innerRadius: 1, outerRadius: 32, colors: [color(0.44, 0.64, 0.64), color(0.07, 0.20, 0.23)])
    fillEllipse(context, center: CGPoint(x: woofer.x - 11, y: woofer.y + 18), radius: 6, color(0.88, 0.99, 0.94, 0.34))
}

private func drawLock(_ context: CGContext) {
    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: 418, y: 474))
    shackle.addLine(to: CGPoint(x: 418, y: 609))
    shackle.addCurve(to: CGPoint(x: 606, y: 609), control1: CGPoint(x: 418, y: 770), control2: CGPoint(x: 606, y: 770))
    shackle.addLine(to: CGPoint(x: 606, y: 474))

    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.addPath(shackle)
    context.setStrokeColor(color(0.012, 0.095, 0.12, 0.94))
    context.setLineWidth(88)
    context.strokePath()
    context.addPath(shackle)
    context.setStrokeColor(color(0.29, 0.91, 0.73))
    context.setLineWidth(62)
    context.strokePath()
    context.addPath(shackle)
    context.setStrokeColor(color(0.73, 1.0, 0.88, 0.65))
    context.setLineWidth(10)
    context.strokePath()
    context.restoreGState()

    let body = CGRect(x: 316, y: 230, width: 392, height: 316)
    let bodyPath = roundedPath(body, radius: 66)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: color(0.0, 0.055, 0.07, 0.65))
    context.addPath(bodyPath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.49, 1.0, 0.80), color(0.19, 0.77, 0.63)], locations: [0, 1]),
        start: CGPoint(x: body.minX, y: body.maxY),
        end: CGPoint(x: body.maxX, y: body.minY),
        options: []
    )
    context.restoreGState()
    context.addPath(bodyPath)
    context.setStrokeColor(color(0.78, 1.0, 0.90, 0.93))
    context.setLineWidth(5)
    context.strokePath()

    // A soft inset gleam keeps the lock bright without losing its shape at small sizes.
    context.setStrokeColor(color(0.93, 1.0, 0.96, 0.28))
    context.setLineWidth(4)
    context.move(to: CGPoint(x: 374, y: 506))
    context.addLine(to: CGPoint(x: 650, y: 506))
    context.strokePath()

    let keyhole = CGPoint(x: 512, y: 390)
    fillEllipse(context, center: keyhole, radius: 38, color(0.035, 0.22, 0.22, 0.95))
    let keyholeStem = CGMutablePath()
    keyholeStem.move(to: CGPoint(x: 489, y: 385))
    keyholeStem.addLine(to: CGPoint(x: 535, y: 385))
    keyholeStem.addLine(to: CGPoint(x: 550, y: 310))
    keyholeStem.addQuadCurve(to: CGPoint(x: 474, y: 310), control: CGPoint(x: 512, y: 275))
    keyholeStem.closeSubpath()
    context.addPath(keyholeStem)
    context.setFillColor(color(0.035, 0.22, 0.22, 0.95))
    context.fillPath()
    fillEllipse(context, center: CGPoint(x: 501, y: 404), radius: 7, color(0.68, 0.98, 0.83, 0.28))
}

private func renderAppIcon(size: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tile = CGRect(x: 24, y: 24, width: 976, height: 976)
    let tilePath = roundedPath(tile, radius: 204)
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(
        gradient([color(0.055, 0.17, 0.23), color(0.018, 0.075, 0.11)], locations: [0, 1]),
        start: CGPoint(x: 160, y: 1000),
        end: CGPoint(x: 860, y: 24),
        options: []
    )
    drawRadial(context, center: CGPoint(x: 512, y: 660), innerRadius: 15, outerRadius: 610, colors: [color(0.13, 0.48, 0.51, 0.24), color(0.08, 0.31, 0.40, 0)])

    // Quiet background striations give the dark teal field a machined finish.
    context.setStrokeColor(color(0.58, 0.88, 0.84, 0.045))
    context.setLineWidth(2)
    for y in stride(from: 80, through: 940, by: 42) {
        context.move(to: CGPoint(x: 35, y: CGFloat(y)))
        context.addLine(to: CGPoint(x: 989, y: CGFloat(y)))
    }
    context.strokePath()
    context.restoreGState()

    // A subtle outer edge preserves the rounded-square silhouette on dark desktops.
    strokeRounded(context, tile, radius: 204, width: 5, color(0.46, 0.77, 0.78, 0.22))
    drawSpeaker(context, x: 112)
    drawSpeaker(context, x: 562)
    drawLock(context)
    return context.makeImage()!
}

private func renderMenuBarTemplate(size: Int) -> CGImage {
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: CGFloat(size) / 36, y: CGFloat(size) / 36)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    let ink = color(0, 0, 0)

    // Stereo cabinets and cones, cut through so macOS can tint the template.
    fillRounded(context, CGRect(x: 3.5, y: 4, width: 13.5, height: 28), radius: 2.3, ink)
    fillRounded(context, CGRect(x: 19, y: 4, width: 13.5, height: 28), radius: 2.3, ink)
    context.setBlendMode(.clear)
    fillEllipse(context, center: CGPoint(x: 10.25, y: 15), radius: 4.3, color(0, 0, 0, 0))
    fillEllipse(context, center: CGPoint(x: 25.75, y: 15), radius: 4.3, color(0, 0, 0, 0))
    fillEllipse(context, center: CGPoint(x: 10.25, y: 25.8), radius: 1.6, color(0, 0, 0, 0))
    fillEllipse(context, center: CGPoint(x: 25.75, y: 25.8), radius: 1.6, color(0, 0, 0, 0))
    context.setBlendMode(.normal)

    let shackle = CGMutablePath()
    shackle.move(to: CGPoint(x: 14.1, y: 13.2))
    shackle.addLine(to: CGPoint(x: 14.1, y: 23.8))
    shackle.addCurve(to: CGPoint(x: 21.9, y: 23.8), control1: CGPoint(x: 14.1, y: 31.7), control2: CGPoint(x: 21.9, y: 31.7))
    shackle.addLine(to: CGPoint(x: 21.9, y: 13.2))
    context.addPath(shackle)
    context.setStrokeColor(ink)
    context.setLineWidth(3.2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    fillRounded(context, CGRect(x: 11, y: 6.4, width: 14, height: 11.2), radius: 2.7, ink)

    // The negative keyhole keeps the silhouette recognizable at status-item size.
    context.setBlendMode(.clear)
    fillEllipse(context, center: CGPoint(x: 18, y: 12.9), radius: 1.15, color(0, 0, 0, 0))
    context.fill(CGRect(x: 17.35, y: 8.1, width: 1.3, height: 4.6))
    context.setBlendMode(.normal)
    return context.makeImage()!
}

private func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw NSError(domain: "IOGuardIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create PNG destination at \(url.path)"])
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "IOGuardIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not finish PNG at \(url.path)"])
    }
}

private func generateIcons(root: URL) throws {
    let assets = root.appendingPathComponent("Assets", isDirectory: true)
    let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    try writePNG(renderAppIcon(size: 1024), to: assets.appendingPathComponent("AppIcon.png"))
    let iconSizes: [(String, Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
    ]
    for (filename, size) in iconSizes {
        try writePNG(renderAppIcon(size: size), to: iconset.appendingPathComponent(filename))
    }
    try writePNG(renderMenuBarTemplate(size: 18), to: assets.appendingPathComponent("MenuBarIconTemplate.png"))
    try writePNG(renderMenuBarTemplate(size: 36), to: assets.appendingPathComponent("MenuBarIconTemplate@2x.png"))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path, "-o", assets.appendingPathComponent("AppIcon.icns").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "IOGuardIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"])
    }
    print("Created AppIcon.icns, AppIcon.png, and menu bar templates in \(assets.path)")
}

do {
    let root = CommandLine.arguments.count > 1
        ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        : URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    try generateIcons(root: root)
} catch {
    fputs("Icon generation failed: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
