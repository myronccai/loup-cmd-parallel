# Check, test and run commands for this host-scripted Loup project.
#
# The program is a script (bin/parallel.lpscr) that `loup run` executes from
# source. A script entry cannot be compiled (E-BUILD-COMPILED), so there is
# no build target. On Linux x86-64 `loup` is the self-hosted driver and
# `loup-bootstrap` is Stage0; `check` and `test` need Stage0 there. On macOS,
# Windows and Linux arm64 both names run Stage0, so the targets work unchanged.

APP            ?= parallel
LOUP           ?= loup
LOUP_BOOTSTRAP ?= loup-bootstrap
# The entry script, and the worker script it starts with spawnWorker (no
# script imports the worker, so it is checked on its own).
SCRIPTS        := $(wildcard bin/*.lpscr) lib/launcher.lpscr
TESTS          ?= $(wildcard tests/*_test.lpscr)
ARGS           ?=
TEST_ARGS      ?=

.PHONY: all run check test e2e ci clean

all: ci

# Run from source, e.g. `make run ARGS="-k echo ::: a b c"`. The arguments
# follow `--` so that long options reach the script.
run:
	$(LOUP) run bin/$(APP).lpscr -- $(ARGS)

# Type-check the entry script with every lib/ module it imports, and the
# worker script.
check:
	@for script in $(SCRIPTS); do \
		echo "check $$script"; \
		$(LOUP_BOOTSTRAP) check --no-color $$script || exit 1; \
	done

# Unit tests (tests/*_test.lpscr). They import lib/ with relative imports
# (`from ..lib.args import (...)`), which the Stage0 runner resolves. Files
# run one at a time and tests one at a time (--no-parallel): the 1.26.0
# runner's parallel mode fails random tests on a busy machine, and some of
# these tests start processes.
# Narrow the run: `make test TESTS=tests/args_test.lpscr TEST_ARGS="--filter halt"`.
test:
	@status=0; for t in $(TESTS); do \
		$(LOUP_BOOTSTRAP) test --no-color --no-parallel --file $$t $(TEST_ARGS) || status=1; \
	done; exit $$status

# End-to-end tests: run the script with `loup run` and compare its output,
# job log and exit status with the expected ones.
e2e:
	bash tests/e2e.sh $(LOUP)

# Everything CI runs, ending with a smoke test of the entry script.
ci: check test e2e
	$(LOUP) run bin/$(APP).lpscr -- --version

clean:
	rm -rf .temp
