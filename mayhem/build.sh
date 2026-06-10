#!/usr/bin/env bash
#
# mayhem/build.sh — build epub2txt2's IN-PROCESS XML/XHTML parser as a libFuzzer target.
#
# WHY NOT THE CLI: epub2txt2 is a small C program that extracts text from an EPUB. The CLI does
# NOT read the input itself — epub2txt_do_file() shells out to the system `unzip` binary
# (src/epub2txt.c -> run_command{"unzip",...}) to expand the EPUB into a tempdir, so only the
# unzip *child* reads the file. A `epub2txt @@` Mayhem target therefore never touches the input
# ("the target isn't reading inputs") and the campaign can't progress.
#
# WHAT WE FUZZ INSTEAD: the genuinely interesting surface is the in-process parsing epub2txt runs
# over the already-unzipped documents — the bundled sxmlc DOM parser (src/sxmlc.c, used for
# container.xml / the OPF) and the hand-rolled XHTML state machine (src/xhtml.c, xhtml_to_stdout /
# xhtml_file_to_stdout, which renders each spine document). mayhem/fuzz_epub2txt.c is an
# in-process libFuzzer harness that feeds the fuzz bytes straight to those parsers (XHTML via the
# real per-spine-file handler xhtml_file_to_stdout on a temp file; sxmlc via XMLDoc_parse_buffer_DOM
# on the buffer). No fork, no unzip — the monitored process reads and parses the input itself.
#
# Builds (both ASan+UBSan-instrumented so we find defects in epub2txt2's OWN code, not the harness):
#   /mayhem/epub2txt-fuzz             libFuzzer (-fsanitize=fuzzer)            <- the Mayhem target
#   /mayhem/epub2txt-fuzz-standalone  StandaloneFuzzTargetMain.c reproducer   <- replays one input
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image exports
# the build contract — CC, CXX, SANITIZER_FLAGS, LIB_FUZZING_ENGINE, STANDALONE_FUZZ_MAIN, SRC,
# MAYHEM_JOBS.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs from the ENVIRONMENT, overridable. SANITIZER_FLAGS uses `=` (not `:=`) so an
# explicit empty `--build-arg SANITIZER_FLAGS=` builds with NO sanitizers (natural crash).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${CC:=clang}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"

# Benign-UB relax (only when UBSan's `function` check is active): the bundled sxmlc XML parser
# (src/sxmlc.c) calls helper readers through a generic function-pointer type that doesn't match
# their definitions (e.g. _bgetc as `int(*)(void*)`). UBSan's `function` check aborts on this for
# EVERY input — including valid XML — which would halt the fuzzer before it explores anything.
# This is the classic "ubiquitous benign UB floods under halting UBSan" case (cf. genometools,
# swftools). Relax ONLY `function`, keeping ASan + the rest of UBSan on and halting so real memory
# and UB defects still crash. (No-op when sanitizers are disabled via empty SANITIZER_FLAGS.)
case " $SANITIZER_FLAGS " in
  *undefined*) SANITIZER_FLAGS="$SANITIZER_FLAGS -fno-sanitize=function" ;;
esac
export SANITIZER_FLAGS CC LIB_FUZZING_ENGINE MAYHEM_JOBS

cd "$SRC"

# Build the PROJECT ITSELF instrumented with $SANITIZER_FLAGS so the fuzzed code (the XHTML/OPF
# parser) is sanitized — not just the harness. The upstream Makefile threads EXTRA_CFLAGS into
# CFLAGS; build all object files there. We don't need the `epub2txt` CLI link (it shells out to
# unzip) — just the instrumented .o's, which we link into the harness binaries below.
make clean >/dev/null 2>&1 || true
make -j"$MAYHEM_JOBS" CC="$CC" EXTRA_CFLAGS="$SANITIZER_FLAGS" \
     $(find src -name '*.c' | sed 's#^src/#build/#; s#\.c$#.o#')

# Collect every project object EXCEPT main.o (the CLI entry point with its own main()). The harness
# provides LLVMFuzzerTestOneInput; libFuzzer / StandaloneFuzzTargetMain.c provide main().
OBJS=$(find build -name '*.o' ! -name 'main.o')
test -n "$OBJS" || { echo "build.sh: no instrumented objects produced" >&2; exit 1; }

# APPNAME/VERSION are -D'd by the Makefile for the project .c's; the harness doesn't need them, but
# pass APPNAME so any shared header that references it is happy.
HCFLAGS="$SANITIZER_FLAGS -I src -DAPPNAME=\"epub2txt\" -DVERSION=\"fuzz\""

# 1) libFuzzer target — KEEP THE NAME `epub2txt-fuzz` for run continuity.
# shellcheck disable=SC2086
$CC $HCFLAGS $LIB_FUZZING_ENGINE \
    mayhem/fuzz_epub2txt.c $OBJS \
    -o /mayhem/epub2txt-fuzz
test -x /mayhem/epub2txt-fuzz || { echo "build.sh: epub2txt-fuzz not produced" >&2; exit 1; }

# 2) standalone reproducer — same harness + LLVM's standalone main (no fuzzing engine). Compile the
# driver as C ($CC) so its LLVMFuzzerTestOneInput reference keeps C linkage.
$CC $SANITIZER_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o
# shellcheck disable=SC2086
$CC $HCFLAGS /tmp/standalone_main.o \
    mayhem/fuzz_epub2txt.c $OBJS \
    -o /mayhem/epub2txt-fuzz-standalone
test -x /mayhem/epub2txt-fuzz-standalone || { echo "build.sh: epub2txt-fuzz-standalone not produced" >&2; exit 1; }

# Seed corpus: minimal VALID XHTML documents fed straight to the in-process parser (NO zip layer).
# Lands at /mayhem/seeds/, referenced by the Mayhemfile testsuite as file:/// URIs.
SEEDDIR="$SRC/seeds"
mkdir -p "$SEEDDIR"
cat > "$SEEDDIR/seed.xhtml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Seed</title></head>
<body><h1>Heading</h1><p>hello <b>epub</b> world &amp; &#9731; <i>italic</i></p>
<ruby>x<rt>y</rt></ruby></body></html>
XML
cat > "$SEEDDIR/seed.opf" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Seed</dc:title>
    <dc:language>en</dc:language>
    <dc:identifier id="bookid">seed-0001</dc:identifier>
  </metadata>
  <manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/></manifest>
  <spine><itemref idref="ch1"/></spine>
</package>
XML
test -f "$SEEDDIR/seed.xhtml" || { echo "build.sh: seed corpus not produced" >&2; exit 1; }

echo "build.sh: built /mayhem/epub2txt-fuzz (+ -standalone) and seed corpus in $SEEDDIR"
