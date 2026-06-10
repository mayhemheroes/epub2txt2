# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile (SMALL form) — builds ON TOP of the org C/C++ base image
# (ghcr.io/mayhemheroes/base), which provides debian + clang/llvm + libFuzzer/afl++ +
# the identities + the build-contract ENV. This only adds the per-commit epub2txt2 build.
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) \
#       [--build-arg SOURCE_DATE_EPOCH=$(date +%s)] \
#       -t mytag .

FROM ghcr.io/mayhemheroes/base:2026-06

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (available to build.sh); do NOT bake it as an ENV — an empty
# value breaks clang. build.sh unsets it when empty.
ARG SOURCE_DATE_EPOCH

# Sanitizer override: base exports SANITIZER_FLAGS (ASan+UBSan, halting) as the default. Declare
# WITHOUT a default so an unset arg lets the base ENV flow through; --build-arg overrides it.
ARG SANITIZER_FLAGS
ARG MAYHEM_JOBS=

# The Mayhem fuzz target is an IN-PROCESS libFuzzer harness over epub2txt2's XML/XHTML parsers
# (mayhem/fuzz_epub2txt.c) — it never forks to unzip and its seed corpus is plain XHTML/OPF (not a
# ZIP), so the fuzz path itself needs no zip tooling. BUT the functional golden oracle (mayhem/test.sh)
# DOES drive the real `epub2txt` CLI, which shells out to `unzip` to unpack an EPUB; the oracle also
# `zip`s its reviewable component files into the test .epub at runtime. Install both so the test gate
# below can run in the commit image. (Harmless to the fuzz build.)
USER root
RUN apt-get update && apt-get install -y --no-install-recommends zip unzip && rm -rf /var/lib/apt/lists/*
USER mayhem

# Source enters from the build CONTEXT (the CI checkout): the FULL repo (incl. .git history) is
# copied to /mayhem as `mayhem`; build.sh builds in place.
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN bash mayhem/build.sh

# Run the project's functional tests at build time IF the repo ships them. epub2txt2 upstream ships
# no functional suite, so we authored mayhem/test.sh — a golden / known-answer oracle that builds the
# CLI with normal flags, assembles a test EPUB, and diffs the extracted text against committed goldens.
# It exits non-zero on any mismatch, failing the image build.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh — repo ships no functional tests"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
