#!/usr/bin/env bash
# End-to-end tests: run bin/parallel.lpscr with `loup run` and compare its
# standard output (byte for byte), standard error where it matters, the job
# log and the exit status with the expected ones. Output order is fixed with
# -k or -j1 wherever more than one job prints.
#
# usage: tests/e2e.sh [LOUP]     (run from the repository root)

set -u
LOUP=${1:-loup}
SCRIPT=bin/parallel.lpscr
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The spool directories go here, so the tests can check they are removed.
export TMPDIR="$TMP/spool"
mkdir -p "$TMPDIR"
pass=0
fail=0

# run ARGS...: the script under test, with ARGS after `--` so that long
# options reach it, standard input from the file named by $IN (default
# /dev/null), output to $TMP/out and $TMP/err. Returns its exit status.
run() {
    "$LOUP" run "$SCRIPT" -- "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
}

report() {
    local name=$1 status=$2 want_status=$3 want_file=$4 got_file=$5
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$got_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff "$want_file" "$got_file" | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT [ARGS...]
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/out"
}

# check_err NAME STATUS EXPECTED_STDERR [ARGS...]: compare standard error.
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/err"
}

# check_sorted NAME STATUS EXPECTED [ARGS...]: compare sorted standard
# output, for jobs that may end in any order.
check_sorted() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    local status=$?
    LC_ALL=C sort "$TMP/out" > "$TMP/sorted"
    report "$name" $status "$want_status" "$TMP/want" "$TMP/sorted"
}

# check_log NAME EXPECTED: compare the job log of the last run without its
# two time columns (Starttime, JobRuntime).
check_log() {
    printf '%s' "$2" > "$TMP/want"
    cut -f1,2,5- "$TMP/log" > "$TMP/logcut"
    report "$1" 0 0 "$TMP/want" "$TMP/logcut"
}

# --- inputs -----------------------------------------------------------------

check "argument list"           0 $'a\nb\nc\n'                   -k echo ::: a b c
printf 'x y\nz\n' > "$TMP/in1"
IN=$TMP/in1 check "standard input" 0 $'[x y]\n[z]\n' -k echo '[{}]'
printf 'one\ntwo\n' > "$TMP/names.txt"
check "argument file"           0 $'one\ntwo\n'                  -k echo :::: "$TMP/names.txt"
check "-a file"                 0 $'one\ntwo\n'                  -k -a "$TMP/names.txt" echo
check "product of sources"      0 $'a-1\na-2\nb-1\nb-2\n'        -k echo {1}-{2} ::: a b ::: 1 2
check "linked source"           0 $'a-1\nb-2\nc-1\n'             -k echo {1}-{2} ::: a b c :::+ 1 2
check "--link"                  0 $'a 1 x\nb 2 x\n'              -k --link echo ::: a b ::: 1 2 ::: x
check "file times list"         0 $'one x\none y\ntwo x\ntwo y\n' -k echo :::: "$TMP/names.txt" ::: x y
printf 'a\tb\nc\td\n' > "$TMP/cols.tsv"
check "--colsep"                0 $'b:a\nd:c\n'                  -k --colsep '\t' echo {2}:{1} :::: "$TMP/cols.tsv"
printf 'a b\000c\000' > "$TMP/in2"
IN=$TMP/in2 check "-0" 0 $'[a b]\n[c]\n'         -k -0 echo '[{}]'
printf 'a\n\n  \nb\n' > "$TMP/in4"
IN=$TMP/in4 check "-r"    0 $'a\nb\n'             -k -r echo
printf 'a\n\nb\n' > "$TMP/in5"
IN=$TMP/in5 check "empty line" 0 $'[a]\n[]\n[b]\n'    -k echo '[{}]'
check "no input, no jobs"       0 ''                             echo hello
check "empty argument list"     0 ''                             echo :::

# --- replacement strings and quoting ---------------------------------------

