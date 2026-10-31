//  Tinte.swift — la tavolozza e i caratteri della carta dello spagnolo.
//
//  31/10, Francesco: la carta era tutta figlia del blu dell'acqua. Ora ha due stanze: in cima
//  la fascia Bevi, che dice solo di bere; sotto lo spagnolo, con una tavolozza sua. Scelta da
//  lui fra tre palette delle sue bacheche: la 438 (Morning Snow · Aqua Mist · Toro Orange ·
//  Black Kite · Garnet). ⭐ L'arancio è il PREMIO e l'azione, mai l'errore: chi sbaglia
//  prende l'acqua, fredda e calma.
//  Il pannello della goccia nella barra in alto resta col suo blu (`Colori`, in Pannello.swift).

import Cocoa

private func esa(_ h: Int, _ alfa: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
            blue: CGFloat(h & 0xff) / 255, alpha: alfa)
}

enum Tinte {
    static let neve    = esa(0xF5F4ED)   // Morning Snow: il testo dello spagnolo, la goccia
    static let acqua   = esa(0xA0C9CB)   // Aqua Mist: la fascia Bevi, le tappe fatte, l'errore
    static let toro    = esa(0xFF6037)   // Toro Orange: il bottone, il premio, la tappa nuova
    static let nibbio  = esa(0x351E1C)   // Black Kite: il fondo dello spagnolo, l'inchiostro su chiaro
    static let granato = esa(0x733635)   // Garnet: il cartellino, l'ombra del bottone
    static let tenue   = esa(0xB8A49E)   // le didascalie
    static let incavo  = esa(0x4D302D)   // tappe vuote, il filo sopra i numeri
    static let bordo   = esa(0x5A3A36)   // il bordo del campo
    static let rilievo = esa(0x45292A)   // le pillole spente

    /// Il velo sugli schermi: lo stesso marrone, più scuro, così la carta ne esce come un'isola.
    static let veloSu  = esa(0x2B1816, 88.0 / 100)
    static let veloGiu = esa(0x120A09, 93.0 / 100)
}

enum Caratteri {
    /// SF Pro Rounded: il carattere dello spagnolo, tondo e giocoso.
    static func tondo(_ corpo: CGFloat, _ peso: NSFont.Weight = .regular) -> NSFont {
        let base = NSFont.systemFont(ofSize: corpo, weight: peso)
        guard let d = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: d, size: corpo) ?? base
    }

    /// New York: il «Bevi.» e il «¡Muy bien!», le due cose che si dicono a voce alta.
    static func serif(_ corpo: CGFloat, corsivo: Bool = false) -> NSFont {
        let base = NSFont.systemFont(ofSize: corpo)
        guard var d = base.fontDescriptor.withDesign(.serif) else { return base }
        if corsivo { d = d.withSymbolicTraits(.italic) }
        return NSFont(descriptor: d, size: corpo) ?? base
    }
}

/// La goccia della fascia Bevi: piena di neve, col riflesso d'acqua in basso a sinistra.
final class Goccia: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 44, height: 58) }

    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 22, y: 56))
        p.curve(to: NSPoint(x: 4, y: 21), controlPoint1: NSPoint(x: 22, y: 56), controlPoint2: NSPoint(x: 4, y: 34))
        p.appendArc(withCenter: NSPoint(x: 22, y: 21), radius: 18, startAngle: 180, endAngle: 360, clockwise: false)
        p.curve(to: NSPoint(x: 22, y: 56), controlPoint1: NSPoint(x: 40, y: 34), controlPoint2: NSPoint(x: 22, y: 56))
        p.close()
        Tinte.neve.setFill()
        p.fill()

        let riflesso = NSBezierPath()
        riflesso.appendArc(withCenter: NSPoint(x: 22, y: 20), radius: 9, startAngle: 180, endAngle: 270, clockwise: false)
        riflesso.lineWidth = 35.0 / 10
        riflesso.lineCapStyle = .round
        Tinte.acqua.setStroke()
        riflesso.stroke()
    }
}

// ── i segni al posto delle parole ────────────────────────────────────────────
// 31/10, Francesco: «se può essere spiegato senza testo, deve essere spiegato senza testo».
// Consegne, titoli dell'esito e nomi dei bottoni sono diventati segni: un simbolo, un colore,
// una parola barrata. Il nome resta nel suggerimento al passaggio del mouse, per chi lo cerca.

/// Un simbolo di sistema (SF Symbols) alla misura e al peso voluti.
func simbolo(_ nome: String, _ corpo: CGFloat, _ peso: NSFont.Weight = .semibold) -> NSImage? {
    NSImage(systemSymbolName: nome, accessibilityDescription: nil)?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: corpo, weight: peso))
}

/// Un bottone che è solo un segno: tenue a riposo, neve sotto il mouse.
final class Icona: NSButton {
    private var dentro = false
    var inchiostri = (Tinte.tenue, Tinte.neve) { didSet { tinta() } }

    init(_ nome: String, corpo: CGFloat = 17, aiuto: String, azione: Selector, bersaglio: AnyObject) {
        super.init(frame: .zero)
        image = simbolo(nome, corpo)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = aiuto
        setAccessibilityLabel(aiuto)
        target = bersaglio
        action = azione
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: corpo + 20).isActive = true
        heightAnchor.constraint(equalToConstant: corpo + 20).isActive = true
        tinta()
    }
    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { dentro = true;  tinta() }
    override func mouseExited(with e: NSEvent)  { dentro = false; tinta() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    private func tinta() { contentTintColor = dentro ? inchiostri.1 : inchiostri.0 }
}

/// Il sigillo dell'esito, al posto di «¡Muy bien!» e «No, si dice così»: un tondo pieno col
/// suo segno. Arancio col ✓ = giusta · acqua con la ✕ = sbagliata · neve col ✓ = quasi.
final class Sigillo: NSView {
    private let lato: CGFloat = 34

    init(_ nome: String, fondo: NSColor, inchiostro: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fondo.cgColor
        layer?.cornerRadius = lato / 2
        translatesAutoresizingMaskIntoConstraints = false
        let segno = NSImageView()
        segno.image = simbolo(nome, 15, .heavy)
        segno.contentTintColor = inchiostro
        segno.translatesAutoresizingMaskIntoConstraints = false
        addSubview(segno)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: lato), heightAnchor.constraint(equalToConstant: lato),
            segno.centerXAnchor.constraint(equalTo: centerXAnchor), segno.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { nil }

    /// Lo stesso gesto della cifra che sale: atterra da più grande, sul suo centro.
    func appare() {
        guard let l = layer else { return }
        let m = CGPoint(x: lato / 2, y: lato / 2)
        var da = CATransform3DMakeTranslation(m.x, m.y, 0)
        da = CATransform3DScale(da, 16.0/10, 16.0/10, 1)
        da = CATransform3DTranslate(da, -m.x, -m.y, 0)
        let pulsa = CABasicAnimation(keyPath: "transform")
        pulsa.fromValue = da; pulsa.toValue = CATransform3DIdentity
        pulsa.duration = 5.0/10; pulsa.timingFunction = curva
        let entra = CABasicAnimation(keyPath: "opacity")
        entra.fromValue = 0; entra.toValue = 1; entra.duration = 3.0/10
        l.add(pulsa, forKey: "pulsa")
        l.add(entra, forKey: "entra")
    }
}
