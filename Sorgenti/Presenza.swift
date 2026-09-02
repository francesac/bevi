//  Presenza.swift — «è un buon momento per disturbare?»
//
//  Un cartello a tutto schermo che compare mentre stai condividendo lo schermo in una
//  riunione è il difetto peggiore che questo programma possa avere. Qui stanno i controlli
//  che lo impediscono, in ordine di costo: prima quelli che costano niente.

import Foundation
import CoreGraphics
import CoreAudio
import CoreMediaIO
import IOKit

// ── la webcam è accesa? ───────────────────────────────────────────────────────
// Segnale fortissimo: se la telecamera gira sei in videochiamata, punto. Ma non basta da
// solo — in riunione la telecamera si tiene spenta spessissimo.
func webcamInUso() -> Bool {
    var elenco = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(0))
    var peso: UInt32 = 0
    let sistema = CMIOObjectID(kCMIOObjectSystemObject)
    guard CMIOObjectGetPropertyDataSize(sistema, &elenco, 0, nil, &peso) == 0, peso > 0
    else { return false }
    let quanti = Int(peso) / MemoryLayout<CMIOObjectID>.size
    var dispositivi = [CMIOObjectID](repeating: 0, count: quanti)
    var usati: UInt32 = 0
    guard CMIOObjectGetPropertyData(sistema, &elenco, 0, nil, peso, &usati, &dispositivi) == 0
    else { return false }

    for apparecchio in dispositivi {
        var uso = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(0))
        var acceso: UInt32 = 0
        var quanto: UInt32 = 0
        if CMIOObjectGetPropertyData(apparecchio, &uso, 0, nil,
                                     UInt32(MemoryLayout<UInt32>.size), &quanto, &acceso) == 0,
           acceso != 0 { return true }
    }
    return false
}

// ── qualcuno sta usando un microfono? ─────────────────────────────────────────
// ⭐ Non si rincorrono le app una per una (Meet, Zoom, Teams, Slack, FaceTime: è una lista
//    che non finisce mai). Si chiede al Mac se lo stream d'ingresso di qualche microfono è
//    aperto: in una chiamata resta aperto anche quando sei in muto, e a riposo nessuno lo
//    tiene acceso a vuoto. Copre così anche le app che non conosciamo.
func microfonoInUso() -> Bool {
    var elenco = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                            mScope: kAudioObjectPropertyScopeGlobal,
                                            mElement: kAudioObjectPropertyElementMain)
    var peso: UInt32 = 0
    let sistema = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(sistema, &elenco, 0, nil, &peso) == noErr else { return false }
    let quanti = Int(peso) / MemoryLayout<AudioObjectID>.size
    guard quanti > 0 else { return false }
    var dispositivi = [AudioObjectID](repeating: 0, count: quanti)
    guard AudioObjectGetPropertyData(sistema, &elenco, 0, nil, &peso, &dispositivi) == noErr
    else { return false }

    for apparecchio in dispositivi {
        // ha davvero dei canali in ingresso? (gli altoparlanti non contano)
        var configurazione = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var pesoConf: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(apparecchio, &configurazione, 0, nil, &pesoConf) == noErr,
              pesoConf > 0 else { continue }
        let memoria = UnsafeMutableRawPointer.allocate(
            byteCount: Int(pesoConf), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memoria.deallocate() }
        guard AudioObjectGetPropertyData(apparecchio, &configurazione, 0, nil, &pesoConf, memoria) == noErr
        else { continue }
        let lista = UnsafeMutableAudioBufferListPointer(
            memoria.assumingMemoryBound(to: AudioBufferList.self))
        var canali = 0
        for pezzo in lista { canali += Int(pezzo.mNumberChannels) }
        guard canali > 0 else { continue }

        var uso = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var acceso: UInt32 = 0
        var pesoUso = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(apparecchio, &uso, 0, nil, &pesoUso, &acceso) == noErr,
           acceso != 0 { return true }
    }
    return false
}

// ── in chiamata, o stai solo dettando? ────────────────────────────────────────
// 🔴 Il microfono da solo NON basta: chi usa la dettatura (Wispr Flow, la dettatura di
//    macOS, un comando vocale) accende il microfono di continuo. Preso alla lettera, il
//    promemoria non uscirebbe mai più.
//    Il discrimine è la DURATA: una dettatura dura secondi, una riunione dura minuti.
//    Quindi, se il microfono è occupato, si guarda se lo resta ININTERROTTAMENTE per una
//    quindicina di secondi. Se si libera anche solo un istante, stavi dettando.
//
// ⛔ Questa funzione DORME: non va mai chiamata dal thread principale, o l'interfaccia
//    si pianta. Chi la usa la manda su una coda di sfondo.
func inChiamata(attesa: Int = 14) -> Bool {
    if webcamInUso() { return true }          // la telecamera gira: è una call, subito
    if !microfonoInUso() { return false }     // microfono libero: via libera, ~60 ms
    var trascorsi = 0
    while trascorsi < attesa {
        Thread.sleep(forTimeInterval: 2)
        trascorsi += 2
        if webcamInUso() { return true }
        if !microfonoInUso() { return false } // si è liberato: era una dettatura
    }
    return true
}

// ── lo schermo è bloccato? ────────────────────────────────────────────────────
func schermoBloccato() -> Bool {
    guard let sessione = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return (sessione["CGSSessionScreenIsLocked"] as? Int) == 1
}

// ── da quanto non tocca il Mac? ───────────────────────────────────────────────
// 🔴 Il display NON si interroga con `pmset -g powerstate IODisplayWrangler`: su macOS
//    recente risponde «Internal failure» e il controllo passa per fallito. Si guarda invece
//    l'inattività di tastiera e mouse — che è pure la domanda giusta: se non sei davanti,
//    il promemoria ti ASPETTA invece di bruciarsi a vuoto.
func fermoDaSecondi() -> Int {
    let servizio = IOServiceGetMatchingService(kIOMainPortDefault,
                                               IOServiceMatching("IOHIDSystem"))
    guard servizio != 0 else { return 0 }
    defer { IOObjectRelease(servizio) }
    guard let proprieta = IORegistryEntryCreateCFProperty(
            servizio, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() else { return 0 }
    var nanosecondi: UInt64 = 0
    if let numero = proprieta as? NSNumber {
        nanosecondi = numero.uint64Value
    } else if CFGetTypeID(proprieta) == CFDataGetTypeID() {
        let dati = proprieta as! CFData
        guard CFDataGetLength(dati) >= 8 else { return 0 }
        withUnsafeMutableBytes(of: &nanosecondi) { destinazione in
            CFDataGetBytes(dati, CFRangeMake(0, 8),
                           destinazione.bindMemory(to: UInt8.self).baseAddress)
        }
    }
    return Int(nanosecondi / 1_000_000_000)
}

// ── c'è un Focus / «Non disturbare» acceso? ───────────────────────────────────
// macOS non offre una domanda pubblica per saperlo, ma tiene il registro in un file:
// se dentro c'è un'asserzione attiva, un Focus è acceso. Se il file cambia forma in una
// versione futura, il controllo semplicemente risponde «nessun Focus» — e il peggio che
// succede è che il promemoria esca comunque, cioè il comportamento normale.
func focusAcceso() -> Bool {
    let percorso = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    guard let dati = try? Data(contentsOf: percorso),
          let radice = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
          let blocchi = radice["data"] as? [[String: Any]] else { return false }
    for blocco in blocchi {
        if let registrazioni = blocco["storeAssertionRecords"] as? [Any], !registrazioni.isEmpty {
            return true
        }
    }
    return false
}
