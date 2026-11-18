# Esecuzione guidata — design

**Data:** 2026-11-18
**Contesto:** fork personale di Superpowers 7.0.2 (non è un contributo upstream).

## Intento e perché

Superpowers funziona bene, e il brainstorming è la parte migliore. Il problema
è l'esecuzione: una volta approvato il piano, l'agente implementa tutti i task
di fila e fa i commit da solo. Il proprietario del progetto conosce la decisione
di design grande, presa insieme a lui, ma non sa cosa dice il codice né quali
piccole scelte sono state fatte lungo la strada. Per lui questi progetti sono
suoi e servono anche a imparare, quindi vuole capire cosa c'è dentro prima che
venga committato.

Esempio reale: in un progetto su un modello di AI, il codice è stato scritto
tutto di fila e non c'è stato il tempo di capirlo.

## Obiettivi

- Un nuovo modo di eseguire un piano, l'**esecuzione guidata**: un task alla
  volta, poi l'agente si ferma.
- Alla fine di ogni task, un **report** breve: cosa è stato fatto, dove sta il
  codice, cosa fanno i pezzi importanti, quali micro-scelte di design sono state
  prese e perché. Il report serve per orientarsi nel codice; dopo averlo usato
  lo si butta via.
- L'agente **non fa mai il commit** in esecuzione guidata. Dice in modo
  esplicito quando è il momento di farlo, spiega perché e propone il messaggio
  di commit, con un riassunto di cosa ci va dentro.
- **Task più piccoli**: ogni task è un commit che una persona legge e capisce in
  circa 10 minuti, così la storia dei commit rispecchia i passi del lavoro.
- Due comandi per andare avanti:
  - **"avvia il prossimo"**: esegue un solo task, poi si ferma di nuovo;
  - **"procedi"**: esegue tutti i task rimanenti come fa oggi Superpowers,
    senza fermarsi e con i commit automatici.

## Non-obiettivi

- Non si tocca il brainstorming.
- Non si modificano `subagent-driven-development` ed `executing-plans`. Restano
  identici e sono quelli che "procedi" usa.
- Integrazione con Notion / to-do: è un progetto successivo e separato. Qui il
  report non va progettato in funzione di Notion.
