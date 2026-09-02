//  main.swift — l'app che vive nella barra in alto.
//
//  Una goccia accanto all'orologio, con i bicchieri di oggi. Un clic apre il pannello.
//  Nessuna finestra, nessuna icona nel Dock.
//
//  Il cuore è un controllo ogni 30 secondi che costa quasi niente, perché le domande sono
//  in ordine di prezzo: quasi tutti i giri si fermano alla prima.

import Cocoa
import ServiceManagement

final class Delegato: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var voce: NSStatusItem!
    private let bolla = NSPopover()
    private let pannello = Controllore()
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
            bottone.image = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: "Bevi")
            bottone.image?.isTemplate = true          // si adatta a barra chiara e scura
            bottone.imagePosition = .imageLeading
            bottone.target = self
            bottone.action = #selector(apriChiudi)
        }

        pannello.alCambio    = { [weak self] in self?.aggiornaBarra() }
        pannello.alProva     = { [weak self] in self?.cartelloDiProva() }
        pannello.alUscita    = { NSApp.terminate(nil) }
        pannello.leggiAvvio  = { [weak self] in self?.parteDaSolo() ?? false }
        pannello.cambiaAvvio = { [weak self] in self?.cambiaAvvio() }

        bolla.contentViewController = pannello
        bolla.behavior = .transient          // si chiude da sé al primo clic fuori
        bolla.animates = true
        bolla.appearance = NSAppearance(named: .darkAqua)
        bolla.delegate = self

        aggiornaBarra()
        orologio = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.controlla()
        }
        orologio?.tolerance = 10             // lascia al Mac la libertà di raggrupparli

        // al risveglio dal sonno si ricontrolla subito: mentre dormiva il timer era fermo
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.controlla()
            }
        controlla()

        if CommandLine.arguments.contains("--collaudo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0/2) {
                let esiti = self.pannello.collaudo()
                print(esiti.joined(separator: "\n"))
                exit(esiti.contains { $0.hasPrefix("NO") } ? 1 : 0)
            }
            return
        }

        // comodo per guardare il pannello senza doverlo aprire a mano
        if CommandLine.arguments.contains("--anteprima") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.apri() }
        }
    }

    // ── il pannello ───────────────────────────────────────────────────────────

    @objc private func apriChiudi() {
        if bolla.isShown { bolla.performClose(nil) } else { apri() }
    }

    private func apri() {
        guard let bottone = voce.button else { return }
        // ⭐ La misura si impone: un pannello disegnato a mano, senza una dimensione
        //    esplicita, può uscire alto zero e sembrare che non si apra affatto.
        let misura = pannello.view.fittingSize
        bolla.contentSize = NSSize(width: max(misura.width, 330), height: max(misura.height, 240))
        pannello.aggiorna()
        bolla.show(relativeTo: bottone.bounds, of: bottone, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)   // così i controlli rispondono al primo clic
        if CommandLine.arguments.contains("--diagnosi") {
            FileHandle.standardError.write(
                "misura \(misura) · mostrato \(bolla.isShown)\n".data(using: .utf8)!)
        }
    }

    // ── la goccia nella barra ─────────────────────────────────────────────────

    private func aggiornaBarra() {
        let imp = Impostazioni.leggi()
        let conto = Conto.leggi()
        voce.button?.title = " \(conto.conta)"
        let simbolo: String
        if !imp.attivo                       { simbolo = "drop" }              // spento
        else if imp.inPausa                  { simbolo = "drop.halffull" }     // in pausa
        else if conto.conta >= imp.obiettivo { simbolo = "drop.circle.fill" }  // obiettivo fatto
        else                                 { simbolo = "drop.fill" }
        if let immagine = NSImage(systemSymbolName: simbolo, accessibilityDescription: "Bevi") {
            immagine.isTemplate = true
            voce.button?.image = immagine
        }
    }

    // ── il controllo periodico ────────────────────────────────────────────────
    // Le domande sono in ordine di costo. Le ultime due, il Focus e la chiamata in corso,
    // si pagano una volta all'ora scarsa: quando tutto il resto ha già detto sì.

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

    private func cartelloDiProva() {
        let imp = Impostazioni.leggi()
        bolla.performClose(nil)
        Cartello.mostra(sotto: "prova  ·  nessun bicchiere contato",
                        secondi: Double(imp.durata), muto: !imp.suono)
    }

    // ── partire da soli all'accensione del Mac ────────────────────────────────

    private func parteDaSolo() -> Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    private func cambiaAvvio() {
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
