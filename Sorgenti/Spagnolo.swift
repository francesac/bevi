//  Spagnolo.swift — il quaderno: le schede, quando ripassarle, come si corregge una risposta.
//
//  Ogni promemoria porta con sé un esercizio da un minuto. Le schede stanno in
//  `spagnolo.json` dentro l'app; quello che sai di ognuna sta in `spagnolo` nella cartella
//  dei dati, un file di testo con una riga per scheda.
//
//  ⭐ Il ripasso è a scatole (Leitner): una scheda indovinata sale di scatola e torna dopo
//     un intervallo più lungo; una sbagliata torna nella prima e rientra il giorno dopo.
//     È la ripetizione dilazionata, la pratica con più prove per fissare il lessico.
//  ⭐ Nessuna intelligenza artificiale: le risposte si confrontano con quelle accettate,
//     e il parlato lo trascrive il Mac stesso (vedi Voce.swift).

import Foundation

// ── la scheda ─────────────────────────────────────────────────────────────────

enum Tipo: String, Codable, CaseIterable {
    case parola      // dall'italiano allo spagnolo, scritto
    case completa    // una frase con un buco, di solito un verbo da coniugare
    case scegli      // tre opzioni: falsi amici, ser/estar, por/para
    case ripeti      // ascolta e ripeti ad alta voce (shadowing)
    case traduci     // di' in spagnolo una frase italiana, ad alta voce
    case parla       // una domanda su di te: rispondi a voce, a parole tue

    var etichetta: String {
        switch self {
        case .parola:   return "PAROLA"
        case .completa: return "COMPLETA"
        case .scegli:   return "SCEGLI"
        case .ripeti:   return "ASCOLTA E RIPETI"
        case .traduci:  return "DILLO IN SPAGNOLO"
        case .parla:    return "PARLA DI TE"
        }
    }

    var consegna: String {
        switch self {
        case .parola:   return "Come si dice in spagnolo?"
        case .completa: return "Completa la frase"
        case .scegli:   return "Qual è quella giusta?"
        case .ripeti:   return "Ascolta, poi ripetila ad alta voce"
        case .traduci:  return "Dilla ad alta voce, in spagnolo"
        case .parla:    return "Rispondi a voce, con parole tue"
        }
    }

    var aVoce: Bool { self == .ripeti || self == .traduci || self == .parla }
}

struct Scheda: Codable {
    let id: String
    let tipo: Tipo
    let livello: Int
    /// Quello che si mostra: la parola o la frase italiana, la frase col buco (`___`),
    /// la domanda. Per `ripeti` è la frase spagnola stessa.
    let domanda: String
    /// La risposta di riferimento, in spagnolo.
    let es: String
    /// Altre risposte che valgono quanto quella di riferimento.
    var accetta: [String]? = nil
    /// Per `scegli`: le opzioni, compresa quella giusta (che è `es`).
    var opzioni: [String]? = nil
    /// Un aiuto fra parentesi sotto la domanda: «(ir, yo)».
    var aiuto: String? = nil
    /// Una riga che si legge DOPO aver risposto: la regola, il falso amico, l'esempio.
    var nota: String? = nil
    /// Cosa vuol dire, in italiano, la risposta giusta (la frase intera): si legge nel
    /// resoconto. Manca dove la scheda è già in italiano (parola, traduci).
    var it: String? = nil
}

// ── quello che sai di ogni scheda ─────────────────────────────────────────────

struct Ricordo {
    var scatola  = 0      // 0 = appena vista o sbagliata · 6 = la sai da mesi
    var scadenza = 0      // timestamp: prima di allora non si ripropone
    var viste    = 0
    var giuste   = 0
}

enum Esito { case giusto, quasi, sbagliato, libero }

// ── il quaderno ───────────────────────────────────────────────────────────────

final class Quaderno {

    static let condiviso = Quaderno()

    private(set) var schede: [Scheda] = []
    private var ricordi: [String: Ricordo] = [:]
    private var nuoveOggi = 0
    private var giornoNuove = ""
    private var ultimoTipo: Tipo?
    private var senzaVoce = 0
    private var ripassiDiFila = 0   // ripassi dall'ultima novità: a uno, tocca a una scheda nuova

