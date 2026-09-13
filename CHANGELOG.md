# 0.2.0

- Albero sessioni/finestre/pannelli (`C-b b`), con navigazione, rami
  comprimibili, spostamento dalla riga corrente e stato del tiling.
- Spostamento reale dei pannelli (`C-b m`) fra finestre o sessioni e delle
  finestre (`C-b M`) fra sessioni. Processi e log conservati; appartenenza,
  nomi e numeri aggiornati; contenitori vuoti rimossi e SYNC disattivata
  nei gruppi modificati. Validazione delle destinazioni prima del trasferimento.
- Tiling automatico predefinito dopo creazione/chiusura, con scelta per
  finestra (`C-b A`) e resize manuale valido fino al prossimo ricalcolo.
  Le chiusure fuori dal pannello zoomato non interrompono lo zoom.
- Stato esterno alle strutture esistenti per permettere il reload a caldo.
- 72 test superati su Ghostel 0.40.0 e 0.53.0, compilazione Lisp e prova
  interattiva TTY; verificato il reload 0.1.9 → 0.2.0 con processi aperti.

# 0.1.9

- Indicatore `[S]` prima del nome per i destinatari effettivi del broadcast
  dal terminale selezionato, indipendente dal colore della sessione.
- Gestione della vera finestra selezionata durante il ridisegno: niente
  indicatori su gruppi estranei, durante anteprime o con input locale in zoom.
- `C-b P` mostra l'anteprima del buffer del pannello, anche nascosto o in zoom,
  mantenendo visibili gli altri riquadri. Invio conferma, C-g ripristina.
- Opzione `ghostel-mux-pane-preview`, fallback senza Consult e gestione del
  pannello terminato durante la scelta. I tre selettori condividono la
  protezione dell'input e il ripristino del contesto originale.
- Repository GitHub con baseline 0.1.8 e fix 0.1.9 in commit separati;
  documentazione per installazione da Git, aggiornamento e recupero versioni.
- 58 test superati su Ghostel 0.40.0 e 0.53.0; prova interattiva con
  Consult/Vertico dopo caricamento sopra la 0.1.8 con tre PTY aperte.

# 0.1.8

- `C-b w` elenca esclusivamente le finestre della sessione attiva, anche in
  viste miste; il prompt indica il nome della sessione interessata.
- Anteprima Consult e fallback standard conservano lo stesso ambito.
  Per cambiare sessione resta disponibile `C-b s`.
- 53 test superati su Ghostel 0.40.0 e 0.53.0, con verifica della lista in
  una vista mista, del ripristino e del caso senza sessione collegata.

# 0.1.7

- `C-b O`: pannello precedente, inverso di `C-b o`, anche nello zoom;
  entrambi i comandi sono disponibili nel selettore `C-b :`.
- `C-b w`: anteprima Consult della finestra esatta selezionata, con tutti
  i suoi buffer e l'eventuale zoom, anche attraverso sessioni diverse.
- Invio conferma, C-g ripristina; protezione dell'input e ripristino condivisi
  con il selettore delle sessioni. Opzione `ghostel-mux-window-preview`.
- 53 test superati su Ghostel 0.40.0 e 0.53.0. Verifica interattiva con
  Consult/Vertico dopo aggiornamento a caldo dalla 0.1.6.

# 0.1.6

- Accenti per sessione attivi per impostazione predefinita: colore solo sul
  nome nell'intestazione, con sfondi e indicatori SYNC/COPY conservati.
- Otto tonalità con varianti chiare/scure, distinte anche a 256 colori;
  assegnazione libera o meno usata, stabile durante la vita della sessione.
- Opzione `ghostel-mux-session-colors` per disattivare; facce e palette
  personalizzabili con Customize. Applicazione anche alle sessioni già aperte.
- 50 test esistenti superati su Ghostel 0.40.0 e 0.53.0. Verifica interattiva
  della resa e dell'aggiornamento a caldo dalla 0.1.5 con quattro PTY aperte.

# 0.1.5

- Numerazione dei buffer per sessione, condivisa dalle sue finestre e stabile
  dopo le chiusure; rinomina dei buffer quando cambia il nome della sessione.
- Migrazione a caldo dei pannelli esistenti, senza cambiare processi, ID o log.
- Appartenenza visibile come sessione:finestra/Bnumero; distinzione tra gruppo
  attivo e terminale selezionato nelle viste miste, con input LOCAL esplicito.
