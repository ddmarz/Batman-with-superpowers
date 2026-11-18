# Esecuzione guidata — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **Your human partner makes every commit: never run `git commit`; at each "Segnala il commit" step, tell them it is time to commit, why, what goes in, and the suggested message.**

**Goal:** Aggiungere a Superpowers una modalità di esecuzione guidata: un task alla volta, un report per task, nessun commit dell'agente, comandi "avvia il prossimo" / "procedi".

**Architecture:** Una nuova skill `guided-execution` con quattro script bash propri. Condivide workspace e registro con `executing-plans` e `subagent-driven-development`, che restano intatte. Un hook `PreToolUse` blocca i `git commit` dell'agente quando nella cartella del piano c'è il marcatore `guided`. `writing-plans` produce task più piccoli e propone la modalità guidata come predefinita.

**Tech Stack:** bash (Git Bash su Windows), git. Nessuna dipendenza esterna (niente jq).

**Spec:** `docs/superpowers/specs/2026-11-18-esecuzione-guidata-design.md`

## Global Constraints

- L'esecutore non esegue mai `git commit`. Ogni task finisce con "Segnala il commit".
- Prerequisito: il repo deve essere un repository git con almeno un commit. Lo crea il proprietario (`git init` e un primo commit) prima del Task 1. Gli script del registro (`sdd-repo --with-commit`) si rifiutano di partire senza.
- Nessuna dipendenza oltre bash e git; niente jq, python, node negli script nuovi.
- Gli script nuovi seguono lo stile di `skills/executing-plans/scripts/`: `set -euo pipefail`, gli script fratelli invocati via `"${BASH:-bash}"`, i percorsi stampati in forma `C:/...` con `cygpath -m` quando disponibile (come `sdd-workspace`).
- L'hook deve uscire senza fare fork (niente `$(...)`, pipe o comandi esterni) quando l'input non contiene la stringa `commit`, perché gira su ogni comando Bash/PowerShell.
- L'hook passa da `hooks/run-hook.cmd` e la sua voce in `hooks/hooks.json` ricalca la forma della voce `SessionStart` (`command`, `powershell`, `shell: bash`, `async: false`).
- Il testo della skill è in inglese. Report e messaggi al partner sono nella lingua della conversazione.
- `skills/guided-execution/SKILL.md` deve restare sotto i 20000 byte (`tests/skill-size`). Nessun file `test-*.md` dentro `skills/` (`tests/skill-layout`).
- Non modificare `skills/executing-plans/`, `skills/subagent-driven-development/` né `skills/brainstorming/`.
- Riga di completamento nel registro per i task guidati: inizia con `Task <N>: complete`, così la ripresa di `executing-plans`/`subagent-driven-development` riconosce il task come fatto.

## Review Focus

1. `cwd` di Windows nell'input JSON dell'hook (`"C:\\Users\\..."`, con backslash raddoppiati): il marcatore va trovato lo stesso. → test nel Task 1.
2. Forme di commit diverse da `git commit -m`: `git -C dir commit`, `git -c k=v commit`, `git add . && git commit -m x`. → bloccate, test nel Task 1.
3. Comandi che contengono "commit" ma non sono un commit: `git log --grep commit`, `echo commit`. → permessi, test nel Task 1.
4. File nuovi, non tracciati, creati dal task: devono comparire nel diff del task. → test nel Task 2 e nel Task 4.
5. Le modifiche già in stage del proprietario non vanno toccate dalle istantanee. → test nel Task 2.

---

### Task 1: Hook che blocca i commit dell'agente

**Files:**
- Create: `hooks/guided-commit-guard`
- Modify: `hooks/hooks.json` (aggiungere `PreToolUse`)
- Test: `tests/hooks/test-guided-commit-guard.sh`

**Interfaces:**
- Produces: un marcatore `<repo>/.superpowers/sdd/<slug-piano>/guided` (file il cui contenuto è il percorso del piano) attiva il blocco. Chiunque lo crei o lo tolga (Task 3, Task 5) usa questo percorso.

- [ ] **Step 1: Scrivi i test che falliscono** in `tests/hooks/test-guided-commit-guard.sh`, nello stile di `tests/hooks/test-session-start.sh` (pass/fail, conteggio `FAILURES`, uscita 1 se ci sono fallimenti). Una helper `run_guard <json>` passa il JSON su stdin a `hooks/guided-commit-guard` e cattura stdout ed exit code. Per i casi "con marcatore" crea un repo temporaneo con `.superpowers/sdd/plan/guided`. Casi:

