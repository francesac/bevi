//  main.swift — l'app che vive nella barra in alto.
//
//  Una goccia accanto all'orologio, con i bicchieri di oggi. Un clic apre tutto: bere,
//  mettere in pausa, cambiare il passo. Nessuna finestra, nessuna icona nel Dock.
//
//  Il cuore è un controllo ogni 30 secondi che costa quasi niente, perché i controlli sono
//  in ordine di prezzo: quasi tutti i giri finiscono alla prima domanda.

import Cocoa
import ServiceManagement

final class Delegato: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var voce: NSStatusItem!
    private var orologio: Timer?
    private let coda = DispatchQueue(label: "design.francesac.bevi.controlli", qos: .utility)
    private var staVerificando = false

    // ── avvio ─────────────────────────────────────────────────────────────────

    func applicationDidFinishLaunching(_ nota: Notification) {
        Casa.prepara()
        if !FileManager.default.fileExists(atPath: Casa.config.path) {
            Impostazioni().salva()          // primo avvio: si parte dai valori di buon senso
        }

        voce = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let bottone = voce.button {
            bottone.image = NSImage(systemSymbolName: "drop.fill",
                                    accessibilityDescription: "Bevi")
            bottone.image?.isTemplate = true          // si adatta a barra chiara e scura
            bottone.imagePosition = .imageLeading
        }
        let menu = NSMenu()
        menu.delegate = self
        voce.menu = menu

        aggiornaBarra()
        orologio = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.controlla()
        }
        orologio?.tolerance = 10                      // lascia al Mac la libertà di raggrupparli

        // al risveglio dal sonno si ricontrolla subito: il timer, mentre dormiva, è fermo
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.controlla()
            }
        controlla()
    }

    // ── la goccia nella barra ─────────────────────────────────────────────────

    private func aggiornaBarra() {
        let imp = Impostazioni.leggi()
        let conto = Conto.leggi()
        voce.button?.title = " \(conto.conta)"
        let simbolo: String
        if !imp.attivo            { simbolo = "drop" }              // spento: goccia vuota
        else if imp.inPausa       { simbolo = "drop.halffull" }     // in pausa
        else if conto.conta >= imp.obiettivo { simbolo = "drop.circle.fill" }  // obiettivo fatto
        else                      { simbolo = "drop.fill" }
        if let immagine = NSImage(systemSymbolName: simbolo, accessibilityDescription: "Bevi") {
            immagine.isTemplate = true
            voce.button?.image = immagine
        }
    }

    // ── il controllo periodico ────────────────────────────────────────────────
    // I controlli sono in ordine di costo. Gli ultimi due — il Focus e la chiamata in corso —
    // si pagano una volta all'ora scarsa, quando tutto il resto ha già detto sì.

    @objc private func controlla() {
        aggiornaBarra()
        let imp = Impostazioni.leggi()
        guard imp.attivo, imp.schermo else { return }
        guard imp.dentroLaFascia(), !imp.inPausa else { return }

        let conto = Conto.leggi()
        let adesso = Int(Date().timeIntervalSince1970)
        guard adesso - conto.ultimo >= imp.intervallo else { return }

        // ⛔ Da qui in poi NON si tocca l'orologio se si rinuncia: l'avviso non si brucia,
        //    resta in canna e uscirà appena il momento è buono.
        guard !schermoBloccato() else { return }
        guard fermoDaSecondi() <= 600 else { return }   // non è davanti: lo aspettiamo
        guard !focusAcceso() else { return }

        guard !staVerificando else { return }
        staVerificando = true
        coda.async { [weak self] in
            let occupato = inChiamata()                 // può dormire fino a 14 s: mai sul main
            DispatchQueue.main.async {
                self?.staVerificando = false
                guard !occupato else { return }
                self?.mostraPromemoria()
            }
        }
    }

    private func mostraPromemoria() {
        let imp = Impostazioni.leggi()
        var conto = Conto.leggi()
        // rilettura: fra il controllo e adesso può aver bevuto da solo, o può averlo fatto
        // uscire un altro canale. Chi arriva secondo lascia perdere.
        let adesso = Int(Date().timeIntervalSince1970)
        guard adesso - conto.ultimo >= imp.intervallo else { return }

        conto.segnaUnBicchiere()
        annota("cartello")
        aggiornaBarra()

        let ore = DateFormatter()
        ore.dateFormat = "HH:mm"
        Cartello.mostra(sotto: "bicchiere \(conto.conta) di \(imp.obiettivo)  ·  sono le \(ore.string(from: Date()))",
                        secondi: Double(imp.durata), muto: !imp.suono)
    }

    // ── il menu, ricostruito ogni volta che si apre ───────────────────────────

    func menuNeedsUpdate(_ menu: NSMenu) {
        let imp = Impostazioni.leggi()
        let conto = Conto.leggi()
        menu.removeAllItems()

        let testa = NSMenuItem(title: "\(conto.conta) bicchieri oggi, su \(imp.obiettivo)",
                               action: nil, keyEquivalent: "")
        testa.isEnabled = false
        menu.addItem(testa)

        let riga = NSMenuItem(title: descrizioneAttesa(imp, conto), action: nil, keyEquivalent: "")
        riga.isEnabled = false
        menu.addItem(riga)

        menu.addItem(.separator())
        menu.addItem(azione("Ho appena bevuto", #selector(hoBevuto), tasto: "b"))

        let pausa = NSMenu()
        pausa.addItem(scelta("30 minuti", #selector(pausa30), acceso: false))
        pausa.addItem(scelta("1 ora", #selector(pausa60), acceso: false))
        pausa.addItem(scelta("2 ore", #selector(pausa120), acceso: false))
        pausa.addItem(scelta("Fino a domani", #selector(pausaDomani), acceso: false))
        if imp.inPausa {
            pausa.addItem(.separator())
            pausa.addItem(azione("Riprendi adesso", #selector(riprendi)))
        }
        let vocePausa = NSMenuItem(title: "Fai una pausa", action: nil, keyEquivalent: "")
        vocePausa.submenu = pausa
        menu.addItem(vocePausa)

        menu.addItem(.separator())
        menu.addItem(scelta("Promemoria acceso", #selector(accendiSpegni), acceso: imp.attivo))
        menu.addItem(scelta("Cartello a tutto schermo", #selector(cambiaSchermo), acceso: imp.schermo))
        menu.addItem(scelta("Suono", #selector(cambiaSuono), acceso: imp.suono))

        menu.addItem(.separator())
        menu.addItem(sottomenu("Ogni quanto", valori: [30, 45, 60, 90], attuale: imp.intervallo / 60,
                               etichetta: { $0 == 60 ? "1 ora" : ($0 == 90 ? "1 ora e mezza" : "\($0) minuti") },
                               azione: #selector(scegliIntervallo)))
        menu.addItem(sottomenu("Comincia alle", valori: [6, 7, 8, 9, 10], attuale: imp.dalle,
                               etichetta: { "\($0):00" }, azione: #selector(scegliDalle)))
        menu.addItem(sottomenu("Smetti alle", valori: [17, 18, 19, 20, 21, 23], attuale: imp.alle,
                               etichetta: { "\($0):00" }, azione: #selector(scegliAlle)))
        menu.addItem(sottomenu("Bicchieri al giorno", valori: [6, 8, 10, 12], attuale: imp.obiettivo,
                               etichetta: { "\($0)" }, azione: #selector(scegliObiettivo)))

        menu.addItem(.separator())
        menu.addItem(scelta("Parti all'avvio del Mac", #selector(cambiaAvvio), acceso: parteDaSolo()))
        menu.addItem(azione("Mostra un cartello di prova", #selector(prova)))
        menu.addItem(.separator())
        menu.addItem(azione("Esci da Bevi", #selector(esci), tasto: "q"))
    }

    private func descrizioneAttesa(_ imp: Impostazioni, _ conto: Conto) -> String {
        if !imp.attivo { return "Promemoria spento" }
        if imp.inPausa {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return "In pausa fino alle \(f.string(from: Date(timeIntervalSince1970: Double(imp.pausaFino))))"
        }
        if !imp.dentroLaFascia() { return "Fuori orario — riprende alle \(imp.dalle):00" }
        let manca = imp.intervallo - (Int(Date().timeIntervalSince1970) - conto.ultimo)
        if manca <= 0 { return "Il prossimo: a momenti" }
        let minuti = (manca + 59) / 60
        return minuti >= 60 ? "Il prossimo fra \(minuti / 60) h e \(minuti % 60) min"
                            : "Il prossimo fra \(minuti) min"
    }

    // ── piccoli aiuti per costruire le voci ───────────────────────────────────

    private func azione(_ titolo: String, _ sel: Selector, tasto: String = "") -> NSMenuItem {
        let v = NSMenuItem(title: titolo, action: sel, keyEquivalent: tasto)
        v.target = self
        return v
    }

    private func scelta(_ titolo: String, _ sel: Selector, acceso: Bool) -> NSMenuItem {
        let v = azione(titolo, sel)
        v.state = acceso ? .on : .off
        return v
    }

    private func sottomenu(_ titolo: String, valori: [Int], attuale: Int,
                           etichetta: (Int) -> String, azione sel: Selector) -> NSMenuItem {
        let dentro = NSMenu()
        for valore in valori {
            let v = NSMenuItem(title: etichetta(valore), action: sel, keyEquivalent: "")
            v.target = self
            v.tag = valore
            v.state = (valore == attuale) ? .on : .off
            dentro.addItem(v)
        }
        let fuori = NSMenuItem(title: titolo, action: nil, keyEquivalent: "")
        fuori.submenu = dentro
        return fuori
    }

    private func modifica(_ cambia: (inout Impostazioni) -> Void) {
        var imp = Impostazioni.leggi()
        cambia(&imp)
        imp.salva()
        aggiornaBarra()
    }

    // ── cosa fanno le voci ────────────────────────────────────────────────────

    @objc private func hoBevuto() {
        var conto = Conto.leggi()
        conto.segnaUnBicchiere()
        annota("bevuto")
        aggiornaBarra()
    }

    @objc private func pausa30()     { metti(inPausaMinuti: 30) }
    @objc private func pausa60()     { metti(inPausaMinuti: 60) }
    @objc private func pausa120()    { metti(inPausaMinuti: 120) }
    @objc private func riprendi()    { modifica { $0.pausaFino = 0 } }

    @objc private func pausaDomani() {
        let imp = Impostazioni.leggi()
        var domani = DateComponents()
        domani.day = 1
        guard let fra24 = Calendar.current.date(byAdding: domani, to: Date()) else { return }
        let inizio = Calendar.current.date(bySettingHour: imp.dalle, minute: 0, second: 0,
                                           of: fra24) ?? fra24
        modifica { $0.pausaFino = Int(inizio.timeIntervalSince1970) }
    }

    private func metti(inPausaMinuti minuti: Int) {
        modifica { $0.pausaFino = Int(Date().timeIntervalSince1970) + minuti * 60 }
    }

    @objc private func accendiSpegni() { modifica { $0.attivo = !$0.attivo } }
    @objc private func cambiaSchermo() { modifica { $0.schermo = !$0.schermo } }
    @objc private func cambiaSuono()   { modifica { $0.suono = !$0.suono } }

    @objc private func scegliIntervallo(_ v: NSMenuItem) { modifica { $0.intervallo = v.tag * 60 } }
    @objc private func scegliDalle(_ v: NSMenuItem)      { modifica { $0.dalle = v.tag } }
    @objc private func scegliAlle(_ v: NSMenuItem)       { modifica { $0.alle = v.tag } }
    @objc private func scegliObiettivo(_ v: NSMenuItem)  { modifica { $0.obiettivo = v.tag } }

    @objc private func prova() {
        let imp = Impostazioni.leggi()
        Cartello.mostra(sotto: "prova  ·  nessun bicchiere contato",
                        secondi: Double(imp.durata), muto: !imp.suono)
    }

    @objc private func esci() { NSApp.terminate(nil) }

    // ── partire da soli all'accensione del Mac ────────────────────────────────

    private func parteDaSolo() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func cambiaAvvio() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let avviso = NSAlert()
            avviso.messageText = "Non sono riuscito a cambiare l'avvio automatico"
            avviso.informativeText = "Puoi farlo a mano da Impostazioni di Sistema › "
                + "Generali › Elementi login.\n\n(\(error.localizedDescription))"
            avviso.runModal()
        }
    }
}

// ── si parte ──────────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // niente icona nel Dock, niente voce nel cambio-app
let delegato = Delegato()
app.delegate = delegato
app.run()
