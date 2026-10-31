import AppKit

// ── il premio di una risposta ─────────────────────────────────────────────────
// 31/10, Francesco: «rendilo visivamente più interessante e rewarding». Un gesto solo, lo stesso
// dappertutto: ciò che si guadagna SI ACCENDE (cresce da sinistra o pulsa, con la `curva` di casa)
// e lascia un alone che si spegne piano. ⛔ rimbalzi, ⛔ coriandoli: è una carta che premia, non una slot.
// I colori sono quelli della carta (Tinte.swift): ciò che si guadagna è arancio Toro, il fatto è acqua.

/// Quanto manca al prossimo ripasso, a parole.
func fraQuanto(_ secondi: Int) -> String {
    switch secondi / 86400 {
    case ...1:   return "torna domani"
    case 2...5:  return "torna fra \(secondi / 86400) giorni"
    case 6...8:  return "torna fra una settimana"
    case 9...25: return "torna fra \(secondi / 86400) giorni"
    case 26...45: return "torna fra un mese"
    case 46...120: return "torna fra tre mesi"
    default:     return "torna fra sei mesi"
    }
}

/// La scala di UNA scheda: sei tappe, dal ripasso fra tre giorni a quello fra sei mesi. Dalla
/// terza la scheda è «saputa», e lì c'è più aria fra i gradini. Alla risposta giusta la tappa
/// nuova si accende d'arancio; a quella sbagliata le tappe fatte si spengono.
final class Scala: NSView {
    static let tappe = 6
    private let lato = CGSize(width: 28, height: 8)
    private let passo: CGFloat = 5, soglia: CGFloat = 13

    private let prima: Int
    private var dopo: Int, esito: Esito?
    private var pieni: [CALayer] = []
    private var larghezzaTotale: CGFloat = 0

    /// Dal 31/10 la scala sta in cima alla carta già PRIMA della risposta, come la barra di
    /// Duolingo: si vede cosa c'è in gioco. Alla risposta `rispondi` la fa salire o spegnere.
    init(prima: Int) {
        self.prima = min(prima, Scala.tappe); self.dopo = self.prima
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        var x: CGFloat = 0
        for i in 1...Scala.tappe {
            if i == 3 { x += soglia - passo }
            let fondo = CALayer()
            fondo.frame = CGRect(x: x, y: 0, width: lato.width, height: lato.height)
            fondo.cornerRadius = lato.height / 2
            fondo.backgroundColor = Tinte.incavo.cgColor
            layer?.addSublayer(fondo)

            let pieno = CALayer()
            pieno.anchorPoint = .zero
            pieno.position = CGPoint(x: x, y: 0)
            pieno.bounds = CGRect(origin: .zero, size: lato)
            pieno.cornerRadius = lato.height / 2
            pieno.shadowOffset = .zero
            pieno.shadowRadius = 5
            pieno.isHidden = true
            layer?.addSublayer(pieno)
            pieni.append(pieno)
            x += lato.width + passo
        }
        larghezzaTotale = x - passo
        disponi()
    }
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: larghezzaTotale, height: lato.height) }

    /// Lo stato di partenza: le tappe già fatte prima di questa risposta.
    private func disponi() {
        for (i, p) in pieni.enumerated() {
            let tappa = i + 1
            p.isHidden = tappa > max(prima, dopo)
            p.backgroundColor = Tinte.acqua.cgColor
            if tappa > prima { p.backgroundColor = Tinte.toro.cgColor }
        }
    }

    /// La risposta è arrivata: la tappa nuova si accende, o quelle fatte si spengono.
    func rispondi(dopo nuova: Int, esito e: Esito) {
        dopo = min(nuova, Scala.tappe); esito = e
        disponi()
        accendi()
        toolTip = didascalia.0
    }

    /// Il gesto: la tappa nuova cresce da sinistra con l'alone, o le tappe perse si spengono.
    private func accendi(dopo ritardo: CFTimeInterval = 25.0/100) {
        let ora = CACurrentMediaTime() + ritardo
        if esito == .sbagliato {
            for p in pieni.prefix(prima) {
                let via = CABasicAnimation(keyPath: "opacity")
                via.fromValue = 1; via.toValue = 0
                // più lento della tappa che si accende: chi ha sbagliato deve VEDERE cosa perde
                via.beginTime = ora + 35.0/100; via.duration = 12.0/10; via.timingFunction = curva
                via.fillMode = .backwards
                p.opacity = 0
                p.add(via, forKey: "spegni")
            }
            return
        }
        guard dopo > prima, dopo >= 1 else { return }
        let p = pieni[dopo - 1]
        let cresce = CABasicAnimation(keyPath: "bounds.size.width")
        cresce.fromValue = 0; cresce.toValue = lato.width
        cresce.beginTime = ora; cresce.duration = 55.0/100; cresce.timingFunction = curva
        cresce.fillMode = .backwards
        p.add(cresce, forKey: "cresce")

        p.shadowColor = Tinte.toro.cgColor
        p.shadowOpacity = 45.0/100
        let alone = CABasicAnimation(keyPath: "shadowOpacity")
        alone.fromValue = 1; alone.toValue = 35.0/100
        alone.beginTime = ora + 4.0/10; alone.duration = 16.0/10; alone.timingFunction = curva
        alone.fillMode = .backwards
        p.add(alone, forKey: "alone")
    }

    /// Cosa dice la scala, a parole, accanto ai gradini.
    var didascalia: (String, NSColor, NSFont.Weight) {
        let quando = fraQuanto(Quaderno.intervalli[max(0, min(dopo, Quaderno.intervalli.count - 1))])
        guard let esito else { return (prima == 0 ? "scheda nuova" : "tappa \(prima) di \(Scala.tappe)", Tinte.tenue, .medium) }
        switch esito {
        case .sbagliato:
            return (prima > 0 ? "si riparte · torna domani" : "torna domani", Tinte.acqua, .medium)
        case .quasi:
            return (prima > 0 ? "resta alla tappa \(prima) · \(quando)" : quando, Tinte.tenue, .medium)
        default:
            if dopo == 3 && prima < 3 { return ("Saputa!  ·  \(quando)", Tinte.toro, .bold) }
            if dopo == prima           { return ("la sai da mesi · \(quando)", Tinte.toro, .medium) }
            return ("tappa \(dopo) di \(Scala.tappe) · \(quando)", Tinte.tenue, .medium)
        }
    }
}