    /// Quante schede MAI viste si aprono al giorno. Il resto dei promemoria è ripasso:
    /// con un promemoria ogni mezz'ora sono una ventina di esercizi, e sei novità bastano.
    var nuoveAlGiorno = 6

    /// Gli intervalli delle scatole, in secondi. La scatola 0 rientra il giorno dopo: a due ore
    /// (com'era fino al 21/10/2026) una scheda sbagliata tornava quattro volte in un pomeriggio,
    /// prima di tutte le altre, e la carta sembrava sempre la stessa.
    /// ⭐ La prima risposta giusta porta a TRE giorni (22/10/2026, Francesco: «continua a non
    /// registrare i progressi»): a un giorno la scheda indovinata tornava l'indomani identica,
    /// e un'altra volta ancora prima di salire, e sembrava che la risposta non fosse contata.
    static let intervalli = [86400, 3 * 86400, 7 * 86400, 16 * 86400,
                             35 * 86400, 90 * 86400, 180 * 86400]

    static var progressi: URL { Casa.cartella.appendingPathComponent("spagnolo") }
    static var diario: URL { Casa.cartella.appendingPathComponent("spagnolo-diario") }

    init(fonte: URL? = nil) {
        let url = fonte ?? Bundle.main.url(forResource: "spagnolo", withExtension: "json")
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
                .deletingLastPathComponent().appendingPathComponent("../Resources/spagnolo.json")
        if let dati = try? Data(contentsOf: url),
           let lette = try? JSONDecoder().decode([Scheda].self, from: dati) {
            schede = lette
        }
        leggi()
    }

    // ── il file dei progressi: `id	scatola	scadenza	viste	giuste` ─────────────
    //    più una riga di testa `#nuove	giorno	quante`, per il tetto delle schede nuove.

    private func leggi() {
        guard let testo = try? String(contentsOf: Quaderno.progressi, encoding: .utf8) else { return }
        for riga in testo.split(separator: "\n") {
            let c = riga.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            if c.first == "#nuove", c.count >= 3 {
                giornoNuove = c[1]; nuoveOggi = Int(c[2]) ?? 0; continue
            }
            guard c.count >= 5 else { continue }
            ricordi[c[0]] = Ricordo(scatola: Int(c[1]) ?? 0, scadenza: Int(c[2]) ?? 0,
                                    viste: Int(c[3]) ?? 0, giuste: Int(c[4]) ?? 0)
        }
    }

    private func salva() {
        Casa.prepara()
        var testo = "#nuove\t\(giornoNuove)\t\(nuoveOggi)\n"
        for (id, r) in ricordi.sorted(by: { $0.key < $1.key }) {
            testo += "\(id)\t\(r.scatola)\t\(r.scadenza)\t\(r.viste)\t\(r.giuste)\n"
        }
        let ponte = Quaderno.progressi.appendingPathExtension("tmp")
        guard (try? testo.write(to: ponte, atomically: false, encoding: .utf8)) != nil else { return }
        if FileManager.default.fileExists(atPath: Quaderno.progressi.path) {
            _ = try? FileManager.default.replaceItemAt(Quaderno.progressi, withItemAt: ponte)
        } else {
            try? FileManager.default.moveItem(at: ponte, to: Quaderno.progressi)
        }
    }

    // ── quale scheda adesso ───────────────────────────────────────────────────
    // 1. una scheda scaduta, la più vecchia, possibilmente di un tipo diverso dall'ultima
    // 2. altrimenti una nuova, nell'ordine del quaderno, finché non si tocca il tetto
    // 3. altrimenti una domanda «parla di te», che non finisce mai
    // 4. altrimenti la scheda che scade per prima, anticipata

