// Zeichnet das App-Icon der Config-App und legt alle macOS-Größen im Asset-Katalog ab.
// Aufruf aus dem Repo-Wurzelverzeichnis: swift Tools/make-app-icon.swift
import AppKit

let out = "ConfigApp/Assets.xcassets/AppIcon.appiconset"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s, y: s)

    // Grundform nach Apples Icon-Raster: 824 × 824 in der Mitte, mit Schatten.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x111318))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space, colors: [color(0x2C3240), color(0x111318)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])

    func tile(_ r: CGRect) {
        let p = CGPath(roundedRect: r, cornerWidth: 64, cornerHeight: 64, transform: nil)
        ctx.addPath(p)
        ctx.setFillColor(color(0xFFFFFF, 0.07))
        ctx.fillPath()
        ctx.addPath(p)
        ctx.setStrokeColor(color(0xFFFFFF, 0.12))
        ctx.setLineWidth(3)
        ctx.strokePath()
    }

    // Oben: breite Kachel mit Kursverlauf wie im Stock-Widget.
    let top = CGRect(x: 190, y: 530, width: 644, height: 304)
    tile(top)
    let xs: [CGFloat] = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1]
    let ys: [CGFloat] = [0.30, 0.38, 0.30, 0.46, 0.42, 0.58, 0.50, 0.66, 0.62, 0.78, 0.84]
    let chart = top.insetBy(dx: 56, dy: 60)
    let pts = zip(xs, ys).map { CGPoint(x: chart.minX + $0 * chart.width, y: chart.minY + $1 * chart.height) }

    let line = CGMutablePath()
    line.addLines(between: pts)
    let area = CGMutablePath()
    area.addPath(line)
    area.addLine(to: CGPoint(x: pts.last!.x, y: chart.minY - 20))
    area.addLine(to: CGPoint(x: pts.first!.x, y: chart.minY - 20))
    area.closeSubpath()
    ctx.saveGState()
    ctx.addPath(area)
    ctx.clip()
    let fade = CGGradient(colorsSpace: space, colors: [color(0x5BD18B, 0.45), color(0x5BD18B, 0)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: chart.maxY), end: CGPoint(x: 0, y: chart.minY - 20), options: [])
    ctx.restoreGState()

    // Gestrichelte Bezugslinie (Kaufkurs).
    ctx.setStrokeColor(color(0xFFFFFF, 0.35))
    ctx.setLineWidth(6)
    ctx.setLineDash(phase: 0, lengths: [18, 14])
    ctx.move(to: CGPoint(x: chart.minX, y: chart.minY + 0.36 * chart.height))
    ctx.addLine(to: CGPoint(x: chart.maxX, y: chart.minY + 0.36 * chart.height))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    ctx.addPath(line)
    ctx.setStrokeColor(color(0x5BD18B))
    ctx.setLineWidth(22)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    // Unten links: Listenzeilen mit ▲ / ▼.
    let left = CGRect(x: 190, y: 190, width: 304, height: 304)
    tile(left)
    let rows: [(CGFloat, Bool)] = [(0.72, true), (0.5, false), (0.28, true)]
    for (y, up) in rows {
        let cy = left.minY + y * left.height
        let cx = left.minX + 66
        let tri = CGMutablePath()
        if up {
            tri.move(to: CGPoint(x: cx, y: cy + 20)); tri.addLine(to: CGPoint(x: cx - 22, y: cy - 16))
            tri.addLine(to: CGPoint(x: cx + 22, y: cy - 16))
        } else {
            tri.move(to: CGPoint(x: cx, y: cy - 20)); tri.addLine(to: CGPoint(x: cx - 22, y: cy + 16))
            tri.addLine(to: CGPoint(x: cx + 22, y: cy + 16))
        }
        tri.closeSubpath()
        ctx.addPath(tri)
        ctx.setFillColor(up ? color(0x5BD18B) : color(0xF26D6D))
        ctx.fillPath()
        let bar = CGRect(x: cx + 46, y: cy - 12, width: 150, height: 24)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 12, cornerHeight: 12, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.55))
        ctx.fillPath()
    }

    // Unten rechts: Zahnrad-Andeutung für „konfigurieren“ als Ring mit Plus.
    let right = CGRect(x: 530, y: 190, width: 304, height: 304)
    tile(right)
    let c = CGPoint(x: right.midX, y: right.midY)
    ctx.setStrokeColor(color(0x6AA8FF))
    ctx.setLineWidth(22)
    ctx.addEllipse(in: CGRect(x: c.x - 82, y: c.y - 82, width: 164, height: 164))
    ctx.strokePath()
    ctx.setLineWidth(24)
    ctx.move(to: CGPoint(x: c.x - 40, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + 40, y: c.y))
    ctx.move(to: CGPoint(x: c.x, y: c.y - 40)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 40))
    ctx.strokePath()

    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
var images: [String] = []
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let file = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try render(size: px).write(to: URL(fileURLWithPath: "\(out)/\(file)"))
        images.append(#"    { "idiom" : "mac", "size" : "\#(base)x\#(base)", "scale" : "\#(scale)x", "filename" : "\#(file)" }"#)
    }
}
let contents = "{\n  \"images\" : [\n\(images.joined(separator: ",\n"))\n  ],\n  \"info\" : { \"version\" : 1, \"author\" : \"xcode\" }\n}\n"
try contents.write(toFile: "\(out)/Contents.json", atomically: true, encoding: .utf8)
try #"{ "info" : { "version" : 1, "author" : "xcode" } }"#.appending("\n")
    .write(toFile: "ConfigApp/Assets.xcassets/Contents.json", atomically: true, encoding: .utf8)
print("App-Icon geschrieben nach \(out)")
