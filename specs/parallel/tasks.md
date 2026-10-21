# Tasks: parallel

- [x] 1. Project skeleton: manifest, Makefile (run, check, test, e2e, ci,
  clean; no build target), CI without a native build, `lib/appinfo.loup`,
  `lib/usage.loup`.
  - _Requirements: 1.4_
- [x] 2. Command-line parser `lib/args.loup` with `Options`, `SourceSpec`,
  value parsers (`lib/numbers.loup`) and usage errors; unit tests.
  - _Requirements: 1.1, 1.2, 1.3, 2.2, 2.4, 4.1, 4.5_
- [x] 3. Halt policies `lib/halt.loup`: parsing, the halt test, notices and
  the exit status; unit tests.
  - _Requirements: 5.1, 5.2, 5.3, 6.2, 6.3_
- [x] 4. Replacement strings `lib/cmdline.loup`; unit tests.
  - _Requirements: 3.1, 3.2, 3.3, 3.4_
- [x] 5. Inputs `lib/records.loup` (delimiters, columns, combinations) and
  the async generator `lib/inputs.lpscr`; unit tests.
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6_
- [x] 6. Results `lib/results.loup`: jobs, output groups, `--tag`, `-v`,
  job log lines, the order buffer; unit tests.
  - _Requirements: 4.2, 4.3, 6.1_
- [x] 7. Processes `lib/shell.lpscr` and the launcher worker
  `lib/launcher.lpscr`; unit tests for quoting, signals and launch lines.
  - _Requirements: 4.1_
- [x] 8. `lib/runner.lpscr`: Tally, JobLog, Collector, Stopper; unit tests
  on real processes.
  - _Requirements: 4.5, 6.1_
- [x] 9. `lib/scheduler.lpscr` and `bin/parallel.lpscr`: slots, batches,
  polling, settling, halting, dry run, exit status.
  - _Requirements: 2.7, 4.1, 4.2, 4.4, 5.1, 5.2, 6.2, 6.3, 6.4_
- [x] 10. End-to-end tests `tests/e2e.sh`.
  - _Requirements: all_
- [x] 11. README, AGENTS.md, file headers, `make ci` green locally and on
  GitHub.