| Caso | `tool_name` | `command` | `cwd` | Atteso |
|---|---|---|---|---|
| nessun marcatore | Bash | `git commit -m x` | repo senza marcatore | exit 0, stdout vuoto |
| commit semplice | Bash | `git commit -m x` | repo con marcatore | stdout contiene `"permissionDecision":"deny"` |
| PowerShell | PowerShell | `git commit -m x` | repo con marcatore | deny |
| `-C` | Bash | `git -C sub commit -m x` | repo con marcatore | deny |
| `-c` | Bash | `git -c user.name=a commit` | repo con marcatore | deny |
| concatenato | Bash | `git add . && git commit -m x` | repo con marcatore | deny |
| sottocartella | Bash | `git commit -m x` | `<repo>/src` | deny |
| cwd stile Windows | Bash | `git commit -m x` | percorso del repo in forma `C:\\...` (con `cygpath -w`, poi backslash raddoppiati come in JSON); salta il caso se `cygpath` non c'è | deny |
| log | Bash | `git log --grep commit` | repo con marcatore | exit 0, stdout vuoto |
| echo | Bash | `echo commit` | repo con marcatore | exit 0, stdout vuoto |
| status | Bash | `git status` | repo con marcatore | exit 0, stdout vuoto |
| fuori dal repo | Bash | `git commit -m x` | cartella temporanea senza `.superpowers` | exit 0, stdout vuoto |
| motivo | Bash | `git commit -m x` | repo con marcatore | `permissionDecisionReason` contiene `guided-execution` e il percorso del piano letto dal marcatore |

Più un caso sulla configurazione: `hooks/hooks.json` contiene `"PreToolUse"`, il matcher `Bash|PowerShell` e `guided-commit-guard`.

- [ ] **Step 2: Esegui i test e verifica che falliscono**

