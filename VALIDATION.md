# Verifica della versione 0.2.0

**72 test ERT superati su Ghostel 0.40.0 e 0.53.0, 0 errori inattesi.**
Emacs 29.3 su Linux, shell Bash locali con PTY reali. I risultati sono in
`test-results.txt`; la descrizione dell'ambiente precedente resta sotto.

Le nuove prove verificano:

- Spostamento di pannelli nella stessa sessione e fra sessioni, conservando
  identità del processo, ID del pannello, file di log e numerazione coerente.
- Consegna SYNC soltanto al nuovo gruppo visibile dopo riattivazione;
  disattivazione dei gruppi coinvolti nel trasferimento.
- Trasferimento dell'ultimo pannello con creazione della nuova finestra senza
  nuova shell e rimozione dei contenitori lasciati vuoti.
- Spostamento dell'intera finestra con conservazione di processi e zoom.
- Destinazioni scadute, anteprime aperte ed errori di layout: trasferimento
  rifiutato prima di cambiare appartenenza e stato SYNC.
- Tiling dopo chiusura, chiusura in una sessione nascosta, conservazione dello
  zoom quando termina un altro pannello e modalità manuale per finestra.
- Albero, visita del layout completo, chiusura dell'ultima shell nell'albero,
  digitazione nel prompt di spostamento e annullamento senza effetti.

Prova interattiva in Emacs TTY con Ghostel 0.53.0: tre pannelli `lab`, una
finestra `sandbox`; apertura dell'albero con `C-b b`, movimento con `n`,
`m` e annullamento del prompt conservando la riga; trasferimento del pannello
B2 in `sandbox`, `RET` per aprirne il layout a due pannelli; trasferimento
della finestra `tools` in `lab`, numeri B4/B5, sessione vuota rimossa.
Il processo del pannello trasferito è rimasto vivo durante entrambe le mosse.

Prova di reload 0.1.9 → 0.2.0 con terminali già aperti: identità del processo
conservata, spostamento fra sessioni, apertura/chiusura dell'albero e ripristino
del layout. Le strutture esistenti non vengono sostituite al caricamento.

Le prove interattive sono su un singolo frame TTY e shell locali: non sono
una verifica con server SSH/PSMP reali o più frame grafici simultanei.

# Storico: verifica della versione 0.1.9

## Ambiente

- Emacs 29.3, Linux x86_64, esecuzione batch.
- Ghostel 0.40.0 e 0.53.0, ciascuno con il proprio modulo nativo ufficiale Linux x86_64.
- `ghostel.el` verificato sul blob
  `1c496a1fde8285dce98ba2ec4dd52b77bd066166`.
- Shell locali `/bin/bash --noprofile --norc`, PTY reali.
- Shell integration disattivata nelle prove per non caricare profili personali.
- which-key 3.6.0: test di discovery delle mappe e prova interattiva in Emacs TTY.
- Consult 2.0 e Vertico 2.0: selezione e anteprima dei layout in Emacs TTY.

## Risultato

**58 test ERT superati su ciascuna delle due versioni, 0 errori inattesi.**

Nella 0.1.9 sono verificati i destinatari del marker `[S]` rispetto alla
consegna dell'input: più pannelli, zoom, buffer nascosti, sorgente estranea,
e incolla esplicito dalla copy mode. Il test del rendering distingue la
finestra temporaneamente selezionata da Emacs da quella effettiva e controlla
che il colore della sessione resti applicato soltanto al nome.

Per C-b P: selezione tramite keyboard macro con Consult, pannello scelto
nello zoom, fallback standard, anteprima di un buffer nascosto, blocco degli
invii, annullamento e candidato terminato durante l'anteprima.

Verifica interattiva su Ghostel 0.40.0, Consult 2.0 e Vertico 2.0 dopo reload
0.1.8 -> 0.1.9: tre PTY conservate; marker su P1/P3 con P2 nascosto;
anteprima di P2 lasciando visibili i riquadri fratelli; digitazione aggiuntiva
nel minibuffer; C-g ripristina P1/P3; Invio seleziona P2 e aggiorna i marker
a P1/P2; zoom su P2 rimuove i marker. `test-results.txt` include questi stati.

Nella 0.1.8, i test del selettore verificano che i candidati appartengano
solo alla sessione attiva. La prova include un terminale di un'altra sessione
visualizzato nel pannello selezionato: lista e prompt restano riferiti alla
sessione collegata. Verificati anteprima, annullamento, selezione tramite
keyboard macro con Consult, fallback standard e errore senza sessione attiva.