    func prossima(adesso: Int = Int(Date().timeIntervalSince1970)) -> Scheda? {
        guard !schede.isEmpty else { return nil }
        if giornoNuove != Conto.oggi { giornoNuove = Conto.oggi; nuoveOggi = 0 }

        let scadute = schede.filter { s in
            guard let r = ricordi[s.id], r.viste > 0 else { return false }
            return r.scadenza <= adesso && s.tipo != .parla
        }.sorted { (ricordi[$0.id]?.scadenza ?? 0) < (ricordi[$1.id]?.scadenza ?? 0) }

        // dopo due esercizi muti si cerca la voce dappertutto: ripasso, novità, domanda personale
        if senzaVoce >= 2 {
            let nuoveVoce = nuoveOggi < nuoveAlGiorno
                ? maiViste(adesso).filter { $0.tipo == .ripeti || $0.tipo == .traduci }
                : []
            let domanda = schede.filter { $0.tipo == .parla && (ricordi[$0.id]?.scadenza ?? 0) <= adesso }
            let prima = ripassiDiFila >= 1 ? Array(nuoveVoce.prefix(3)) + scadute : scadute + nuoveVoce.prefix(3)
            if let s = (prima + domanda).first(where: { $0.tipo.aVoce }) { return s }
        }
        // ripasso e novità si ALTERNANO (22/10/2026): prima il ripasso passava sempre davanti, e
        // con una scheda scaduta a ogni promemoria le nuove ⛔ entravano più — 17 schede su 785
        // in tre giorni, sempre quelle
        if ripassiDiFila >= 1, nuoveOggi < nuoveAlGiorno,
           let s = variata(Array(maiViste(adesso).prefix(10))) { return s }
        if let s = variata(scadute) { return s }

        if nuoveOggi < nuoveAlGiorno {
            // si prende fra le prime dieci del gradino di turno, variando il tipo
            if let s = variata(Array(maiViste(adesso).prefix(10))) { return s }
        }

        let domande = schede.filter { $0.tipo == .parla }
            .sorted { (ricordi[$0.id]?.scadenza ?? 0) < (ricordi[$1.id]?.scadenza ?? 0) }
        if let s = domande.first, (ricordi[s.id]?.scadenza ?? 0) <= adesso { return s }

        // niente da ripassare e il tetto delle novità toccato: meglio una scheda nuova in più che
        // una già vista anticipata, che è proprio la «stessa schedina di ieri»
        if let s = variata(Array(maiViste(adesso).prefix(10))) { return s }

        return schede.filter { $0.tipo != .parla && (ricordi[$0.id]?.viste ?? 0) > 0 }
            .min { (ricordi[$0.id]?.scadenza ?? 0) < (ricordi[$1.id]?.scadenza ?? 0) }
            ?? schede.first
    }

    /// Le schede mai viste, col gradino di turno davanti: le novità della giornata girano
    /// sui tre livelli dal primo giorno. Chi ha le basi di scuola sa già le parole, e sbaglia
    /// i tempi (passato prossimo per «ieri», «cuando» senza congiuntivo): in fila per livello
    /// quelle schede arriverebbero dopo cinquanta giorni di vocaboli.
    private func maiViste(_ adesso: Int) -> [Scheda] {
        // una scheda nuova saltata resta nuova, ma aspetta il suo turno: non si ripresenta subito
        let mai = schede.filter { (ricordi[$0.id]?.viste ?? 0) == 0 && $0.tipo != .parla
                                  && (ricordi[$0.id]?.scadenza ?? 0) <= adesso }
        let turno = nuoveOggi % 3 + 1
        return mai.filter { $0.livello == turno } + mai.filter { $0.livello != turno }
    }

    /// Mescolare i tipi aiuta a ricordare (interleaving): si evita di ripetere l'ultimo.
    /// E il parlato è lo scopo: dopo due esercizi muti, il terzo è a voce se ce n'è uno.
    private func variata(_ elenco: [Scheda]) -> Scheda? {
        if senzaVoce >= 2, let s = elenco.first(where: { $0.tipo.aVoce }) { return s }
        return elenco.first { $0.tipo != ultimoTipo } ?? elenco.first
    }

    // ── segnare com'è andata ──────────────────────────────────────────────────

