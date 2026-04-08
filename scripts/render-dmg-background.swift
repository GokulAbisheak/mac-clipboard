import AppKit
import Foundation

guard CommandLine.argc == 4,
      let w = Int(CommandLine.arguments[1]),
      let h = Int(CommandLine.arguments[2]),
      w > 0, h > 0
else {
    fputs("usage: render-dmg-background <width> <height> <out.png>\n", stderr)
    exit(1)
}

let outPath = CommandLine.arguments[3]
let size = NSSize(width: CGFloat(w), height: CGFloat(h))

let img = NSImage(size: size)
img.lockFocus()

NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

let ruleGray = NSColor(calibratedWhite: 0.88, alpha: 1)
ruleGray.setStroke()
let line = NSBezierPath()
line.lineWidth = 1
let yTopRule: CGFloat = CGFloat(h) - 52
let yBottomRule: CGFloat = 36
line.move(to: NSPoint(x: 0, y: yTopRule))
line.line(to: NSPoint(x: CGFloat(w), y: yTopRule))
line.move(to: NSPoint(x: 0, y: yBottomRule))
line.line(to: NSPoint(x: CGFloat(w), y: yBottomRule))
line.stroke()

let title = "Clipboard" as NSString
let titleFont = NSFont.systemFont(ofSize: 15, weight: .semibold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.labelColor,
]
let titleSize = title.size(withAttributes: titleAttrs)
title.draw(
    at: NSPoint(x: (CGFloat(w) - titleSize.width) / 2, y: CGFloat(h) - 38),
    withAttributes: titleAttrs
)

let body = "Drag and drop Clipboard into the Applications folder to install." as NSString
let bodyFont = NSFont.systemFont(ofSize: 11, weight: .regular)
let para = NSMutableParagraphStyle()
para.alignment = .center
para.lineBreakMode = .byWordWrapping
let bodyAttrs: [NSAttributedString.Key: Any] = [
    .font: bodyFont,
    .foregroundColor: NSColor.secondaryLabelColor,
    .paragraphStyle: para,
]
let bodyRect = NSRect(x: 28, y: 52, width: CGFloat(w) - 56, height: 36)
body.draw(with: bodyRect, options: [.usesLineFragmentOrigin], attributes: bodyAttrs)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("error: could not encode PNG\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