La prova interattiva Consult/Vertico della 0.1.7 aveva verificato la
continuazione della digitazione dopo un'anteprima e il ripristino con C-g.
Nella 0.1.8 non è stata ripetuta: l'ambito dei candidati è cambiato e il
protocollo di anteprima è rimasto identico. I test di regressione sono stati
rieseguiti con il nuovo ambito.

La seguente verifica dei colori risale alla 0.1.6:

Verificato in Emacs TTY a 256 colori il caricamento della 0.1.6 sopra la
0.1.5: tre sessioni e quattro PTY conservate, accenti applicati ai nomi già
visualizzati. Rinomina e secondo ricaricamento conservano le associazioni;
disattivando l'opzione ritorna la faccia circostante. Numeri e COPY mantengono
le loro facce. Verificata la resa in una vista mista e con il tema Wombat.
La palette contiene otto codici terminale distinti sia in modalità chiara
sia scura; nessuna faccia accento imposta uno sfondo. La verifica interattiva
è separata dalla suite dei 50 test di regressione esistenti.

La migrazione dei numeri dalla 0.1.4 alla 0.1.5 era stata verificata con sei
PTY e due ricaricamenti; i test di migrazione sono mantenuti nella suite.

Le seguenti prove interattive risalgono alla 0.1.4; i corrispondenti test ERT
sono stati rieseguiti nella 0.1.9:

Con Consult e Vertico in Emacs interattivo: apertura con C-b s, navigazione
tra sessioni con layout diversi, anteprima senza cambiare la sessione
collegata, C-g con ripristino e Invio con cambio effettivo. Dopo la conferma,
il pannello resta in semi-char mode. Le barre mostrano un solo SELECTED e
distinguono gli altri destinatari attivando SYNC.

Nella prova interattiva TTY, attendere dopo `C-b` ha aperto il popup
which-key con i comandi Mux; digitare `g` ha mostrato quelli Ghostel.
L'indicatore PREFIX era attivo per entrambe le sequenze e si è spento
all'uscita dal prefisso. La prova non usa una chiamata manuale al popup.
L'Emacs estratto ha emesso avvisi relativi al proprio compilatore nativo
non installato: il funzionamento dei popup è stato osservato ugualmente.

La 0.40.0 non contiene `ghostel-create`: la suite verifica quindi anche
la creazione effettiva dei terminali attraverso il percorso precedente,
incluse nuove sessioni, split, SYNC e ripristino dei layout.

La suite è stata eseguita anche sul sorgente `.el` non compilato mediante il
`Makefile` e `test/run-tests.el` inclusi nell'archivio. Il file principale è
stato inoltre compilato in bytecode senza diagnostiche relative al pacchetto.
Il bytecode non viene distribuito: Emacs carica il sorgente corrispondente.

`test-results.txt` contiene l'output delle due esecuzioni finali. Gli avvisi di
registrazione e consegna parziale presenti nel file sono errori provocati
intenzionalmente dai relativi test. Il warning sul percorso Lisp predefinito
deriva dall'Emacs di verifica estratto in una directory privata; i percorsi
effettivi delle librerie erano impostati esplicitamente.

## Comportamenti verificati

- Numeri dei buffer indipendenti per sessione, condivisi dalle sue finestre;
  continuità dopo una chiusura e rinomina con log e processo invariati.
- Migrazione ripetuta senza riallocare numeri; buffer estranei con nomi in
  conflitto conservati durante la rinomina.
- Vista mista con X:2 selezionato e Y:1 attivo: ruolo locale, gruppo esplicito,
  C-b y su Y, input in X locale e input in Y escluso da X e dal terminale nascosto.
- C-b M-5 ripristina i terminali nascosti del gruppo; C-b a attiva la corretta
  sessione e finestra del terminale selezionato, con tutte le PTY ancora vive.

- Creazione e selezione di sessioni e finestre; terminali distinti per split.
- Conservazione dei buffer, degli indici e dei layout.
- Zoom, cambio sessione, ritorno e ripristino del layout completo.
- Navigazione tra pannelli mentre la finestra è zoomata.
- Broadcast solo ai pannelli visibili, separazione tra sessioni e disattivazione.
- Zoom: input locale da shell reale; dopo lo zoom out il broadcast riprende.
  Un comando successivo ricevuto da tutti funge da barriera per verificare
  che il comando locale precedente non sia arrivato ai pannelli nascosti.
- Tasti, interrupt, prefisso letterale e incolla da tastiera durante lo zoom:
  riceve solo il pannello visibile, anche cambiando pannello mentre si è zoomati.
