# Report and end-of-task message

Part of superpowers:guided-execution. Write both in the language of the
conversation. Keep the report short: it is a map for reading the code, read
once and then thrown away.

## The report (file at the `report:` path)

```markdown
# Task <N>/<total> — <task title>

## Cosa è stato fatto
<Two or three sentences: what exists now that didn't before, and why the
plan needed it.>

## Dove guardare
<Files in the order you'd read them, each with +added/−removed lines from
the stat and one line on what it holds.>
1. `path/to/file` (+42) — <what it holds>
2. ...

## Cosa fa il codice
<The key parts, explained in words, each pointing at `file:line`. Explain
what a reader needs in order to understand it: the idea, the non-obvious
step, the concept they may not know. Not a line-by-line paraphrase.>

## Micro-scelte
<Every decision the plan did not make, one per line:
decision — why — what it costs if wrong (and how hard it is to change).
"None" only when there truly were none.>

## Test
<Test names (or the cases they cover) and the final result.>

## Commit proposto
<The suggested message, and why now is a good point. If earlier tasks are
still uncommitted, say so: list them and propose either one commit per task
(files and message for each) or one commit covering all of them.>
```

## The end-of-task message (chat)

```
── Task <N>/<total> — <title> ──────────────
Report: <path>

<Commit signal, explicit. One of:>
È il momento di fare il commit: <why — what is complete and coherent now>.
Entrano: <files, and the sense of the change>.
  git add <files>
  git commit -m "<message>"
<or>
Non ancora: <why — what is still half-done>. Il commit arriva con il task <M>.

<Micro-choices: one line each, the ones most worth a look.>

→ "avvia il prossimo" · "procedi"
```

Include the `git add` / `git commit` lines as text for your partner to
run. You never run them.
