import AppKit

let words = ["오늘", "단어", "타이핑", "기록", "하루", "생각", "문장", "글", "쓰기", "메모",
             "코드", "노트", "일상", "시간", "마음", "바다", "산", "하늘", "구름", "바람"]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let plate = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(calibratedRed: 0.976, green: 0.973, blue: 0.957, alpha: 1).setFill()
    plate.fill()

    ctx.saveGState()
    plate.addClip()

    // Fills most of the plate so the silhouette still reads at 16pt.
    let m = NSBezierPath()
    let baseY = rect.minY + rect.height * 0.13
    let peakY = rect.minY + rect.height * 0.88
    m.move(to: CGPoint(x: rect.minX - s * 0.02, y: baseY))
    m.line(to: CGPoint(x: rect.minX + rect.width * 0.36, y: peakY))
    m.line(to: CGPoint(x: rect.minX + rect.width * 0.52, y: baseY + rect.height * 0.34))
    m.line(to: CGPoint(x: rect.minX + rect.width * 0.70, y: peakY - rect.height * 0.13))
    m.line(to: CGPoint(x: rect.maxX + s * 0.02, y: baseY))
    m.close()
    m.addClip()

    let ink = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.10, alpha: 1)
    // Dense enough that the words read as texture, not as a sentence —
    // the shape is what should carry at icon sizes.
    let rowH = s * 0.036
    var y = baseY
    var i = 0
    while y < peakY {
        // Offsetting each row keeps clipped edge glyphs from lining up
        // into a false vertical seam.
        var x = rect.minX - s * 0.03 - CGFloat((i * 7) % 5) * s * 0.012
        while x < rect.maxX + s * 0.03 {
            let word = words[i % words.count]
            let fontSize = rowH * 0.84
            let font = NSFont(descriptor: NSFont.systemFont(ofSize: fontSize, weight: .medium)
                .fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: fontSize).fontDescriptor,
                              size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let str = word as NSString
            let w = str.size(withAttributes: attrs).width
            str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            x += w + s * 0.010
            i += 1
        }
        y += rowH
    }
    ctx.restoreGState()
    image.unlockFocus()
    return image
}

let out = CommandLine.arguments[1]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let img = drawIcon(size: CGFloat(size))
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try! png.write(to: URL(fileURLWithPath: "\(out)/icon_\(size).png"))
}
print("done")