- Buffer nascosti senza zoom e buffer di un'altra sessione visualizzati
  accanto alla corrente: esclusi dai destinatari del gruppo corrente.
- Viste duplicate dello stesso buffer: una consegna; un destinatario che
  diventa nascosto durante la consegna viene escluso prima del suo turno.
- Digitazione attraverso keyboard macro con i tasti effettivi `C-b %`,
  `C-b y` e `C-b z`, e comandi ricevuti dalle shell.
- Una sola consegna per pannello anche quando l'encoder usa il fallback.
- Invio del prefisso letterale `C-b` su ciascun pannello sincronizzato.
- `C-b : new-session` e successivo nome digitati via keyboard macro,
  con minibuffer reali, senza sostituire le funzioni di lettura.
- Rinomina pannello tramite `C-b T`, con lettere che prima invocavano comandi.
- `C-b M-5` da zoom: quattro buffer conservati e dimensioni bilanciate.
- Indicatori copy mode all'ingresso, dopo la copia e all'uscita.
- Rimozione delle vecchie rimappature Mux conservando quelle dell'utente.
- Input interattivo replicato e invii programmatici lasciati locali.
- Incolla Unicode e multilinea tramite encoder separati.
- Due PTY con modalità cursore diversa: la freccia su produce rispettivamente
  `ESC [ A` e `ESC O A`, verificati con `dd` e `od` dentro le shell.
- Callback di output e invii automatici lasciati locali.
- Selezione persistente, copia senza cancellazione del buffer e uscita.
- Eventi mouse sintetici: drag e rilascio, doppio clic, triplo clic e reset.
- Precedenza delle mappe di prefisso/copia anche in Ghostel char mode.
- Discovery dei prefissi nativi con `key-binding`, `where-is-internal` e
  which-key caricato; cambi modalità Ghostel eseguiti via keyboard macro.
- Le modifiche alla mappa originale Ghostel sono visibili anche sotto `C-b g`.
- Anteprime ripetute di layout e zoom senza mutare gli stati salvati,
  l'ownership o l'identità dei terminali; finestra origine Consult conservata.
- Prompt Consult reale da keyboard macro; annullamento dopo anteprima e dopo
  chiusura della sessione originale, con ripristino dell'ambiente Emacs.
- Input bloccato durante l'anteprima e gestione rinviata dei processi terminati.
- Ruoli dei pannelli, elenco dei destinatari, stato locale e selezione durante
  il ridisegno delle barre verificati separatamente.
- Registrazione delle sequenze ANSI originali e dell'output nascosto.
- Conservazione nei log di output già espulso dallo scrollback in memoria.
- Permessi e nomi dei file di log; gestione degli errori di registrazione.
- Disattivazione di SYNC dopo una consegna parziale, senza retry.
- Chiusura di pannelli, pulizia dei layout e rinumerazione delle finestre.
- Uscita reale della shell su entrambi i backend PTY: pannello e buffer chiusi,
  output finale nel log, ultimo pannello rimosso con ritorno all'ambiente Emacs.
- Morte forzata di una shell nascosta: lo zoom sul pannello sopravvissuto resta
  attivo e il suo input rimane locale.
- Rollback del layout se la creazione di un terminale fallisce.
- Detach con ripristino dell'ambiente Emacs e terminali ancora attivi.
- Disponibilità del backend PTY nativo quando i log sono disabilitati.

Le prove combinano integrazione reale con PTY/modulo e verifiche mirate con
funzioni sostituite per contare le consegne o provocare un errore. Non tutte
le asserzioni sono prove end-to-end di una shell.

## Limiti della verifica

Non sono stati verificati il tuo tema grafico, il puntatore fisico e la
clipboard Windows, le tue altre estensioni Emacs, sessioni in più frame
grafici, collegamenti PSMP/TRAMP/sudo reali o carichi di output prolungati.
Il supporto a future versioni Ghostel deve essere verificato perché
l'adattatore usa anche funzioni private.
L'integrazione Consult usa `consult--read` e il suo protocollo di stato;
anche questi richiedono una verifica in caso di cambiamenti upstream.

Il test which-key viene saltato se il pacchetto non è disponibile. Per
includerlo con una copia esterna, imposta `WHICH_KEY_LISP` alla directory
che contiene `which-key.el`. Nelle esecuzioni consegnate non è stato saltato.
I test Consult vengono saltati se Consult non è disponibile. Nelle prove
consegnate è caricato dal percorso delle librerie di verifica.

Questa versione copre il flusso richiesto dentro un processo Emacs vivo;
non implementa un server indipendente che conservi le PTY dopo la sua uscita.
