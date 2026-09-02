//  Cartello.swift — il cartello a tutto schermo.
//
//  Compare su OGNI monitor, resta un paio di secondi e se ne va da solo (o al primo clic).
//  ⭐ Non ruba il fuoco alla tastiera: se stai scrivendo, le lettere continuano ad arrivare
//     nell'app che sta sotto. È la differenza fra un promemoria e un'interruzione.

import Cocoa
import QuartzCore

private final class VistaCliccabile: NSView {
    var alClic: (() -> Void)?
    override func mouseDown(with event: NSEvent) { alClic?() }
}

final class Cartello {
    private var finestre: [NSWindow] = []
    private var contenitori: [NSView] = []
    private var giaChiuso = false
    private var alTermine: (() -> Void)?

    /// Un cartello per volta: se ne sta già girando uno, il secondo non parte.
    private static var inCorso: Cartello?

    static func mostra(parola: String = "BEVI", sotto: String, simbolo: String = "💧",
                       secondi: Double = 2, muto: Bool = false, suono: String = "Submarine") {
        if inCorso != nil { return }
        let c = Cartello()
        inCorso = c
        c.alTermine = { inCorso = nil }
        c.apri(parola: parola, sotto: sotto, simbolo: simbolo,
               secondi: secondi, muto: muto, suono: suono)
    }

    // ── il contenuto ──────────────────────────────────────────────────────────

    private func etichetta(_ testo: String, corpo: CGFloat, peso: NSFont.Weight,
                           kern: CGFloat, opacita: CGFloat) -> NSTextField {
        let campo = NSTextField(labelWithString: "")
        let stile = NSMutableParagraphStyle()
        stile.alignment = .center
        campo.attributedStringValue = NSAttributedString(string: testo, attributes: [
            .font: NSFont.systemFont(ofSize: corpo, weight: peso),
            .foregroundColor: NSColor.white.withAlphaComponent(opacita),
            .kern: kern,
            .paragraphStyle: stile,
        ])
        campo.isBezeled = false
        campo.drawsBackground = false
        campo.isEditable = false
        campo.isSelectable = false
        campo.sizeToFit()
        return campo
    }

    private func costruisci(_ schermo: NSScreen, parola: String, sotto: String,
                            simbolo: String) -> NSWindow {
        let cornice = schermo.frame

        let finestra = NSWindow(contentRect: cornice, styleMask: .borderless,
                                backing: .buffered, defer: false)
        finestra.isOpaque = false
        finestra.backgroundColor = .clear
        finestra.hasShadow = false
        finestra.alphaValue = 0
        // sopra tutto, anche sopra le app a schermo intero, su qualunque Scrivania
        finestra.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        finestra.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                       .stationary, .ignoresCycle]

        let radice = VistaCliccabile(frame: NSRect(origin: .zero, size: cornice.size))
        radice.wantsLayer = true
        radice.alClic = { [weak self] in self?.chiudi() }

        // la Scrivania sfocata dietro, tinta di blu profondo
        let velo = NSVisualEffectView(frame: radice.bounds)
        velo.material = .hudWindow
        velo.blendingMode = .behindWindow
        velo.state = .active
        velo.autoresizingMask = [.width, .height]
        radice.addSubview(velo)

        let tinta = NSView(frame: radice.bounds)
        tinta.wantsLayer = true
        tinta.autoresizingMask = [.width, .height]
        let sfumatura = CAGradientLayer()
        sfumatura.frame = radice.bounds
        sfumatura.colors = [
            NSColor(srgbRed: 13.0/255, green: 48.0/255, blue: 84.0/255, alpha: 90.0/100).cgColor,
            NSColor(srgbRed:  5.0/255, green: 18.0/255, blue: 36.0/255, alpha: 94.0/100).cgColor,
        ]
        sfumatura.startPoint = CGPoint(x: 1.0/2, y: 1)
        sfumatura.endPoint   = CGPoint(x: 1.0/2, y: 0)
        tinta.layer = sfumatura
        radice.addSubview(tinta)

        let corpo = min(cornice.width * 17.0/100, cornice.height * 28.0/100)
        let goccia = etichetta(simbolo, corpo: corpo * 40.0/100, peso: .regular, kern: 0, opacita: 1)
        let titolo = etichetta(parola, corpo: corpo, peso: .black,
                               kern: corpo * 6.0/100, opacita: 1)
        let riga = sotto.isEmpty ? nil
            : etichetta(sotto, corpo: max(corpo * 11.0/100, 15), peso: .medium,
                        kern: corpo * 2.0/100, opacita: 62.0/100)

        let stacco1 = corpo * 16.0/100
        let stacco2 = corpo * 14.0/100
        var altezza = goccia.frame.height + stacco1 + titolo.frame.height
        if let r = riga { altezza += stacco2 + r.frame.height }
        var larghezza = max(goccia.frame.width, titolo.frame.width)
        if let r = riga { larghezza = max(larghezza, r.frame.width) }

        let contenitore = NSView(frame: NSRect(
            x: (cornice.width - larghezza) / 2,
            y: (cornice.height - altezza) / 2 - 18,   // parte 18 px più in basso: poi sale
            width: larghezza, height: altezza))

        var y: CGFloat = 0
        if let r = riga {
            r.setFrameOrigin(NSPoint(x: (larghezza - r.frame.width) / 2, y: y))
            contenitore.addSubview(r)
            y += r.frame.height + stacco2
        }
        titolo.setFrameOrigin(NSPoint(x: (larghezza - titolo.frame.width) / 2, y: y))
        contenitore.addSubview(titolo)
        y += titolo.frame.height + stacco1
        goccia.setFrameOrigin(NSPoint(x: (larghezza - goccia.frame.width) / 2, y: y))
        contenitore.addSubview(goccia)

        radice.addSubview(contenitore)
        contenitori.append(contenitore)

        finestra.contentView = radice
        finestra.orderFrontRegardless()   // si mostra SENZA rubare il fuoco alla tastiera
        return finestra
    }

    // ── entrata e uscita: UN gesto solo, dissolvenza + risalita ───────────────

    private func apri(parola: String, sotto: String, simbolo: String,
                      secondi: Double, muto: Bool, suono: String) {
        for schermo in NSScreen.screens {
            finestre.append(costruisci(schermo, parola: parola, sotto: sotto, simbolo: simbolo))
        }
        if !muto { NSSound(named: suono)?.play() }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 28.0/100
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for f in finestre { f.animator().alphaValue = 1 }
            for c in contenitori {
                c.animator().setFrameOrigin(NSPoint(x: c.frame.origin.x, y: c.frame.origin.y + 18))
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + secondi) { [weak self] in self?.chiudi() }
        // rete di sicurezza: qualunque cosa vada storta, questa finestra non resta appesa
        DispatchQueue.main.asyncAfter(deadline: .now() + secondi + 4) { [weak self] in
            self?.smonta()
        }
    }

    private func chiudi() {
        if giaChiuso { return }
        giaChiuso = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 34.0/100
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            for f in self.finestre { f.animator().alphaValue = 0 }
            for c in self.contenitori {
                c.animator().setFrameOrigin(NSPoint(x: c.frame.origin.x, y: c.frame.origin.y + 10))
            }
        }, completionHandler: { [weak self] in self?.smonta() })
    }

    private func smonta() {
        for f in finestre { f.orderOut(nil) }
        finestre.removeAll()
        contenitori.removeAll()
        alTermine?()
        alTermine = nil
    }
}
