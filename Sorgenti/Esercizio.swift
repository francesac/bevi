//  Esercizio.swift — la carta dello spagnolo, che arriva subito dopo il cartello BEVI.
//
//  A tutto schermo, come il cartello: un velo sfocato su ogni monitor e la carta al centro
//  di quello principale. Resta finché non rispondi (o non la salti) e si prende la tastiera,
//  perché la risposta si scrive lì — l'app sotto non riceve niente finché la carta c'è.
//
//  Tre momenti: la domanda → (se è a voce) l'ascolto → il resoconto: com'è andata, cosa
//  hai risposto, la forma giusta, cosa vuol dire in italiano, il perché. Dal resoconto un
//  clic ovunque (o Invio, o Esc) spegne tutto. Il voto si segna alla chiusura, così
//  «l'avevo detta giusta» può ancora correggerlo.
//
//  ⭐ Non resta mai sopra una chiamata: se la webcam si accende, o se non sei davanti al
//  Mac da 5 minuti, se ne va da sola senza segnare niente.

import Cocoa

private final class PannelloEsercizio: NSPanel {
    var allEsc: (() -> Void)?
    var allInvio: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { allEsc?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { allInvio?(); return }   // Invio, Invio del tastierino
        super.keyDown(with: event)
    }
}

final class Esercizio: NSObject, NSTextFieldDelegate {

    /// Una carta per volta: se la precedente è ancora lì, il promemoria nuovo non ne apre un'altra.
    private static var inCorso: Esercizio?
    static var aperto: Bool { inCorso != nil }

    /// Solo per il collaudo (`Bevi --spagnolo completa --risponde estaba`): la carta si
    /// risponde da sola dopo un secondo e mezzo, così il resoconto si guarda senza mani.
    static var rispostaDiProva: String?

    /// `bevi`: la riga del bicchiere («bicchiere 5 di 8 · sono le 14:16»). Con lei la carta È il
    /// promemoria: il «Bevi» sta sotto l'esercizio, nello stesso riquadro, col suono del cartello.
    /// Torna `false` se la carta non si apre (un'altra aperta, nessuna scheda): chi chiama mostra
    /// allora il cartello da solo, perché il bicchiere non resti senza avviso.
    @discardableResult
    static func mostra(piede: String, voce: Bool = true, scheda: Scheda? = nil,
                       bevi: String? = nil, suono: String? = nil) -> Bool {
        guard inCorso == nil, let s = scheda ?? Quaderno.condiviso.prossima() else { return false }
        let e = Esercizio(s, piede: piede, voce: voce)
        e.bevi = bevi
        e.suono = suono
        inCorso = e
        e.apri()
        return true
    }

    // ── stato ─────────────────────────────────────────────────────────────────

    private let scheda: Scheda
    private let piedeTesto: String
    private var bevi: String?
    private var suono: String?
    private let parlaAdAltaVoce: Bool
    private var esito: Esito?
    private var detto = ""
    private let orecchio = Orecchio()
    private var inAscolto = false
    private var ultimoCambio = Date()
    private var inizioAscolto = Date()
    private var sorveglia: Timer?
    private var guardiano: Timer?
    private var clic: Any?
    private var risposta = ""          // quello che ha scritto, scelto o detto: va nel resoconto
    private var aspettaVoto = false    // senza orecchio il voto lo dà lui: il clic a vuoto non chiude
    private var chiudendo = false
    private var soluzioneIntera = ""
    private var contaPiede: NSTextField?

    private let finestra: PannelloEsercizio
    private var veli: [NSWindow] = []
    private let colonna = NSStackView()
    private let larghezza: CGFloat = 520
    private let margine: CGFloat = 30

    // pezzi che cambiano
    private var campo: NSTextField?
    private var opzioni: [Pillola] = []
    private let bottone: BottonePieno
    private let secondari = NSStackView()
    private let zonaEsito = NSStackView()
    private let ascolto = scritta("", corpo: 14, colore: Colori.tenue)

