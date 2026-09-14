# Verifica della versione 0.3.1

**91 test ERT superati su ciascuna delle due versioni Ghostel, senza errori
inattesi né test saltati.** Risultati in [test-results.txt](test-results.txt).

## Ambiente

- Emacs 29.3, Linux x86_64, distribuzione portabile nel workspace.
- Ghostel v0.40.0 e v0.53.0, ciascuno con il proprio modulo nativo Linux.
- Bash locali con PTY reali; shell integration disattivata per non caricare
  profili personali. Consult e which-key disponibili nel load-path.
- Compilazione Lisp con i warning trattati come errori, Ghostel 0.53.0:
  nessun warning di compilazione.

In questo runtime portabile i test sono stati eseguiti con
`--eval '(setq comp-enable-subr-trampolines nil)'`: la compilazione nativa
dei trampoline per le funzioni ridefinite dai test non riesce a caricare
l'ambiente del sottoprocesso. Senza questa impostazione quattro test del
completamento falliscono con `native-compiler-error`. È un adattamento del
comando di test, non una modifica alla configurazione richiesta agli utenti.
Il warning iniziale sul percorso Lisp di sistema mancante appartiene allo
stesso runtime; il load-path effettivo punta ai file del bundle.

## Regressioni della 0.3.1

- Otto pannelli dopo le creazioni automatiche: ordine crescente nelle
  posizioni visive, da sinistra a destra per riga e dall'alto al basso.
- Pannello sostituito da scratch, zoom e poi vera keyboard macro C-b M-5:
  tutti i pannelli tornano nell'ordine previsto, conservando la selezione.
- Riordino nell'albero, trasferimento da un'altra sessione e chiusura:
  ordine visivo coerente con la lista dei pannelli e numeri contigui.
- Passaggi fra layout orizzontale, verticale e tiled con cinque pannelli:
  il terminale selezionato resta lo stesso e l'ordine è rispettato.

Ripristinando soltanto la vecchia funzione di tiling, il test degli otto
pannelli fallisce sul confronto delle posizioni visive. La regressione
rileva quindi il difetto precedente, non soltanto la presenza dei buffer.

Restano superati gli 88 test precedenti, inclusi SYNC limitata ai pannelli
visibili, zoom, input e copia, preview Consult, albero, spostamenti,
rinumerazione, processi, scrollback e log.

## Limiti e verifiche precedenti

La 0.3.1 è verificata in batch con finestre Emacs e terminali reali. Non è
stata ripetuta la verifica grafica del mouse: le schermate nel README
provengono dalla 0.3.0 e precedono il fix dell'ordine dei pannelli.
Le prove su Emacs 30.1, drag grafico, installazione use-package e reload
della 0.3.0 sono descritte nel
[rapporto precedente](https://github.com/SweatierKey/ghostel-mux/blob/a735d2d403ffe7f860efd721490c317c4fa7dd29/VALIDATION.md).

Nessuna di queste prove verifica server aziendali, Windows/WSL, CyberArk,
SSH remoto o cambi di utenza. Il documento
[Contesto del pannello e TRAMP](docs/context-awareness.md) è una proposta
basata sul codice e sui protocolli: l'integrazione non è implementata.