    func segna(_ s: Scheda, _ esito: Esito, trascritto: String = "",
               adesso: Int = Int(Date().timeIntervalSince1970)) {
        var r = ricordi[s.id] ?? Ricordo()
        if r.viste == 0 && s.tipo != .parla { nuoveOggi += 1; ripassiDiFila = 0 }
        else if s.tipo != .parla { ripassiDiFila += 1 }
        r.viste += 1
        ultimoTipo = s.tipo
        senzaVoce = s.tipo.aVoce ? 0 : senzaVoce + 1
        switch esito {
        case .giusto:    r.giuste += 1; r.scatola = min(r.scatola + 1, Quaderno.intervalli.count - 1)
        case .quasi:     r.giuste += 1                       // resta dov'è: torna presto uguale
        case .sbagliato: r.scatola = 0
        case .libero:    r.scatola = 0                       // le domande personali girano
        }
        r.scadenza = adesso + (s.tipo == .parla ? 3 * 86400 : Quaderno.intervalli[r.scatola])
        ricordi[s.id] = r
        salva()
        if s.tipo.aVoce && !trascritto.isEmpty { annotaDiario(s, trascritto, esito) }
    }

    /// Una carta chiusa senza risposta (Salta, Esc, nessuno davanti, la webcam) non è un esito:
    /// la scatola resta dov'è, ma la scheda si sposta in fondo. Prima restava prima in fila e il
    /// promemoria dopo riproponeva la stessa: il 20/10 otto «saltato» di fila sulla stessa carta.
    func rinvia(_ s: Scheda, adesso: Int = Int(Date().timeIntervalSince1970)) {
        var r = ricordi[s.id] ?? Ricordo()
        let quando = adesso + 86400   // anche una già vista: a 4 ore tornava nello stesso pomeriggio (22/10)
        guard r.scadenza < quando else { return }
        r.scadenza = quando
        ricordi[s.id] = r
        salva()
    }

    /// Ciò che si è detto a voce resta scritto: rileggerlo fra un mese fa vedere il progresso,
    /// e chi vuole può farselo correggere.
    private func annotaDiario(_ s: Scheda, _ detto: String, _ esito: Esito) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        let segno: String
        switch esito { case .giusto: segno = "ok"; case .quasi: segno = "quasi"
                       case .sbagliato: segno = "no"; case .libero: segno = "libero" }
        let riga = "\(f.string(from: Date()))\t\(s.id)\t\(segno)\t\(s.domanda)\t\(detto)\n"
        guard let dati = riga.data(using: .utf8) else { return }
        if let m = try? FileHandle(forWritingTo: Quaderno.diario) {
            defer { try? m.close() }
            _ = try? m.seekToEnd(); try? m.write(contentsOf: dati)
        } else {
            try? dati.write(to: Quaderno.diario)
        }
    }

    // ── i numeri per il pannello ──────────────────────────────────────────────

    struct Numeri { let viste: Int; let sapute: Int; let daRipassare: Int; let totale: Int }

    func numeri(adesso: Int = Int(Date().timeIntervalSince1970)) -> Numeri {
        let vere = schede.filter { $0.tipo != .parla }
        let viste = vere.filter { (ricordi[$0.id]?.viste ?? 0) > 0 }
        return Numeri(viste: viste.count,
                      sapute: viste.filter { (ricordi[$0.id]?.scatola ?? 0) >= 3 }.count,
                      daRipassare: viste.filter { (ricordi[$0.id]?.scadenza ?? 0) <= adesso }.count,
                      totale: vere.count)
    }
}

// ── correggere ────────────────────────────────────────────────────────────────

enum Correttore {