- `C-b y` nomina il gruppo interessato. `C-b a` attiva la sessione e la finestra
  del terminale selezionato; disponibile anche nel selettore dei comandi.
- Invariato l'ambito SYNC: soltanto terminali vivi e visibili del gruppo attivo.
- 50 test superati su Ghostel 0.40.0 e 0.53.0; aggiornamento dalla 0.1.4
  verificato con sei PTY aperte e due ricaricamenti consecutivi.

# 0.1.4

- Anteprima dei layout di sessione tramite Consult, integrata con Vertico;
  Invio conferma e C-g ripristina la vista iniziale. Consult resta opzionale.
- Anteprima senza cambio di ownership o salvataggio del layout temporaneo;
  input terminale bloccato durante la scelta e riconciliazione dei processi
  terminati rinviata al ripristino della vista originale.
- Ruoli SELECTED, SYNC TARGET e INACTIVE; SYNC OFF esplicito, elenco dei
  destinatari e motivo della sospensione. PREFIX non nasconde più SYNC.
- Indicatore di selezione corretto anche durante il ridisegno Emacs delle barre.
- 46 test superati su Ghostel 0.40.0 e 0.53.0; prova interattiva con Consult
  2.0 e Vertico 2.0, oltre al caricamento a caldo dalla 0.1.3.

# 0.1.3

- `C-b` è un vero prefisso Emacs: suggerimenti which-key e riconoscimento
  delle sequenze complete tramite gli strumenti di aiuto standard.
- `C-b g` espone la mappa originale del prefisso Ghostel `C-c`, comprese
  le sue personalizzazioni. `C-c` diretto continua a inviare l'interrupt.
- Comandi numerici e resize con nomi leggibili, anziché closure anonime.
- Indicatore PREFIX aggiornato senza lettura manuale dei tasti.
- 40 test superati su Ghostel 0.40.0 e 0.53.0, con which-key 3.6.0 caricato.
  Verificati anche popup interattivi e aggiornamento a caldo dalla 0.1.2.

# 0.1.2

- Risolto il prefisso Mux che intercettava lettere nei minibuffer di comandi,
  nomi e percorsi: la mappa temporanea termina prima dell'esecuzione.
- `C-b M-5` seleziona il layout tiled; `C-b : balance` bilancia quello corrente.
- Aspetto basato sul tema Emacs, senza sfondi o colori terminale imposti.
- Indicatore `[COPY MODE]` in testa a intestazione e barra inferiore, con
  promemoria dei comandi di copia e uscita.
- Aggiornamento a caldo dalla 0.1.1 verificato con sessioni e PTY aperte;
  rimozione delle vecchie rimappature senza alterare quelle dell'utente.
- SYNC limitato ai pannelli vivi e visibili della finestra e del frame
  correnti. Zoom e buffer nascosti non ricevono broadcast; `SYNC PAUSED
  (LOCAL)` indica l'invio locale con un solo destinatario visibile.
- Chiusura automatica alla fine del processo, con flush dei log e pulizia
  di pannello, finestra e sessione. Supportati entrambi i backend PTY.
- 37 test superati su Ghostel 0.40.0 e 0.53.0, inclusi i prompt percorsi con
  keyboard macro reali.

# 0.1.1

- Risolto l'errore `ghostel-create` mancante: percorso di creazione compatibile
  tramite il comando pubblico `ghostel` per le versioni precedenti.
- Compatibilità con la variabile del titolo `ghostel--title` delle versioni
  precedenti, oltre al nome pubblico `ghostel-title`.
- Doctor mostra il percorso della definizione effettivamente caricata.
- Invio del prefisso letterale compatibile anche con Ghostel 0.40.0.
- 27 test superati sia su Ghostel 0.40.0 sia su Ghostel 0.53.0, con i rispettivi
  moduli nativi e shell reali.

# 0.1.0

- Sessioni nominate, finestre multiple, pannelli Ghostel con identità stabile.
- Selettori di sessioni, finestre e pannelli; indici da 1.
- Prefisso C-b, split, navigazione, resize, layout, zoom e detach.
- SYNC per finestra con codifica individuale dei tasti e dell'incolla.
- Selezione persistente e copia col mouse e con M-w/C-w/C-g.
- Presentazione PREFIX/SYNC/normal ispirata alla configurazione tmux fornita.
- Scrollback esportabile e registrazione grezza per pannello.
- Adattatore per Ghostel 0.53.0 senza patch al progetto upstream.
- Test ERT con Emacs e modulo Ghostel reali.
