# Verifica della versione 0.3.0

**88 test ERT superati su ciascuna delle due versioni Ghostel, senza errori
inattesi né test saltati.** Risultati in [test-results.txt](test-results.txt).

## Ambiente di questa verifica

- Emacs 30.1, Debian Linux x86_64.
- Ghostel v0.40.0 e v0.53.0, ognuno con il modulo nativo ufficiale Linux.
- Shell Bash locali con PTY reali; shell integration disattivata per non
  caricare profili personali.
- Consult disponibile nel load-path; which-key integrato in Emacs 30.1.
- Compilazione Lisp con i warning trattati come errori, usando Ghostel 0.53.0.
- Emacs grafico GTK in un display Xvfb, tema Wombat, per le prove visive e mouse.

## Regressioni aggiunte nella 0.3.0

- Tutte le destinazioni del selettore restano risolvibili dopo l'ordinamento:
  il bug era l'uso di nreverse senza riassegnarne il risultato.
- Keyboard macro C-b m → altra sessione / [new window]: stessa PTY e log,
  nuova finestra nella destinazione, contenitori vuoti rimossi.
- Creazione senza prompt dalla prima apertura, da C-b S e da C-b : new-session;
  nomi occupati saltati e rinomina successiva.
- Riordino sopra/sotto e trasferimenti fra finestre/sessioni; nomi aggiornati
  e contigui, processo conservato, SYNC disattivata nelle finestre interessate.
- Fallimento del layout prima della mutazione; destinazioni non valide e
  drop fuori dalle righe non cambiano i proprietari.
- Il drag conserva l'oggetto premuto anche se il testo dell'albero si aggiorna.
- Tre sessioni, sei terminali: tutti restano nella buffer-list e nel completamento
  generale Emacs; il selettore globale raggiunge una sessione non selezionata.
- Anteprima dell'albero in un buffer distinto, senza modalità Ghostel né
  appartenenza Mux, di sola lettura; ritorno al layout e stato SYNC conservati.
- Morte del terminale in anteprima: selezione della riga superstite e
  aggiornamento della preview; chiusura dell'albero libera i buffer temporanei.
- Navigazione, rinomina e riordino dell'albero attraverso keyboard macro.
- Otto pannelli: niente header duplicato, barre entro la larghezza disponibile,
  percorso W.P e numero dei destinatari presenti; COPY e zoom restano visibili.

Restano attivi i test precedenti su SYNC visibile, zoom, viste miste,
incolla, codifica delle frecce per terminale, log, scrollback, uscita dei
processi e annullamento delle anteprime Consult.

## Prove grafiche

Aperti otto terminali reali in Emacs GTK: una sola barra per pannello,
[S:8] su tutti i destinatari, selezione e accenti della sessione.
Aperto l'albero con anteprima laterale e verificata l'uscita al layout.

Usati eventi mouse reali inviati al display X: trascinamento del pannello 8
sotto e poi sopra il pannello 1, con l'ordine atteso e SYNC disattivata.
Trascinato poi un pannello sulla sessione tools: il pannello è passato a
una nuova finestra tools:2, mentre la sessione lab è rimasta con sette pannelli.

Le schermate [otto pannelli](docs/media/eight-panes.png) e
[albero](docs/media/tree.png) provengono da queste prove. Non sono mockup.

## Aggiornamento e installazione

Caricato il sorgente 0.3.0 sopra la 0.2.0 con due PTY vive e l'albero già aperto:
modifica delle barre, attivazione della preview, ritorno al layout e
trasferimento verso una nuova finestra verificati, con gli stessi processi.

Valutato il blocco use-package esatto di example-init.el in un Emacs pulito,
reindirizzando soltanto il percorso di destinazione a una directory temporanea
e l'URL di clone al checkout Git locale. Il clone è stato eseguito realmente.
Una seconda valutazione non riclona. Iniettato un errore di Git: nessuna
destinazione parziale o directory di staging residua; il tentativo successivo
riesce. Il warning use-package nell'output corrisponde al guasto simulato.

## Limiti

Queste prove non usano Windows/WSL, le shell remote dell'utente o CyberArk.
Il mouse è verificato in un frame grafico; le posizioni sintetiche ERT
coprono anche il fallback del terminale. Non è una prova manuale di drag
con più frame grafici contemporanei.

L'anteprima dell'albero riproduce solo il testo renderizzato, non le immagini
del terminale né l'intero scrollback nativo. Il comportamento delle sessioni
in Emacs resta in memoria: la chiusura di Emacs termina i suoi processi.
