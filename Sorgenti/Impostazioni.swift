//  Impostazioni.swift — dove vivono le preferenze e il conto della giornata.
//
//  Il formato è volutamente banale: `chiave=valore`, una per riga. Così lo stesso file
//  si legge e si scrive anche da uno script di shell (`. config`) senza nessuna libreria,
//  e chi vuole può cambiarlo a mano con un editor di testo.

import Foundation

/// La cartella dei dati.
/// 1. `$BEVI_HOME` se qualcuno lo impone · 2. una cartella preesistente, per non spezzare
/// installazioni più vecchie · 3. il posto giusto su macOS per tutti gli altri.
enum Casa {
    static let cartella: URL = {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        if let scelta = ProcessInfo.processInfo.environment["BEVI_HOME"], !scelta.isEmpty {
            return URL(fileURLWithPath: (scelta as NSString).expandingTildeInPath)
        }
        let precedente = home.appendingPathComponent(".claude/.bevi")
        if fm.fileExists(atPath: precedente.appendingPathComponent("config").path) {
            return precedente
        }
        return home.appendingPathComponent("Library/Application Support/Bevi")
    }()

    static var config:    URL { cartella.appendingPathComponent("config") }
    static var stato:     URL { cartella.appendingPathComponent("stato") }
    static var registro:  URL { cartella.appendingPathComponent("registro") }

    static func prepara() {
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
    }
}

// ── le preferenze ─────────────────────────────────────────────────────────────

struct Impostazioni {
    var attivo     = true
    var intervallo = 3600      // secondi fra un promemoria e l'altro
    var dalle      = 8
    var alle       = 21
    var obiettivo  = 8         // bicchieri al giorno
    var pausaFino  = 0         // timestamp: prima di allora non si disturba
    var schermo    = true      // il cartello grande a tutto schermo
    var suono      = true
    var durata     = 2         // secondi di permanenza del cartello

    static func leggi() -> Impostazioni {
        var i = Impostazioni()
        guard let testo = try? String(contentsOf: Casa.config, encoding: .utf8) else { return i }
        for riga in testo.split(separator: "\n") {
            let pulita = riga.trimmingCharacters(in: .whitespaces)
            guard !pulita.hasPrefix("#"), let taglio = pulita.firstIndex(of: "=") else { continue }
            let chiave = String(pulita[pulita.startIndex..<taglio])
            guard let valore = Int(pulita[pulita.index(after: taglio)...]
                                    .trimmingCharacters(in: .whitespaces)) else { continue }
            switch chiave {
            case "attivo":     i.attivo     = valore != 0
            case "intervallo": i.intervallo = max(60, valore)
            case "dalle":      i.dalle      = valore
            case "alle":       i.alle       = valore
            case "obiettivo":  i.obiettivo  = max(1, valore)
            case "pausa_fino": i.pausaFino  = valore
            case "schermo":    i.schermo    = valore != 0
            case "suono":      i.suono      = valore != 0
            case "durata":     i.durata     = max(1, valore)
            default: break
            }
        }
        return i
    }

    /// Scrittura atomica: si scrive di fianco e si sposta sopra. Chi legge nello stesso
    /// istante trova il file vecchio o quello nuovo, mai uno a metà.
    func salva() {
        Casa.prepara()
        let testo = """
        attivo=\(attivo ? 1 : 0)
        intervallo=\(intervallo)
        dalle=\(dalle)
        alle=\(alle)
        obiettivo=\(obiettivo)
        pausa_fino=\(pausaFino)
        schermo=\(schermo ? 1 : 0)
        suono=\(suono ? 1 : 0)
        durata=\(durata)

        """
        let ponte = Casa.config.appendingPathExtension("tmp")
        guard (try? testo.write(to: ponte, atomically: false, encoding: .utf8)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(Casa.config, withItemAt: ponte)
    }

    var inPausa: Bool { Int(Date().timeIntervalSince1970) < pausaFino }

    /// Siamo dentro la fascia oraria? Regge anche una fascia che scavalca la mezzanotte.
    func dentroLaFascia(_ adesso: Date = Date()) -> Bool {
        let ora = Calendar.current.component(.hour, from: adesso)
        if dalle == alle { return true }
        return dalle < alle ? (ora >= dalle && ora < alle) : (ora >= dalle || ora < alle)
    }
}

// ── il conto della giornata ───────────────────────────────────────────────────

/// Quattro righe: quando è uscito l'ultimo promemoria · che giorno era · quanti bicchieri ·
/// se un altro canale ha un avviso in canna. La quarta riga non ci serve, ma **si conserva**:
/// il file è condiviso, e cancellare un dato di qualcun altro è il modo più veloce per
/// rompere una cosa che funzionava.
struct Conto {
    var ultimo = 0
    var giorno = ""
    var conta  = 0
    var quarta = "0"

    static func leggi() -> Conto {
        var c = Conto()
        guard let testo = try? String(contentsOf: Casa.stato, encoding: .utf8) else { return c }
        let righe = testo.components(separatedBy: "\n")
        if righe.count > 0 { c.ultimo = Int(righe[0].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if righe.count > 1 { c.giorno = righe[1].trimmingCharacters(in: .whitespaces) }
        if righe.count > 2 { c.conta  = Int(righe[2].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if righe.count > 3 { c.quarta = righe[3].trimmingCharacters(in: .whitespaces) }
        if c.giorno != Conto.oggi { c.conta = 0 }       // giorno nuovo, si riparte da zero
        return c
    }

    func salva() {
        Casa.prepara()
        let testo = "\(ultimo)\n\(giorno)\n\(conta)\n\(quarta)\n"
        let ponte = Casa.stato.appendingPathExtension("tmp")
        guard (try? testo.write(to: ponte, atomically: false, encoding: .utf8)) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(Casa.stato, withItemAt: ponte)
    }

    static var oggi: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Un bicchiere in più, e l'orologio riparte da adesso.
    mutating func segnaUnBicchiere() {
        ultimo = Int(Date().timeIntervalSince1970)
        giorno = Conto.oggi
        conta += 1
        quarta = "0"
        salva()
    }
}

/// Una riga per ogni promemoria uscito: serve solo a poter rispondere, il giorno dopo,
/// alla domanda «ma me ne è comparso davvero solo uno?».
func annota(_ cosa: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    let riga = "\(f.string(from: Date()))\tBarra\t\(cosa)\tapp\t-\n"
    guard let dati = riga.data(using: .utf8) else { return }
    Casa.prepara()
    if let maniglia = try? FileHandle(forWritingTo: Casa.registro) {
        defer { try? maniglia.close() }
        _ = try? maniglia.seekToEnd()
        try? maniglia.write(contentsOf: dati)
    } else {
        try? dati.write(to: Casa.registro)
    }
}
