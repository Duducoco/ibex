#!/usr/bin/env bash
# Run ibex random verification for every test in testlist.yaml.
# Each test gets its own fully isolated OUT directory (build + metadata + run).
# Usage: ./run_make.sh [TEST_NUM]
#   TEST_NUM: number of random-seed runs per test (default: 1)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source ibex environment (sets PKG_CONFIG_PATH for ibex-cosim Spike)
IBEX_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ -f "$IBEX_ROOT/setup_env.sh" ]]; then
    source "$IBEX_ROOT/setup_env.sh"
fi
TESTLIST="$SCRIPT_DIR/riscv_dv_extension/testlist.yaml"
TEST_NUM="${1:-1}"

MAX_JOBS=$(( $(nproc) / 2 ))
(( MAX_JOBS < 1 )) && MAX_JOBS=1

mapfile -t TESTS < <(grep '^- test:' "$TESTLIST" | awk '{print $3}' | tr -d '\r')
[[ ${#TESTS[@]} -eq 0 ]] && { echo "ERROR: No tests found in $TESTLIST"; exit 1; }

total=$(( ${#TESTS[@]} * TEST_NUM ))

echo "============================================================"
echo " Ibex random verification"
echo " Tests: ${#TESTS[@]}, Runs/test: $TEST_NUM, Total: $total"
echo " Parallel jobs: $MAX_JOBS / $(nproc) CPUs"
echo " Mode: fully isolated (each test has its own build + run dir)"
echo "============================================================"

# ---------------------------------------------------------------------------
# Run all tests in parallel, each with its own isolated OUT directory
# ---------------------------------------------------------------------------
echo ""
echo ">>> Running tests in parallel (max $MAX_JOBS jobs)..."
echo ""

RESULT_DIR=$(mktemp -d)
trap 'rm -rf "$RESULT_DIR"' EXIT

run_one() {
    local test="$1" seed="$2"
    local run_dir="out/runs/${test}_${seed}"

    make -C "$SCRIPT_DIR" \
        SIMULATOR=vcs ISS=spike IBEX_CONFIG=opentitan \
        TEST="$test" SEED="$seed" ITERATIONS=1 COV=1 \
        OUT="$run_dir" \
        > "$RESULT_DIR/${test}__${seed}.log" 2>&1
    local rc=$?

    local status
    if (( rc == 0 )); then
        status="PASS"
    else
        status="FAIL"
    fi

    echo "$status" > "$RESULT_DIR/${test}__${seed}.result"
    echo "[$status] $test  seed=$seed"
}

declare -a pids=()

for test in "${TESTS[@]}"; do
    for ((i = 0; i < TEST_NUM; i++)); do
        seed=$RANDOM

        while (( ${#pids[@]} >= MAX_JOBS )); do
            wait -n 2>/dev/null || true
            new_pids=()
            for pid in "${pids[@]}"; do
                kill -0 "$pid" 2>/dev/null && new_pids+=("$pid")
            done
            pids=("${new_pids[@]}")
        done

        echo "  --> launching $test  seed=$seed"
        run_one "$test" "$seed" &
        pids+=($!)
    done
done

wait

# ---------------------------------------------------------------------------
# Collect and print results
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " RESULTS:"
pass=0; fail=0
declare -a results=()
for f in "$RESULT_DIR"/*.result; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .result)
    test="${base%__*}"
    seed="${base##*__}"
    status=$(<"$f")
    results+=("[$status] $test  seed=$seed")
    if [[ $status == "PASS" ]]; then
        (( pass++ ))
    else
        (( fail++ ))
        echo "  [log] $SCRIPT_DIR/out/runs/${test}_${seed}/regr.log" >&2
    fi
done

printf '%s\n' "${results[@]}" | sort | sed 's/^/  /'

echo ""
echo " SUMMARY: $pass/$total PASSED,  $fail FAILED"
echo "============================================================"

(( fail == 0 ))
