# loup-cmd-parallel

A small GNU `parallel` written as a [Loup](https://code-craft.ai/references/loup)
script: it runs a shell command once per input, several jobs at a time, with
GNU parallel's replacement strings (`{}`, `{.}`, `{/}`, `{//}`, `{/.}`,
`{#}`, `{%}`, `{1}` ...), `:::`/`::::` input sources, `-j`, `-k`, `--halt`,
`--joblog`, `--timeout` and `--dry-run`. The output of each job is printed
as one group when it ends.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` project: an entry script in `bin/` and modules
in `lib/`, run with `loup run`. It is the series' example of Loup's
concurrency features: a worker script (`spawnWorker`/`WorkerChannel`),
`spawnBlocking`, `async`/`await`, an async generator read with `for await`,
`atomic {}`, `core.waiting`, threads, a thread pool, a mutex and atomic
counters.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later (`loup` and `loup-bootstrap` on `PATH`); see [Installing Loup Lite](#installing-loup-lite).
- A POSIX system with `sh`, `mktemp`, `kill` and, to stop whole process
  groups, `setsid` (util-linux); `nproc` for the default `-j`.
- `make` and `bash` for the checks and tests. No C compiler: nothing is built.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make run ARGS="-k echo ::: a b c"     # loup run bin/parallel.lpscr -- ARGS
./bin/parallel.lpscr -- -j4 gzip -9 ::: *.log
make ci                               # check, unit tests, end-to-end tests
```

The script is executable (`#!/usr/bin/env -S loup run`). Inputs come from
`:::` lists, `::::` files or standard input, and fill the replacement
strings; several sources give one job per combination:

```text
$ ./bin/parallel.lpscr -- -k echo ::: a b c
a
b
c
$ cat files.txt
photos/beach.jpeg
photos/city night.jpeg
docs/report.tex
$ ./bin/parallel.lpscr -- -k 'echo {} {.} {/} {//} {/.}' :::: files.txt
photos/beach.jpeg photos/beach beach.jpeg photos beach
photos/city night.jpeg photos/city night city night.jpeg photos city night
docs/report.tex docs/report report.tex docs report
$ ./bin/parallel.lpscr -- --dry-run convert {} {.}.png :::: files.txt
convert photos/beach.jpeg photos/beach.png
convert 'photos/city night.jpeg' 'photos/city night'.png
convert docs/report.tex docs/report.png
$ ./bin/parallel.lpscr -- -k echo {1}-{2} ::: x y ::: 1 2 3
x-1
x-2
x-3
y-1
y-2
y-3
$ ./bin/parallel.lpscr -- -k --tag 'echo {#}/{%}' ::: x y z
x	1/1
y	2/2
z	3/3
$ ./bin/parallel.lpscr -- -k --colsep , 'echo {2} is {1}' ::: red,apple yellow,banana
apple is red
banana is yellow
```

Jobs really run at the same time, and each one's output comes out whole when
it ends; `-k` restores input order:

```text
$ seq 3 | ./bin/parallel.lpscr -- -j3 'sleep 0.$((4 - {})); echo job {}'
job 3
job 2
job 1
$ seq 3 | ./bin/parallel.lpscr -- -j3 -k 'sleep 0.$((4 - {})); echo job {}'
job 1
job 2
job 3
$ time ./bin/parallel.lpscr -- -j4 --timeout 1.5 'sleep {}; echo slept {}' ::: 1 2 1 1
slept 1
slept 1
slept 1

real	0m1.842s
```

`--halt` stops a run early; `--joblog` records every job, a stopped one with
exit value -1 and the signal that ended it:

```text
$ ./bin/parallel.lpscr -- -j2 --halt now,fail=1 --joblog jobs.tsv 'echo start {}; sleep {}; test {} != 0.5' ::: 0.2 0.5 3 1
start 0.2
start 0.5
parallel: This job failed:
echo start 0.5; sleep 0.5; test 0.5 != 0.5
parallel: Stopping 1 running jobs.
start 3
$ echo $?
1
$ cat jobs.tsv
Seq	Host	Starttime	JobRuntime	Send	Receive	Exitval	Signal	Command
1	:	1792562961.997	     0.216	0	10	0	0	echo start 0.2; sleep 0.2; test 0.2 != 0.5
2	:	1792562961.997	     0.521	0	10	1	0	echo start 0.5; sleep 0.5; test 0.5 != 0.5
3	:	1792562962.220	     0.325	0	8	-1	15	echo start 3; sleep 3; test 3 != 0.5
```

### Options

| Option | Meaning |
|---|---|
| `-j`, `-P`, `--jobs N` | job slots: `N`, `+N`/`-N` (CPUs plus/minus N), `N%` of the CPUs, `0` for 250; default one per CPU |
| `-k`, `--keep-order` | print the output groups in input order |
| `--halt WHEN,COND=N` | stop after N jobs failed (`fail`), succeeded (`success`) or finished (`done`): `soon` starts no new job, `now` also stops the running ones; `never` (default), `0`, `1`, `2` |
| `--joblog FILE` | GNU parallel's tab-separated job log |
| `--dry-run` | print the command lines instead of running them |
| `--tag` | start every output line with the job's values and a tab |
| `-v` / `-t`, `--verbose` | print each command line before its output / on standard error as it starts |
| `-q`, `--quote` | quote every command word for the shell |
| `-a`, `--arg-file FILE` | an input source read from FILE (`-` is standard input) |
| `-0`, `--null` | inputs are separated by NUL instead of newline |
| `-C`, `--colsep REGEX` | split every input into columns (`{1}`, `{2}` ...) |
| `-r`, `--no-run-if-empty` | skip empty and blank inputs |
| `--link`, `--xapply` | take all input sources side by side (`:::+`, `::::+` link one) |
| `--timeout SECS` | stop jobs that run longer (TERM, then KILL after 200 ms) |
| `--tmpdir DIR` | where job output waits (default `$TMPDIR` or `/tmp`) |
| `-h`, `--help` / `-V`, `--version` | help text / `parallel (loup-cmd-parallel) 0.1.0` |