check "path forms"              0 $'dir.d/f.tar dir.d f.tar.gz f.tar\n' echo {.} {//} {/} {/.} ::: dir.d/f.tar.gz
check "sequence and slot"       0 $'1 1 a\n2 1 b\n3 1 c\n'       -j1 echo {#} {%} {} ::: a b c
check "values are quoted"       0 $'[a  b]\n[$HOME]\n[it\'s]\n'  -k "printf '[%s]\\n'" ::: 'a  b' '$HOME' "it's"
check "the command is shell"    0 $'4\n'                         'echo {} | wc -c' ::: abc
check "inputs are commands"     0 $'one\ntwo\n'                  -k ::: 'echo one' 'echo two'
check "-q quotes words"         0 $'a|b\n'                       -q sh -c 'echo "$0|$1"' ::: a ::: b
check "environment"             0 $'1/1 a\n2/1 b\n'              -j1 'echo $PARALLEL_SEQ/$PARALLEL_JOBSLOT' ::: a b
check "awk braces stay"         0 $'x\n'                         "echo a {} | awk '{print \$2}'" ::: x

# --- output ---------------------------------------------------------------------

check "--tag"                   0 $'a\tA\nb\tB\n'                -k --tag 'echo {} | tr a-z A-Z' ::: a b
check "-v"                      0 $'echo a\na\necho b\nb\n'       -k -v echo ::: a b
check "--dry-run"               0 $'gzip -9 \'a b.txt\'\ngzip -9 \'c$d\'\n' --dry-run gzip -9 ::: 'a b.txt' 'c$d'
check_err "stderr grouped"      0 $'err a\nerr b\n'              -k 'echo err {} >&2' ::: a b
check_err "-t"                  0 $'echo a\necho b\n'            -j1 -t echo ::: a b
check_sorted "all jobs, any order" 0 $'a\nb\nc\nd\n'            -j3 echo ::: d c b a
check "completion order, -j2"   0 $'second\nfirst\n'             -j2 'sleep {1}; echo {2}' ::: 0.6 0.05 :::+ first second
check "-k keeps input order"    0 $'first\nsecond\n'             -j2 -k 'sleep {1}; echo {2}' ::: 0.6 0.05 :::+ first second

# --- exit status, halting, job log, timeout --------------------------------------

check "failures counted"        2 ''                             'exit {}' ::: 0 1 2
check "more than 101 failures"  101 ''                           -j 0 false ::: $(seq 1 102)
check "halt soon"               3 $'0\n3\n'                      -j1 --halt soon,fail=1 'echo {}; exit {}' ::: 0 3 0
check_err "halt soon notice"    3 $'parallel: This job failed:\necho 3; exit 3\n' -j1 --halt 1 'echo {}; exit {}' ::: 0 3 0
check "halt soon waits"         1 $'end 1\nend 4\n'               -j2 --halt soon,fail=1 'sleep 0.{}; echo end {}; exit {}' ::: 4 1 5
check_err "halt now"            1 $'parallel: This job failed:\nsleep 0.2; exit 1\nparallel: Stopping 1 running jobs.\n' \
                                                                 -j2 --halt now,fail=1 'sleep {}; exit 1' ::: 0.2 30
check "halt on success"         0 $'ok\n'                        -j1 --halt now,success=1 'echo ok; exit 0' ::: a b c
run -j2 --joblog "$TMP/log" -k 'echo {}; exit {}' ::: 0 3
report "joblog run" $? 1 /dev/null /dev/null
check_log "joblog" $'Seq\tHost\tSend\tReceive\tExitval\tSignal\tCommand\n1\t:\t0\t2\t0\t0\techo 0; exit 0\n2\t:\t0\t2\t3\t0\techo 3; exit 3\n'
run --joblog "$TMP/log" --timeout 0.3 'echo started; sleep {}' ::: 30
report "timeout status" $? 1 /dev/null /dev/null
check_log "timeout joblog" $'Seq\tHost\tSend\tReceive\tExitval\tSignal\tCommand\n1\t:\t0\t8\t-1\t15\techo started; sleep 30\n'
check "timeout output kept"     1 $'started\n'                   --timeout 0.3 'echo started; sleep {}' ::: 30

# Four one-second jobs on four slots overlap: well under the four seconds
# they take one by one.
start=$(date +%s%N)
check "jobs run concurrently"   0 $'1\n2\n3\n4\n'                -k -j4 'sleep 1; echo {}' ::: 1 2 3 4
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
if [ "$elapsed" -lt 3000 ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: concurrency took ${elapsed} ms"; fi

if [ -z "$(ls -A "$TMPDIR")" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL: spool left in $TMPDIR: $(ls "$TMPDIR")"; fi

# --- usage and errors ---------------------------------------------------------------

USAGE_HINT="Try 'parallel --help' for more information."
check "version"                 0 $'parallel (loup-cmd-parallel) 0.1.0\n' --version
run --help
head -1 "$TMP/out" > "$TMP/got"
printf 'usage: parallel [OPTION]... [COMMAND [ARG]...] [::: ARG... | :::: FILE...]...\n' > "$TMP/want"
report "help" 0 0 "$TMP/want" "$TMP/got"
check_err "unknown option"      255 "parallel: unrecognized option '--bogus'
$USAGE_HINT
" --bogus echo
check_err "unknown short option" 255 "parallel: invalid option -- 'x'
$USAGE_HINT
" -x echo
check_err "missing value"       255 "parallel: option requires an argument -- 'j'
$USAGE_HINT
" -j
check_err "bad jobs"            255 "parallel: invalid --jobs value 'lots'
$USAGE_HINT
" -j lots echo
check_err "bad halt"            255 "parallel: invalid --halt value 'now,fail=x' (the count must be a positive number)
$USAGE_HINT
" --halt now,fail=x echo
check_err "missing input file"  255 $'parallel: cannot open input file \'nope.txt\': No such file or directory\n' echo :::: nope.txt
check_err "input is a directory" 255 $'parallel: cannot open input file \'tests\': Is a directory\n' -a tests echo
check_err "bad tmpdir"          255 $'parallel: cannot keep temporary files in \'/nonexistent\': not a directory\n' --tmpdir /nonexistent echo ::: a
check_err "bad joblog"          255 $'parallel: cannot write the job log \'/nonexistent/log\': No such file or directory\n' --joblog /nonexistent/log echo ::: a

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
