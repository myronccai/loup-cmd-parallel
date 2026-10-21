# Requirements: parallel

## Introduction

`parallel` runs a shell command once per input, several at a time, like a
small GNU parallel. Inputs come from `:::` argument lists, `::::` and `-a`
files, or standard input; each input fills the replacement strings of the
command template (`{}`, `{.}`, `{/}`, `{//}`, `{/.}`, `{#}`, `{%}`,
`{1}` ...). Jobs run as background processes, up to `-j` at a time; the
output of each job is printed as one group when it ends, in completion
order or, with `-k`, in input order. `--halt` stops a run early after
failures, `--joblog` records every job, `--dry-run` only prints the
commands.

It is a `host.scripted` Loup project run with `loup run`. Its purpose in the
loup-cmd series is to show Loup's concurrency features in a program that
needs them: a worker script started with `spawnWorker`, `spawnBlocking`,
`async`/`await`, an async generator consumed with `for await`, `atomic {}`,
`core.waiting` (`WaitGate`, `waitForItSync`), threads, a thread pool, a
mutex and atomic counters.

## Requirements

### Requirement 1: command line

**User Story:** As a shell user, I want GNU parallel's command-line grammar
so that the commands I know keep working.

#### Acceptance Criteria

1. WHEN options are given, THE parser SHALL read them up to the first word
   that is not an option (or up to `--`), accept short options with an
   attached or separate value (`-j4`, `-j 4`), combined short flags
   (`-kv`), and long options as `--name VALUE` or `--name=VALUE`.
2. WHEN the words after the options are read, THE parser SHALL take them as
   the command template up to the first `:::`, `:::+`, `::::` or `::::+`,
   and every group after a separator as an input source.
3. WHEN an option is unknown, misses its value or has an invalid value, THE
   program SHALL print `parallel: MESSAGE` and `Try 'parallel --help' for
   more information.` on standard error and exit 255, starting no job.
4. WHEN `--help` or `--version` is given, THE program SHALL print the help
   text or `parallel (loup-cmd-parallel) 0.1.0` and exit 0.

### Requirement 2: input sources

**User Story:** As a user, I want to feed jobs from argument lists, files and
standard input so that I can use parallel in pipelines.

#### Acceptance Criteria

1. WHEN no source is given, THE program SHALL read the inputs from standard
   input, one per line.
2. WHEN `::: A B C` is given, THE program SHALL use A, B and C as one source;
   WHEN `:::: F G` or `-a F -a G` is given, every file SHALL be a source of
   its own, `-` meaning standard input.
3. WHEN there are several sources, THE program SHALL run one job for every
   combination, the last source varying fastest; WHEN `--link` is given or a
   source is introduced with `:::+`/`::::+`, linked sources SHALL be taken
   side by side, a shorter one wrapping around.
4. WHEN `-0`/`--null` is given, file and stdin inputs SHALL be split at NUL
   instead of newlines; a final delimiter does not make an empty input.
5. WHEN `--colsep REGEX` is given, every input SHALL be split into columns
   that count as separate values (`{1}`, `{2}` ...).
6. WHEN `-r` is given, empty or blank file and stdin inputs SHALL be
   skipped.
7. WHEN an input file is missing or a directory, THE program SHALL report
   `parallel: cannot open input file 'F': ...` and exit 255 before starting
   any job.

### Requirement 3: command template

**User Story:** As a user, I want replacement strings so that each job's
command line is built from its input.

#### Acceptance Criteria

1. WHEN the command contains `{}`, THE job SHALL get the input (all values
   joined by spaces); `{.}` without its extension, `{/}` its basename,
   `{//}` its directory, `{/.}` its basename without extension, `{#}` the job
   sequence number, `{%}` the job slot number, `{N}` and `{N.}`, `{N/}`,
   `{N//}`, `{N/.}` the N-th value.
2. WHEN the command contains no replacement string, THE values SHALL be
   appended to it, separated by spaces.
3. WHEN values are inserted, THE program SHALL quote them for the shell, so
   that spaces and special characters reach the command unchanged; WHEN
   `-q` is given, every command word SHALL be quoted instead.
4. WHEN there is no command, THE inputs themselves SHALL be the commands.

### Requirement 4: running jobs

**User Story:** As a user, I want jobs to run concurrently and their output
not to mix so that I can read it.

#### Acceptance Criteria

1. WHEN jobs run, THE program SHALL run each with `sh` in the background, at
   most `-j N` at a time (`N`, `+N`, `-N` or `N%` of the CPUs, `0` meaning
   250; default: one per CPU), with standard input from `/dev/null` and
   `PARALLEL_SEQ` and `PARALLEL_JOBSLOT` in its environment.
2. WHEN a job ends, THE program SHALL print its standard output, then its
   standard error, as one group; WHEN `-k` is given, groups SHALL be printed
   in input order, otherwise in the order the jobs end.
3. WHEN `--tag` is given, every output line SHALL start with the job's
   values and a tab; WHEN `-v` is given, the command line SHALL be printed
   before the job's output; WHEN `-t` is given, it SHALL be printed on
   standard error as the job starts.
4. WHEN `--dry-run` is given, THE program SHALL print each command line
   instead of running it.
5. WHEN `--timeout SECS` is given, a job running longer SHALL be stopped
   (TERM, then KILL after 200 ms) and count as failed.

### Requirement 5: halting

**User Story:** As a user, I want the run to stop after failures so that a
broken batch does not run to the end.

#### Acceptance Criteria

1. WHEN `--halt soon,fail=N` is given and N jobs have failed, THE program
   SHALL start no more jobs, print `This job failed:` with the command and
   how many jobs it waits for, and wait for the running jobs.
2. WHEN `--halt now,fail=N` is given and N jobs have failed, THE program
   SHALL also stop the running jobs at once.
3. WHEN `success=N` or `done=N` is used instead of `fail=N`, THE condition
   SHALL count succeeded or finished jobs; `never`, `0`, `1` and `2` SHALL
   mean `never`, `soon,fail=1` and `now,fail=1`.

### Requirement 6: job log and exit status

**User Story:** As a user, I want a record of every job and a meaningful exit
status so that scripts can check what happened.

#### Acceptance Criteria

1. WHEN `--joblog FILE` is given, THE program SHALL write GNU parallel's
   tab-separated header and one line per job as it ends: sequence number,
   host `:`, start time, run time, bytes sent and received, exit value,
   signal and command; a stopped job SHALL have exit value -1 and the signal
   that ended it.
2. WHEN all jobs succeed, THE exit status SHALL be 0; otherwise the number
   of failed jobs, at most 101.
3. WHEN a run halts on failures, THE exit status SHALL be the exit value of
   the job that triggered the halt (255 for a stopped job); halting on
   successes SHALL exit 0.
4. WHEN anything else goes wrong (usage, input files, temporary files), THE
   exit status SHALL be 255.
