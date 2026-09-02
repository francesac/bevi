//  Pannello.swift — il pannello che scende dalla goccia.
//
//  Un menu di sistema non sa mostrare le gocce che si riempiono, il numero grande, il
//  bottone pieno. Quindi il pannello è disegnato: stessa identità del cartello a tutto
//  schermo, blu notte, azzurro acqua per le sole cose che si toccano.
//
//  ⭐ Le regole che tengono insieme il disegno:
//     · l'azzurro è SOLO azione e selezione, mai decorazione;
//     · un vocabolario solo di controlli — pillole ovunque, e per gli interruttori quello
//       vero di macOS (che segue anche il colore scelto nelle impostazioni del Mac);
//     · il movimento dice uno stato che cambia, e dura 180 ms. Niente coreografie all'apertura:
//       questo pannello si apre venti volte al giorno.

import Cocoa
import QuartzCore

// ── i colori ──────────────────────────────────────────────────────────────────

enum Colori {
    static let fondo     = NSColor(srgbRed:  7.0/255, green: 21.0/255, blue: 34.0/255, alpha: 1)
    static let carta     = NSColor(srgbRed: 14.0/255, green: 35.0/255, blue: 56.0/255, alpha: 1)
    static let bordo     = NSColor(srgbRed: 28.0/255, green: 58.0/255, blue: 87.0/255, alpha: 1)
    static let testo     = NSColor(srgbRed: 232.0/255, green: 241.0/255, blue: 248.0/255, alpha: 1)
    static let tenue     = NSColor(srgbRed: 143.0/255, green: 169.0/255, blue: 192.0/255, alpha: 1)
    static let acqua     = NSColor(srgbRed: 90.0/255, green: 180.0/255, blue: 240.0/255, alpha: 1)
    static let acquaCupa = NSColor(srgbRed: 29.0/255, green: 92.0/255, blue: 140.0/255, alpha: 1)
    static let scuro     = NSColor(srgbRed:  4.0/255, green: 18.0/255, blue: 30.0/255, alpha: 1)
    static let pillola   = NSColor(srgbRed: 19.0/255, green: 44.0/255, blue: 69.0/255, alpha: 1)
    static let pillolaSu = NSColor(srgbRed: 26.0/255, green: 56.0/255, blue: 82.0/255, alpha: 1)
    static let verde     = NSColor(srgbRed: 63.0/255, green: 191.0/255, blue: 143.0/255, alpha: 1)
    static let cimaCarta = NSColor(srgbRed: 18.0/255, green: 57.0/255, blue: 92.0/255, alpha: 1)
    static let fondoCarta = NSColor(srgbRed: 11.0/255, green: 31.0/255, blue: 51.0/255, alpha: 1)
}

private let curva = CAMediaTimingFunction(controlPoints: 22.0/100, 61.0/100, 36.0/100, 1)

// ── mattoni ───────────────────────────────────────────────────────────────────

/// Una carta: angoli tondi, bordo sottile, tinta piatta o sfumata.
final class Carta: NSView {
    private let sfumatura = CAGradientLayer()

    init(tinta: NSColor? = nil, sfuma: [NSColor]? = nil, raggio: CGFloat = 16) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = raggio
        layer?.borderWidth = 1
        layer?.borderColor = Colori.bordo.cgColor
        if let tinta { layer?.backgroundColor = tinta.cgColor }
        if let sfuma {
            sfumatura.colors = sfuma.map { $0.cgColor }
            sfumatura.startPoint = CGPoint(x: 15.0/100, y: 1)
            sfumatura.endPoint   = CGPoint(x: 85.0/100, y: 0)
            sfumatura.cornerRadius = raggio
            layer?.insertSublayer(sfumatura, at: 0)
        }
    }
    required init?(coder: NSCoder) { nil }
    override func layout() { super.layout(); sfumatura.frame = bounds }
}

/// La fila di gocce. Piene fino ai bicchieri bevuti, vuote per quelli che mancano.
final class Gocce: NSView {
    var bevuti = 0 { didSet { if bevuti != oldValue { needsDisplay = true } } }
    var totale = 8 { didSet { if totale != oldValue { invalidateIntrinsicContentSize(); needsDisplay = true } } }

