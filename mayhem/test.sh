#!/usr/bin/env bash
#
# mayhem/test.sh — run glib's own GLib-core unit tests (selected in mayhem/tests.list, built by
# build.sh with normal flags) through meson and map the per-test verdicts to CTRF. Every one of these
# tests asserts values (g_assert_cmpstr/cmpint/...) and reports a TAP plan; a neutered or no-op
# binary prints no plan, which meson records as a failure.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SRC:=/mayhem}"
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

TEST_B="$SRC/meson-build/tests"
if [ ! -f "$TEST_B/build.ninja" ]; then
  echo "test.sh: $TEST_B is not configured — mayhem/build.sh must run first" >&2
  emit_ctrf meson-glib-tests 0 1
  exit 1
fi

mapfile -t names < <(cat "$SRC/mayhem/tests.list")
rm -f "$TEST_B/meson-logs/testlog.json"
meson test -C "$TEST_B" --no-rebuild --print-errorlogs --num-processes "${MAYHEM_JOBS:-$(nproc)}" \
  "${names[@]}" >&2 || true

counts="$(python3 - "$TEST_B/meson-logs/testlog.json" "${#names[@]}" <<'PY'
import json, sys
path, expected = sys.argv[1], int(sys.argv[2])
passed = failed = skipped = other = 0
seen = set()
try:
    lines = [l for l in open(path) if l.strip()]
except OSError:
    lines = []
for l in lines:
    r = json.loads(l)
    seen.add(r["name"])
    res = r["result"]
    if res in ("OK", "UNEXPECTEDPASS"):
        passed += 1
    elif res == "SKIP":
        skipped += 1
    else:
        failed += 1
failed += max(0, expected - len(seen))
print(passed, failed, skipped, other)
PY
)"
read -r P F S O <<<"$counts"
emit_ctrf meson-glib-tests "$P" "$F" "$S" 0 "$O"
