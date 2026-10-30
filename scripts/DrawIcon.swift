import AppKit

// A single, generous checkmark keeps the icon legible at small sizes.
let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
NSGraphicsContext.current!.imageInterpolation = .high
let paper = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 185, yRadius: 185)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
shadow.shadowBlurRadius = 22
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.white.setFill(); paper.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor.white, ending: NSColor(calibratedWhite: 0.96, alpha: 1))!.draw(in: paper, angle: -90)
NSColor(calibratedWhite: 0.85, alpha: 0.6).setStroke()
paper.lineWidth = 2; paper.stroke()
let circle = NSBezierPath(ovalIn: NSRect(x: 282, y: 282, width: 460, height: 460))
NSGradient(starting: NSColor(calibratedRed: 0.08, green: 0.58, blue: 1, alpha: 1),
           ending: NSColor(calibratedRed: 0.04, green: 0.40, blue: 0.94, alpha: 1))!.draw(in: circle, angle: -90)
let check = NSBezierPath()
check.move(to: NSPoint(x: 405, y: 510))
check.line(to: NSPoint(x: 484, y: 433))
check.line(to: NSPoint(x: 624, y: 592))
check.lineWidth = 43
check.lineCapStyle = .round; check.lineJoinStyle = .round
NSColor.white.setStroke(); check.stroke()
canvas.unlockFocus()
let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
