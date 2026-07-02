#!/usr/bin/env bash
# epub2txt2/mayhem/test.sh — GOLDEN / known-answer oracle for kevinboone/epub2txt2.
#
# epub2txt2 ships NO functional test suite (its Makefile has no test target and the repo bundles no
# sample EPUBs / expected output). We author one here as a known-answer functional oracle:
#
#   * The .epub container we feed in is ASSEMBLED AT RUNTIME from reviewable component files committed
#     under mayhem/testdata/epub_src/ (mimetype + META-INF/container.xml + OEBPS/{content.opf,*.xhtml}).
#     The `mimetype` member is stored uncompressed first (`zip -X -0`), the rest added (`zip -X -rg`),
#     exactly per the EPUB OCF spec. epub2txt then shells out to `unzip` to expand it, so the .epub's
#     compression is irrelevant to the oracle — but the assembly is byte-reproducible regardless.
#   * It builds epub2txt2 INDEPENDENTLY with the project's NORMAL flags (`make` — the documented
#     -O3 gcc build), NOT the sanitizer/fuzz build mayhem/build.sh produces. So the oracle exercises
#     the real shipped behavior and won't false-fail on benign UB the fuzz build's UBSan would halt on.
#   * It then RUNS the CLI under several documented invocations (default, --noansi, --raw, --meta) and
#     DIFFs each stdout against a committed golden (mayhem/testdata/golden/<name>.txt). The goldens were
#     captured once from this freshly-built binary and were verified byte-stable across repeated runs.
#
# This is an anti-reward-hack oracle by construction: it asserts the EXACT extracted TEXT of each
# invocation, not merely "exited 0". A no-op / exit(0) "patch", or any change that stops epub2txt
# correctly walking the OPF spine and rendering the XHTML, yields empty or mismatched output and FAILS
# the diff. The cases exercise distinct paths: the XHTML state machine (src/xhtml.c — bold/italic ANSI,
# HTML entities &amp;/&lt;/&gt;/&#169;/&#160;/&#8212;), the noansi/raw render modes, and the bundled
# sxmlc DOM parser over the OPF metadata (--meta dumps Title/Language/Identifier).
set -uo pipefail

# clang/gcc reject SOURCE_DATE_EPOCH='' (empty); must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"

# SRC is /mayhem in the commit image; default to this checkout's repo root so the suite also runs
# straight from a developer checkout (mayhem/ is one level below the repo root).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${SRC:=$(cd "$HERE/.." && pwd)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
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

GOLDEN="$SRC/mayhem/testdata/golden"
EPUBSRC="$SRC/mayhem/testdata/epub_src"
[ -d "$GOLDEN" ] || { echo "missing golden dir $GOLDEN — wrong tree?" >&2; emit_ctrf "epub2txt2-golden" 0 1; exit 2; }
[ -f "$EPUBSRC/mimetype" ] || { echo "missing EPUB component sources under $EPUBSRC — wrong tree?" >&2; emit_ctrf "epub2txt2-golden" 0 1; exit 2; }

command -v zip   >/dev/null 2>&1 || { echo "test.sh: 'zip' not found (needed to assemble the test EPUB)" >&2;   emit_ctrf "epub2txt2-golden" 0 1; exit 2; }
command -v unzip >/dev/null 2>&1 || { echo "test.sh: 'unzip' not found (epub2txt shells out to it)" >&2;        emit_ctrf "epub2txt2-golden" 0 1; exit 2; }

# Build epub2txt2 INDEPENDENTLY with the project's NORMAL flags (NOT the sanitizer/fuzz build). The
# Makefile's default target links the `epub2txt` CLI from the -O3 gcc objects. `make -B` forces a
# fresh compile so stale objects can't mask a build regression. We stage the binary to a private path
# (BIN) so the oracle is independent of whatever mayhem/build.sh produced (it builds /mayhem/*-fuzz).
: "${CC:=gcc}"
export CC
BIN="$SRC/epub2txt-test"
make -B -j"$MAYHEM_JOBS" CC="$CC" >/tmp/epub2txt-test-build.log 2>&1 || {
  echo "test.sh: normal-flags build failed:" >&2; tail -40 /tmp/epub2txt-test-build.log >&2
  emit_ctrf "epub2txt2-golden" 0 1; exit 2
}
[ -x "$SRC/epub2txt" ] || { echo "test.sh: build produced no ./epub2txt" >&2; emit_ctrf "epub2txt2-golden" 0 1; exit 2; }
cp -f "$SRC/epub2txt" "$BIN"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Assemble the test EPUB from the committed component files, per the EPUB OCF rules: `mimetype`
# stored uncompressed FIRST, then the rest added. Done in a subshell so the cd doesn't leak.
EPUB="$WORK/book.epub"
(
  cd "$EPUBSRC" || exit 1
  zip -X -0 "$EPUB" mimetype >/dev/null    || exit 1
  zip -X -rg "$EPUB" META-INF OEBPS >/dev/null
) || { echo "test.sh: failed to assemble test EPUB" >&2; emit_ctrf "epub2txt2-golden" 0 1; exit 2; }
[ -f "$EPUB" ] || { echo "test.sh: test EPUB not produced" >&2; emit_ctrf "epub2txt2-golden" 0 1; exit 2; }

passed=0; failed=0

# run_case <name> <epub2txt flags...>
# Runs `epub2txt <flags> book.epub`, diffs stdout against mayhem/testdata/golden/<name>.txt. The CLI
# MUST exit 0 AND match the golden byte-for-byte, else the case fails.
run_case() {
  local name="$1"; shift
  local gold="$GOLDEN/$name.txt" got="$WORK/$name.txt" rc
  if [ ! -f "$gold" ]; then
    echo "FAIL $name: missing golden $gold" >&2; failed=$((failed+1)); return
  fi
  "$BIN" "$@" "$EPUB" > "$got" 2>"$WORK/$name.err"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "FAIL $name: epub2txt $* exited $rc (expected 0)" >&2
    sed 's/^/    /' "$WORK/$name.err" >&2
    failed=$((failed+1)); return
  fi
  if diff -u "$gold" "$got" > "$WORK/$name.diff" 2>&1; then
    echo "PASS $name"; passed=$((passed+1))
  else
    echo "FAIL $name: output differs from golden" >&2
    head -20 "$WORK/$name.diff" | sed 's/^/    /' >&2
    failed=$((failed+1))
  fi
}

# Documented CLI invocations against the assembled test book.
run_case default            # full render: ANSI bold/italic + UTF-8 entities, both spine chapters
run_case noansi  -n         # --noansi: same text, ANSI terminal codes suppressed
run_case raw     -r         # --raw: no formatting at all
run_case meta    -m -n      # --meta: dump OPF metadata (sxmlc DOM parser) then body

emit_ctrf "epub2txt2-golden" "$passed" "$failed"
