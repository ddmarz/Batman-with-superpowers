---
name: guided-execution
description: Use when executing an implementation plan one task at a time so your human partner can read each task's code and make every commit themselves — the default execution mode writing-plans offers
---

# Guided Execution

Execute the plan yourself, one task at a time, in this session. After each
task, write a short report on what the code does and which choices you made,
tell your human partner it is time to commit, and stop.

**Why guided:** Your human partner treats this project as theirs, and as a
way to learn. Fast execution leaves them owning commits whose code they never
read and whose small design choices they never saw. Guided execution trades
speed for that understanding. The report saves them time while they read the
code; it does not replace reading it.

**Core principle:** One task, one report, one stop. The commit is theirs:
it is the moment they confirm they understood what goes in.

**Announce at start:** "I'm using the guided-execution skill: one task at a
time, a report after each, and you make the commits."

## The Rules

These four do not bend, whatever the plan, the context or the partner's
mood says:

1. **Never commit.** Not when the plan's step says `git commit`, not when
   your partner says "fai tu il commit", not "just this once". In guided
   mode the commit is theirs. A hook denies your `git commit` anyway; if it
   fires, you broke this rule — signal the commit instead.
2. **Stop after every task.** The end-of-task message is your last output
   until your partner gives a command.
3. **Never start the next task unasked.** Not because it is small, not
   because it is obvious, not because the previous one went well.
4. **Every decision the plan did not make goes in the report.** A choice
   too small to mention is exactly the kind your partner asked to see.

## Setup

- Work where executing-plans works: use superpowers:using-git-worktrees to
  create an isolated workspace or verify the existing one. Never start on
  main/master without your partner's explicit consent. If that skill wants
  a commit (say, adding the worktree directory to `.gitignore`), make the
  file change and send it as a commit signal: Rule 1 holds from the start.
- The repository needs at least one commit. If it has none, or is not a
  repository at all, ask your partner to run `git init` and make a first
  commit. Do not do it yourself: that would be your commit.
- The workspace and ledger are shared with superpowers:executing-plans and
  superpowers:subagent-driven-development
  (`<repo-root>/.superpowers/sdd/<plan-basename>/progress.md`). If the
  ledger's first line names your plan, tasks with a `Task <N>: complete`
  line are done: resume at the first task without one.
- Read the plan once and its Spec if it names one. Create a todo per task.
- **REQUIRED SUB-SKILL:** load superpowers:test-driven-development before
  Task 1. It governs every step.

## The Task Loop

### 1. Take the task (only when your partner asked for it)

Run this skill's `scripts/guided-task-start PLAN_FILE N` by its absolute
path, from the working tree you're executing in. It prints `brief:`,
`base:` (a snapshot of the working tree when the task first started — keep
it for step 3), `uncommitted:` and `resumed:`. It also turns guided mode on
for this plan. Running it again for the same task is safe and reprints the
same `base:`: do that whenever you have lost it (after a compaction, in a
new session).

If it says `uncommitted: yes`, an earlier guided task's work is still
uncommitted: tell your partner in one line ("il task N-1 non è ancora
committato") and carry on. They may choose to read several tasks and commit
once; that is their call. Do not wait for an answer.

If it says `resumed: yes`, this task was started before: check what is
already done against the brief and continue from there.

Read the brief, even for a task you remember.

### 2. Work the steps

Follow the brief's steps in order under superpowers:test-driven-development.
Compare every `Expected:` line with real output. When the code is wrong, use
superpowers:systematic-debugging. When the plan is wrong, make the smallest
change the spec allows and write it down as a ruling:
`Task <N>: Ruling: <what you decided> — <why> — <what it costs if wrong>`.

**The plan's commit steps are not run.** Each one becomes the commit signal
in step 4. Do not `git add` either: the staging area is your partner's.

### 3. Close the task

Run this skill's `scripts/guided-task-done PLAN_FILE N BASE -- <test command>`
by its absolute path, from the working tree you're executing in, with the
`base:` from step 1 and the test command the brief names for the whole task.
It runs the tests and, only if they pass, saves this task's diff (this task
alone, even with earlier tasks uncommitted), prints its stat and appends the
ledger line. It prints `diff:` and `report:` paths.

