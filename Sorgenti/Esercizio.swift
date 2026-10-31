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
//  🎨 31/10: due stanze. In cima la fascia Bevi, che dice solo di bere (⛔ conti di bicchieri:
//  «senza conteggio, senza niente»); sotto lo spagnolo, con la tavolozza sua (Tinte.swift).
//  ⭐ E senza testo, dove un segno basta (31/10: «se può essere spiegato senza testo, deve
//  essere spiegato senza testo»): ⛔ consegne, ⛔ cartellino, ⛔ titoli dell'esito, ⛔ «clic ovunque»,
//  ⛔ una cosa detta due volte. L'esito è un sigillo; la correzione si vede DENTRO la frase
//  (il buco si riempie, le parole mancate si sottolineano, le tue sbagliate si barrano).
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

    /// `bevi`: se c'è, la carta È il promemoria: la fascia Bevi sta in cima, nello stesso riquadro,
    /// col suono del cartello. Il testo che porta (il bicchiere, l'ora) ⛔ si mostra più: dal 31/10
    /// la fascia dice solo di bere.
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
    private var progressi: Progressi?
    private lazy var domandaCampo: NSTextField = domanda()
    private var corpoDomanda: CGFloat { scheda.domanda.count > 60 ? 21 : 26 }

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
    private let banda = NSView()                // la banda dell'esito, a tutta larghezza
    private let fondoBottoni = NSStackView()
    private var filoPiede: NSView?
    private var scala: Scala?
    private let ascolto = scritta("", corpo: 14, colore: Tinte.tenue)

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

        let carta = Carta(tinta: Tinte.nibbio, raggio: 22)
        carta.layer?.borderWidth = 0
        carta.layer?.masksToBounds = true          // la fascia Bevi segue gli angoli tondi
        carta.translatesAutoresizingMaskIntoConstraints = false
        finestra.contentView = carta

        // ① in cima la fascia Bevi, se la carta è il promemoria · ② sotto lo spagnolo ·
        // ③ la banda dell'esito, che compare alla risposta · ④ il piede coi numeri
        let stanza = NSView()
        stanza.translatesAutoresizingMaskIntoConstraints = false
        let piede = NSView()
        let pila = NSStackView(views: (bevi != nil ? [fasciaBevi()] : []) + [stanza, banda, piede])
        pila.orientation = .vertical
        pila.spacing = 0
        pila.translatesAutoresizingMaskIntoConstraints = false
        carta.addSubview(pila)
        for v in pila.arrangedSubviews { v.widthAnchor.constraint(equalTo: pila.widthAnchor).isActive = true }
        banda.wantsLayer = true
        banda.isHidden = true

        colonna.orientation = .vertical
        colonna.alignment = .leading
        colonna.spacing = 10
        colonna.translatesAutoresizingMaskIntoConstraints = false
        stanza.addSubview(colonna)
        NSLayoutConstraint.activate([
            carta.widthAnchor.constraint(equalToConstant: larghezza),
            pila.topAnchor.constraint(equalTo: carta.topAnchor),
            pila.leadingAnchor.constraint(equalTo: carta.leadingAnchor),
            pila.trailingAnchor.constraint(equalTo: carta.trailingAnchor),
            pila.bottomAnchor.constraint(equalTo: carta.bottomAnchor),
            colonna.topAnchor.constraint(equalTo: stanza.topAnchor, constant: 14),
            colonna.leadingAnchor.constraint(equalTo: stanza.leadingAnchor, constant: margine),
            colonna.trailingAnchor.constraint(equalTo: stanza.trailingAnchor, constant: -margine),
            colonna.bottomAnchor.constraint(equalTo: stanza.bottomAnchor, constant: -24),
        ])

        // la testa, come la barra di Duolingo: a sinistra i gradini di QUESTA scheda (cosa c'è
        // in gioco), a destra la ✕ che la salta. ⛔ cartellino, ⛔ consegna: l'esercizio lo dice la forma
        let salta = Icona("xmark", corpo: 13, aiuto: "Salta", azione: #selector(salta), bersaglio: self)
        var testa: [NSView] = []
        if scheda.tipo != .parla {
            let s = Scala(prima: Quaderno.condiviso.ricordo(scheda).scatola)
            s.toolTip = s.didascalia.0
            scala = s
            testa.append(s)
        }
        let rigaTesta = NSStackView(views: testa + [NSView(), salta])
        rigaTesta.orientation = .horizontal
        rigaTesta.alignment = .centerY
        aggiungi(rigaTesta, pieno: true)
        colonna.setCustomSpacing(8, after: rigaTesta)
        // la ✕ esce di 10 punti dalla colonna: è l'aria del suo bottone, il segno resta in riga col testo
        salta.trailingAnchor.constraint(equalTo: rigaTesta.trailingAnchor, constant: 10).isActive = true

        aggiungi(domandaCampo)
        colonna.setCustomSpacing(6, after: domandaCampo)
        if let a = scheda.aiuto { aggiungi(testo(a, Caratteri.tondo(14), Tinte.tenue)) }
        if scheda.tipo == .parla, let n = scheda.nota {
            aggiungi(aCapo(n, corpo: 12.5, colore: Tinte.tenue), pieno: true)
        }
        colonna.setCustomSpacing(18, after: colonna.arrangedSubviews.last!)

        rispostaPerTipo()

        // il bottone c'è solo dove serve: a voce è il microfono, un tondo; il campo si conferma
        // dal suo ⏎, le pillole da sole. ⛔ un ✓ accanto al campo: era la stessa cosa due volte
        secondari.orientation = .horizontal
        secondari.spacing = 14
        fondoBottoni.setViews([bottone, secondari], in: .leading)
        fondoBottoni.orientation = .horizontal
        fondoBottoni.spacing = 14
        fondoBottoni.alignment = .centerY
        bottone.fondo = Tinte.toro
        bottone.ombra = Tinte.granato
        bottone.layer?.cornerRadius = 28
        // un tondo vero: via l'altezza di serie, che col simbolo dentro lo allungava a uovo
        bottone.removeConstraints(bottone.constraints.filter { $0.firstAttribute == .height })
        bottone.widthAnchor.constraint(equalToConstant: 56).isActive = true
        bottone.heightAnchor.constraint(equalToConstant: 56).isActive = true
        bottone.tondo = true
        aggiungi(fondoBottoni)
        fondoBottoni.isHidden = !scheda.tipo.aVoce

        let linea = filo()
        linea.layer?.backgroundColor = Tinte.incavo.cgColor
        linea.translatesAutoresizingMaskIntoConstraints = false
        filoPiede = linea
        let numeri = Progressi(Quaderno.condiviso.numeri())
        progressi = numeri
        // da solo (senza la fascia Bevi) il piede dice anche da dove viene la carta
        let riga = NSStackView(views: bevi != nil ? [numeri, NSView()]
                                                  : [numeri, NSView(), testo(piedeTesto, Caratteri.tondo(11.5), Tinte.tenue)])
        riga.orientation = .horizontal
        riga.alignment = .centerY
        riga.translatesAutoresizingMaskIntoConstraints = false
        piede.addSubview(linea)
        piede.addSubview(riga)
        NSLayoutConstraint.activate([
            linea.topAnchor.constraint(equalTo: piede.topAnchor),
            linea.leadingAnchor.constraint(equalTo: piede.leadingAnchor, constant: margine),
            linea.trailingAnchor.constraint(equalTo: piede.trailingAnchor, constant: -margine),
            riga.topAnchor.constraint(equalTo: piede.topAnchor, constant: 16),
            riga.bottomAnchor.constraint(equalTo: piede.bottomAnchor, constant: -18),
            riga.leadingAnchor.constraint(equalTo: piede.leadingAnchor, constant: margine),
            riga.trailingAnchor.constraint(equalTo: piede.trailingAnchor, constant: -margine),
        ])

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
                if self.scheda.tipo.aVoce {         // a voce: come se l'orecchio avesse sentito `r`
                    self.risposta = r; self.detto = r
                    self.mostraEsito(Correttore.detta(r, self.scheda))
                } else if let p = self.opzioni.first(where: { $0.title.contains(r) }) { self.sceglie(p) } else {
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

    private func aggiungi(_ v: NSView, pieno: Bool = false) {
        colonna.addArrangedSubview(v)
        if pieno { v.widthAnchor.constraint(equalTo: colonna.widthAnchor).isActive = true }
    }

    private func aCapo(_ t: String, corpo: CGFloat, peso: NSFont.Weight = .regular,
                       colore: NSColor = Tinte.neve, largo: CGFloat? = nil) -> NSTextField {
        let c = NSTextField(wrappingLabelWithString: "")
        c.attributedStringValue = NSAttributedString(string: t, attributes: [
            .font: Caratteri.tondo(corpo, peso), .foregroundColor: colore])
        c.preferredMaxLayoutWidth = largo ?? larghezza - 2 * margine
        c.isSelectable = false
        return c
    }

    /// La fascia Bevi: acqua piena, la goccia e la parola. ⛔ numeri, ⛔ orari, ⛔ sottotitolo: solo l'invito.
    private func fasciaBevi() -> NSView {
        let fascia = NSView()
        fascia.wantsLayer = true
        fascia.layer?.backgroundColor = Tinte.acqua.cgColor
        let parola = testo("Bevi.", Caratteri.serif(52), Tinte.nibbio)
        let goccia = Goccia()
        let riga = NSStackView(views: [goccia, parola])
        riga.orientation = .horizontal
        riga.alignment = .centerY
        riga.spacing = 18
        riga.translatesAutoresizingMaskIntoConstraints = false
        fascia.addSubview(riga)
        NSLayoutConstraint.activate([
            riga.topAnchor.constraint(equalTo: fascia.topAnchor, constant: 24),
            riga.bottomAnchor.constraint(equalTo: fascia.bottomAnchor, constant: -22),
            riga.leadingAnchor.constraint(equalTo: fascia.leadingAnchor, constant: margine),
        ])
        return fascia
    }

    /// La domanda, grande: il buco «___» si vede in arancio, è lì che si gioca.
    private func domanda() -> NSTextField {
        let testo = NSMutableAttributedString(string: scheda.domanda, attributes: [
            .font: Caratteri.tondo(corpoDomanda, .bold), .foregroundColor: Tinte.neve])
        var da = scheda.domanda.startIndex
        while let r = scheda.domanda.range(of: "___", range: da..<scheda.domanda.endIndex) {
            testo.addAttribute(.foregroundColor, value: Tinte.toro, range: NSRange(r, in: scheda.domanda))
            da = r.upperBound
        }
        let c = NSTextField(wrappingLabelWithString: "")
        c.attributedStringValue = testo
        c.preferredMaxLayoutWidth = larghezza - 2 * margine - 22    // l'aria per la ✕ nell'angolo
        c.isSelectable = false
        return c
    }

    /// Un testo su una riga col SUO carattere: `scritta` conosce solo quello di sistema, e un
    /// `.font` messo dopo lo scavalca l'attributo già scritto (31/10: «Bevi.» usciva piccolo).
    private func testo(_ t: String, _ f: NSFont, _ c: NSColor, spaziatura: CGFloat = 0) -> NSTextField {
        let campo = NSTextField(labelWithString: t)
        campo.attributedStringValue = NSAttributedString(string: t, attributes: [
            .font: f, .foregroundColor: c, .kern: spaziatura])
        campo.lineBreakMode = .byTruncatingTail
        return campo
    }

    private func spagnola(_ p: Pillola) {
        p.fondi = (Tinte.rilievo, Tinte.incavo, Tinte.toro)
        p.inchiostri = (Tinte.neve.withAlphaComponent(85.0/100), Tinte.neve, Tinte.nibbio)
        p.carattere = { Caratteri.tondo($0, .medium) }
        p.corpo = 14
        p.layer?.cornerRadius = 12
    }

    private func rispostaPerTipo() {
        switch scheda.tipo {
        case .parola, .completa:
            let fondo = Carta(tinta: Tinte.rilievo.withAlphaComponent(55.0/100), raggio: 14)
            fondo.layer?.borderWidth = 2
            fondo.layer?.borderColor = Tinte.bordo.cgColor
            let f = NSTextField()
            f.isBezeled = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = Caratteri.tondo(18, .medium)
            f.textColor = Tinte.neve
            f.delegate = self
            f.translatesAutoresizingMaskIntoConstraints = false
            fondo.addSubview(f)
            // ⛔ «scrivi e premi Invio»: il ⏎ in fondo al campo lo dice; la parola italiana chiede
            // lo spagnolo con la bandiera in testa
            // il ⏎ è anche il bottone: ⛔ un ✓ a parte, che diceva la stessa cosa due volte
            let invio = Icona("return", corpo: 15, aiuto: "Controlla", azione: #selector(principale), bersaglio: self)
            invio.inchiostri = (Tinte.tenue, Tinte.toro)
            fondo.addSubview(invio)
            var testa = fondo.leadingAnchor
            var rientro: CGFloat = 16
            if scheda.tipo == .parola {
                let bandiera = testo("🇪🇸", NSFont.systemFont(ofSize: 20), Tinte.neve)
                bandiera.translatesAutoresizingMaskIntoConstraints = false
                fondo.addSubview(bandiera)
                bandiera.leadingAnchor.constraint(equalTo: fondo.leadingAnchor, constant: 14).isActive = true
                bandiera.centerYAnchor.constraint(equalTo: fondo.centerYAnchor).isActive = true
                testa = bandiera.trailingAnchor
                rientro = 10
            }
            NSLayoutConstraint.activate([
                fondo.heightAnchor.constraint(equalToConstant: 50),
                f.leadingAnchor.constraint(equalTo: testa, constant: rientro),
                f.trailingAnchor.constraint(equalTo: invio.leadingAnchor, constant: -10),
                f.centerYAnchor.constraint(equalTo: fondo.centerYAnchor),
                invio.trailingAnchor.constraint(equalTo: fondo.trailingAnchor, constant: -6),
                invio.centerYAnchor.constraint(equalTo: fondo.centerYAnchor),
            ])
            campo = f
            aggiungi(fondo, pieno: true)
        case .scegli:
            let elenco = NSStackView()
            elenco.orientation = .vertical
            elenco.alignment = .leading
            elenco.spacing = 8
            for (i, o) in (scheda.opzioni ?? [scheda.es]).enumerated() {
                let p = Pillola(o, valore: i, azione: #selector(sceglie(_:)), bersaglio: self)
                spagnola(p)
                p.removeConstraints(p.constraints.filter { $0.firstAttribute == .height })
                p.heightAnchor.constraint(equalToConstant: 40).isActive = true
                opzioni.append(p)
                elenco.addArrangedSubview(p)
                p.widthAnchor.constraint(equalTo: elenco.widthAnchor).isActive = true
            }
            aggiungi(elenco, pieno: true)
        case .ripeti, .traduci, .parla:
            ascolto.isHidden = true
            ascolto.alignment = .left
            ascolto.lineBreakMode = .byWordWrapping
            ascolto.maximumNumberOfLines = 3
            ascolto.preferredMaxLayoutWidth = larghezza - 2 * margine
            aggiungi(ascolto, pieno: true)
        }
    }

    private func impostaPrimoStato() {
        secondari.arrangedSubviews.forEach { $0.removeFromSuperview() }
        switch scheda.tipo {
        case .parola, .completa, .scegli:
            break
        case .ripeti, .traduci, .parla:
            segno(aVoceVera ? "mic.fill" : "eye.fill", aVoceVera ? "Parla" : "Mostra la soluzione")
            if scheda.tipo != .traduci {
                secondari.addArrangedSubview(Icona("speaker.wave.2.fill", aiuto: "Riascolta",
                                                   azione: #selector(riascolta), bersaglio: self))
            }
        }
    }

    /// Il bottone arancio porta un segno, ⛔ una parola: ✓ controlla · 🎙 parla · ■ basta · → avanti.
    private func segno(_ nome: String, _ nome_a_parole: String) {
        bottone.isHidden = false
        bottone.title = ""
        bottone.attributedTitle = NSAttributedString(string: "")
        bottone.image = simbolo(nome, 18, .heavy)
        bottone.imagePosition = .imageOnly
        bottone.contentTintColor = Tinte.nibbio
        bottone.toolTip = nome_a_parole
        bottone.setAccessibilityLabel(nome_a_parole)
    }

    /// Mentre ascolta, il bottone respira: è lui a dire «ti sento», ⛔ una scritta.
    private func respira(_ si: Bool) {
        guard let l = bottone.layer else { return }
        guard si else { l.removeAnimation(forKey: "respira"); return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1; a.toValue = 55.0/100
        a.duration = 7.0/10; a.autoreverses = true; a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        l.add(a, forKey: "respira")
    }

    /// Non ha sentito niente: il bottone fa «no» con la testa e torna al microfono.
    private func scuoti() {
        guard let l = bottone.layer else { return }
        let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
        a.values = [0, -9, 8, -6, 4, -2, 0]
        a.duration = 45.0/100
        l.add(a, forKey: "scuoti")
    }

    /// Solo per il collaudo: la carta com'è adesso, in PNG, nella cartella `BEVI_SCATTI`.
    private func fotografa(_ nome: String) {
        guard let cartella = ProcessInfo.processInfo.environment["BEVI_SCATTI"],
              let v = finestra.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: cartella).appendingPathComponent("\(nome).png"))
    }

    /// Il velo di uno schermo: la Scrivania sfocata e tinta del marrone della carta.
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
        sfumatura.colors = [Tinte.veloSu.cgColor, Tinte.veloGiu.cgColor]
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
            self.segno("stop.fill", "Ho finito")
            self.respira(true)
            self.ascolto.isHidden = true      // compare quando arriva la prima parola
            self.posa()
            self.inizioAscolto = Date()
            self.ultimoCambio = Date()
            self.orecchio.ascolta(mentre: { [weak self] testo in
                guard let self, self.inAscolto else { return }
                if testo != self.detto { self.detto = testo; self.ultimoCambio = Date() }
                guard !testo.isEmpty else { return }
                self.ascolto.isHidden = false
                self.scriviAscolto(testo, colore: Tinte.neve)
            }, errore: { [weak self] messaggio in
                self?.inAscolto = false
                self?.respira(false)
                self?.ascolto.isHidden = false
                self?.scriviAscolto(messaggio, colore: Tinte.tenue)
                self?.segno("eye.fill", "Mostra la soluzione")
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
            .font: Caratteri.tondo(16, .medium), .foregroundColor: colore])
        posa()
    }

    private func smettiDiAscoltare() {
        guard inAscolto else { return }
        inAscolto = false
        sorveglia?.invalidate()
        respira(false)
        segno("ellipsis", "Un attimo")
        orecchio.basta { [weak self] finale in
            guard let self else { return }
            let testo = finale.isEmpty ? self.detto : finale
            guard !testo.isEmpty else {
                // ⛔ «non ti ho sentito»: il bottone scuote la testa e torna al microfono
                self.ascolto.isHidden = true
                self.segno("mic.fill", "Riprova")
                self.scuoti()
                self.posa()
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
                      colore: Tinte.tenue)
        ascolto.isHidden = false
        segno("eye.fill", "Mostra la soluzione")
        posa()
    }

    /// Senza orecchio (Mac vecchio o microfono negato) si fa all'antica: la dici, guardi,
    /// e ti dai il voto da solo. Il richiamo a voce c'è stato lo stesso.
    private func mostraSoluzioneDaGiudicare() {
        mostraEsito(Correttore.Verdetto(esito: .quasi, messaggio: scheda.es), giudichi: true)
    }

    // ── il resoconto ──────────────────────────────────────────────────────────

    /// Cosa vuol dire, in italiano, la forma giusta: il campo `it` della scheda. Dove la domanda
    /// è già in italiano (la parola, la frase da dire) ⛔ si ripete.
    private var inItaliano: String? {
        switch scheda.tipo {
        case .parola, .traduci: return nil        // l'italiano è la domanda, già sotto gli occhi
        default: return scheda.it
        }
    }

    /// I progressi nel piede: le viste crescono con le schede nuove, le giuste a ogni risposta
    /// giusta (anche su una già vista), le sapute dopo una settimana senza sbagliare.
    static func fatte(_ n: Quaderno.Numeri) -> String {
        guard n.viste > 0 else { return "la prima scheda" }
        return "\(n.oggi) oggi  ·  \(n.viste) viste  ·  \(n.giuste) giuste  ·  \(n.sapute) \(n.sapute == 1 ? "saputa" : "sapute") su \(n.totale)"
    }

    /// Il piede si riscrive appena si risponde: prima restava fermo ai numeri di quando la carta
    /// si era aperta, perché la risposta si salva solo alla chiusura (31/10).
    private func aggiornaPiede(_ e: Esito) {
        progressi?.aggiorna(Quaderno.condiviso.numeri(conRisposta: (scheda, e)))
    }

    /// Le parole di `frase` che non stanno in `contro`, confrontate senza accenti né punteggiatura.
    private func fuori(_ frase: String, da contro: String) -> [NSRange] {
        let note = Set(Correttore.piatta(contro).split(separator: " ").map(String.init))
        var trovate: [NSRange] = []
        frase.enumerateSubstrings(in: frase.startIndex..., options: .byWords) { w, r, _, _ in
            if let w, !note.contains(Correttore.piatta(w)) { trovate.append(NSRange(r, in: frase)) }
        }
        return trovate
    }

    /// La correzione DENTRO la domanda: il buco si riempie con la forma giusta (arancio se l'ha
    /// presa, acqua se no); nel «ripeti» le parole che non ha detto si tingono d'acqua.
    private func correggiDomanda(_ e: Esito, tua: String) {
        let base: [NSAttributedString.Key: Any] = [.font: Caratteri.tondo(corpoDomanda, .bold),
                                                   .foregroundColor: Tinte.neve]
        if scheda.domanda.contains("___") && scheda.tipo != .parola {
            var piena = base
            piena[.foregroundColor] = e == .sbagliato ? Tinte.acqua : Tinte.toro
            let t = NSMutableAttributedString()
            let pezzi = scheda.domanda.components(separatedBy: "___")
            for (i, p) in pezzi.enumerated() {
                t.append(NSAttributedString(string: p, attributes: base))
                if i < pezzi.count - 1 { t.append(NSAttributedString(string: scheda.es, attributes: piena)) }
            }
            domandaCampo.attributedStringValue = t
        } else if scheda.tipo == .ripeti, e != .giusto, !tua.isEmpty {
            let t = NSMutableAttributedString(string: scheda.domanda, attributes: base)
            for r in fuori(scheda.domanda, da: tua) {
                t.addAttribute(.foregroundColor, value: Tinte.acqua, range: r)
            }
            domandaCampo.attributedStringValue = t
        }
    }

    /// Quello che ha detto, con le parole che non c'entrano barrate in acqua: ⛔ «Hai detto».
    private func dettaSegnata(_ tua: String, _ e: Esito, colore: NSColor, largo: CGFloat) -> NSTextField {
        let t = NSMutableAttributedString(string: tua, attributes: [
            .font: Caratteri.tondo(16, .medium), .foregroundColor: colore])
        if e == .sbagliato || e == .quasi {
            let buone = ([scheda.es] + (scheda.accetta ?? [])).joined(separator: " ")
            for r in fuori(tua, da: buone) {
                t.addAttributes([.foregroundColor: Tinte.acqua, .strikethroughColor: Tinte.acqua,
                                 .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: r)
            }
        }
        let c = NSTextField(wrappingLabelWithString: "")
        c.attributedStringValue = t
        c.preferredMaxLayoutWidth = largo
        c.isSelectable = false
        return c
    }

    /// I colori della banda. L'arancio PIENO è il premio, e la carta lo grida; chi sbaglia prende
    /// l'acqua, appena stesa sul marrone: fredda e calma, si impara e non si punisce.
    private struct TinteBanda { let fondo, testo, piano, sigillo, segnoSigillo, bottone, freccia: NSColor }
    private func tinteBanda(_ e: Esito, giudichi: Bool) -> TinteBanda {
        if giudichi {
            return TinteBanda(fondo: Tinte.rilievo, testo: Tinte.neve, piano: Tinte.neve.withAlphaComponent(70.0/100),
                              sigillo: Tinte.neve, segnoSigillo: Tinte.nibbio, bottone: Tinte.neve, freccia: Tinte.nibbio)
        }
        if e == .quasi {        // quasi: l'arancio a metà, caldo ma non pieno
            return TinteBanda(fondo: Tinte.nibbio.blended(withFraction: 45.0/100, of: Tinte.toro)!,
                              testo: Tinte.neve, piano: Tinte.neve.withAlphaComponent(78.0/100),
                              sigillo: Tinte.neve, segnoSigillo: Tinte.nibbio, bottone: Tinte.neve, freccia: Tinte.nibbio)
        }
        if e == .sbagliato {
            return TinteBanda(fondo: Tinte.fondale,
                              testo: Tinte.neve, piano: Tinte.neve.withAlphaComponent(70.0/100),
                              sigillo: Tinte.acqua, segnoSigillo: Tinte.nibbio, bottone: Tinte.acqua, freccia: Tinte.nibbio)
        }
        return TinteBanda(fondo: Tinte.toro, testo: Tinte.nibbio, piano: Tinte.nibbio.withAlphaComponent(75.0/100),
                          sigillo: Tinte.nibbio, segnoSigillo: Tinte.toro, bottone: Tinte.nibbio, freccia: Tinte.toro)
    }

    private func mostraEsito(_ v: Correttore.Verdetto, giudichi: Bool = false) {
        esito = v.esito
        aspettaVoto = giudichi
        if !giudichi { aggiornaPiede(v.esito) }
        campo?.isEditable = false
        finestra.makeFirstResponder(nil)     // via la selezione, e Invio torna alla carta: chiude

        let completa = scheda.domanda.replacingOccurrences(of: "___", with: scheda.es)
            .trimmingCharacters(in: CharacterSet(charactersIn: "«»"))
        let soluzione = scheda.domanda.contains("___") && scheda.tipo != .parola ? completa : scheda.es
        soluzioneIntera = soluzione
        let tua = risposta.trimmingCharacters(in: .whitespacesAndNewlines)
        let giusta = v.esito == .giusto || v.esito == .libero

        // ① la correzione si vede dove si è risposto: nella frase, nel campo, nelle pillole
        if !giudichi { correggiDomanda(v.esito, tua: tua) }
        if let campo, !tua.isEmpty {
            var a: [NSAttributedString.Key: Any] = [.font: Caratteri.tondo(18, .medium),
                                                    .foregroundColor: giusta ? Tinte.toro : Tinte.neve]
            if v.esito == .sbagliato {
                a[.foregroundColor] = Tinte.acqua
                a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                a[.strikethroughColor] = Tinte.acqua
            }
            campo.attributedStringValue = NSAttributedString(string: tua, attributes: a)
        }
        for o in opzioni {
            let questa = Correttore.pulisci(o.title) == Correttore.pulisci(scheda.es)
            o.scelta = questa
            // quella presa per sbaglio resta velata d'acqua: si vede cosa si era scelto
            if !questa && Correttore.pulisci(o.title) == Correttore.pulisci(tua) {
                o.fondi = (Tinte.fondale, Tinte.fondale, Tinte.toro)
                o.inchiostri = (Tinte.acqua, Tinte.acqua, Tinte.nibbio)
            }
        }
        // ② i gradini in cima salgono o si spengono: è lì che si vede cosa vale la risposta
        if !giudichi, v.esito != .libero, let scala {
            let prima = Quaderno.condiviso.ricordo(scheda)
            let dopo = Quaderno.dopo(prima, scheda, v.esito, adesso: Int(Date().timeIntervalSince1970))
            scala.rispondi(dopo: dopo.scatola, esito: v.esito)
        }

        // ③ la banda: TUTTO il verdetto in un posto solo, a tutta larghezza, col suo colore.
        // ⛔ «¡Muy bien!», ⛔ «No, si dice così»: lo dicono il colore e il sigillo
        let t = tinteBanda(v.esito, giudichi: giudichi)
        let azioni = NSStackView()
        azioni.orientation = .horizontal
        azioni.alignment = .centerY
        azioni.spacing = 6
        var largoAzioni: CGFloat = 0
        if !giudichi {
            if scheda.tipo != .parla {
                let ancora = Icona("speaker.wave.2.fill", aiuto: "Riascolta", azione: #selector(riascoltaSoluzione), bersaglio: self)
                ancora.inchiostri = (t.piano, t.testo)
                azioni.addArrangedSubview(ancora)
                largoAzioni += 37 + 6
            }
            let avanti = BottonePieno("", azione: #selector(principale), bersaglio: self)
            avanti.fondo = t.bottone
            avanti.tondo = true
            avanti.layer?.cornerRadius = 26
            avanti.image = simbolo("arrow.right", 18, .heavy)
            avanti.imagePosition = .imageOnly
            avanti.contentTintColor = t.freccia
            avanti.toolTip = "Avanti"
            avanti.setAccessibilityLabel("Avanti")
            avanti.removeConstraints(avanti.constraints.filter { $0.firstAttribute == .height })
            avanti.widthAnchor.constraint(equalToConstant: 52).isActive = true
            avanti.heightAnchor.constraint(equalToConstant: 52).isActive = true
            azioni.addArrangedSubview(avanti)
            largoAzioni += 52
        }
        let largo = larghezza - 2 * margine - 34 - 16 - (largoAzioni > 0 ? largoAzioni + 16 : 0)

        var righe: [NSView] = []
        // a voce: quello che ha detto, barrato dove non va, e il ✓ per dire «era giusta»
        // (il riconoscimento sbaglia anche lui: l'ultima parola sul parlato è sua)
        if scheda.tipo.aVoce, !tua.isEmpty, v.esito != .giusto {
            var pezzi: [NSView] = [dettaSegnata(tua, v.esito, colore: v.esito == .libero ? t.testo : t.piano,
                                                largo: largo - (scheda.tipo != .parla ? 30 : 0))]
            if scheda.tipo != .parla {
                let ok = Icona("checkmark.circle", corpo: 16, aiuto: "L'avevo detta giusta",
                               azione: #selector(avevoRagione), bersaglio: self)
                ok.inchiostri = (t.piano, Tinte.toro)
                pezzi.append(ok)
            }
            let riga = NSStackView(views: pezzi)
            riga.orientation = .horizontal
            riga.alignment = .centerY
            riga.spacing = 2
            righe.append(riga)
        }
        // la forma giusta, grande, solo dove non si vede già nella frase o nelle pillole
        let giaVista = scheda.domanda.contains("___") || scheda.tipo == .ripeti || scheda.tipo == .scegli
            || (scheda.tipo == .parola && v.esito == .giusto && Correttore.pulisci(tua) == Correttore.pulisci(scheda.es))
        if v.esito == .libero {
            righe.append(aCapo(scheda.es, corpo: 16, peso: .medium, colore: t.piano, largo: largo))
        } else if !giaVista {
            righe.append(aCapo(soluzione, corpo: 21, peso: .bold, colore: t.testo, largo: largo))
        }
        // cosa vuol dire, se l'italiano non è già la domanda · il perché, se non è la stessa riga
        let it = inItaliano
        if let it, !it.isEmpty {
            righe.append(aCapo(it, corpo: 15, peso: .medium, colore: righe.isEmpty ? t.testo : t.piano, largo: largo))
        }
        if let n = scheda.nota, scheda.tipo != .parla, n != it, n != scheda.domanda {
            // da sola è lei la riga che conta, e prende la voce piena
            righe.append(righe.isEmpty ? aCapo(n, corpo: 15, peso: .medium, colore: t.testo, largo: largo)
                                       : aCapo(n, corpo: 13, colore: t.piano, largo: largo))
        }
        if giudichi {
            // tre segni al posto della freccia: il voto lo dà lui (✓ la sapevo · ~ quasi · ✕ no)
            let voti = NSStackView()
            voti.spacing = 8
            for (segno, e) in [("✓", Esito.giusto), ("~", .quasi), ("✕", .sbagliato)] {
                let p = Pillola(segno, valore: e == .giusto ? 0 : (e == .quasi ? 1 : 2),
                                azione: #selector(voto(_:)), bersaglio: self)
                spagnola(p)
                p.corpo = 17
                p.toolTip = e == .giusto ? "La sapevo" : (e == .quasi ? "Quasi" : "No")
                p.removeConstraints(p.constraints.filter { $0.firstAttribute == .height })
                p.heightAnchor.constraint(equalToConstant: 40).isActive = true
                p.widthAnchor.constraint(equalToConstant: 56).isActive = true
                voti.addArrangedSubview(p)
            }
            righe.append(voti)
        }
        let contenuto = NSStackView(views: righe)
        contenuto.orientation = .vertical
        contenuto.alignment = .leading
        contenuto.spacing = 5
        // larghezza fissata: dentro la riga la pila si stringeva e le note uscivano tagliate a metà
        contenuto.widthAnchor.constraint(equalToConstant: largo).isActive = true
        for r in righe { r.widthAnchor.constraint(lessThanOrEqualToConstant: largo).isActive = true }
        if righe.count > 1 { contenuto.setCustomSpacing(8, after: righe[0]) }

        let sigillo: Sigillo
        switch v.esito {
        case _ where giudichi: sigillo = Sigillo("eye.fill", fondo: t.sigillo, inchiostro: t.segnoSigillo)
        case .giusto, .quasi:  sigillo = Sigillo("checkmark", fondo: t.sigillo, inchiostro: t.segnoSigillo)
        case .sbagliato:       sigillo = Sigillo("xmark", fondo: t.sigillo, inchiostro: t.segnoSigillo)
        case .libero:          sigillo = Sigillo("book.closed.fill", fondo: t.sigillo, inchiostro: t.segnoSigillo)
        }
        let riga = NSStackView(views: [sigillo, contenuto, azioni])
        riga.orientation = .horizontal
        riga.alignment = righe.count > 2 || giudichi ? .top : .centerY
        riga.spacing = 16
        riga.translatesAutoresizingMaskIntoConstraints = false
        banda.subviews.forEach { $0.removeFromSuperview() }
        banda.layer?.backgroundColor = t.fondo.cgColor
        banda.addSubview(riga)
        NSLayoutConstraint.activate([
            riga.topAnchor.constraint(equalTo: banda.topAnchor, constant: 20),
            riga.bottomAnchor.constraint(equalTo: banda.bottomAnchor, constant: -20),
            riga.leadingAnchor.constraint(equalTo: banda.leadingAnchor, constant: margine),
            riga.trailingAnchor.constraint(equalTo: banda.trailingAnchor, constant: -margine),
        ])

        // il bottone del giro di prima se ne va: ora si va avanti dalla banda
        fondoBottoni.isHidden = true
        ascolto.isHidden = true
        filoPiede?.isHidden = true
        banda.isHidden = false
        banda.alphaValue = 0
        posa()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = curva
            banda.animator().alphaValue = 1
        }
        DispatchQueue.main.async { sigillo.appare() }

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