/// I numeri in fondo alla carta: tre coppie, un segno e la cifra (☀ oggi · ✓ giuste · ★ sapute;
/// il nome sta nel suggerimento). Quando una cifra sale si accende d'arancio, pulsa una volta e
/// lascia salire un «+1».
final class Progressi: NSStackView {
    private final class Cifra {
        let numero = NSTextField(labelWithString: "")
        let colonna: NSStackView
        var valore: Int

        init(_ v: Int, _ segno: String, _ nome: String) {
            valore = v
            numero.font = Caratteri.tondo(20, .heavy)
            numero.textColor = Tinte.neve
            numero.stringValue = "\(v)"
            numero.wantsLayer = true
            let icona = NSImageView()
            icona.image = simbolo(segno, 14, .bold)
            icona.contentTintColor = Tinte.tenue
            colonna = NSStackView(views: [icona, numero])
            colonna.orientation = .horizontal
            colonna.alignment = .centerY
            colonna.spacing = 7
            colonna.toolTip = nome
        }
    }

    private let oggi: Cifra, giuste: Cifra, sapute: Cifra

    init(_ n: Quaderno.Numeri) {
        oggi   = Cifra(n.oggi, "sun.max.fill", "risposte oggi")
        giuste = Cifra(n.giuste, "checkmark", "risposte giuste")
        sapute = Cifra(n.sapute, "star.fill", "schede sapute su \(n.totale)")
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 30
        for c in [oggi, giuste, sapute] { addArrangedSubview(c.colonna) }
    }
    required init?(coder: NSCoder) { nil }

    /// I numeri nuovi, appena si risponde. Quelli saliti si festeggiano.
    func aggiorna(_ n: Quaderno.Numeri, ritardo: TimeInterval = 45.0/100) {
        var saliti: [(Cifra, Int)] = []
        for (c, v) in [(oggi, n.oggi), (giuste, n.giuste), (sapute, n.sapute)] {
            if v > c.valore { saliti.append((c, v - c.valore)) }
            c.valore = v
            c.numero.stringValue = "\(v)"
        }
        guard !saliti.isEmpty else { return }
        for (c, _) in saliti { c.numero.textColor = Tinte.toro }
        DispatchQueue.main.asyncAfter(deadline: .now() + ritardo) { [weak self] in
            guard let self else { return }
            for (i, (c, quanti)) in saliti.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 12.0/100) {
                    self.festeggia(c, quanti)
                }
            }
        }
    }

    private func festeggia(_ c: Cifra, _ quanti: Int) {
        // ① la cifra pulsa: atterra da un filo più grande, sul suo centro
        if let l = c.numero.layer {
            let m = CGPoint(x: l.bounds.midX, y: l.bounds.midY)
            var da = CATransform3DMakeTranslation(m.x, m.y, 0)
            da = CATransform3DScale(da, 14.0/10, 14.0/10, 1)
            da = CATransform3DTranslate(da, -m.x, -m.y, 0)
            let pulsa = CABasicAnimation(keyPath: "transform")
            pulsa.fromValue = da; pulsa.toValue = CATransform3DIdentity
            pulsa.duration = 55.0/100; pulsa.timingFunction = curva
            l.add(pulsa, forKey: "pulsa")
        }
        // ② il «+1» sale e svanisce, sopra la cifra
        if let carta = window?.contentView {
            let piu = NSTextField(labelWithString: "+\(quanti)")
            piu.font = Caratteri.tondo(13, .heavy)
            piu.textColor = Tinte.toro
            piu.sizeToFit()
            let dove = c.numero.convert(c.numero.bounds, to: carta)
            piu.frame.origin = CGPoint(x: dove.midX - piu.frame.width / 2, y: dove.maxY - 2)
            carta.addSubview(piu)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 11.0/10
                ctx.timingFunction = curva
                ctx.allowsImplicitAnimation = true
                piu.animator().setFrameOrigin(CGPoint(x: piu.frame.origin.x, y: piu.frame.origin.y + 18))
                piu.animator().alphaValue = 0
            }, completionHandler: { piu.removeFromSuperview() })
        }
        // ③ l'arancio si scioglie piano nella neve
        DispatchQueue.main.asyncAfter(deadline: .now() + 14.0/10) {
            let sfuma = CATransition()
            sfuma.type = .fade
            sfuma.duration = 8.0/10
            c.numero.layer?.add(sfuma, forKey: "sfuma")
            c.numero.textColor = Tinte.neve
        }
    }
}