Run: `bash tests/hooks/test-guided-commit-guard.sh`
Expected: FAIL (lo script dell'hook non esiste)

- [ ] **Step 3: Implementa `hooks/guided-commit-guard`** (bash, senza estensione come `session-start`)

Algoritmo:
1. Legge tutto stdin con il builtin `read -r -d ''`. Se l'input non contiene `commit`, `exit 0` subito.
2. Estrae i valori stringa di `command` e `cwd` con una regex bash (`"command"[[:space:]]*:[[:space:]]*"(([^"\\]|\\.)*)"`) e li de-escapa: `\"` → `"`, `\\` → `\`, `\n` → a capo. In `cwd` converte `\` in `/`.
3. Spezza il comando in segmenti su `&&`, `||`, `;`, `|` e a capo. In ogni segmento cerca il token `git` (anche `*/git` o `git.exe`), salta le opzioni globali (`-C <arg>`, `-c <arg>`, ogni altro token che inizia con `-`) e, se il primo token non-opzione è `commit`, il comando è un commit. Se non è un commit: `exit 0`.
4. Risale da `cwd` verso la radice cercando `.superpowers/sdd/*/guided` (glob bash, niente `find`). Se non lo trova: `exit 0`.
5. Legge il percorso del piano dal marcatore con `read` e stampa su stdout:
   `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<testo>"}}`
   con il testo (escapato per JSON come in `session-start`):
   `Guided execution is active for plan <plan> in this working tree: your human partner makes every commit. Do not commit and do not retry. Signal the commit instead (why now, what goes in, suggested message) and stop. If you are resuming this plan with executing-plans or subagent-driven-development, switch to superpowers:guided-execution. Guided mode ends when your partner says "procedi".`

Poi aggiungi in `hooks/hooks.json`, accanto a `SessionStart`, una voce `PreToolUse` con `"matcher": "Bash|PowerShell"` e comando `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" guided-commit-guard`, nella stessa forma della voce esistente (incluse `powershell`, `shell`, `async`).

- [ ] **Step 4: Esegui i test e verifica che passano**

Run: `bash tests/hooks/test-guided-commit-guard.sh && bash tests/hooks/test-session-start.sh`
Expected: tutti PASS

- [ ] **Step 5: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(hooks): blocca i git commit dell'agente in esecuzione guidata`

---

### Task 2: Istantanea dell'albero di lavoro

**Files:**
- Create: `skills/guided-execution/scripts/guided-snapshot`
- Test: `tests/claude-code/test-guided-execution-scripts.sh`

**Interfaces:**
- Produces: `guided-snapshot [-C DIR]` → stampa su stdout lo SHA (40 caratteri esadecimali) di un oggetto *tree* git con tutto l'albero di lavoro: file tracciati modificati e file non tracciati, esclusi quelli ignorati. Non modifica l'indice né l'albero di lavoro.

- [ ] **Step 1: Scrivi i test che falliscono** in un nuovo file `tests/claude-code/test-guided-execution-scripts.sh`, con la stessa impalcatura di `tests/claude-code/test-executing-plans-scripts.sh` (repo temporaneo con `git init`, `git_id`, fixture `plan.md` con `## Task 1:` e `## Task 2:`, commit della fixture). Casi:
  - albero pulito: lo SHA stampato è uguale a `git rev-parse HEAD^{tree}`;
  - dopo aver creato un file non tracciato `new.txt`: lo SHA cambia, e `git ls-tree -r <sha>` contiene `new.txt`;
  - un file ignorato (`.gitignore` con `ignored.txt`) non compare in `git ls-tree -r <sha>`;
  - indice intatto: con un file in stage (`git add staged.txt`) prima dell'istantanea, `git diff --cached --name-only` e `git status --porcelain` sono identici prima e dopo;
  - `-C <repo>` lanciato da fuori il repo dà lo stesso SHA.

- [ ] **Step 2: Esegui e verifica che falliscono**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: FAIL (lo script non esiste)

- [ ] **Step 3: Implementa `guided-snapshot`.** Approccio: risolve il repo con `../../subagent-driven-development/scripts/sdd-repo --with-commit`; copia l'indice reale in un file temporaneo (`git rev-parse --git-path index`, `mktemp`), poi `GIT_INDEX_FILE=<tmp> git add -A` e `GIT_INDEX_FILE=<tmp> git write-tree`; rimuove il file temporaneo con un `trap`. L'indice reale non viene mai scritto.

- [ ] **Step 4: Esegui e verifica che passano**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: tutti PASS

- [ ] **Step 5: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): istantanea dell'albero di lavoro senza toccare l'indice`

---

### Task 3: Inizio di un task guidato

**Files:**
- Create: `skills/guided-execution/scripts/guided-task-start`
- Test: `tests/claude-code/test-guided-execution-scripts.sh` (aggiungere casi)

**Interfaces:**
- Consumes: `guided-snapshot` (Task 2); `subagent-driven-development/scripts/task-brief` e `sdd-workspace`; il formato del marcatore definito nel Task 1.
- Produces: `guided-task-start PLAN_FILE N` → stampa tre righe:
  - `brief: <percorso del brief>`
  - `base: <sha tree di guided-snapshot>`
  - `uncommitted: yes|no`
  
  e garantisce che esistano `<workspace>/guided` (contenuto: `PLAN_FILE` così come è stato passato) e la cartella `<workspace>/reports/`. Exit 2 se gli argomenti non sono due.

- [ ] **Step 1: Scrivi i test che falliscono.** Casi:
  - senza numero di task → exit 2;
  - albero pulito: l'output contiene `brief: $repo/.superpowers/sdd/plan/task-1-brief.md`, `base: <sha di 40 caratteri>` e `uncommitted: no`;
  - dopo la chiamata esistono `$repo/.superpowers/sdd/plan/guided` (contenuto `plan.md`) e `$repo/.superpowers/sdd/plan/reports/`;
  - con un file modificato e non committato: `uncommitted: yes`;
  - la cartella `.superpowers/` non rende `uncommitted: yes` (è ignorata dal suo `.gitignore`).

- [ ] **Step 2: Esegui e verifica che falliscono**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: FAIL sui nuovi casi

- [ ] **Step 3: Implementa `guided-task-start PLAN_FILE N`**, sul modello di `skills/executing-plans/scripts/task-start`. Brief da `task-brief`, workspace da `sdd-workspace`, `base` da `guided-snapshot`, `uncommitted` da `git status --porcelain` non vuoto. Il marcatore lo scrive solo se manca.

- [ ] **Step 4: Esegui e verifica che passano**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: tutti PASS

- [ ] **Step 5: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): inizio task con brief, istantanea e marcatore`

---

### Task 4: Fine di un task guidato

**Files:**
- Create: `skills/guided-execution/scripts/guided-task-done`
- Test: `tests/claude-code/test-guided-execution-scripts.sh` (aggiungere casi)

**Interfaces:**
- Consumes: `guided-snapshot` (Task 2); il `base` stampato da `guided-task-start` (Task 3).
- Produces: `guided-task-done PLAN_FILE N BASE -- TEST_COMMAND [ARGS...]`:
  - esegue i test e salva l'output in `<workspace>/task-N-tests.log`, stampandone le ultime 5 righe;
  - se i test falliscono: niente nel registro, exit con lo stesso codice dei test;
  - se passano: fa una nuova istantanea, salva `git diff BASE <nuova>` in `<workspace>/task-N.diff`, stampa `git diff --stat BASE <nuova>`, aggiunge al registro `Task <N>: complete (guided, uncommitted, trees <base7>..<new7>, tests: <cmd> → <ultima riga non vuota>)` e stampa le righe `diff: <percorso>` e `report: <workspace>/reports/task-NN.md` (N con due cifre);
  - exit 2 se gli argomenti sono sbagliati o se BASE non è un oggetto tree (`git cat-file -t`).

- [ ] **Step 1: Scrivi i test che falliscono.** Casi:
  - argomenti sbagliati (manca `--`) → exit 2;
  - BASE che non è un tree (es. lo SHA di un commit) → exit 2;
  - test che fallisce (`false`) → exit diverso da 0 e nessuna riga `Task 1:` in `progress.md`;
  - test che passa (`true`) dopo aver creato il file non tracciato `added.txt`: il registro contiene una riga che inizia con `Task 1: complete (guided, uncommitted, trees `; `task-1.diff` contiene `added.txt`; l'output contiene `added.txt` (nello stat), `diff: ` e `report: $repo/.superpowers/sdd/plan/reports/task-01.md`;
  - due task di fila senza commit in mezzo: il `task-2.diff` contiene solo i file del task 2.

- [ ] **Step 2: Esegui e verifica che falliscono**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: FAIL sui nuovi casi

- [ ] **Step 3: Implementa `guided-task-done`**, sul modello di `skills/executing-plans/scripts/task-done` (stessa resa del comando per la riga del registro, stessa creazione del registro se manca).

- [ ] **Step 4: Esegui e verifica che passano**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: tutti PASS

- [ ] **Step 5: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): fine task con diff del solo task e riga di registro`

---

### Task 5: Uscita dalla modalità guidata

**Files:**
- Create: `skills/guided-execution/scripts/guided-off`
- Test: `tests/claude-code/test-guided-execution-scripts.sh` (aggiungere casi)

**Interfaces:**
- Produces: `guided-off PLAN_FILE` → rimuove `<workspace>/guided` e stampa `guided: off`. Se il marcatore non c'è, stampa lo stesso `guided: off` ed esce con 0.

- [ ] **Step 1: Scrivi i test che falliscono.** Casi:
  - dopo `guided-task-start`, `guided-off plan.md` rimuove il marcatore e stampa `guided: off`;
  - una seconda chiamata esce con 0;
  - integrazione con il Task 1: con il marcatore presente l'hook nega `git commit -m x` con `cwd=$repo`; dopo `guided-off` lo permette.

- [ ] **Step 2: Esegui e verifica che falliscono**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: FAIL sui nuovi casi

- [ ] **Step 3: Implementa `guided-off`** (workspace da `sdd-workspace`, `rm -f`).

- [ ] **Step 4: Esegui e verifica che passano**

Run: `bash tests/claude-code/test-guided-execution-scripts.sh`
Expected: tutti PASS

- [ ] **Step 5: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): comando per uscire dalla modalità guidata`

---

### Task 6: La skill — ciclo per task e report

**Files:**
- Create: `skills/guided-execution/SKILL.md`
- Create: `skills/guided-execution/references/report-template.md`
- Test: `tests/skill-size/test-skill-size.sh`, `tests/skill-layout/test-no-dev-files-in-skills.sh` (esistenti)

**Interfaces:**
- Consumes: gli script dei Task 2–5, chiamati per percorso assoluto dalla cartella di lavoro, come fa `executing-plans`.

- [ ] **Step 1: Scrivi `SKILL.md`** con questo frontmatter, letterale:

```yaml
---
name: guided-execution
description: Use when executing an implementation plan one task at a time so your human partner can read each task's code and make every commit themselves — the default execution mode writing-plans offers
---
```

Sezioni e contenuto obbligatorio (prosa nello stile delle altre skill; termine "your human partner"):

1. **Overview / why**: il partner vuole capire il codice e le micro-scelte; il report gli fa risparmiare tempo nella lettura, non la sostituisce.
2. **The rules** (quattro, non negoziabili): non fare mai commit, nemmeno se il partner lo chiede (l'hook lo impedisce comunque); fermarsi dopo ogni task; non iniziare mai il task successivo senza un comando; ogni decisione che il piano non conteneva va nel report.
3. **Setup**: worktree tramite `superpowers:using-git-worktrees` come in `executing-plans`; ripresa dal registro (i task con la riga `Task <N>: complete` sono fatti; si riprende dal primo senza); caricare `superpowers:test-driven-development` prima del primo task; se il repo non ha commit, chiedere al partner di fare `git init` e un primo commit (non farlo).
4. **The task loop**: `guided-task-start` → se `uncommitted: yes`, una riga al partner ("il task N-1 non è ancora committato", senza fermarsi) → passi del brief in ordine TDD, confrontando ogni `Expected:` → i passi di commit del piano **non** si eseguono → `guided-task-done` → leggere il file `diff:` → scrivere il report nel percorso `report:` seguendo `references/report-template.md` → messaggio di fine task (dal template) → fermarsi.
5. **Commands**: "avvia il prossimo" e equivalenti chiari ("next", "un altro") = un task; "procedi" e equivalenti chiari ("tutti", "vai fino in fondo") = vedi Task 7; comandi ambigui ("continua", "vai") → chiedere se intende uno o tutti; qualunque altra cosa è conversazione normale e si resta in pausa.
6. **Red Flags**: tabella con almeno "Il partner ha detto 'fai tu il commit'" → no, il commit è il momento in cui conferma di aver capito; "Il task è piccolo, faccio anche il prossimo" → no, fermati; "Questa scelta è troppo piccola per il report" → se il piano non la diceva, va nel report; "L'hook mi ha bloccato, riprovo con un altro comando" → no, segnala il commit.

- [ ] **Step 2: Scrivi `references/report-template.md`** con le due forme, nella lingua della conversazione:
  - **Il report** (file): Cosa è stato fatto (2–3 frasi) · Dove guardare (file con +/− e una riga ciascuno, in ordine di lettura consigliato) · Cosa fa il codice (punti chiave con riferimenti `file:riga`, non una parafrasi riga per riga) · Micro-scelte (decisione — perché — cosa costa se è sbagliata) · Test (nomi ed esito) · Commit proposto (messaggio e motivo; se ci sono più task non committati, li elenca tutti).
  - **Il messaggio in chat**: `Task N/M — <titolo>` · percorso del report · segnale di commit esplicito ("È il momento di fare il commit" con perché e cosa entra, oppure "Non ancora" con il motivo) · messaggio di commit proposto · `→ "avvia il prossimo" · "procedi"`.

- [ ] **Step 3: Verifica dimensione e struttura**

Run: `bash tests/skill-size/test-skill-size.sh && bash tests/skill-layout/test-no-dev-files-in-skills.sh`
Expected: tutti PASS

- [ ] **Step 4: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): skill con ciclo per task e template del report`

---

### Task 7: La skill — "procedi" e fine piano

**Files:**
- Modify: `skills/guided-execution/SKILL.md` (aggiungere due sezioni)

- [ ] **Step 1: Aggiungi la sezione "When your partner says procedi"**, in quest'ordine:
  1. `guided-off PLAN_FILE`;
  2. se ci sono modifiche guidate non committate, farne un commit, aggiungendo solo i file elencati nei `task-N.diff` dei task non committati e usando il messaggio proposto nei loro report (ora i commit automatici sono ammessi);
  3. dire in una riga quale esecutore prende il resto: quello indicato dalla riga `Fallback executor:` nell'intestazione del piano, oppure `superpowers:executing-plans` se manca;
  4. invocarlo. Riprende dal registro.

- [ ] **Step 2: Aggiungi la sezione "When every task is complete"**:
  1. se ci sono modifiche non committate: segnale di commit e attesa (la revisione finale lavora sui commit);
  2. revisione finale come in `executing-plans` (Final Review, `review-package PLAN_FILE MERGE_BASE HEAD`, revisore fresco se disponibile);
  3. le correzioni sono un ultimo task guidato chiamato `final` (report `reports/task-final.md`, segnale di commit, pausa);
  4. nel messaggio finale, l'elenco completo delle righe `Ruling:` del registro;
  5. `superpowers:finishing-a-development-branch` solo su comando esplicito del partner; `guided-off` prima di invocarla.

- [ ] **Step 3: Verifica dimensione**

Run: `bash tests/skill-size/test-skill-size.sh`
Expected: PASS

- [ ] **Step 4: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(guided-execution): passaggio a "procedi" e fase finale`

---

### Task 8: writing-plans — task più piccoli

**Files:**
- Modify: `skills/writing-plans/SKILL.md` (sezione "Task Right-Sizing")

- [ ] **Step 1: Sostituisci il paragrafo di "Task Right-Sizing"** con una regola che dica: un task è un commit che una persona legge e capisce in circa 10 minuti, con una sola idea e un deliverable testabile; setup e configurazione vanno nel task che li usa solo se restano dentro quel limite, altrimenti diventano un task a sé; quando hai dubbi, dividi. Togli la frase "split only where a reviewer could meaningfully reject one task while approving its neighbor".

- [ ] **Step 2: Verifica**

Run: `bash tests/skill-size/test-skill-size.sh`
Expected: PASS

- [ ] **Step 3: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(writing-plans): task più piccoli, uno per commit leggibile`

---

### Task 9: writing-plans — modalità guidata come predefinita

**Files:**
- Modify: `skills/writing-plans/SKILL.md` ("Plan Document Header" ed "Execution Handoff")

- [ ] **Step 1: Intestazione del piano.** Nel template, la riga "For agentic workers" diventa:
  `> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:guided-execution (default), superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.`
  e sotto `**Spec:**` aggiungi `**Fallback executor:** [superpowers:subagent-driven-development or superpowers:executing-plans — the one guided-execution hands the remaining tasks to when your partner says "procedi"]`.

- [ ] **Step 2: Handoff.** La lista delle modalità diventa di tre, con **Guided** per prima: "I implement one task at a time, write a short report on what the code does and the choices I made, and stop. You read the code and make the commit; 'avvia il prossimo' runs one more task, 'procedi' runs the rest automatically." La raccomandazione predefinita è Guided. Aggiungi "**If Guided chosen:** REQUIRED SUB-SKILL: Use superpowers:guided-execution". Le descrizioni di Subagent-driven e Native restano invariate.

- [ ] **Step 3: Verifica**

Run: `bash tests/skill-size/test-skill-size.sh && grep -c "guided-execution" skills/writing-plans/SKILL.md`
Expected: PASS e un conteggio di almeno 3

- [ ] **Step 4: Segnala il commit** (non eseguirlo). Messaggio suggerito: `feat(writing-plans): proponi l'esecuzione guidata come predefinita`

---

### Task 10: Prova manuale (con il partner)

Non è codice: è la verifica che la spec chiede.

- [ ] **Step 1:** Installa il fork in locale al posto dell'originale (o in una sessione separata) e crea un piccolo progetto di prova con un piano di 3–4 task.
- [ ] **Step 2:** Esegui il piano in modalità guidata e verifica insieme al partner, segnando sì/no:
  - dopo ogni task l'agente si ferma, c'è il report e il segnale di commit;
  - nessun commit dell'agente (`git log` invariato finché il partner non committa);
  - "avvia il prossimo" senza commit → una riga di avviso e un report che copre solo il nuovo task;
  - un comando ambiguo ("continua") → l'agente chiede;
  - "procedi" → commit delle modifiche rimaste, esecutore annunciato, esecuzione fino in fondo;
  - un commit con `!git commit` del partner non viene bloccato.
- [ ] **Step 3:** Annota nel registro cosa non ha funzionato e riportalo al partner.
