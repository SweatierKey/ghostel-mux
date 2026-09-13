# Installazione e aggiornamenti con Git

Repository: [SweatierKey/ghostel-mux](https://github.com/SweatierKey/ghostel-mux).
Il ramo di lavoro è `main`; contiene la versione 0.1.9 e le istruzioni
aggiornate. La cronologia conserva separatamente la base e gli ultimi fix:

| Versione | Commit |
|---|---|
| 0.1.8 | [406091d](https://github.com/SweatierKey/ghostel-mux/commit/406091d280f5ace527ad769bbc8fafa8331904ad) |
| 0.1.9 | [f89ab2e](https://github.com/SweatierKey/ghostel-mux/commit/f89ab2e513d745ed71ce4276f04310ad93e7f410) |

## Passare dall'installazione ZIP a Git

Clona in una cartella nuova, senza sovrascrivere quella usata finora:

```sh
git clone https://github.com/SweatierKey/ghostel-mux.git ~/src/ghostel-mux
```

Nella configurazione Emacs sostituisci l'aggiunta del vecchio percorso Mux
al `load-path` con:

```elisp
(add-to-list 'load-path (expand-file-name "~/src/ghostel-mux"))
```

I tuoi autoload, il binding `C-c m` e le opzioni Mux possono restare come
sono. Valuta la nuova forma e carica il file dal clone:

```text
M-x load-file RET ~/src/ghostel-mux/ghostel-mux.el RET
M-x ghostel-mux-refresh RET
```

Non occorre chiudere i terminali. Conserva la vecchia cartella finché hai
verificato che Emacs carichi il nuovo percorso; `M-x find-library RET
ghostel-mux RET` mostra il file trovato nel `load-path`.

## Aggiornamenti successivi

Dal clone:

```sh
git -C ~/src/ghostel-mux status --short
git -C ~/src/ghostel-mux pull --ff-only
```

Se hai modifiche locali, conservale prima di aggiornare. Dopo il pull,
elimina l'eventuale vecchio `ghostel-mux.elc` dal clone e ricarica il sorgente
come sopra. Il pacchetto distribuisce il file Lisp, senza bytecode.

## Recuperare una versione precedente

Crea una cartella separata per la versione 0.1.8:

```sh
git -C ~/src/ghostel-mux worktree add --detach ../ghostel-mux-0.1.8 406091d280f5ace527ad769bbc8fafa8331904ad
```

Questo conserva il clone corrente. Prova un downgrade in un nuovo processo
Emacs: il caricamento a caldo è verificato in avanti, non come procedura
generale di rollback.

## Bundle consegnato prima della pubblicazione

Il precedente `ghostel-mux-0.1.9.bundle` conserva la cronologia locale e i
tag locali `v0.1.8` e `v0.1.9`. I commit importati su GitHub hanno gli stessi
file delle due versioni, ma identificativi diversi. Per seguire gli
aggiornamenti GitHub usa un clone nuovo come sopra; il bundle resta una
copia autonoma. I tag del bundle non sono stati pubblicati su GitHub.
