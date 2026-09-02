//  Controllore.swift — il pannello montato, e cosa succede quando lo si tocca.

import Cocoa

final class Controllore: NSViewController {

    /// Chiamata a ogni modifica, perché la goccia nella barra si aggiorni all'istante.
    var alCambio: (() -> Void)?
    var alProva:  (() -> Void)?
    var alUscita: (() -> Void)?
    var leggiAvvio:  (() -> Bool)?
    var cambiaAvvio: (() -> Void)?

    private let larghezza: CGFloat = 330

    private let gocce = Gocce()
    private var numero = scritta("", corpo: 28, peso: .bold)
    private var suQuanti = scritta("", corpo: 12, colore: Colori.tenue)
    private var prossimo = scritta("", corpo: 12, colore: Colori.tenue)
    private lazy var acceso  = Interruttore(azione: #selector(interruttore(_:)), bersaglio: self)
    private lazy var schermo = Interruttore(azione: #selector(interruttore(_:)), bersaglio: self)
    private lazy var suono   = Interruttore(azione: #selector(interruttore(_:)), bersaglio: self)
    private lazy var avvio   = Interruttore(azione: #selector(interruttore(_:)), bersaglio: self)
    private var gruppoPasso: Gruppo!, gruppoDalle: Gruppo!, gruppoAlle: Gruppo!, gruppoMeta: Gruppo!
    private let rigaPausa = NSStackView()
    private var battito: Timer?
    private var bottone: BottonePieno!

    // ── il montaggio ──────────────────────────────────────────────────────────

    override func loadView() {
        let radice = NSView(frame: NSRect(x: 0, y: 0, width: larghezza, height: 10))
        radice.wantsLayer = true
        radice.layer?.backgroundColor = Colori.fondo.cgColor

        let colonna = NSStackView()
        colonna.orientation = .vertical
        colonna.spacing = 10
        colonna.alignment = .leading
        colonna.translatesAutoresizingMaskIntoConstraints = false
        radice.addSubview(colonna)
        NSLayoutConstraint.activate([
            colonna.topAnchor.constraint(equalTo: radice.topAnchor, constant: 14),
            colonna.leadingAnchor.constraint(equalTo: radice.leadingAnchor, constant: 14),
            colonna.trailingAnchor.constraint(equalTo: radice.trailingAnchor, constant: -14),
            colonna.bottomAnchor.constraint(equalTo: radice.bottomAnchor, constant: -12),
            radice.widthAnchor.constraint(equalToConstant: larghezza),
        ])

        colonna.addArrangedSubview(cartaConto())
        colonna.addArrangedSubview(cartaInterruttori())
        colonna.addArrangedSubview(cartaRegolazioni())
        colonna.addArrangedSubview(cartaPausa())
        colonna.addArrangedSubview(piede())
        for v in colonna.arrangedSubviews {
            v.widthAnchor.constraint(equalTo: colonna.widthAnchor).isActive = true
        }
        view = radice
    }

    // ── il conto della giornata ───────────────────────────────────────────────

    private func cartaConto() -> NSView {
        let carta = Carta(sfuma: [Colori.cimaCarta, Colori.fondoCarta], raggio: 16)
        let dentro = NSStackView()
        dentro.orientation = .vertical
        dentro.alignment = .leading
        dentro.spacing = 0
        dentro.translatesAutoresizingMaskIntoConstraints = false
        carta.addSubview(dentro)
        NSLayoutConstraint.activate([
            dentro.topAnchor.constraint(equalTo: carta.topAnchor, constant: 17),
            dentro.leadingAnchor.constraint(equalTo: carta.leadingAnchor, constant: 17),
            dentro.trailingAnchor.constraint(equalTo: carta.trailingAnchor, constant: -17),
            dentro.bottomAnchor.constraint(equalTo: carta.bottomAnchor, constant: -17),
        ])

        dentro.addArrangedSubview(gocce)
        dentro.setCustomSpacing(16, after: gocce)

        let riga = NSStackView(views: [numero, suQuanti])
        riga.orientation = .horizontal
        riga.alignment = .firstBaseline
        riga.spacing = 8
        dentro.addArrangedSubview(riga)
        dentro.setCustomSpacing(2, after: riga)

        dentro.addArrangedSubview(prossimo)
        dentro.setCustomSpacing(16, after: prossimo)

        bottone = BottonePieno("Ho appena bevuto", azione: #selector(hoBevuto), bersaglio: self)
        dentro.addArrangedSubview(bottone)
        bottone.widthAnchor.constraint(equalTo: dentro.widthAnchor).isActive = true
        return carta
    }

    // ── gli interruttori ──────────────────────────────────────────────────────

    private func cartaInterruttori() -> NSView {
        for (i, s) in [acceso, schermo, suono, avvio].enumerated() { s.tag = i }
        return carta(righe: [
            riga("Promemoria acceso", acceso),
            riga("Cartello a tutto schermo", schermo),
            riga("Suono", suono),
            riga("Parti all'avvio del Mac", avvio),
        ])
    }

    // ── le regolazioni ────────────────────────────────────────────────────────

    private func cartaRegolazioni() -> NSView {
        gruppoPasso = Gruppo(valori: [("30", 30), ("45", 45), ("1 h", 60), ("1½ h", 90)],
                             azione: #selector(scegliPasso(_:)), bersaglio: self)
        gruppoDalle = Gruppo(valori: [("6", 6), ("7", 7), ("8", 8), ("9", 9)],
                             azione: #selector(scegliDalle(_:)), bersaglio: self)
        gruppoAlle  = Gruppo(valori: [("18", 18), ("20", 20), ("21", 21), ("23", 23)],
                             azione: #selector(scegliAlle(_:)), bersaglio: self)
        gruppoMeta  = Gruppo(valori: [("6", 6), ("8", 8), ("10", 10), ("12", 12)],
                             azione: #selector(scegliMeta(_:)), bersaglio: self)
        return carta(righe: [
            riga("Ogni quanto", gruppoPasso.vista),
            riga("Comincia alle", gruppoDalle.vista),
            riga("Smetti alle", gruppoAlle.vista),
            riga("Bicchieri al giorno", gruppoMeta.vista),
        ])
    }

    // ── la pausa ──────────────────────────────────────────────────────────────

    private func cartaPausa() -> NSView {
        rigaPausa.orientation = .horizontal
        rigaPausa.alignment = .centerY
        rigaPausa.spacing = 10
        let carta = Carta(tinta: Colori.carta, raggio: 16)
        rigaPausa.translatesAutoresizingMaskIntoConstraints = false
        carta.addSubview(rigaPausa)
        NSLayoutConstraint.activate([
            rigaPausa.topAnchor.constraint(equalTo: carta.topAnchor, constant: 12),
            rigaPausa.leadingAnchor.constraint(equalTo: carta.leadingAnchor, constant: 16),
            rigaPausa.trailingAnchor.constraint(equalTo: carta.trailingAnchor, constant: -16),
            rigaPausa.bottomAnchor.constraint(equalTo: carta.bottomAnchor, constant: -12),
        ])
        return carta
    }

    /// La riga della pausa cambia faccia: o offre le pause, o dice fin quando sei fermo.
    private func componiPausa(_ imp: Impostazioni) {
        rigaPausa.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if imp.inPausa {
            let ore = DateFormatter(); ore.dateFormat = "HH:mm"
            let fino = ore.string(from: Date(timeIntervalSince1970: Double(imp.pausaFino)))
            rigaPausa.addArrangedSubview(scritta("In pausa fino alle \(fino)",
                                                 corpo: 12, colore: Colori.tenue))
            let vuoto = NSView()
            vuoto.setContentHuggingPriority(.init(1), for: .horizontal)
            rigaPausa.addArrangedSubview(vuoto)
            rigaPausa.addArrangedSubview(
                Pillola("Riprendi", valore: 0, azione: #selector(riprendi), bersaglio: self))
        } else {
            rigaPausa.addArrangedSubview(scritta("Pausa", corpo: 12, colore: Colori.tenue))
            let vuoto = NSView()
            vuoto.setContentHuggingPriority(.init(1), for: .horizontal)
            rigaPausa.addArrangedSubview(vuoto)
            for (testo, minuti) in [("30 m", 30), ("1 h", 60), ("2 h", 120), ("Domani", -1)] {
                rigaPausa.addArrangedSubview(
                    Pillola(testo, valore: minuti, azione: #selector(pausa(_:)), bersaglio: self))
            }
        }
    }

    // ── il piede ──────────────────────────────────────────────────────────────

    private func piede() -> NSView {
        let riga = NSStackView()
        riga.orientation = .horizontal
        riga.alignment = .centerY
        riga.addArrangedSubview(testoCliccabile("Cartello di prova", #selector(prova)))
        let vuoto = NSView()
        vuoto.setContentHuggingPriority(.init(1), for: .horizontal)
        riga.addArrangedSubview(vuoto)
        riga.addArrangedSubview(testoCliccabile("Esci", #selector(esci)))
        return riga
    }

    private func testoCliccabile(_ testo: String, _ azione: Selector) -> NSButton {
        TestoCliccabile(testo, azione: azione, bersaglio: self)
    }

    // ── aiuti di impaginazione ────────────────────────────────────────────────

    private func riga(_ etichetta: String, _ destra: NSView) -> NSView {
        let sinistra = scritta(etichetta, corpo: 13)
        sinistra.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        let riga = NSStackView(views: [sinistra])
        riga.orientation = .horizontal
        riga.alignment = .centerY
        riga.spacing = 8
        let vuoto = NSView()
        vuoto.setContentHuggingPriority(.init(1), for: .horizontal)
        riga.addArrangedSubview(vuoto)
        riga.addArrangedSubview(destra)
        riga.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return riga
    }

    private func carta(righe: [NSView]) -> NSView {
        let carta = Carta(tinta: Colori.carta, raggio: 16)
        let colonna = NSStackView()
        colonna.orientation = .vertical
        colonna.alignment = .leading
        colonna.spacing = 0
        colonna.translatesAutoresizingMaskIntoConstraints = false
        carta.addSubview(colonna)
        NSLayoutConstraint.activate([
            colonna.topAnchor.constraint(equalTo: carta.topAnchor, constant: 4),
            colonna.leadingAnchor.constraint(equalTo: carta.leadingAnchor, constant: 16),
            colonna.trailingAnchor.constraint(equalTo: carta.trailingAnchor, constant: -16),
            colonna.bottomAnchor.constraint(equalTo: carta.bottomAnchor, constant: -4),
        ])
        for (i, r) in righe.enumerated() {
            if i > 0 { let f = filo(); colonna.addArrangedSubview(f)
                       f.widthAnchor.constraint(equalTo: colonna.widthAnchor).isActive = true }
            colonna.addArrangedSubview(r)
            r.widthAnchor.constraint(equalTo: colonna.widthAnchor).isActive = true
        }
        return carta
    }

    // ── mostrare i valori di adesso ───────────────────────────────────────────

    func aggiorna() {
        let imp = Impostazioni.leggi()
        let conto = Conto.leggi()

        gocce.totale = imp.obiettivo
        gocce.bevuti = min(conto.conta, imp.obiettivo)
        numero.attributedStringValue = NSAttributedString(
            string: "\(conto.conta)",
            attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold),
                         .foregroundColor: Colori.testo, .kern: -1.0/2])
        suQuanti.stringValue = "bicchieri oggi, su \(imp.obiettivo)"
        prossimo.stringValue = attesa(imp, conto)

        acceso.acceso  = imp.attivo
        schermo.acceso = imp.schermo
        suono.acceso   = imp.suono
        avvio.acceso   = leggiAvvio?() ?? false

        gruppoPasso.segna(imp.intervallo / 60)
        gruppoDalle.segna(imp.dalle)
        gruppoAlle.segna(imp.alle)
        gruppoMeta.segna(imp.obiettivo)

        componiPausa(imp)

        // spento il promemoria, le regolazioni restano visibili ma smorzate
        let vive = imp.attivo ? 1.0 : 45.0/100
        for gruppo in [gruppoPasso!, gruppoDalle!, gruppoAlle!, gruppoMeta!] {
            gruppo.vista.alphaValue = vive
            gruppo.vista.isHidden = false
            for p in gruppo.pillole { p.isEnabled = imp.attivo }
        }
        rigaPausa.alphaValue = vive
    }

    private func attesa(_ imp: Impostazioni, _ conto: Conto) -> String {
        if !imp.attivo { return "Promemoria spento" }
        if imp.inPausa { return "In pausa" }
        if !imp.dentroLaFascia() { return "Fuori orario, riprende alle \(imp.dalle):00" }
        let manca = imp.intervallo - (Int(Date().timeIntervalSince1970) - conto.ultimo)
        if manca <= 0 { return "Il prossimo: a momenti" }
        let minuti = (manca + 59) / 60
        if minuti < 60 { return "Il prossimo fra \(minuti) min" }
        let resto = minuti % 60
        return resto == 0 ? "Il prossimo fra \(minuti / 60) h"
                          : "Il prossimo fra \(minuti / 60) h e \(resto) min"
    }

    // ── il pannello è aperto: si tiene vivo il conto alla rovescia ─────────────

    override func viewWillAppear() {
        super.viewWillAppear()
        aggiorna()
        battito = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.aggiorna()
        }
    }
    override func viewWillDisappear() {
        super.viewWillDisappear()
        battito?.invalidate()
        battito = nil
    }

    // ── cosa fanno i controlli ────────────────────────────────────────────────

    private func modifica(_ cambia: (inout Impostazioni) -> Void) {
        var imp = Impostazioni.leggi()
        cambia(&imp)
        imp.salva()
        aggiorna()
        alCambio?()
    }

    @objc private func hoBevuto() {
        var conto = Conto.leggi()
        conto.segnaUnBicchiere()
        annota("bevuto")
        aggiorna()
        alCambio?()
    }

    @objc private func interruttore(_ s: Interruttore) {
        switch s.tag {
        case 0: modifica { $0.attivo  = s.acceso }
        case 1: modifica { $0.schermo = s.acceso }
        case 2: modifica { $0.suono   = s.acceso }
        default:
            cambiaAvvio?()
            aggiorna()
        }
    }

    @objc private func scegliPasso(_ p: Pillola) { modifica { $0.intervallo = p.valore * 60 } }
    @objc private func scegliDalle(_ p: Pillola) { modifica { $0.dalle = p.valore } }
    @objc private func scegliAlle(_ p: Pillola)  { modifica { $0.alle = p.valore } }
    @objc private func scegliMeta(_ p: Pillola)  { modifica { $0.obiettivo = p.valore } }
    @objc private func riprendi()                { modifica { $0.pausaFino = 0 } }

    @objc private func pausa(_ p: Pillola) {
        if p.valore > 0 {
            modifica { $0.pausaFino = Int(Date().timeIntervalSince1970) + p.valore * 60 }
            return
        }
        let imp = Impostazioni.leggi()                     // «Domani»: fino all'ora d'inizio
        var giorno = DateComponents(); giorno.day = 1
        guard let fra24 = Calendar.current.date(byAdding: giorno, to: Date()) else { return }
        let inizio = Calendar.current.date(bySettingHour: imp.dalle, minute: 0, second: 0,
                                           of: fra24) ?? fra24
        modifica { $0.pausaFino = Int(inizio.timeIntervalSince1970) }
    }

    // ── collaudo automatico ───────────────────────────────────────────────────
    // Preme i controlli VERI (stessa strada del mouse) e guarda se il file di
    // configurazione è cambiato. Un pannello che si disegna ma non comanda niente è il
    // difetto che uno scatto non fa vedere.
    func collaudo() -> [String] {
        var esiti: [String] = []
        func verifica(_ cosa: String, _ atteso: String, _ trovato: String) {
            esiti.append("\(trovato == atteso ? "OK  " : "NO  ")\(cosa): atteso \(atteso), trovato \(trovato)")
        }
        _ = view
        aggiorna()

        gruppoPasso.pillole.first { $0.valore == 45 }?.performClick(nil)
        verifica("pillola «45 min»", "2700", "\(Impostazioni.leggi().intervallo)")

        gruppoMeta.pillole.first { $0.valore == 12 }?.performClick(nil)
        verifica("pillola «12 bicchieri»", "12", "\(Impostazioni.leggi().obiettivo)")

        let prima = Impostazioni.leggi().suono
        suono.performClick(nil)
        verifica("interruttore «Suono»", "\(!prima)", "\(Impostazioni.leggi().suono)")

        let bicchieri = Conto.leggi().conta
        bottone.performClick(nil)
        verifica("bottone «Ho appena bevuto»", "\(bicchieri + 1)", "\(Conto.leggi().conta)")

        rigaPausa.arrangedSubviews.compactMap { $0 as? Pillola }
            .first { $0.valore == 60 }?.performClick(nil)
        verifica("pillola «pausa 1 h»", "true", "\(Impostazioni.leggi().inPausa)")

        aggiorna()
        let riprendi = rigaPausa.arrangedSubviews.compactMap { $0 as? Pillola }.first
        riprendi?.performClick(nil)
        verifica("pillola «Riprendi»", "false", "\(Impostazioni.leggi().inPausa)")

        return esiti
    }

    @objc private func prova() { alProva?() }
    @objc private func esci()  { alUscita?() }
}
