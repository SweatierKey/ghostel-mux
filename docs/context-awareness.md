# Contesto del pannello e TRAMP — 0.4.0

L'integrazione è **opzionale e attivata esplicitamente nella shell corrente**.
Segue host, utente e directory; associa quei dati a un percorso TRAMP scelto
da te. Non modifica SSH, PSMP o sudo e non installa file sul server.

## Uso

Posizionati su un **prompt Bash interattivo vuoto**, senza comandi parziali,
password da inserire o programmi a tutto schermo in esecuzione. Premi
`C-b i` e indica il prefisso TRAMP della shell nella quale ti trovi:

| Shell corrente | Prefisso da inserire |
| --- | --- |
| Locale, stesso utente di Emacs | Lascia vuoto e premi Invio |
| Dopo `ssh server1` | `/ssh:server1:` |
| Su server1 dopo `sudo -iu oracle` | `/ssh:server1\|sudo:oracle@server1:` |
| Collegamento con più passaggi | Copia il prefisso TRAMP che usi già con successo |

Le barre verticali nella tabella fanno parte dei prefissi TRAMP.
Un nome completo come `/ssh:server1:/home/me/` è accettato: viene conservata
la parte di connessione; la directory arriva dalla shell.
Gli alias e gli utenti omessi restano tali, quindi SSH/TRAMP applicano la
tua configurazione. Non serve espandere gli alias o inserire l'utente
quando normalmente non lo specifichi. La cronologia facilita il riuso.

Dopo l'attivazione:

- `C-j` oppure `C-b j` apre Dired nella directory corrente.
- `M-x compile`, `M-x shell-command`, `M-x async-shell-command` e
  `M-x shell`, richiamati dal terminale, usano quel contesto.
- La barra mostra `utente@host` quando c'è spazio. `[CTX?]` indica
  un contesto non disponibile. `C-b I` mostra directory, identità,
  prefisso esatto ed eventuale errore.
- Un normale `cd` aggiorna automaticamente la directory al prompt seguente.

**Ogni nuova shell richiede una nuova attivazione**, anche dopo SSH, sudo,
su o un altro Bash. Tornando con `exit` a una shell già integrata,
l'associazione precedente riprende al suo prompt. Puoi correggere il
prefisso ripetendo `C-b i`. Anche la prima shell locale richiede
l'attivazione: questa versione non invia codice automaticamente.

Esempio: attiva la shell locale con prefisso vuoto; entra in server1,
attiva con `/ssh:server1:`; passa a oracle e attiva con
`/ssh:server1|sudo:oracle@server1:`. I successivi `cd` e i ritorni alle
shell precedenti vengono seguiti senza riscrivere il prefisso.

## Che cosa viene inviato

Mux legge il file locale [ghostel-mux-context.bash](../shell/ghostel-mux-context.bash)
e lo invia come un comando Bash nella PTY selezionata. Il comando definisce
funzioni, variabili, un'aggiunta a `PROMPT_COMMAND` e una combinazione
privata di Readline **nella memoria di quella shell**. Non scrive profili,
file di configurazione, wrapper o agenti remoti. Il comando può comparire
nella normale history o nei log già attivi.

L'attivazione rileva hostname e utente tramite `hostname` e `id -un`.
Ai prompt successivi invia directory, identità, PID e numero di sequenza
con un messaggio OSC, usando soltanto builtin Bash. Conserva il
`PROMPT_COMMAND` esistente, scalare o array; non modifica `PS1` o il
trap `DEBUG`. Un `PROMPT_COMMAND` readonly impedisce l'attivazione.
Su Bash 4.2 usa anche la sequenza Readline `C-x C-^` come passaggio interno,
riservandola nella shell attivata: aggira il limite di quella versione sui
binding lunghi di `bind -x`. Un `PROMPT_COMMAND` array richiede Bash 5.1+.

L'OSC usa il canale Ghostel `52;e` e un singolo ricevitore esplicitamente
autorizzato in quel buffer. I campi sono dati codificati in esadecimale,
non espressioni Lisp da eseguire. Il ricevitore non apre file o connessioni.
I prefissi TRAMP restano in Emacs e non vengono inseriti nel codice Bash.