- Rinominare il plugin, il marketplace locale e la pulizia del supporto ad altri
  harness: progetto separato (necessario per installare il fork accanto
  all'originale, ma indipendente da questo).

## Anti-obiettivi (sarebbe un fallimento anche se funzionasse)

- Report lunghi che parafrasano il diff riga per riga: devono far risparmiare
  tempo nella lettura del codice, non sostituirla.
- Un agente che fa un commit in esecuzione guidata, anche "solo questa volta".
- Un agente che, in esecuzione guidata, fa partire il task successivo senza che
  il proprietario lo abbia chiesto.
- Micro-scelte prese e non riportate.

## Vincoli

- Le skill di esecuzione esistenti condividono workspace e registro
  (`<repo>/.superpowers/sdd/<piano>/progress.md`, ignorato da git), creati da
  `subagent-driven-development/scripts/sdd-workspace`. La riga di completamento
  di un task oggi è `Task <N>: complete (commits <base7>..<head7>, ...)` e la
  ripresa dopo una compattazione si basa su quelle righe più `git log`.
  L'esecuzione guidata deve scrivere nello stesso registro, in un formato che
  `executing-plans` e `subagent-driven-development` capiscono quando "procedi"
  passa loro il resto del piano.
- I piani scritti da `writing-plans` contengono passi letterali
  `git commit -m "..."`. In esecuzione guidata vanno interpretati come "segnala
  il commit", non eseguiti.
- Le skill di Superpowers sono in inglese; la nuova skill resta in inglese per
  coerenza. I report e i messaggi al proprietario sono nella lingua della
  conversazione (qui italiano).
- Windows + Git Bash è l'ambiente del proprietario: ogni hook nuovo deve passare
  da `hooks/run-hook.cmd` come quello esistente.

## Approcci considerati

- **A. Modificare `subagent-driven-development` ed `executing-plans`** (pausa,
  niente commit, report). Scartato: tocca due skill grandi e tarate, piene di
  "non fermarti mai"; "procedi" dovrebbe ripristinare un comportamento appena
  tolto; ogni aggiornamento upstream va riconciliato a mano.
- **B. Nuova skill `guided-execution` accanto alle altre** — **scelto dal
  proprietario.** Il Superpowers attuale resta intatto, e "procedi" lo usa
  davvero invece di imitarlo. Costo: una skill in più da mantenere.
- **C. Solo hook che bloccano `git commit`.** Scartato come approccio principale:
  si scontra con le skill che dicono all'agente di non fermarsi. Tenuto come
  rete di sicurezza dentro B (vedi sotto).

## Come funziona (deciso)

### 1. `writing-plans`: task più piccoli e terza modalità

- **Dimensione dei task.** La sezione "Task Right-Sizing" oggi dice di accorpare
  setup, configurazione, scaffolding e documentazione nel task che li usa. La
  nuova regola: un task è un commit che una persona legge e capisce in circa 10
  minuti, con una sola idea dentro e un deliverable testabile. Vale per tutte le
  modalità (in subagent-driven significa più revisioni per task: costo
  accettato).
- **Handoff.** Alla fine del piano le modalità proposte diventano tre:
  guidata, subagent-driven, native. La **guidata è la raccomandazione
  predefinita**.

### 2. Nuova skill `guided-execution`

Esegue il piano in linea, nella sessione principale, un task alla volta.

Ciclo per ogni task:

1. Prende il task (stesso brief e stesso registro di `executing-plans`).
2. Lo implementa seguendo TDD, come `executing-plans`.
3. Quando la decisione non è già nel piano, decide da solo (come le "Ruling"
   di oggi) e la annota.
4. **Non esegue i passi di commit del piano.**
5. Scrive il report del task (vedi formato sotto).
6. Mostra in chat il messaggio di fine task e **si ferma**.

Il messaggio di fine task in chat contiene:

- quale task è finito (N di totale) e il percorso del report;
- il **segnale di commit**, esplicito: "È il momento di fare il commit" (o "Non
  ancora", con il motivo, se il task non è arrivato a uno stato coerente),
  perché è il momento, cosa entra nel commit (file e senso della modifica) e il
  messaggio di commit proposto;
- i comandi disponibili: "avvia il prossimo" · "procedi".

Comandi:

- **"avvia il prossimo"**: un altro ciclo, poi si ferma di nuovo.
- **"procedi"**: passa i task rimanenti a `subagent-driven-development` o
  `executing-plans` (quella che il piano raccomanda) senza modificarle; da lì in
  avanti i commit sono automatici come oggi.
- Qualunque altra cosa (domande sul codice, "spiegami questa funzione", "cambia
  questa scelta") è una conversazione normale; l'agente resta in pausa finché
  non riceve uno dei due comandi.

### 3. Formato del report

Un file per task, nella cartella del piano ignorata da git:
`<repo>/.superpowers/sdd/<piano>/reports/task-NN.md`. Essendo ignorato da git,
non finisce mai in un commit e si può cancellare senza conseguenze.

Contenuto, breve:

- **Cosa è stato fatto**, in due o tre frasi.
- **Dove guardare**: i file toccati, con righe aggiunte/tolte e una riga su
  cosa contiene ciascuno, in un ordine di lettura consigliato.
- **Cosa fa il codice**: i punti chiave, spiegati a parole con riferimenti a
  file:riga. Non una parafrasi riga per riga.
- **Micro-scelte**: ogni decisione presa che il piano non diceva, con il
  perché e cosa costa se è sbagliata.
- **Test**: quali test esistono per questo task e il loro esito.
- **Commit proposto**: messaggio e motivo.

### 4. Hook di sicurezza sul commit

Un hook `PreToolUse` sul tool Bash blocca i comandi `git commit` dell'agente
mentre l'esecuzione guidata è attiva, con un messaggio che gli ricorda di
segnalare il commit invece di farlo. La skill accende la modalità creando un
file marcatore nella cartella del piano all'avvio e lo rimuove quando riceve
"procedi" o quando il piano finisce. Senza marcatore l'hook non fa nulla.

### 5. Decisioni prese dopo la revisione

Le voci segnate "deciso dal proprietario" vengono da lui; tutte le altre sono
scelte di Claude, da verificare.

- **Task precedenti non committati** (deciso dal proprietario). Su "avvia il
  prossimo" con modifiche non committate, l'agente lo fa notare in una riga
  ("il task 3 non è ancora committato") e va avanti: a volte il proprietario
  sceglie di fare più passi, capirli e fare un solo commit alla fine. Il report
  del nuovo task descrive solo le modifiche di quel task: la base del task è
  un'istantanea dell'albero di lavoro al suo inizio (per esempio
  `git stash create`, che non tocca nulla), non `HEAD`. Il commit proposto
  invece copre tutti i task ancora non committati, ed elenca quali.
- **Mai commit dall'agente** (deciso dal proprietario). Neanche se il
  proprietario lo chiede in modalità guidata.
- **Executor di "procedi".** L'intestazione del piano indica la modalità
  guidata più un esecutore di riserva (subagent-driven o native, quello che
  `writing-plans` raccomanda oggi). Su "procedi" l'agente dice in una riga quale
  usa e parte, senza chiedere.
- **Modifiche non committate al momento di "procedi".** Con "procedi" si passa
  ai commit automatici, quindi le modifiche del task guidato rimaste aperte
  diventano il primo commit automatico, con il messaggio già proposto nel
  report.
- **Durata della modalità guidata.** Vale per il piano, non per la sessione. Se
  il proprietario torna giorni dopo, il piano riprende in modalità guidata. Il
  marcatore indica il piano e il suo worktree/ramo; l'hook blocca i commit solo
  lì, non nel resto del repository. Se una sessione nuova prova a riprendere il
  piano con `executing-plans`, il messaggio dell'hook le dice che il piano è in
  modalità guidata e di usare `guided-execution`.
- **Fine piano.** La revisione finale gira come oggi. Le correzioni che produce
  vengono trattate come un ultimo task guidato: un report, un segnale di commit,
  una pausa. `finishing-a-development-branch` (merge/PR) parte solo su comando
  esplicito del proprietario. Il marcatore viene rimosso a quel punto.
- **Comandi.** Sono accettati gli equivalenti chiari ("next", "un altro" =
  avvia il prossimo; "vai fino in fondo", "tutti" = procedi). Davanti a un
  comando ambiguo ("continua", "vai") l'agente chiede quale dei due intende.
- **Hook.** Copre sia il tool Bash sia il tool PowerShell. I commit fatti dal
  proprietario (nel suo terminale o con `!` in Claude Code) non passano dai
  tool dell'agente e non vengono bloccati.
- **Verifica.** Test automatici per l'hook (attivo/non attivo, Bash/PowerShell,
  fuori dal worktree del piano) più una prova manuale su un piccolo progetto
  reale con un piano di 3–4 task. Niente harness di eval.

## Lasciato al builder

- Il formato esatto della riga di completamento nel registro per i task
  guidati, purché `executing-plans`/`subagent-driven-development` la
  riconoscano come completata quando ricevono il piano con "procedi".
- Come trovare il marcatore dall'hook (percorso, nome del file).
- Il testo esatto della skill, nel rispetto dello stile delle altre skill di
  Superpowers.
- Quali parti di `executing-plans` (setup, worktree, completion contract,
  revisione finale) la skill guidata richiama e quali ricopia.
