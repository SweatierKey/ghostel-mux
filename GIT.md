# Git e pubblicazione

Il repository locale contiene `main` e i tag `v0.1.8` e `v0.1.9`.
La prima versione conserva il pacchetto funzionante prima degli ultimi fix;
la seconda aggiunge marker SYNC e anteprima dei pannelli. La destinazione
prevista è `SweatierKey/ghostel-mux` su GitHub. La pubblicazione non è ancora
avvenuta: al momento della preparazione il collegamento disponibile non
poteva creare nuovi repository.

## Conservare la cronologia dal bundle

Il file `ghostel-mux-0.1.9.bundle` è un repository Git trasportabile.
Da una directory che lo contiene, scegli una cartella nuova per il clone:

```sh
git clone ghostel-mux-0.1.9.bundle ghostel-mux-git
cd ghostel-mux-git
git log --oneline --decorate
```

Il clone conserva file, commit e tag. Non sovrascrive la tua installazione
Emacs. Per usare questa cartella, imposta il percorso corrispondente nel
`load-path` oppure copia il file Lisp nella tua installazione e ricaricalo
come descritto nel README.

## Caricare da un Git locale autenticato

Crea prima un repository GitHub `ghostel-mux` sul tuo account. Per pubblicare
l'esatta cronologia del bundle con i comandi qui sotto, il repository remoto
deve essere vuoto. Se è già inizializzato, integra prima la sua cronologia:
non usare un push forzato.

```sh
git remote set-url origin https://github.com/SweatierKey/ghostel-mux.git
git push -u origin main
git push origin v0.1.8 v0.1.9
```

Sono necessarie le normali credenziali GitHub configurate sul tuo computer;
non inserire token o password nei file del progetto.

## Aggiornare dopo la pubblicazione

Dal clone collegato al repository remoto:

```sh
git status --short
git pull --ff-only
```

Se hai modifiche locali, conservale prima dell'aggiornamento. Dopo il pull,
elimina l'eventuale bytecode vecchio e ricarica `ghostel-mux.el` in Emacs.
`git pull --ff-only` si ferma se le storie sono divergenti.

## Recuperare una versione senza alterare il clone corrente

```sh
git worktree add --detach ../ghostel-mux-0.1.8 v0.1.8
```

Questo crea una cartella separata con la versione precedente. Un downgrade
va caricato in un nuovo processo Emacs: l'aggiornamento a caldo è verificato
in avanti, non come procedura generale di rollback.
