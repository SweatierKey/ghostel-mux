# Demo di Ghostel Mux

La GIF e il video mostrano Ghostel Mux **0.1.9** realmente eseguito in
**Emacs 29.3 in modalità terminale**, con **Ghostel 0.53.0**, Consult,
Vertico e il tema integrato Wombat. Tutte le shell sono Bash locali,
avviate senza caricare la configurazione personale; non sono connessioni SSH.

La sequenza è composta da schermate catturate dall'output ANSI di Emacs
tramite una PTY e renderizzate in PNG. Le didascalie e le pause di lettura
sono aggiunte al montaggio; il contenuto dei pannelli proviene dal programma.
Il video è senza audio. In Emacs grafico font e tema dipendono dalla tua
configurazione.

## Cosa mostra

| Azione | Tasti | Risultato visibile |
|---|---|---|
| Dividere il layout | `C-b %`, `C-b "` | Tre buffer Ghostel indipendenti |
| Sincronizzare | `C-b y` | Marker `[S]`, destinatari in barra e comando ricevuto da tre shell |
| Ingrandire un pannello | `C-b z` | `SYNC PAUSED (LOCAL)` e comando ricevuto solo dal pannello ingrandito |
| Ripristinare il layout | `C-b z` | I pannelli tornano visibili, con il proprio output conservato |
| Scegliere una finestra | `C-b w` | Anteprima Consult limitata alla sessione attiva |
| Scegliere una sessione | `C-b s` | Anteprima del layout e input terminale bloccato durante la scelta |
| Entrare in copy mode | `C-b [` | Indicatore COPY MODE e scorciatoie per copiare o uscire |

## File

- [GIF animata](demo.gif)
- [Video MP4](demo.mp4)
- [Pannelli sincronizzati](sync.png)
- [Zoom con input locale](zoom.png)
- [Anteprima della sessione](session-preview.png)

Per ripetere la dimostrazione: crea la sessione `lab`, dividi il layout in
tre pannelli e prova `printf 'SYNC: ricevuto\n'` con SYNC attiva. Ingrandisci
un pannello e prova `printf 'ZOOM: solo questo pannello\n'`; tornando al
layout completo, il secondo messaggio compare soltanto lì. Crea poi una
seconda finestra con `C-b c` e una sessione `sandbox` con `C-b S` per provare
i selettori. Usa shell locali per questa prova.
