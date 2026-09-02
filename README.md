# Bevi

Una goccia nella barra in alto del Mac che ti ricorda di bere, e **tace quando non deve
disturbare**.

Niente finestre, niente icona nel Dock, niente account. Un clic sulla goccia e c'è tutto:
i bicchieri di oggi, «ho appena bevuto», il passo, la fascia oraria, la pausa.

Quando è il momento, un cartello blu attraversa tutti i monitor per due secondi e sparisce
da solo. Non ruba il fuoco alla tastiera: se stai scrivendo, le lettere continuano ad
arrivare nell'app che sta sotto.

---

## Installazione

Serve solo Xcode Command Line Tools (`xcode-select --install`), niente altro.

```bash
git clone https://github.com/<utente>/bevi.git
cd bevi
./installa.sh
```

L'app finisce in `~/Applications/Bevi.app` e si accende subito. Per farla partire da sola
quando accendi il Mac: clic sulla goccia → **«Parti all'avvio del Mac»**.

Per disinstallarla: togli la spunta all'avvio automatico, esci dall'app e butta
`~/Applications/Bevi.app`. I dati stanno in una cartella sola (sotto), cancellabile a mano.

---

## Quando tace

È la parte che conta davvero: un cartello a tutto schermo che compare **mentre condividi
lo schermo in una riunione** è il difetto peggiore che un programma così possa avere.

Bevi sta zitta se:

| Situazione | Come se ne accorge |
|---|---|
| **Sei in videochiamata** | la webcam è accesa, oppure un microfono è occupato **senza pause per 14 secondi** |
| **Stai dettando** | il microfono si libera per un istante → era dettatura, non una call |
| **Non sei davanti al Mac** | tastiera e mouse fermi da più di 10 minuti |
| **Lo schermo è bloccato** | sessione bloccata |
| **Hai un Focus acceso** | «Non disturbare» o qualunque altro Focus |
| **Fuori dalla tua fascia oraria** | o durante una pausa che hai chiesto tu |

⭐ E in nessuno di questi casi **l'avviso si brucia**: l'orologio non riparte, il promemoria
resta in canna e esce appena il momento è buono. Se torni al Mac dopo un'ora di riunione,
lo trovi lì ad aspettarti — non ne hai persi tre.

> **Perché il microfono e non la lista delle app.** Rincorrere Meet, Zoom, Teams, Slack,
> FaceTime una per una è una lista che non finisce mai e invecchia da sola. Si chiede invece
> al Mac se lo stream d'ingresso di un microfono è aperto: in una chiamata resta aperto
> anche in muto, e a riposo nessuno lo tiene acceso a vuoto. Copre anche le app che non
> conosciamo.

---

## Cosa c'è nel menu

- **N bicchieri oggi, su M** e quanto manca al prossimo
- **Ho appena bevuto** — segna un bicchiere e fa ripartire l'orologio
- **Fai una pausa** — 30 minuti, 1 ora, 2 ore, fino a domani
- **Promemoria acceso** · **Cartello a tutto schermo** · **Suono**
- **Ogni quanto** (30/45/60/90 min) · **Comincia alle** · **Smetti alle** · **Bicchieri al giorno**
- **Parti all'avvio del Mac**
- **Mostra un cartello di prova** — non conta nessun bicchiere

---

## Dove tiene i dati

In `~/Library/Application Support/Bevi/`, due file di testo:

- **`config`** — le preferenze, in formato `chiave=valore`. Volutamente banale: lo si legge
  e lo si scrive anche da uno script di shell (`. config`), o a mano con un editor.
- **`stato`** — quando è uscito l'ultimo promemoria, che giorno è, quanti bicchieri.

Puoi spostare la cartella impostando la variabile d'ambiente `BEVI_HOME`.

Nessuna rete, nessuna telemetria, nessun account: i dati non escono mai dal tuo Mac.

---

## Com'è fatta

Quattro file Swift, nessuna dipendenza esterna.

| File | Cosa fa |
|---|---|
| `Sorgenti/main.swift` | l'icona nella barra, il menu, il controllo ogni 30 secondi |
| `Sorgenti/Impostazioni.swift` | leggere e scrivere `config` e `stato` |
| `Sorgenti/Presenza.swift` | webcam, microfono, inattività, schermo bloccato, Focus |
| `Sorgenti/Cartello.swift` | il cartello a tutto schermo |

I controlli girano **in ordine di costo**: quasi tutti i risvegli si fermano alla prima
domanda, che costa quanto leggere un file di novanta byte. Quelli cari — il Focus e la
chiamata in corso — si pagano una volta all'ora scarsa, quando tutto il resto ha già detto sì.

Il controllo della chiamata può dormire fino a 14 secondi, quindi gira **su una coda di
sfondo**: l'interfaccia non si pianta mai.

Per ricompilare senza installare: `./costruisci.sh` → `build/Bevi.app`.

---

## Licenza

MIT — vedi [LICENSE](LICENSE).
