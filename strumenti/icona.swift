//  icona.swift — disegna l'icona dell'app.
//
//  Sta qui, e non come file binario buttato nel repo, perché un'icona che si può rifare è
//  un'icona che si può correggere. Si lancia con:  swift strumenti/icona.swift
//  Produce Risorse/Bevi.icns e documentazione/icona.png.

import Cocoa

let lato: CGFloat = 1024
let margine: CGFloat = 100          // il respiro che macOS si aspetta attorno all'icona

func disegna(_ misura: CGFloat) -> NSImage {
    let immagine = NSImage(size: NSSize(width: misura, height: misura))
    immagine.lockFocus()
    let scala = misura / lato
    let ctx = NSGraphicsContext.current!
    ctx.imageInterpolation = .high
    ctx.cgContext.scaleBy(x: scala, y: scala)

    // il quadrato con gli angoli tondi, come tutte le icone di macOS
    let corpo = NSRect(x: margine, y: margine,
                       width: lato - margine*2, height: lato - margine*2)
    let sagoma = NSBezierPath(roundedRect: corpo,
                              xRadius: corpo.width * 225.0/1000,
                              yRadius: corpo.width * 225.0/1000)
    NSGraphicsContext.saveGraphicsState()
    sagoma.addClip()
    let sfumatura = NSGradient(colors: [
        NSColor(srgbRed: 22.0/255, green: 68.0/255, blue: 110.0/255, alpha: 1),
        NSColor(srgbRed:  7.0/255, green: 24.0/255, blue: 42.0/255, alpha: 1),
    ])!
    sfumatura.draw(in: corpo, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // la goccia: stessa sagoma di quelle del pannello
    let s = corpo.width * 46.0/100
    let goccia = NSBezierPath()
    goccia.move(to: NSPoint(x: s/2, y: s))
    goccia.line(to: NSPoint(x: 0, y: s))
    goccia.line(to: NSPoint(x: 0, y: s/2))
    goccia.appendArc(withCenter: NSPoint(x: s/2, y: s/2), radius: s/2,
                     startAngle: 180, endAngle: 90, clockwise: false)
    goccia.close()
    var giro = AffineTransform.identity
    giro.append(AffineTransform(translationByX: -s/2, byY: -s/2))
    giro.append(AffineTransform(rotationByDegrees: -45))
    goccia.transform(using: giro)
    let scatola = goccia.bounds
    goccia.transform(using: AffineTransform(
        translationByX: corpo.midX - scatola.midX,
        byY: corpo.midY - scatola.midY))

    NSGraphicsContext.saveGraphicsState()
    let alone = NSShadow()
    alone.shadowColor = NSColor(srgbRed: 90.0/255, green: 180.0/255, blue: 240.0/255,
                                alpha: 45.0/100)
    alone.shadowBlurRadius = corpo.width * 9.0/100
    alone.shadowOffset = .zero
    alone.set()
    NSColor(srgbRed: 90.0/255, green: 180.0/255, blue: 240.0/255, alpha: 1).setFill()
    goccia.fill()
    NSGraphicsContext.restoreGraphicsState()

    immagine.unlockFocus()
    return immagine
}

func salva(_ immagine: NSImage, _ dove: String) {
    guard let dati = immagine.tiffRepresentation,
          let mappa = NSBitmapImageRep(data: dati),
          let png = mappa.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: dove))
}

let base = FileManager.default.currentDirectoryPath
let set = "\(base)/Bevi.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: "\(base)/documentazione",
                                         withIntermediateDirectories: true)

for (misura, nomi) in [(16, ["16x16"]), (32, ["16x16@2x", "32x32"]), (64, ["32x32@2x"]),
                       (128, ["128x128"]), (256, ["128x128@2x", "256x256"]),
                       (512, ["256x256@2x", "512x512"]), (1024, ["512x512@2x"])] {
    let img = disegna(CGFloat(misura))
    for nome in nomi { salva(img, "\(set)/icon_\(nome).png") }
}
salva(disegna(512), "\(base)/documentazione/icona.png")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", set, "-o", "\(base)/Risorse/Bevi.icns"]
try? iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
print(iconutil.terminationStatus == 0 ? "✓ Risorse/Bevi.icns e documentazione/icona.png"
                                      : "⚠️ iconutil non ce l'ha fatta")
