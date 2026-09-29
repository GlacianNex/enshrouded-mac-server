import AppKit
import Foundation

// Original ember motif; no game artwork or logos.
let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
NSColor(calibratedRed: 0.045, green: 0.10, blue: 0.14, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 964, height: 964), xRadius: 205, yRadius: 205).fill()
let flame = NSBezierPath()
flame.move(to: NSPoint(x: 530, y: 870))
flame.curve(to: NSPoint(x: 700, y: 240), controlPoint1: NSPoint(x: 455, y: 610), controlPoint2: NSPoint(x: 910, y: 470))
flame.curve(to: NSPoint(x: 300, y: 240), controlPoint1: NSPoint(x: 605, y: 125), controlPoint2: NSPoint(x: 400, y: 125))
flame.curve(to: NSPoint(x: 355, y: 680), controlPoint1: NSPoint(x: 130, y: 410), controlPoint2: NSPoint(x: 325, y: 590))
flame.curve(to: NSPoint(x: 410, y: 475), controlPoint1: NSPoint(x: 340, y: 550), controlPoint2: NSPoint(x: 410, y: 540))
flame.curve(to: NSPoint(x: 530, y: 870), controlPoint1: NSPoint(x: 510, y: 620), controlPoint2: NSPoint(x: 430, y: 705))
flame.close()
NSGradient(starting: NSColor(calibratedRed: 1, green: 0.34, blue: 0.12, alpha: 1), ending: NSColor(calibratedRed: 1, green: 0.81, blue: 0.36, alpha: 1))!.draw(in: flame, angle: 90)
NSColor(calibratedRed: 1, green: 0.92, blue: 0.65, alpha: 1).setFill()
let core = NSBezierPath()
core.move(to: NSPoint(x: 515, y: 550))
core.curve(to: NSPoint(x: 590, y: 260), controlPoint1: NSPoint(x: 520, y: 420), controlPoint2: NSPoint(x: 670, y: 360))
core.curve(to: NSPoint(x: 435, y: 260), controlPoint1: NSPoint(x: 550, y: 200), controlPoint2: NSPoint(x: 475, y: 200))
core.curve(to: NSPoint(x: 515, y: 550), controlPoint1: NSPoint(x: 365, y: 350), controlPoint2: NSPoint(x: 470, y: 405))
core.close(); core.fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
