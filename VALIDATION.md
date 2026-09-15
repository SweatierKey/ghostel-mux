# Verifica della versione 0.4.0

**110 test ERT superati su Ghostel 0.40.0 e 0.53.0**, su ciascuna versione,
senza errori inattesi né test saltati. Risultati in
[test-results.txt](test-results.txt).

## Ambiente

- Emacs 30.1, Debian Linux x86_64.
- Ghostel v0.40.0 e v0.53.0, ciascuno con il proprio modulo nativo ufficiale.
- Bash 5.2.15 e terminali con PTY reali, profili e shell integration Ghostel
  disattivati nella suite ordinaria. Consult e which-key disponibili.
- Due test condizionali hanno eseguito realmente sudo locale: shell
  `sudo -n -iu root`, ritorno al genitore e accesso TRAMP/sudo con Dired e
  `shell-command`. In altri ambienti sono saltati se sudo senza password
  non è disponibile.
- Byte-compilazione di `ghostel-mux.el` e `ghostel-mux-context.el` con
  warning trattati come errori, Ghostel 0.53: nessun warning.
- Sintassi dello script verificata con Bash 4.2 e 5.2; `git diff --check`
  senza errori.

Le prove sono state lanciate con
`--eval '(setq comp-enable-subr-trampolines nil)'` per tenere la suite
indipendente dalla compilazione nativa delle funzioni ridefinite dai test.
È un'impostazione del comando di test, non un requisito nell'init utente.

## Contesto: prove reali e regressioni

Le 19 nuove prove coprono:

- Attivazione, cambio directory e richiesta di risposta fresca su PTY.
- Percorsi Unicode, spazi e virgolette; protocollo esadecimale; un percorso
  locale con sintassi simile a TRAMP resta locale.
- Conservazione letterale di alias, porte e catene multihop senza
  registrare proxy; rifiuto di un utente sudo incoerente.
- Rifiuto di sequenze vecchie, token e identificativi di richiesta errati,
  messaggi malformati e cambi inattesi dell'identità della shell.
- Shell figlia non integrata: azione bloccata anche simulando un vecchio
  prompt arrivato in ritardo; nuova attivazione e ripristino del genitore.
- SYNC con due terminali: attivazione e verifica locali; invalidazione di
  ciascun destinatario dell'input, anche via scrittura PTY diretta;
  durante lo zoom la directory del pannello nascosto resta invariata.
- Binding C-j, Dired reale, shell-command, compilazione e nuovo buffer shell.
- C-g e scomparsa del buffer durante una richiesta: nessuna azione avviata
  e nessuna modifica accidentale al buffer che riceve il focus.
- PROMPT_COMMAND scalare e array, trap DEBUG preesistente e Readline in vi;
  attivazione bloccata con PROMPT_COMMAND readonly.
- sudo reale, Dired via TRAMP/sudo e comando `id -un; pwd` eseguito come root
  in /root, attraverso una connessione separata da quella del terminale.

Il test sulla scomparsa del buffer ha inizialmente rilevato una modifica
errata della directory del buffer successivo: ora l'attesa e la pulizia
restano legate al buffer originale.

Restano superati i 91 test precedenti: ordine del tiling, processi,
scrollback, log, SYNC solo visibile, zoom, copia, Consult, albero, spostamenti
e rinumerazione.

## Bash 4.2

È stato compilato GNU Bash 4.2.0 dal sorgente ufficiale in un ambiente di
prova isolato, senza installarlo sul sistema dell'utente.

**18 test di contesto su 18 superati** con quel Bash come shell dei pannelli,
Ghostel 0.53. È esclusa dalla selezione la prova PROMPT_COMMAND array,
funzionalità che richiede Bash 5.1+. Le shell sudo e la shell figlia esplicita
usano il Bash di sistema.

Questa prova ha rilevato il limite di Bash 4.2 nella risoluzione dei binding
lunghi di `bind -x`. Il percorso compatibile usa una macro Readline verso
`C-x C-^`; i test verificano la risposta fresca, anche in modalità vi.
Il test della directory Unicode invia un letterale Bash ASCII che costruisce
i byte UTF-8: verifica il percorso comunicato senza dipendere dalle
impostazioni di input multibyte del vecchio Readline.

Per ripetere la selezione con un Bash alternativo imposta
`GHOSTEL_TEST_BASH=/percorso/bash` e usa il selettore ERT:

```elisp
(and "^mux-context-"
     (not mux-context-real-preserves-prompt-array-debug-and-vi))
```

## Limiti

Non è una verifica di RHEL7, Windows/WSL, server aziendali, SSH remoto,
CyberArk o bridge aziendali. La prova dell'utente con printf conferma
il trasporto OSC nel suo percorso, anche dopo sudo; attivazione completa,
risposta Readline e apertura Dired vanno ancora provate su quel percorso.

Non è stata ripetuta la verifica grafica del mouse: schermate README dalla
0.3.0; GIF/video dalla 0.1.9. Le verifiche precedenti sono conservate nel
[rapporto 0.3.1](https://github.com/SweatierKey/ghostel-mux/blob/c8dfe18ab41be81300f8eb9e908e8cda5186a000/VALIDATION.md).

Per il funzionamento e i limiti d'uso leggi
[Contesto del pannello e TRAMP](docs/context-awareness.md).
