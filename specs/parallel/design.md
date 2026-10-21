# Design: parallel

## Overview

Loup 1.26 has no non-blocking process API: `exec` waits for its child, and
the interpreters run `async` bodies, `spawnBlocking` closures, threads and
workers one after another. Real concurrency therefore comes from the
operating system: every job is started in the background by `sh`, writes
its output to a spool directory, and publishes its exit status in a file
when it ends. The scheduler polls the spool for finished jobs. Loup's
concurrency features organise the program around that: they are written
against the specified model (tasks that interleave, workers that run beside
the host, threads that run at once), and they behave correctly, if
sequentially, in 1.26.

```text
inputs (async gen) --for await--> Scheduler --batch--> launcher worker --sh &--> jobs
                                     |  ^                                         |
                                     |  +-- poll spool (waitForItSync) <----------+
                                     +--> ThreadPool: collect   Thread: stop
                                     +--> OrderBuffer --> stdout/stderr, JobLog (Mutex)
```

## Modules

| Module | Mode | Contents |
| --- | --- | --- |
| `bin/parallel.lpscr` | scripted | entry: arguments, `--help`/`--version`, input checks, top-level `await` of the scheduler, spool clean-up in `finally`, exit status |
| `lib/appinfo.loup` | dual | name, version, exit statuses, limits |
| `lib/args.loup` | dual | `Options`, `SourceSpec` (enum `Origin`), `parse_args`, `resolve_jobs` |
| `lib/numbers.loup` | dual | `parse_whole`, `parse_millis`, `seconds3`, `pad_left` |
| `lib/usage.loup` | dual | `usage()`, `version_line()` |
| `lib/halt.loup` | dual | `HaltPolicy` (enums `HaltWhen`, `HaltOn`), `parse_halt`, `halt_reached`, `halt_notice`, `exit_status` |
| `lib/cmdline.loup` | dual | replacement strings: `Fill`, `expand_word`, `build_command` (`template` is a reserved word) |
| `lib/records.loup` | dual | splitting inputs (`split_records`, `split_columns`) and combining sources (`link_groups`, `tuple_count`, `tuple_at`) |
| `lib/results.loup` | dual | `Job`, `JobResult`, output groups (`render_output`), job log lines, `OrderBuffer` for `-k` |
| `lib/shell.lpscr` | scripted | `Shell` (Sendable): `exec` with the self-hosted quoting fix, process-group signals, CPU count, spool directory |
| `lib/runner.lpscr` | scripted | `Tally` (Atomic counters), `JobLog` (Mutex), `Collector`, `Stopper` |
| `lib/inputs.lpscr` | scripted | `argument_tuples`: the async generator over input tuples, reading files with `spawnBlocking` |
| `lib/launcher.lpscr` | scripted | the worker script: writes each job's command file and starts it in the background |
| `lib/scheduler.lpscr` | scripted | `Scheduler`: slots, batches, polling, settling, halting |

Data types live in `host.dual` modules so that both kinds of module can use
them; everything that needs `async`, `spawnWorker` or `spawnBlocking` is a
script module.

## Job life cycle

1. `argument_tuples` yields the values of one job. The scheduler numbers it
   (`{#}`), builds its command line (`build_command`), reserves the lowest
   free slot (`{%}`) inside an `atomic {}` block and adds it to the batch.
2. When no slot is free (or the input ends), the batch goes to a new
   launcher worker: the scheduler sends every job, then receives one reply
   per job (workers run in batch mode in 1.26). The worker writes
   `SPOOL/N.cmd` and runs, through `exec`:
   `setsid sh -c WRAPPER job SPOOL N SLOT > /dev/null 2>&1 < /dev/null &`,
   replying with the background PID. The wrapper runs
   `PARALLEL_SEQ=N PARALLEL_JOBSLOT=SLOT sh SPOOL/N.cmd` with its output in
   `N.out` and `N.err`, then writes `$?` to `N.tmp` and renames it to
   `N.rc`, so the status appears whole.
3. `waitForItSync` polls every 10 ms until a running job has an `N.rc`
   file or is past its `--timeout`.
4. Finished jobs are collected on a `ThreadPool`: the `Collector` reads and
   removes the four spool files, builds a `JobResult`, appends the job log
   line under the `JobLog` mutex and counts the job in `Tally`. Overdue jobs
   each get a `Thread`: the `Stopper` signals the job's process group
   (`kill -TERM -- -PID`), waits up to 200 ms with `waitForItSync` and sends
   KILL on its `TimeoutError`; then the collector records it with exit
   value -1.
5. The scheduler frees the slots, hands each result to the `OrderBuffer`
   (immediately printable without `-k`; held until its predecessors are
   printed with `-k`), prints the groups and checks the halt policy.

## Halting

`HaltPolicy` says when (`soon`, `now`), on what (`fail`, `success`,
`done`) and after how many jobs. When it is reached the scheduler sets a
`WaitGate`; the input loop and the batch starter check the gate and start
nothing more. `now` also stops every running job (one `Thread` each). The
exit status is the triggering job's exit value (255 if it was stopped) for
`fail`, 0 for `success`, and otherwise the failed-job count capped at 101.

## Lanes and 1.26 behaviour

- `loup run` (self-hosted, used by `make run`, e2e and users) passes every
  `exec` argument through `sh` inside double quotes. `Shell` detects this
  once (`printf %s '\$'` prints `$` there) and escapes `\`, `"`, `$` and
  `` ` `` before such calls; under Stage0 arguments pass unchanged.
- Worker scripts cannot import anything, and under Stage0 they see no
  module-level constants or types, so the launcher uses prelude functions,
  lists and strings only. Its path is relative to the entry script's
  directory (`../lib/launcher.lpscr` from `bin/`).
- The self-hosted runtime runs an async generator to the end before the
  first `for await` iteration and threads at `Thread.spawnWith`; Stage0 is
  lazy and has real threads. The program is correct either way.
- `spawnWorker` fails inside the Stage0 test runner, so the scheduler is
  covered by `tests/e2e.sh`; unit tests cover every other module.

## Error handling

- Usage errors: `Err(message)` from `parse_args`, printed by the entry
  script with the `Try` line, status 255.
- Input files are checked with `exists`/`isDir` before the run (the
  self-hosted runtime cannot catch `IoError`).
- A failed `mktemp`, an unwritable `--joblog` or a launch error ends the
  run with status 255; the spool directory is removed in a `finally` block
  file by file, never with `rm -rf`.

## Testing

- Unit tests (`tests/*_test.lpscr`, Stage0): arguments, halt policies,
  replacement strings, records and combinations, results and the order
  buffer, the job log, the shell helpers, the launcher's functions and the
  collector and stopper on real processes (skipped where `setsid` is
  missing), and the async input generator.
- `tests/e2e.sh` runs `bin/parallel.lpscr` with `loup run`: sources,
  replacement strings, quoting, `-k`, `--tag`, `-v`, `--dry-run`,
  `--joblog`, `--halt`, `--timeout`, exit statuses, error messages, and a
  timing check that four one-second jobs with `-j4` overlap.