    /// minuscole, senza punteggiatura, spazi semplici. Gli accenti restano.
    static func pulisci(_ t: String) -> String {
        let via = CharacterSet.punctuationCharacters.union(.symbols)
        let senza = t.lowercased().unicodeScalars.map { via.contains($0) ? " " : String($0) }.joined()
        return senza.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// come `pulisci`, e in più senza accenti: «está» e «esta» diventano uguali.
    static func piatta(_ t: String) -> String {
        pulisci(t).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "es"))
    }

    static func distanza(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var riga = Array(0...y.count)
        for i in 1...x.count {
            var prec = riga[0]; riga[0] = i
            for j in 1...y.count {
                let t = riga[j]
                riga[j] = min(riga[j] + 1, riga[j - 1] + 1, prec + (x[i - 1] == y[j - 1] ? 0 : 1))
                prec = t
            }
        }
        return riga[y.count]
    }

    struct Verdetto { let esito: Esito; let messaggio: String }

    /// Una risposta SCRITTA: parola o buco da riempire.
    static func scritta(_ risposta: String, _ s: Scheda) -> Verdetto {
        let tutte = [s.es] + (s.accetta ?? [])
        let r = pulisci(risposta)
        guard !r.isEmpty else { return Verdetto(esito: .sbagliato, messaggio: s.es) }
        // con o senza articolo: «el agua» e «agua» valgono uguale
        func senzaArticolo(_ t: String) -> String {
            let p = t.split(separator: " ")
            if p.count > 1, ["el", "la", "los", "las", "un", "una"].contains(String(p[0])) {
                return p.dropFirst().joined(separator: " ")
            }
            return t
        }
        for g in tutte {
            let pg = pulisci(g)
            if r == pg || senzaArticolo(r) == senzaArticolo(pg) {
                return Verdetto(esito: .giusto, messaggio: g)
            }
        }
        for g in tutte where piatta(risposta) == piatta(g)
            || senzaArticolo(piatta(risposta)) == senzaArticolo(piatta(g)) {
            return Verdetto(esito: .quasi, messaggio: "Occhio all'accento: \(g)")
        }
        for g in tutte {
            let pg = piatta(g), pr = piatta(risposta)
            if pg.count >= 5 && distanza(pr, pg) == 1 {
                return Verdetto(esito: .quasi, messaggio: "Quasi, si scrive: \(g)")
            }
        }
        return Verdetto(esito: .sbagliato, messaggio: s.es)
    }

    /// Quante parole del riferimento sono arrivate, nell'ordine giusto (0…1), e quali mancano.
    static func copertura(_ detto: String, _ atteso: String) -> (quota: Double, mancano: [String]) {
        let d = piatta(detto).split(separator: " ").map(String.init)
        let a = piatta(atteso).split(separator: " ").map(String.init)
        guard !a.isEmpty else { return (0, []) }
        // sottosequenza comune più lunga, parola per parola
        var t = Array(repeating: Array(repeating: 0, count: d.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: d.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == d[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var mancano: [String] = []
        var i = 0, j = 0
        let originali = pulisci(atteso).split(separator: " ").map(String.init)
        while i < a.count {
            if j < d.count && a[i] == d[j] { i += 1; j += 1 }
            else if j < d.count && t[i][j + 1] >= t[i + 1][j] { j += 1 }
            else { mancano.append(i < originali.count ? originali[i] : a[i]); i += 1 }
        }
        return (Double(t[0][0]) / Double(a.count), mancano)
    }

    /// Una risposta DETTA: si confronta la trascrizione col riferimento e le varianti.
    static func detta(_ trascritto: String, _ s: Scheda) -> Verdetto {
        if s.tipo == .parla {
            return Verdetto(esito: .libero, messaggio: trascritto)
        }
        let tutte = [s.es] + (s.accetta ?? [])
        var meglio = (quota: -1.0, mancano: [String](), frase: s.es)
        for g in tutte {
            let c = copertura(trascritto, g)
            if c.quota > meglio.quota { meglio = (c.quota, c.mancano, g) }
        }
        if meglio.quota >= 85.0/100 { return Verdetto(esito: .giusto, messaggio: meglio.frase) }
        if meglio.quota >= 55.0/100 {
            return Verdetto(esito: .quasi,
                            messaggio: "Non ho sentito: \(meglio.mancano.joined(separator: ", "))")
        }
        return Verdetto(esito: .sbagliato, messaggio: meglio.frase)
    }
}