Inserted values are quoted for the shell (`'city night.jpeg'`), while the
command words are joined as written, so `'echo {} | wc -c'` is a pipeline.
Without a replacement string the values are appended; without a command the
inputs are the commands. Each job sees `PARALLEL_SEQ` and `PARALLEL_JOBSLOT`.

**Long options need `--` under `loup run`.** `loup run SCRIPT ARGS` treats
words starting with `--` as its own flags, and the self-hosted `loup run` on
Linux x86-64 drops unknown ones silently. Write
`./bin/parallel.lpscr -- --halt now,fail=1 ...`; `make run` adds the `--`.

Exit status: `0` when every job succeeded; otherwise the number of failed
jobs, at most `101`; after `--halt ...,fail=N`, the exit value of the job
that triggered it (`255` if it was stopped), after `success=N` `0`; `255` for
usage errors and other errors.

## How it works

Loup 1.26 has no non-blocking process API, and its interpreters run tasks,
workers and threads one after another; the concurrency comes from the
operating system. Each job runs in the background under `sh`, in a process
group of its own (`setsid`), with its output in a spool directory; when it
ends, it renames a status file into place. The scheduler watches the spool.
The Loup concurrency features organise that work, written for the specified
model (tasks that interleave, workers beside the host, threads at once) and
correct, if sequential, in 1.26:

- **Async generator and `for await`**: `lib/inputs.lpscr` yields one value
  tuple per job, combining the sources like an odometer; the scheduler pulls
  the next one only when it can start it.
- **`spawnBlocking`**: reading an input file or standard input inside the
  generator.
- **`spawnWorker` / `WorkerChannel`**: `lib/launcher.lpscr` is a worker
  script. The scheduler sends it a batch of jobs (one per free slot) and
  receives a PID for each, as 1.26's batch-mode workers require.
- **`async`/`await` and `atomic {}`**: the scheduler's methods are async;
  taking the lowest free slot (`{%}`) is an `atomic {}` block, so no task
  could take the same slot between the check and the claim.
- **`core.waiting`**: `waitForItSync` polls the spool every 10 ms and waits
  out the grace period before KILL (its `TimeoutError` triggers the KILL); a
  `WaitGate` is the halt flag.
- **`ThreadPool`, `Thread`, `Mutex`, `Atomic`, `Sendable`**: finished jobs
  are collected on a thread pool, jobs to stop each get a thread, the job
  log is appended under a mutex, and atomic counters tally the jobs; the
  classes these threads share are `Sendable`.
- **Running processes from both runtimes**: the self-hosted `loup run`
  passes `exec` arguments through `sh` in double quotes, so `lib/shell.lpscr`
  detects that once and escapes `\`, `"`, `$` and the backquote.

## Differences from GNU parallel

- Jobs run locally only: no `--sshlogin`, `--pipe`, `--onall`, `--bar`,
  `--eta`, `--progress`, `--resume`, `--retries`, `--delay`, `--shuf`,
  `{= perl =}` replacement strings, or the `-I`/`--er` family of custom
  replacement strings. Of the input separators only `-0` is there (no
  `-d DELIM`).
- `--halt` takes counts, not percentages (`fail=10%`).
- Input is read whole before the first job starts (GNU parallel starts jobs
  while it reads), so `tail -f log | parallel ...` never starts.
- Jobs always get `/dev/null` as standard input, and output is always
  grouped (no `--ungroup`, `--line-buffer`): it waits in files until the job
  ends. A job's standard error is printed with a final newline added when it
  has none.
- Values are quoted with single quotes (`'a b'`); GNU parallel writes
  `a\ b`. `--dry-run` shows the difference.
- `--timeout` and `--halt now` send TERM, then KILL after 200 ms (GNU's
  default `--termseq` is TERM, TERM, TERM, KILL). Without `setsid` only the
  job's wrapper shell is signalled. The job log's times are measured by the
  scheduler, to within its 10 ms polling; stopped jobs show exit value -1 and
  the signal, other jobs the shell's exit status (a job killed by a signal
  shows 128+N there).
- Messages differ in wording (`parallel: cannot open input file 'x': ...`),
  and `-j 0` means 250 slots.

## Layout

```text
bin/parallel.lpscr          # entry script: arguments, checks, top-level await, exit status
lib/scheduler.lpscr         # slots, batches, polling, collecting, halting
lib/launcher.lpscr          # the worker script that starts jobs in the background
lib/inputs.lpscr            # the async generator over input tuples
lib/runner.lpscr            # Tally (Atomic), JobLog (Mutex), Collector, Stopper
lib/shell.lpscr             # exec on both runtimes, signals, CPUs, the spool directory
lib/args.loup               # option parsing
lib/halt.loup               # --halt policies and the exit status
lib/cmdline.loup            # replacement strings and command lines
lib/records.loup            # input records, columns, combining sources
lib/results.loup            # jobs, results, output groups, job log lines, -k buffer
lib/numbers.loup            # number parsing and formatting
lib/appinfo.loup            # name, version, exit statuses, limits
lib/usage.loup              # --help and --version text
tests/*_test.lpscr          # unit tests (make test)
tests/e2e.sh                # end-to-end tests with loup run (make e2e)
specs/parallel/             # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