    private init(_ s: Scheda, piede: String, voce: Bool) {
        scheda = s
        piedeTesto = piede
        parlaAdAltaVoce = voce
        finestra = PannelloEsercizio(contentRect: NSRect(x: 0, y: 0, width: 384, height: 200),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        bottone = BottonePieno("", azione: #selector(Esercizio.principale), bersaglio: NSNull())
        super.init()
        bottone.target = self
    }

    // ── costruzione ───────────────────────────────────────────────────────────

    private var aVoceVera: Bool { scheda.tipo.aVoce && Orecchio.disponibile }

    private func apri() {
        finestra.isOpaque = false
        finestra.backgroundColor = .clear
        finestra.hasShadow = true
        // sopra il velo, e il velo sopra tutto: anche le app a schermo intero, su ogni Scrivania
        finestra.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        finestra.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        finestra.hidesOnDeactivate = false
        finestra.becomesKeyOnlyIfNeeded = false
        finestra.appearance = NSAppearance(named: .darkAqua)
        finestra.allEsc = { [weak self] in
            guard let self else { return }
            self.chiudi(segna: self.esito != nil && !self.aspettaVoto)
        }
        finestra.allInvio = { [weak self] in self?.principale() }

        let carta = Carta(sfuma: [Colori.cimaCarta, Colori.fondoCarta], raggio: 16)
        carta.translatesAutoresizingMaskIntoConstraints = false
        finestra.contentView = carta

        colonna.orientation = .vertical
        colonna.alignment = .leading
        colonna.spacing = 10
        colonna.translatesAutoresizingMaskIntoConstraints = false
        carta.addSubview(colonna)
        NSLayoutConstraint.activate([
            carta.widthAnchor.constraint(equalToConstant: larghezza),
            colonna.topAnchor.constraint(equalTo: carta.topAnchor, constant: margine - 4),
            colonna.leadingAnchor.constraint(equalTo: carta.leadingAnchor, constant: margine),
            colonna.trailingAnchor.constraint(equalTo: carta.trailingAnchor, constant: -margine),
            colonna.bottomAnchor.constraint(equalTo: carta.bottomAnchor, constant: -margine + 6),
        ])

        // testa: che esercizio è · «Salta»
        let testa = NSStackView()
        testa.orientation = .horizontal
        let tipo = scritta("ESPAÑOL  ·  \(scheda.tipo.etichetta)", corpo: 10.5, peso: .semibold,
                           colore: Colori.acqua, spaziatura: 1.2)
        let salta = TestoCliccabile("Salta", azione: #selector(salta), bersaglio: self)
        testa.addArrangedSubview(tipo)
        testa.addArrangedSubview(NSView())
        testa.addArrangedSubview(salta)
        aggiungi(testa, pieno: true)

        aggiungi(scritta(consegnaVera, corpo: 12, colore: Colori.tenue))
        colonna.setCustomSpacing(4, after: colonna.arrangedSubviews.last!)
        aggiungi(aCapo(scheda.domanda, corpo: scheda.domanda.count > 60 ? 18 : 22, peso: .semibold),
                 pieno: true)
        if let a = scheda.aiuto { aggiungi(scritta(a, corpo: 13, colore: Colori.tenue)) }
        if scheda.tipo == .parla, let n = scheda.nota {
            aggiungi(aCapo(n, corpo: 12, colore: Colori.tenue), pieno: true)
        }

        rispostaPerTipo()

        zonaEsito.orientation = .vertical
        zonaEsito.alignment = .leading
        zonaEsito.spacing = 6
        zonaEsito.isHidden = true
        aggiungi(zonaEsito, pieno: true)

        secondari.orientation = .horizontal
        secondari.spacing = 16
        let fondo = NSStackView(views: [bottone, secondari])
        fondo.orientation = .horizontal
        fondo.spacing = 16
        bottone.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        aggiungi(fondo)
        colonna.setCustomSpacing(16, after: zonaEsito)

        aggiungi(filo(), pieno: true)
        let fatte = Esercizio.fatte(Quaderno.condiviso.numeri())
        if let b = bevi {
            // il promemoria dell'acqua, sotto l'esercizio: lo stesso avviso, ⛔ un secondo dopo il primo
            let goccia = scritta("💧", corpo: 26)
            let parole = NSStackView(views: [
                scritta("Bevi", corpo: 22, peso: .bold, colore: Colori.acqua),
                scritta(b, corpo: 12, colore: Colori.tenue),
            ])
            parole.orientation = .vertical
            parole.alignment = .leading
            parole.spacing = 0
            let conta = scritta(fatte, corpo: 11, colore: Colori.tenue)
            contaPiede = conta
            let riga = NSStackView(views: [goccia, parole, NSView(), conta])
            riga.orientation = .horizontal
            riga.alignment = .centerY
            riga.spacing = 12
            colonna.setCustomSpacing(14, after: colonna.arrangedSubviews.last!)
            aggiungi(riga, pieno: true)
        } else {
            let conta = scritta("\(piedeTesto)  ·  \(fatte)", corpo: 11, colore: Colori.tenue)
            contaPiede = conta
            aggiungi(conta)
        }

        impostaPrimoStato()
        posa(prima: true)

        // il velo su ogni schermo, lo stesso del cartello: dal bicchiere alla carta non c'è stacco
        veli = NSScreen.screens.map(velo)
        for v in veli { v.alphaValue = 0; v.orderFrontRegardless() }

        // entrata: lo stesso gesto del pannello — dissolvenza e risalita di 18 punti
        finestra.alphaValue = 0
        let arrivo = finestra.frame
        finestra.setFrame(arrivo.offsetBy(dx: 0, dy: -18), display: false)
        // davanti anche se Bevi non è l'app attiva, poi la tastiera: è un pannello che non
        // attiva l'app, quindi la prende senza togliere il primo piano a chi stava sotto
        finestra.orderFrontRegardless()
        finestra.makeKey()
        if let campo { finestra.makeFirstResponder(campo) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = curva
            for v in veli { v.animator().alphaValue = 1 }
            finestra.animator().alphaValue = 1
            finestra.animator().setFrame(arrivo, display: true)
        }

        // da qui in poi un clic fuori dai bottoni, a resoconto pronto, spegne tutto
        clic = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] ev in
            guard let self, self.esito != nil, !self.aspettaVoto else { return ev }
            if ev.window === self.finestra, let vista = self.finestra.contentView,
               let sotto = vista.hitTest(vista.convert(ev.locationInWindow, from: nil)),
               sotto is NSControl { return ev }
            annota("spagnolo: clic, chiusa")
            self.chiudi(segna: true)
            return nil
        }
        if let r = Esercizio.rispostaDiProva {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                annota("collaudo: carta \(Int(self.finestra.frame.width))×\(Int(self.finestra.frame.height)) "
                       + "visibile \(self.finestra.isVisible) tastiera \(self.finestra.isKeyWindow) "
                       + "alfa \(self.finestra.alphaValue) in \(self.finestra.frame.origin) n \(self.finestra.windowNumber)")
                self.fotografa("domanda")
                if let p = self.opzioni.first(where: { $0.title.contains(r) }) { self.sceglie(p) } else {
                    self.campo?.stringValue = r
                    self.principale()
                }
                // e si toglie da sola: la prova non deve restare sullo schermo di nessuno
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.fotografa("resoconto") }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.chiudi(segna: false) }
            }
        }
        // e non resta mai sopra una chiamata che parte, né davanti a una sedia vuota
        guardiano = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            if webcamInUso() { annota("spagnolo: webcam accesa, via"); self.chiudi(segna: false); return }
            if self.esito == nil && !self.inAscolto && fermoDaSecondi() > 300 {
                annota("spagnolo: nessuno davanti, via"); self.chiudi(segna: false)
            }
        }

        // il suono del promemoria, poi la voce: lasciata un attimo dopo, per non parlarci sopra
        var attesa = 0.0
        if let nome = suono, let suona = NSSound(named: nome) { suona.play(); attesa = 0.9 }
        if parlaAdAltaVoce && (scheda.tipo == .ripeti || scheda.tipo == .parla) {
            DispatchQueue.main.asyncAfter(deadline: .now() + attesa) { [weak self] in
                guard let self, !self.chiudendo, self.esito == nil, !self.inAscolto else { return }
                Bocca.di(self.scheda.tipo == .ripeti ? self.scheda.es : self.scheda.domanda,
                         lenta: self.scheda.tipo == .ripeti)
            }
        }
    }

    private var consegnaVera: String {
        if scheda.tipo.aVoce && !Orecchio.disponibile { return "Dilla ad alta voce, poi guarda la soluzione" }
        return scheda.tipo.consegna
    }

    private func aggiungi(_ v: NSView, pieno: Bool = false) {
        colonna.addArrangedSubview(v)
        if pieno { v.widthAnchor.constraint(equalTo: colonna.widthAnchor).isActive = true }
    }

    private func aCapo(_ t: String, corpo: CGFloat, peso: NSFont.Weight = .regular,
                       colore: NSColor = Colori.testo) -> NSTextField {
        let c = NSTextField(wrappingLabelWithString: "")
        c.attributedStringValue = NSAttributedString(string: t, attributes: [
            .font: NSFont.systemFont(ofSize: corpo, weight: peso), .foregroundColor: colore])
        c.preferredMaxLayoutWidth = larghezza - 2 * margine
        c.isSelectable = false
        return c
    }

    private func rispostaPerTipo() {
        switch scheda.tipo {
        case .parola, .completa:
            let fondo = Carta(tinta: Colori.pillola, raggio: 10)
            let f = NSTextField()
            f.isBezeled = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = .systemFont(ofSize: 17)
            f.textColor = Colori.testo
            f.placeholderAttributedString = NSAttributedString(
                string: "scrivi e premi Invio",
                attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: Colori.tenue])
            f.delegate = self
            f.translatesAutoresizingMaskIntoConstraints = false
            fondo.addSubview(f)
            NSLayoutConstraint.activate([
                fondo.heightAnchor.constraint(equalToConstant: 40),
                f.leadingAnchor.constraint(equalTo: fondo.leadingAnchor, constant: 12),
                f.trailingAnchor.constraint(equalTo: fondo.trailingAnchor, constant: -12),
                f.centerYAnchor.constraint(equalTo: fondo.centerYAnchor),
            ])
            campo = f
            aggiungi(fondo, pieno: true)
        case .scegli:
            let elenco = NSStackView()
            elenco.orientation = .vertical
            elenco.alignment = .leading
            elenco.spacing = 6
            for (i, o) in (scheda.opzioni ?? [scheda.es]).enumerated() {
                let p = Pillola(o, valore: i, azione: #selector(sceglie(_:)), bersaglio: self)
                p.removeConstraints(p.constraints.filter { $0.firstAttribute == .height })
                p.heightAnchor.constraint(equalToConstant: 32).isActive = true
                opzioni.append(p)
                elenco.addArrangedSubview(p)
                p.widthAnchor.constraint(equalTo: elenco.widthAnchor).isActive = true
            }
            aggiungi(elenco, pieno: true)
        case .ripeti, .traduci, .parla:
            ascolto.isHidden = true
            ascolto.lineBreakMode = .byWordWrapping
            ascolto.maximumNumberOfLines = 3
            ascolto.preferredMaxLayoutWidth = larghezza - 2 * margine
            aggiungi(ascolto, pieno: true)
        }
    }

    private func impostaPrimoStato() {
        secondari.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch scheda.tipo {
        case .parola, .completa:
            titolo("Controlla")
        case .scegli:
            bottone.isHidden = true
        case .ripeti, .traduci, .parla:
            titolo(aVoceVera ? "🎙  Parla" : "Mostra la soluzione")
            if scheda.tipo == .ripeti {
                secondari.addArrangedSubview(TestoCliccabile("Riascolta", azione: #selector(riascolta),
                                                             bersaglio: self))
            }
        }
    }

    private func titolo(_ t: String) {
        bottone.isHidden = false
        bottone.title = t
        bottone.attributedTitle = NSAttributedString(string: "  \(t)  ", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Colori.scuro])
    }

    /// Solo per il collaudo: la carta com'è adesso, in PNG, nella cartella `BEVI_SCATTI`.
    private func fotografa(_ nome: String) {
        guard let cartella = ProcessInfo.processInfo.environment["BEVI_SCATTI"],
              let v = finestra.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: cartella).appendingPathComponent("\(nome).png"))
    }

    /// Il velo di uno schermo: la Scrivania sfocata e tinta di blu profondo, come il cartello.
    /// I clic che ci cadono sopra li raccoglie il guardiano dei clic (in `apri`).
    private func velo(_ schermo: NSScreen) -> NSWindow {
        let cornice = schermo.frame
        let w = NSWindow(contentRect: cornice, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let radice = NSView(frame: NSRect(origin: .zero, size: cornice.size))
        radice.wantsLayer = true
        let sfoca = NSVisualEffectView(frame: radice.bounds)
        sfoca.material = .hudWindow
        sfoca.blendingMode = .behindWindow
        sfoca.state = .active
        sfoca.autoresizingMask = [.width, .height]
        radice.addSubview(sfoca)
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
        w.contentView = radice
        return w
    }

    /// Lo schermo dove sta il mouse, cioè dove stai guardando; deciso una volta all'apertura.
    private lazy var dove: NSScreen? = {
        let m = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(m, $0.frame, false) } ?? NSScreen.main
    }()

    /// Misura e mette la carta al centro dello schermo dove stai guardando, un filo sopra la metà
    /// (dove cade l'occhio). Se cresce, cresce da tutte e due le parti e resta centrata.
    private func posa(prima: Bool = false) {
        guard let carta = finestra.contentView else { return }
        carta.layoutSubtreeIfNeeded()
        let misura = carta.fittingSize
        let schermo = (dove ?? NSScreen.screens[0]).frame
        let centro = NSPoint(x: schermo.midX, y: schermo.midY + schermo.height * 0.06)
        let cornice = NSRect(x: (centro.x - misura.width / 2).rounded(), y: (centro.y - misura.height / 2).rounded(),
                          width: misura.width, height: misura.height)
        if prima {
            finestra.setFrame(cornice, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = curva
                finestra.animator().setFrame(cornice, display: true)
            }
        }
    }

    // ── le azioni ─────────────────────────────────────────────────────────────

    func control(_ c: NSControl, textView: NSTextView, doCommandBy comando: Selector) -> Bool {
        if comando == #selector(NSResponder.insertNewline(_:)) { principale(); return true }
        return false
    }

    @objc private func principale() {
        if esito != nil { chiudi(segna: true); return }
        switch scheda.tipo {
        case .parola, .completa:
            let r = campo?.stringValue ?? ""
            guard !r.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            risposta = r.trimmingCharacters(in: .whitespaces)
            mostraEsito(Correttore.scritta(r, scheda))
        case .scegli:
            break
        case .ripeti, .traduci, .parla:
            if !aVoceVera { mostraSoluzioneDaGiudicare(); return }
            inAscolto ? smettiDiAscoltare() : comincia()
        }
    }

    @objc private func sceglie(_ p: Pillola) {
        guard esito == nil else { return }
        let presa = scheda.opzioni?[p.valore] ?? ""
        for o in opzioni { o.scelta = (o === p) }
        risposta = presa
        let giusto = Correttore.pulisci(presa) == Correttore.pulisci(scheda.es)
        mostraEsito(Correttore.Verdetto(esito: giusto ? .giusto : .sbagliato, messaggio: scheda.es))
    }

    @objc private func riascolta() {
        Bocca.di(scheda.tipo == .parla ? scheda.domanda : scheda.es, lenta: true)
    }

    @objc private func salta() { chiudi(segna: false) }

    // ── l'ascolto ─────────────────────────────────────────────────────────────

    private func comincia() {
        Bocca.zitta()
        Orecchio.chiediPermesso { [weak self] ok in
            guard let self else { return }
            guard ok else { self.senzaMicrofono(); return }
            self.inAscolto = true
            self.detto = ""
            self.titolo("■  Ho finito")
            self.ascolto.isHidden = false
            self.scriviAscolto("ti ascolto…", colore: Colori.tenue)
            self.posa()
            self.inizioAscolto = Date()
            self.ultimoCambio = Date()
            self.orecchio.ascolta(mentre: { [weak self] testo in
                guard let self, self.inAscolto else { return }
                if testo != self.detto { self.detto = testo; self.ultimoCambio = Date() }
                self.scriviAscolto(testo.isEmpty ? "ti ascolto…" : "«\(testo)»", colore: Colori.testo)
            }, errore: { [weak self] messaggio in
                self?.inAscolto = false
                self?.scriviAscolto(messaggio, colore: Colori.tenue)
                self?.titolo("Mostra la soluzione")
                self?.sorveglia?.invalidate()
            })
            // si chiude da sé dopo una pausa: chi ha finito di parlare non deve cercare il bottone
            self.sorveglia = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                guard let self, self.inAscolto else { return }
                let zitto = Date().timeIntervalSince(self.ultimoCambio)
                let dentro = Date().timeIntervalSince(self.inizioAscolto)
                let tetto: Double = self.scheda.tipo == .parla ? 45 : 15
                if (!self.detto.isEmpty && zitto > (self.scheda.tipo == .parla ? 2.6 : 1.6))
                    || dentro > tetto || (self.detto.isEmpty && dentro > 9) {
                    self.smettiDiAscoltare()
                }
            }
        }
    }

    private func scriviAscolto(_ t: String, colore: NSColor) {
        ascolto.attributedStringValue = NSAttributedString(string: t, attributes: [
            .font: NSFont.systemFont(ofSize: 14), .foregroundColor: colore])
        posa()
    }

    private func smettiDiAscoltare() {
        guard inAscolto else { return }
        inAscolto = false
        sorveglia?.invalidate()
        titolo("…")
        orecchio.basta { [weak self] finale in
            guard let self else { return }
            let testo = finale.isEmpty ? self.detto : finale
            guard !testo.isEmpty else {
                self.scriviAscolto("Non ti ho sentito. Riprova, un po' più vicino al Mac.", colore: Colori.tenue)
                self.titolo("🎙  Riprova")
                return
            }
            self.detto = testo
            self.risposta = testo
            self.ascolto.isHidden = true     // «hai detto» lo ripete il resoconto, accanto alla correzione
            self.mostraEsito(Correttore.detta(testo, self.scheda))
        }
    }

    private func senzaMicrofono() {
        scriviAscolto("Il microfono è spento per Bevi: si accende in Impostazioni di Sistema › Privacy › Microfono.",
                      colore: Colori.tenue)
        ascolto.isHidden = false
        titolo("Mostra la soluzione")
        posa()
    }

    /// Senza orecchio (Mac vecchio o microfono negato) si fa all'antica: la dici, guardi,
    /// e ti dai il voto da solo. Il richiamo a voce c'è stato lo stesso.
    private func mostraSoluzioneDaGiudicare() {
        mostraEsito(Correttore.Verdetto(esito: .quasi, messaggio: scheda.es), giudichi: true)
    }

    // ── il resoconto ──────────────────────────────────────────────────────────

    /// Cosa vuol dire, in italiano, la forma giusta. Dove la domanda è già in italiano
    /// (la parola, la frase da dire) è la domanda stessa; altrove è il campo `it` della scheda.
    private var inItaliano: String? {
        switch scheda.tipo {
        case .parola, .traduci: return scheda.domanda
        default: return scheda.it
        }
    }

    private var verbo: String {
        switch scheda.tipo {
        case .parola, .completa: return "Hai scritto"
        case .scegli: return "Hai scelto"
        default: return "Hai detto"
        }
    }

    /// I progressi nel piede: le viste crescono con le schede nuove, le giuste a ogni risposta
    /// giusta (anche su una già vista), le sapute dopo una settimana senza sbagliare.
    static func fatte(_ n: Quaderno.Numeri) -> String {
        guard n.viste > 0 else { return "la prima scheda" }
        return "\(n.viste) viste  ·  \(n.giuste) giuste  ·  \(n.sapute) \(n.sapute == 1 ? "saputa" : "sapute") su \(n.totale)"
    }

    /// Il piede si riscrive appena si risponde: prima restava fermo ai numeri di quando la carta
    /// si era aperta, perché la risposta si salva solo alla chiusura (31/10).
    private func aggiornaPiede(_ e: Esito) {
        guard let c = contaPiede, c.attributedStringValue.length > 0 else { return }
        let n = Esercizio.fatte(Quaderno.condiviso.numeri(conRisposta: (scheda, e)))
        let testo = bevi == nil ? "\(piedeTesto)  ·  \(n)" : n
        let stile = c.attributedStringValue.attributes(at: 0, effectiveRange: nil)
        c.attributedStringValue = NSAttributedString(string: testo, attributes: stile)
    }

    private func mostraEsito(_ v: Correttore.Verdetto, giudichi: Bool = false) {
        esito = v.esito
        aspettaVoto = giudichi
        if !giudichi { aggiornaPiede(v.esito) }
        campo?.isEditable = false
        finestra.makeFirstResponder(nil)     // via la selezione, e Invio torna alla carta: chiude
        zonaEsito.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // la frase intera, quando la domanda ha il buco (anche nelle scelte): si impara la frase, non la parola
        let completa = scheda.domanda.replacingOccurrences(of: "___", with: scheda.es)
            .trimmingCharacters(in: CharacterSet(charactersIn: "«»"))
        let soluzione = scheda.domanda.contains("___") && scheda.tipo != .parola ? completa : scheda.es
        // nella scelta resta accesa quella giusta: la tua, se era sbagliata, la dice la riga «Hai scelto»
        for o in opzioni { o.scelta = Correttore.pulisci(o.title) == Correttore.pulisci(scheda.es) }
        soluzioneIntera = soluzione
        let tua = risposta.trimmingCharacters(in: .whitespacesAndNewlines)

        // ① com'è andata
        if !giudichi {
            let (parola, colore): (String, NSColor)
            switch v.esito {
            case .giusto:    (parola, colore) = ("¡Muy bien!", Colori.verde)
            case .quasi:     (parola, colore) = ("Casi — quasi giusta", Colori.acqua)
            case .sbagliato: (parola, colore) = ("No, si dice così", Colori.corallo)
            case .libero:    (parola, colore) = ("Salvata nel diario", Colori.verde)
            }
            zonaEsito.addArrangedSubview(scritta(parola, corpo: 16, peso: .semibold, colore: colore))
        }
        // ② cosa hai risposto tu, se non era già la forma insegnata
        if !tua.isEmpty, v.esito != .giusto || Correttore.pulisci(tua) != Correttore.pulisci(scheda.es) {
            let coda = v.esito == .giusto ? ": va bene anche così" : ""
            zonaEsito.addArrangedSubview(aCapo("\(verbo) «\(tua)»\(coda)", corpo: 13.5,
                                               colore: v.esito == .sbagliato ? Colori.corallo : Colori.tenue))
        }
        if v.esito == .quasi && !giudichi && v.messaggio != scheda.es {
            zonaEsito.addArrangedSubview(aCapo(v.messaggio, corpo: 13, colore: Colori.tenue))
        }
        // ③ la forma giusta, grande
        if v.esito == .libero {
            zonaEsito.addArrangedSubview(aCapo("Per esempio: \(scheda.es)", corpo: 18, peso: .semibold))
        } else {
            zonaEsito.addArrangedSubview(aCapo(soluzione, corpo: 20, peso: .semibold))
        }
        // ④ cosa vuol dire
        if let it = inItaliano, !it.isEmpty {
            zonaEsito.addArrangedSubview(aCapo(it, corpo: 15, colore: Colori.testo.withAlphaComponent(0.82)))
        }
        // ⑤ il perché
        if let n = scheda.nota, scheda.tipo != .parla {
            zonaEsito.addArrangedSubview(aCapo(n, corpo: 12.5, colore: Colori.tenue))
        }
        for riga in zonaEsito.arrangedSubviews {
            riga.widthAnchor.constraint(equalTo: zonaEsito.widthAnchor).isActive = true
        }
        if zonaEsito.arrangedSubviews.count > 1 {
            zonaEsito.setCustomSpacing(10, after: zonaEsito.arrangedSubviews[0])
        }
        zonaEsito.isHidden = false

        secondari.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if giudichi {
            // tre pillole al posto del bottone: il voto lo dai tu
            bottone.isHidden = true
            for (t, e) in [("La sapevo", Esito.giusto), ("Quasi", .quasi), ("No", .sbagliato)] {
                let p = Pillola(t, valore: e == .giusto ? 0 : (e == .quasi ? 1 : 2),
                                azione: #selector(voto(_:)), bersaglio: self)
                secondari.addArrangedSubview(p)
            }
        } else {
            titolo("Avanti")
            if scheda.tipo != .parla {
                secondari.addArrangedSubview(TestoCliccabile("Riascolta", azione: #selector(riascoltaSoluzione),
                                                             bersaglio: self))
            }
            // il riconoscimento sbaglia anche lui: l'ultima parola sul parlato è tua
            if scheda.tipo.aVoce && scheda.tipo != .parla && v.esito != .giusto {
                secondari.addArrangedSubview(TestoCliccabile("L'avevo detta giusta",
                                                             azione: #selector(avevoRagione), bersaglio: self))
            }
            secondari.addArrangedSubview(scritta("clic ovunque per chiudere", corpo: 11, colore: Colori.tenue))
        }
        posa()

        if parlaAdAltaVoce && scheda.tipo != .parla { Bocca.di(soluzione) }
    }

    @objc private func riascoltaSoluzione() {
        Bocca.di(soluzioneIntera, lenta: true)
    }

    @objc private func avevoRagione() {
        esito = .giusto
        chiudi(segna: true)
    }

    @objc private func voto(_ p: Pillola) {
        esito = [Esito.giusto, .quasi, .sbagliato][p.valore]
        chiudi(segna: true)
    }

    // ── chiusura ──────────────────────────────────────────────────────────────

    private func chiudi(segna: Bool) {
        guard !chiudendo else { return }   // un clic e il guardiano possono arrivare insieme
        chiudendo = true
        sorveglia?.invalidate()
        guardiano?.invalidate()
        if let c = clic { NSEvent.removeMonitor(c); clic = nil }
        Bocca.zitta()
        if inAscolto { inAscolto = false; orecchio.annulla() }
        if segna, let e = esito {
            Quaderno.condiviso.segna(scheda, e, trascritto: detto)
            annota("spagnolo \(scheda.id)")
        } else {
            // senza un esito la scheda va in fondo alla fila (il collaudo invece non tocca niente)
            if Esercizio.rispostaDiProva == nil { Quaderno.condiviso.rinvia(scheda) }
            annota("spagnolo saltato \(scheda.id)")
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = curva
            finestra.animator().alphaValue = 0
            for v in veli { v.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.finestra.orderOut(nil)
            for v in self.veli { v.orderOut(nil) }
            self.veli = []
            Esercizio.inCorso = nil
        })
    }
}