    private let lato: CGFloat = 16
    private let passo: CGFloat = 8

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(totale) * lato + CGFloat(max(0, totale - 1)) * passo,
               height: lato * 121.0/100)
    }

    /// La goccia del pannello web: un quadrato con tre angoli tondi e uno vivo, ruotato di
    /// 45°, così la punta guarda in alto.
    private func sagoma(in cella: NSRect) -> NSBezierPath {
        let s = lato
        let c = NSPoint(x: s/2, y: s/2)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: s/2, y: s))
        p.line(to: NSPoint(x: 0, y: s))            // l'angolo vivo: diventerà la punta
        p.line(to: NSPoint(x: 0, y: s/2))
        p.appendArc(withCenter: c, radius: s/2, startAngle: 180, endAngle: 90, clockwise: false)
        p.close()

        let giro = AffineTransform(translationByX: c.x, byY: c.y)
        var t = AffineTransform.identity
        t.append(AffineTransform(translationByX: -c.x, byY: -c.y))
        t.append(AffineTransform(rotationByDegrees: -45))
        t.append(giro)
        p.transform(using: t)
        // ricentrata nella cella: la punta sporge dal quadrato di partenza
        let scatola = p.bounds
        p.transform(using: AffineTransform(
            translationByX: cella.minX + (cella.width - scatola.width)/2 - scatola.minX,
            byY: cella.minY + (cella.height - scatola.height)/2 - scatola.minY))
        return p
    }

    override func draw(_ dirtyRect: NSRect) {
        for i in 0..<totale {
            let cella = NSRect(x: CGFloat(i) * (lato + passo), y: 0,
                               width: lato, height: bounds.height)
            let goccia = sagoma(in: cella)
            if i < bevuti {
                NSGraphicsContext.saveGraphicsState()
                let alone = NSShadow()
                alone.shadowColor = Colori.acqua.withAlphaComponent(40.0/100)
                alone.shadowBlurRadius = 9
                alone.shadowOffset = .zero
                alone.set()
                Colori.acqua.setFill()
                goccia.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                Colori.acquaCupa.setStroke()
                goccia.lineWidth = 2.0/1
                goccia.stroke()
            }
        }
    }
}

/// Il bottone pieno: una sola azione principale in tutto il pannello.
final class BottonePieno: NSButton {
    private var dentro = false
    private var premuto = false

    init(_ testo: String, azione: Selector, bersaglio: AnyObject) {
        super.init(frame: .zero)
        title = testo
        target = bersaglio
        action = azione
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = Colori.acqua.cgColor
        attributedTitle = NSAttributedString(string: testo, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: Colori.scuro,
        ])
        heightAnchor.constraint(equalToConstant: 38).isActive = true
    }
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseEntered(with e: NSEvent) { dentro = true;  tinta() }
    override func mouseExited(with e: NSEvent)  { dentro = false; tinta() }
    override func mouseDown(with e: NSEvent)    { premuto = true; tinta(); super.mouseDown(with: e)
                                                  premuto = false; tinta() }
    private func tinta() {
        let colore = premuto ? Colori.acqua.blended(withFraction: 18.0/100, of: .black)!
                   : dentro  ? Colori.acqua.blended(withFraction: 12.0/100, of: .white)!
                   : Colori.acqua
        layer?.backgroundColor = colore.cgColor
    }
}

/// Una pillola di scelta. Spenta è un fondo appena accennato; accesa è azzurra.
final class Pillola: NSButton {
    var scelta = false { didSet { tinta() } }
    private var dentro = false
    let valore: Int

    init(_ testo: String, valore: Int, azione: Selector, bersaglio: AnyObject) {
        self.valore = valore
        super.init(frame: .zero)
        title = testo
        target = bersaglio
        action = azione
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        tinta()
    }
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        var s = super.intrinsicContentSize
        s.width += 14
        return s
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseEntered(with e: NSEvent) { dentro = true;  tinta() }
    override func mouseExited(with e: NSEvent)  { dentro = false; tinta() }

    private func tinta() {
        let fondo = scelta ? Colori.acqua : (dentro ? Colori.pillolaSu : Colori.pillola)
        let inchiostro = scelta ? Colori.scuro : (dentro ? Colori.testo : Colori.tenue)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 18.0/100
            ctx.timingFunction = curva
            layer?.backgroundColor = fondo.cgColor
        }
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: scelta ? .semibold : .regular),
            .foregroundColor: inchiostro,
        ])
    }
}

