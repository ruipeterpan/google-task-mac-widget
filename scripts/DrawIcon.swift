import AppKit
let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
NSGraphicsContext.current!.imageInterpolation = .high
let paper = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.white.setFill(); paper.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor.white, ending: NSColor(calibratedWhite: 0.94, alpha: 1))!.draw(in: paper, angle: -90)
NSColor(calibratedWhite: 0.82, alpha: 0.65).setStroke(); paper.lineWidth = 2; paper.stroke()
let blue = NSColor(calibratedRed: 0.04, green: 0.47, blue: 0.98, alpha: 1)
for (index, y) in [692.0, 512.0, 332.0].enumerated() {
    let circle = NSBezierPath(ovalIn: NSRect(x: 221, y: y - 47, width: 94, height: 94))
    blue.setFill(); blue.setStroke()
    if index == 0 {
        circle.fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: 244, y: y))
        check.line(to: NSPoint(x: 261, y: y - 17))
        check.line(to: NSPoint(x: 292, y: y + 20))
        check.lineWidth = 10; check.lineCapStyle = .round; check.lineJoinStyle = .round
        NSColor.white.setStroke(); check.stroke()
    } else {
        circle.lineWidth = 10; circle.stroke()
        blue.withAlphaComponent(0.045).setFill(); circle.fill()
    }
    let width = index == 1 ? 335.0 : 390.0
    NSColor(calibratedRed: 0.40, green: 0.44, blue: 0.49, alpha: index == 0 ? 0.85 : 0.65).setFill()
    NSBezierPath(roundedRect: NSRect(x: 375, y: y + 7, width: width, height: 25), xRadius: 12.5, yRadius: 12.5).fill()
    NSColor(calibratedRed: 0.67, green: 0.70, blue: 0.74, alpha: 0.65).setFill()
    NSBezierPath(roundedRect: NSRect(x: 375, y: y - 32, width: index == 1 ? 250 : 295, height: 16), xRadius: 8, yRadius: 8).fill()
}
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