## Disponibilità e verifica prima di agire

L'input del terminale invalida il contesto finché non arriva un nuovo prompt.
Questo evita di continuare a presentare come attuale una directory osservata
prima di un SSH, sudo o comando ancora in esecuzione.

Inoltre, **ogni apertura Dired tramite i tasti Mux e ogni comando elencato
sopra richiede una risposta nuova**, con un identificativo specifico per
quell'azione. La richiesta usa la combinazione privata di Readline nella
stessa PTY: non avvia una seconda connessione SSH e non invia un comando
di shell né un Invio. Un vecchio prompt o una risposta ritardata a un'altra
richiesta non basta per procedere.

Se manca la risposta, arriva da un'altra shell, l'identità cambia o premi
`C-g`, l'azione si interrompe. Non ripiega su localhost. La directory del
buffer diventa un percorso bloccato, così le normali operazioni sui file
non usano silenziosamente la directory precedente.

Un programma o una shell senza hook potrebbe mostrare i caratteri di una
richiesta non riconosciuta. In quel caso torna a un prompt vuoto, pulisci
l'eventuale testo parziale e attiva l'integrazione. Il protocollo è
collaborazione con la shell, non un sistema di autenticazione dell'output.

L'attesa massima è personalizzabile:

```elisp
(setq ghostel-mux-context-timeout 6)
```

Le notifiche dei prompt non fanno accessi TRAMP. La verifica aggiunge un
andata/ritorno sulla connessione terminale già aperta; solo dopo Dired o
il comando richiesto effettuano il normale accesso locale/TRAMP.

## Accesso, identità e limiti

- Il prefisso è un'associazione **esplicita**, non una ricostruzione della
  catena SSH. Hostname remoto e alias di connessione possono essere diversi;
  Mux non può dimostrare che un alias punti all'host osservato.
- Per un prefisso locale controlla hostname locale e UID di Emacs.
  Per un ultimo passaggio sudo/su/doas controlla anche l'utente dichiarato.
  Non riscrive gli username di accesso, che possono avere sintassi PSMP.
- TRAMP apre o riusa la propria connessione. Non adotta il processo SSH
  del terminale. Host, utente e directory non implicano il riuso di variabili
  esportate, virtualenv, stato del processo o ambiente Oracle della PTY.
- `shell` crea un buffer separato; non riusa implicitamente una shell già
  aperta con un'altra identità. Le compilazioni hanno nomi legati al contesto.
- Gli altri comandi compatibili con TRAMP possono usare
  `default-directory` aggiornato al prompt; **non tutti i pacchetti Emacs
  ricevono la verifica fresca** prevista per i quattro comandi elencati.
- Una volta aperto Dired o un buffer di compilazione, quel buffer conserva
  il suo contesto. Non segue i futuri `cd` del terminale.
- L'attivazione richiede Bash 4.2+ interattivo con Readline. Zsh, fish,
  applicazioni a tutto schermo e shell senza prompt hook non sono coperti.
  La prova aziendale con `printf` verifica il trasporto OSC; il giro
  completo di attivazione e richiesta Readline va provato sul tuo percorso.
- Disattivare il minor mode ripristina la directory precedente; le funzioni
  nella shell restano fino alla sua chiusura. Per una sessione pulita chiudi
  quella shell. Il supporto Ghostel ordinario resta disponibile nei pannelli
  in cui questa integrazione non viene attivata.

## SYNC e struttura Mux

Attivazione, risposte automatiche e richieste di verifica restano nel solo
pannello selezionato. Non si propagano tramite SYNC.

L'input ordinario segue le regole Mux: solo i pannelli vivi e visibili della
finestra attiva; durante lo zoom solo quello visibile. Ogni destinatario
invalida e aggiorna il proprio contesto separatamente.

Il contesto appartiene al buffer del terminale: spostare quel pannello tra
finestre o sessioni non cambia la sua shell o il prefisso assegnato.

## Verifica

Vedi [VALIDATION.md](../VALIDATION.md) per ambiente, prove reali e limiti.