/// L'interruttore.
/// 🔴 Non si usa `NSSwitch`: prende il **colore accento del Mac**, che su una macchina
///    qualsiasi può essere arancione o rosso e litiga con l'azzurro del pannello. Un
///    interruttore è un affordance standard, quindi la forma resta identica a quella di
///    sistema: cambia solo il colore, che qui è una scelta di identità.
final class Interruttore: NSControl {
    var acceso = false { didSet { if acceso != oldValue { anima() } } }

    private let pista = CALayer()
    private let pomello = CALayer()
    private let larghezza: CGFloat = 42, altezza: CGFloat = 25, bordo: CGFloat = 3

    init(azione: Selector, bersaglio: AnyObject) {
        super.init(frame: .zero)
        target = bersaglio
        action = azione
        wantsLayer = true
        layer?.addSublayer(pista)
        layer?.addSublayer(pomello)
        pista.cornerRadius = altezza / 2
        pomello.cornerRadius = (altezza - bordo * 2) / 2
        pomello.backgroundColor = Colori.testo.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: larghezza).isActive = true
        heightAnchor.constraint(equalToConstant: altezza).isActive = true
        anima(subito: true)
    }
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        pista.frame = bounds
        anima(subito: true)
    }

    private func anima(subito: Bool = false) {
        let lato = altezza - bordo * 2
        let x = acceso ? bounds.width - lato - bordo : bordo
        CATransaction.begin()
        CATransaction.setDisableActions(subito)
        CATransaction.setAnimationDuration(18.0/100)
        CATransaction.setAnimationTimingFunction(curva)
        pista.backgroundColor = (acceso ? Colori.verde : Colori.bordo).cgColor
        pomello.frame = CGRect(x: x, y: bordo, width: lato, height: lato)
        CATransaction.commit()
    }

    override func mouseDown(with e: NSEvent) { aziona() }
    /// anche da codice, così il collaudo automatico può premerlo davvero
    override func performClick(_ mittente: Any?) { aziona() }
    private func aziona() {
        acceso.toggle()
        sendAction(action, to: target)
    }
}

/// Un gruppo di pillole che si escludono.
final class Gruppo {
    let vista = NSStackView()
    private(set) var pillole: [Pillola] = []

    init(valori: [(String, Int)], azione: Selector, bersaglio: AnyObject) {
        vista.orientation = .horizontal
        vista.spacing = 5
        for (testo, valore) in valori {
            let p = Pillola(testo, valore: valore, azione: azione, bersaglio: bersaglio)
            pillole.append(p)
            vista.addArrangedSubview(p)
        }
    }
    func segna(_ valore: Int) { for p in pillole { p.scelta = (p.valore == valore) } }
}

/// Un testo che si può cliccare: schiarisce al passaggio del mouse, così si capisce
/// che è un comando e non una didascalia.
final class TestoCliccabile: NSButton {
    private var dentro = false
    private let etichetta: String

    init(_ testo: String, azione: Selector, bersaglio: AnyObject) {
        etichetta = testo
        super.init(frame: .zero)
        title = testo
        target = bersaglio
        action = azione
        isBordered = false
        tinta()
    }
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self))
    }
    override func mouseEntered(with e: NSEvent) { dentro = true;  tinta() }
    override func mouseExited(with e: NSEvent)  { dentro = false; tinta() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    private func tinta() {
        attributedTitle = NSAttributedString(string: etichetta, attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: dentro ? Colori.testo : Colori.tenue,
        ])
    }
}

// ── testi ─────────────────────────────────────────────────────────────────────

func scritta(_ testo: String, corpo: CGFloat = 13, peso: NSFont.Weight = .regular,
             colore: NSColor = Colori.testo, spaziatura: CGFloat = 0) -> NSTextField {
    let campo = NSTextField(labelWithString: testo)
    campo.attributedStringValue = NSAttributedString(string: testo, attributes: [
        .font: NSFont.systemFont(ofSize: corpo, weight: peso),
        .foregroundColor: colore,
        .kern: spaziatura,
    ])
    campo.lineBreakMode = .byTruncatingTail
    return campo
}

func filo() -> NSView {
    let v = NSView()
    v.wantsLayer = true
    v.layer?.backgroundColor = Colori.bordo.withAlphaComponent(60.0/100).cgColor
    v.heightAnchor.constraint(equalToConstant: 1).isActive = true
    return v
}
