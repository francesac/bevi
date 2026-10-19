//  Voce.swift — il Mac che parla spagnolo, e che ascolta.
//
//  Parlare: la voce di sistema «Mónica» (castigliano). Ascoltare: il riconoscimento del
//  parlato di macOS 26, che lavora tutto sul Mac — l'audio ⛔ esce mai dal computer.
//  Su un Mac più vecchio gli esercizi a voce diventano «dillo, poi guarda la soluzione».

import AVFoundation
import AppKit
import Speech

// ── parlare ───────────────────────────────────────────────────────────────────

enum Bocca {
    private static let sintetizzatore = AVSpeechSynthesizer()

    static var voce: AVSpeechSynthesisVoice? {
        let tutte = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "es-ES" }
        // la qualità migliore installata, poi Mónica, poi qualunque castigliano
        return tutte.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "es-ES")
    }

    /// `lenta`: per la prima ascoltata di una frase nuova, un po' sotto il passo normale.
    static func di(_ testo: String, lenta: Bool = false) {
        sintetizzatore.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: testo)
        u.voice = voce
        u.rate = AVSpeechUtteranceDefaultSpeechRate * (lenta ? 0.8 : 0.95)
        sintetizzatore.speak(u)
    }

    static func zitta() { sintetizzatore.stopSpeaking(at: .immediate) }
}

// ── ascoltare ─────────────────────────────────────────────────────────────────

/// Un orecchio per volta. `ascolta` accende il microfono e manda il testo man mano che
/// lo capisce; `basta` chiude e consegna la trascrizione finale.
final class Orecchio {

    static var disponibile: Bool {
        if #available(macOS 26.0, *) { return SpeechTranscriber.isAvailable }
        return false
    }

    /// Il permesso del microfono. La prima volta macOS chiede a lui con la sua finestra.
    static func chiediPermesso(_ fatto: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: fatto(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { fatto(ok) } }
        default: fatto(false)
        }
    }

    private var motore: AnyObject?

    func ascolta(mentre: @escaping (String) -> Void, errore: @escaping (String) -> Void) {
        guard #available(macOS 26.0, *) else { errore("Serve macOS 26 per ascoltarti."); return }
        let m = MotoreAscolto()
        motore = m
        m.parti(mentre: mentre, errore: errore)
    }

    func basta(_ fatto: @escaping (String) -> Void) {
        guard #available(macOS 26.0, *), let m = motore as? MotoreAscolto else { fatto(""); return }
        motore = nil
        m.ferma(fatto)
    }

    func annulla() {
        guard #available(macOS 26.0, *), let m = motore as? MotoreAscolto else { return }
        motore = nil
        m.ferma { _ in }
    }

    /// Il modello spagnolo si scarica una volta sola (qualche decina di MB, da Apple).
    /// Si chiede all'avvio, in sottofondo: così il primo esercizio a voce è già pronto.
    static func preparaModello() {
        guard #available(macOS 26.0, *) else { return }
        Task.detached(priority: .background) {
            let t = SpeechTranscriber(locale: Locale(identifier: "es-ES"), preset: .transcription)
            if let r = try? await AssetInventory.assetInstallationRequest(supporting: [t]) {
                try? await r.downloadAndInstall()
            }
        }
    }
}

@available(macOS 26.0, *)
private final class MotoreAscolto {
    private let audio = AVAudioEngine()
    private var flusso: AsyncStream<AnalyzerInput>.Continuation?
    private var analizzatore: SpeechAnalyzer?
    private var raccolta: Task<String, Never>?
    private var definitivo = ""
    private var provvisorio = ""
    private let chiave = NSLock()

    func parti(mentre: @escaping (String) -> Void, errore: @escaping (String) -> Void) {
        let trascrittore = SpeechTranscriber(locale: Locale(identifier: "es-ES"),
                                             preset: .progressiveTranscription)
        let analizzatore = SpeechAnalyzer(modules: [trascrittore])
        self.analizzatore = analizzatore
        let (ingresso, flusso) = AsyncStream<AnalyzerInput>.makeStream()
        self.flusso = flusso

        raccolta = Task { [weak self] in
            do {
                for try await r in trascrittore.results {
                    guard let self else { break }
                    let ora = self.aggiungi(String(r.text.characters), finale: r.isFinal)
                    DispatchQueue.main.async { mentre(ora) }
                }
            } catch {}
            return self?.aggiungi("", finale: false, soloLeggi: true) ?? ""
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                guard let formato = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [trascrittore]) else { throw Guasto.formato }
                try await analizzatore.start(inputSequence: ingresso)
                try self.accendiMicrofono(verso: formato)
            } catch {
                DispatchQueue.main.async { errore("Non riesco ad ascoltarti: \(error.localizedDescription)") }
            }
        }
    }

    private enum Guasto: Error { case formato }

    /// Il testo capito finora. Sincrona apposta: il lucchetto non si tiene attraverso un `await`.
    private func aggiungi(_ pezzo: String, finale: Bool, soloLeggi: Bool = false) -> String {
        chiave.lock(); defer { chiave.unlock() }
        if !soloLeggi {
            if finale { definitivo += pezzo; provvisorio = "" } else { provvisorio = pezzo }
        }
        return (definitivo + provvisorio).trimmingCharacters(in: .whitespaces)
    }

    private func accendiMicrofono(verso formato: AVAudioFormat) throws {
        let entrata = audio.inputNode
        let naturale = entrata.outputFormat(forBus: 0)
        let traduttore = AVAudioConverter(from: naturale, to: formato)
        entrata.installTap(onBus: 0, bufferSize: 4096, format: naturale) { [weak self] buffer, _ in
            guard let self, let traduttore else { return }
            let quanti = AVAudioFrameCount(Double(buffer.frameLength) * formato.sampleRate / naturale.sampleRate) + 1
            guard let uscita = AVAudioPCMBuffer(pcmFormat: formato, frameCapacity: quanti) else { return }
            var dato = false
            traduttore.convert(to: uscita, error: nil) { _, stato in
                if dato { stato.pointee = .noDataNow; return nil }
                dato = true; stato.pointee = .haveData; return buffer
            }
            self.flusso?.yield(AnalyzerInput(buffer: uscita))
        }
        audio.prepare()
        try audio.start()
    }

    func ferma(_ fatto: @escaping (String) -> Void) {
        audio.inputNode.removeTap(onBus: 0)
        audio.stop()
        flusso?.finish()
        let analizzatore = self.analizzatore
        let raccolta = self.raccolta
        Task {
            // tetto: se il riconoscimento si appende, dopo 4 secondi si consegna quel che c'è
            let chiusura = Task { try? await analizzatore?.finalizeAndFinishThroughEndOfInput() }
            let scadenza = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); chiusura.cancel()
                                  await analizzatore?.cancelAndFinishNow() }
            _ = await chiusura.value
            scadenza.cancel()
            let testo = await raccolta?.value ?? ""
            DispatchQueue.main.async { fatto(testo) }
        }
    }
}
