# Contesto del pannello e TRAMP

**Proposta, non implementata nella 0.3.1.** Obiettivo: dal terminale,
`C-j` apre Dired sull'host, con l'utente effettivo e nella directory corrente;
i comandi Emacs compatibili con TRAMP usano lo stesso contesto.

## Cosa è possibile osservare oggi

| Situazione | Informazioni disponibili senza aggiungere integrazioni |
| --- | --- |
| Shell locale avviata da Ghostel | Con shell integration attiva e supportata, Ghostel segue la directory |
| Terminale avviato da un percorso TRAMP | Emacs conosce già il percorso di accesso e l'utente di login |
| `ssh server1` digitato nella shell locale | Il processo locale può suggerire una destinazione, ma non certifica login riuscito, directory o utente effettivo |
| `cd` nella shell remota | Aggiornabile se quella shell comunica la directory; SSH da solo non lo segnala |
| `sudo su -iu oracle` | Serve una comunicazione dalla nuova shell per conoscere il contesto effettivo |
| Ritorno con `exit`, SSH annidati | Il contesto va aggiornato dalla shell che torna attiva |

Una PTY trasporta input e output. Il protocollo SSH non aggiunge un flusso
standard di notifiche su `cd` e cambi di identità. `SSH_CONNECTION` contiene
indirizzi e porte; `SSH_TTY` identifica il terminale remoto. Queste variabili
esistono nella shell remota e non aggiornano automaticamente Emacs.
Riferimenti: [OpenSSH, ambiente](https://man.openbsd.org/ssh.1#ENVIRONMENT),
[protocollo dei canali SSH](https://www.rfc-editor.org/rfc/rfc4254#section-6).

Leggere il prompt o riconoscere i comandi digitati non è sufficiente: un
login può fallire, un alias può nascondere un comando e un programma può
stampare testo simile a un prompt. Questi indizi non devono scegliere
l'host sul quale aprire file o eseguire comandi.

## Quanto offre già Ghostel

Ghostel usa OSC 7 per aggiornare `default-directory` quando riceve host e
directory dalla shell. L'integrazione Bash fornita nella versione esaminata
emette `file://HOST/PATH`: non comunica l'utente effettivo dopo `sudo`.

`ghostel-tramp-shell-integration` abilita l'iniezione di piccoli file
temporanei per i terminali avviati tramite TRAMP. Non rende automaticamente
aware qualsiasi `ssh` digitato in una shell locale. La nuova shell avviata
da `sudo` deve a sua volta eseguire l'integrazione.
Vedi la [documentazione Ghostel](https://dakra.github.io/ghostel/) e i
sorgenti [shell integration](https://github.com/dakra/ghostel/blob/v0.53.0/lisp/ghostel-shell.el)
e [tracking della directory](https://github.com/dakra/ghostel/blob/v0.53.0/lisp/ghostel.el).

Il tracking corrente riutilizza un prefisso TRAMP già presente: per SSH
annidati non basta quindi copiare ciecamente `default-directory`. Occorre
verificare che host osservato e percorso di accesso corrispondano.

## Conoscere il contesto e potervi accedere sono due cose diverse

La notifica `oracle@server1:/u01/app` descrive dove si trova la shell, ma
non spiega come arrivarci. L'alias SSH, eventuali proxy e l'utente di login
devono essere conservati separatamente dall'utente effettivo.

Per un accesso SSH semplice seguito da sudo, un percorso TRAMP possibile è:

```text
/ssh:server1|sudo:oracle@server1:/u01/app/
```

Il primo hop usa il login SSH configurato; il secondo richiede a sudo il
cambio a `oracle`. È diverso da tentare un login SSH diretto come oracle.
Questo esempio richiede che TRAMP possa ripetere la procedura e che la
politica sudo la consenta: il solo fatto che una shell oracle sia già
aperta non basta. Una regola che autorizza unicamente una specifica
invocazione di `su` può richiedere un metodo dedicato.

Dired/TRAMP usa una propria connessione o un proprio canale di esecuzione;
non adotta genericamente la PTY interattiva di Ghostel. ControlMaster può
permettere la condivisione del trasporto, se configurato e supportato dal
percorso di accesso. Non trasferisce lo stato della shell né garantisce
che un'autenticazione sudo sulla sua TTY valga per TRAMP. Con PSMP o altri
gateway aziendali la riproducibilità del percorso va verificata sul setup
reale. Nessuna promessa di prima apertura istantanea.
Vedi [manuale TRAMP: hop, condivisione SSH e processi remoti](https://github.com/emacs-mirror/emacs/blob/master/doc/misc/tramp.texi).

## Integrazione proposta

1. Una piccola funzione nella shell invia al prompt host, utente effettivo
   e directory assoluta, come dati strutturati. Nessun comando remoto di
   polling a ogni pressione di un tasto.
2. Mux conserva il contesto per pannello e lo associa a un percorso di
   accesso conosciuto. Le notifiche non autorizzano nuovi hop o elevazioni
   di privilegi e non contengono Lisp da valutare.
3. `C-j` apre Dired soltanto con un contesto valido e un percorso risolto.
   Un login o cambio shell non ancora identificato rende il contesto
   indisponibile: niente ripiego silenzioso sulla directory locale o
   sull'ultimo host noto. Questo vale anche se la nuova shell non emette
   notifiche. Va progettato e verificato il segnale di sospensione dalla
   shell di origine, prima di consentire operazioni dal pannello.
4. TRAMP viene contattato solo quando un'operazione lo richiede, riusando
   le sue connessioni già aperte quando possibile. Le notifiche e il
   ridisegno della barra non eseguono accessi di rete.
5. Il percorso alimenta `default-directory` del buffer. Dired, compile e
   nuovi processi shell compatibili con TRAMP possono partire lì. Buffer
   shell già esistenti e `recompile` mantengono il proprio contesto: non
   vanno riciclati indiscriminatamente fra pannelli o utenti.
6. Host e utente compaiono in forma compatta, con directory completa nei
   dettagli. Un contesto non verificato è riconoscibile. L'installazione
   dell'integrazione e i comandi di contesto sono operazioni locali al
   pannello selezionato, mai trasmesse dal broadcast SYNC.

"Stesso contesto" qui significa host, utente e directory. Variabili
esportate a mano, virtualenv, funzioni, alias e altro stato della shell
non passano automaticamente a un nuovo processo TRAMP. I pacchetti Emacs
che ignorano TRAMP richiedono un adattatore; non basta una modifica globale
per rendere remoto qualsiasi comando.

## Il compromesso da scegliere prima di implementare

**Zero modifiche persistenti sui server è un obiettivo ragionevole; zero
cooperazione della shell con rilevamento completo e affidabile no.**

La prima opzione da valutare è una funzione caricata in memoria, solo
nella shell corrente, senza modificare `.bashrc`, `sshd_config` o installare
demoni. Lasciando invariati i comandi SSH e sudo, serve però un'attivazione
esplicita in ogni nuova shell remota e dopo ogni cambio di utenza. Per
renderla automatica occorre intervenire sul modo di avviare quelle shell
o sui loro profili: è un compromesso ulteriore, non implicito.

Anche un'attivazione temporanea invia istruzioni alla shell e può comparire
nella cronologia o nell'audit del terminale. Deve avvenire su richiesta,
al prompt, sul solo pannello scelto; non durante una password o un programma
interattivo. Compatibilità Bash, ritorno da sudo/SSH, gateway e autenticazione
TRAMP devono essere verificati prima di dichiarare completo lo use case.
