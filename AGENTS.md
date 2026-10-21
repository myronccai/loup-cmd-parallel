# AGENTS.md

This repository is `parallel`, a small GNU parallel written in the Loup
programming language, part of the loup-cmd series of example applications.
It is a `host.scripted` project: the program is the `.lpscr` script
`bin/parallel.lpscr`, which `loup run` executes from source, with modules
in `lib/` (`host.scripted` where they use async code, workers or
`spawnBlocking`, `host.dual` otherwise). Nothing is compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/parallel.lpscr), [test] pattern
├── Makefile                     # run, check, test, e2e, ci, clean
├── bin/
│   └── parallel.lpscr           # entry script (executable, shebang `loup run`): arguments, checks, top-level await
├── lib/
│   ├── scheduler.lpscr          # class Scheduler: slots (atomic {}), batches, polling, settling, halting
│   ├── launcher.lpscr           # worker script (spawnWorker): writes N.cmd and starts the job with sh in the background
│   ├── inputs.lpscr             # async gen argument_tuples() (for await, spawnBlocking)
│   ├── runner.lpscr             # Tally (Atomic), JobLog (Mutex), Collector, Stopper: all Sendable
│   ├── shell.lpscr              # class Shell (exec on both runtimes, signals), cpu_count, spool directory
│   ├── args.loup                # struct Options, SourceSpec, parse_args(), resolve_jobs()
│   ├── halt.loup                # HaltPolicy, parse_halt(), halt_reached(), halt_notice(), exit_status()
│   ├── cmdline.loup             # replacement strings: build_command()
│   ├── records.loup             # split_records(), split_columns(), link_groups(), tuple_at()
│   ├── results.loup             # Job, JobResult, render_output(), joblog_line(), OrderBuffer
│   ├── numbers.loup             # parse_whole(), parse_millis(), seconds3(), pad_left()
│   ├── appinfo.loup             # APP_NAME, APP_VERSION, exit statuses, limits
│   └── usage.loup               # usage(), version_line()
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*() / async func test_*()
│   └── e2e.sh                   # end-to-end tests: runs the script with loup run
├── specs/parallel/              # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup` and `loup-bootstrap` on `PATH`), `make`,
`bash`, and `sh`, `mktemp`, `setsid` and `nproc` for the jobs.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="-k echo ::: a b c"` | `loup run bin/parallel.lpscr -- ARGS` |
| Run directly | `./bin/parallel.lpscr -- --halt now,fail=1 CMD ::: ...` | long options only after `--` |
| Type-check | `make check` | `loup-bootstrap check` on the entry script (with its imports) and the worker script |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn, `--no-parallel` |
| One test file | `make test TESTS=tests/runner_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter halt"` | |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: output, job log and exit status of `loup run` |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `.temp/` (unit-test files) |

Run `make ci` before reporting a change as done. Unit tests run under Stage0
(`loup-bootstrap`); the script runs under the self-hosted `loup run`, which
behaves differently in places (below), so only `make e2e` shows what users
get. The scheduler has no unit tests: `spawnWorker` fails inside Stage0's
test runner.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- A script entry cannot be built (`E-BUILD-COMPILED`); there is no build target.
- The interpreters run `async` bodies eagerly, `spawnBlocking` at the call
  site, workers in batch mode (send everything, then receive) and, in the
  self-hosted `loup run`, threads at `Thread.spawnWith` and async generators
  to their end before the first `for await` pass. Jobs run concurrently
  because they are background processes, not because of Loup tasks.
- A worker script cannot import anything, and under Stage0 sees no
  module-level constants or types: keep `lib/launcher.lpscr` to prelude
  functions, lists and strings. `spawnWorker` paths are relative to the
  entry script's directory (`../lib/launcher.lpscr` from `bin/`).
- The self-hosted `loup run` passes `exec` arguments through `sh` in double
  quotes; `Shell.prepare` escapes them. `kill` must go through `sh -c` (dash
  takes no `--`; procps' kill reads `-PID` as an option).
- The self-hosted `loup run` cannot catch `IoError`: check `exists`/`isDir`
  first. It does not process escapes inside `i"..."`; Stage0 does.
- `loup run SCRIPT --long` drops `--long`; script options go after `--`.
- `template` is a reserved word (hence `lib/cmdline.loup`).
- Stage0's `check` rejects `system.collections.filter` on a list of a
  struct from another module; use a comprehension.

## Making a change

1. Update the spec in `specs/parallel/` (see [specs/README.md](specs/README.md)).
2. Change the code: logic in `lib/`, top-level flow in `bin/parallel.lpscr`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`.
4. Run `make ci`.
5. Tick the finished tasks in `specs/parallel/tasks.md`.

## Conventions

- `bin/parallel.lpscr` is `@mode(host.scripted)` with a `#!/usr/bin/env -S
  loup run` line and the executable bit.
- `lib/*.loup` are `@mode(host.dual)`: declarations only, no `Any`; data
  types live there so script and dual modules can share them. `lib/*.lpscr`
  hold everything that needs `async`, workers or `spawnBlocking`.
- Imports are relative: `from ..lib.x import (...)` in `bin/` and `tests/`,
  `from .x import (...)` inside `lib/`.
- Build each struct through a factory in its defining module
  (`new_job`, `values_source`, `make_fill`).
- Classes shared with threads implement `Sendable`: `let` fields only, with
  shared state in an `Atomic` or `Mutex`.
- Never delete recursively: the spool is emptied file by file and removed
  with `rmdir`.
- Keep `APP_VERSION` in `lib/appinfo.loup` equal to `version` in
  `package.lppkg`.