A failing run records nothing. The task is not done: finish it.

### 4. Report and stop

Read the `diff:` file. Write the report at the `report:` path, then send the
end-of-task message. Both follow `references/report-template.md`, in the
language of the conversation. Then stop.

## Commands

| Your partner says | You do |
|---|---|
| "avvia il prossimo", "next", "un altro", "vai col prossimo" | One more loop, then stop again. |
| "procedi", "tutti", "vai fino in fondo" | Hand the rest of the plan over (see below). |
| "continua", "vai", "ok", or anything that could mean one or all | Ask which: the next task, or all of the remaining ones? |
| Anything else: questions, "spiegami questa funzione", "cambia questa scelta" | Normal conversation. Answer, change what they ask, update the report. Stay paused. |

A change your partner asks for after the report belongs to the same task:
make it, then close the task again with `scripts/guided-task-done PLAN_FILE N
BASE -- <test command>`, run by its absolute path from the working tree
you're executing in, with the same BASE. That refreshes the task's diff and
its ledger line. Update the report and the commit signal from the new diff.
It is not the next task.

## When Your Partner Says "procedi"

They are handing you the rest of the plan, with automatic commits, as
Superpowers runs it without guidance. In this order:

1. Run this skill's `scripts/guided-off PLAN_FILE` by its absolute path,
   from the working tree you're executing in. Guided mode is off; commits
   are allowed again.
2. If guided tasks are still uncommitted (`git status` shows changes),
   commit them now. Take the files named in their `task-<N>.diff` files in
   the workspace, and commit only those paths, so nothing your partner had
   staged rides along: `git add -- <files>` then
   `git commit -m "<message>" -- <files>`. One commit per task, with the
   message from its report, when the tasks touch different files;
   otherwise one commit whose message names every task it covers.
3. Say in one line which executor takes over: the plan header's
   `Fallback executor:` line, or superpowers:executing-plans if the plan
   has none.
4. Invoke it. It resumes from the shared ledger: every guided task has its
   `Task <N>: complete` line, so it starts at the first task without one.

## When Every Task Is Complete

After the last task's report, the end-of-task message says it was the last
one and that the final review comes next. When your partner gives the go:

1. **Everything committed first.** The final review reads commits. If
   `git status` shows changes, send the commit signal for them and wait.
2. **Final review.** Read superpowers:executing-plans' "Final Review"
   section and follow it: the review package, a fresh reviewer on the most
   capable model, re-grading the findings by effect.
3. **Fixes are one last guided task, named `final`.** Run this skill's
   `scripts/guided-snapshot` by its absolute path, from the working tree
   you're executing in, for BASE. Fix the Critical and Important findings
   under TDD. Close with `scripts/guided-task-done PLAN_FILE final BASE --
   <full test command>`, run by its absolute path the same way. Report at
   `reports/task-final.md`, commit signal, stop.
4. **Final message.** List every ledger line containing `Ruling:` under
   "Scelte che ho fatto" and every deferred minor finding under
   "Rilievi minori non corretti". Both lists are exhaustive.
5. **Finishing only on command.** When your partner asks to merge, open a
   PR or wrap up: run `scripts/guided-off PLAN_FILE` by its absolute path,
   then use superpowers:finishing-a-development-branch. Delete the plan's
   workspace only after that, and tell your partner the reports go with it.

## Red Flags

| Thought | Reality |
|---|---|
| "My partner said 'fai tu il commit'" | No. The commit is when they confirm they understood. Give them the command to paste. |
| "This task is tiny, I'll do the next one too" | Stop. Rule 3. |
| "That choice is too small for the report" | If the plan didn't make it, it goes in. Rule 4. |
| "The hook blocked me, I'll commit another way" | Never. Signal the commit and stop. |
| "The plan says `git commit`, so it's allowed" | In guided mode, a commit step is a commit signal. |
| "They said 'ok', that means go on" | 'ok' is not a command. Ask: one task, or all? |
| "I'll stage the files so the commit is easy" | The staging area is theirs. List the files in the signal instead. |
| "The report can paraphrase the diff line by line" | It points them to the code and explains the key parts. It is not a second copy. |
