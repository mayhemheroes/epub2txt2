# Prepare Patch Command

## Description
Prepare the repository for patching by creating a single-stage Dockerfile.rlenv and extracting build steps to build.sh.

## Your Task

Create two files:
1. **Dockerfile.rlenv** - Single-stage build with all dependencies and build tools
2. **rlenv/mayhem/data/scripts/build.sh** - Rebuild script (update the existing template)

## Step 1: Analyze the Original Dockerfile

First, examine the original Dockerfile (usually in `mayhem/Dockerfile` or `Dockerfile`) and identify:

### Required Information
- [ ] **Base images**: All FROM stages (e.g., FROM golang:1.18 AS builder, FROM debian:bookworm)
- [ ] **Dependencies**: Every apt-get/apk/yum install command across ALL stages
- [ ] **Language dependencies**: go get, cargo install, npm install, pip install, etc.
- [ ] **Build commands**: RUN commands that compile/build the application
- [ ] **Environment variables**: All ENV directives needed for building
- [ ] **Target executable**: Where the final binary is placed (check metadata.json or Mayhemfile)
- [ ] **Multi-stage artifacts**: Any COPY --from operations between stages
- [ ] **Special preprocessing**: Any sed/awk commands that modify source files

## Step 2: Create Dockerfile.rlenv

**CRITICAL: Follow this exact structure and ordering:**

```dockerfile
# ============================================================================
# 1. Base Image Selection
# ============================================================================
FROM <choose-appropriate-base>

# Common base images by language:
# - Go (OSS-Fuzz): gcr.io/oss-fuzz-base/base-builder-go
# - Rust (cargo-fuzz): ghcr.io/evanrichter/cargo-fuzz OR rustlang/rust:nightly
# - C/C++ (simple): debian:bookworm OR ubuntu:20.04
# - C/C++ (OSS-Fuzz): gcr.io/oss-fuzz-base/base-builder
# - Use --platform=linux/amd64 if building on ARM Mac

# ============================================================================
# 2. System Dependencies (merge ALL stages from original Dockerfile)
# ============================================================================
RUN apt-get update && apt-get install -y \\
    <all-build-dependencies-from-all-stages> \\
    <all-runtime-dependencies-from-all-stages> \\
    jq \\
    && rm -rf /var/lib/apt/lists/*

# REQUIRED: jq is used by validate.sh to parse metadata.json
# Merge ALL apt-get/apk/yum commands from original Dockerfile

# ============================================================================
# 3. Copy MTV Binary (REQUIRED - used by validate.sh)
# ============================================================================
COPY --from="us-east4-docker.pkg.dev/forallsecure-1/rlenv-staging/rlenv-mcp-static:latest" \\
     /rlenv/bin/mtv /rlenv/bin/mtv

# MTV (Mayhem Test & Verify) is required for validation and crash triage

# ============================================================================
# 4. Language-Specific Setup
# ============================================================================
# Set environment variables from original Dockerfile
# Examples:
# ENV FUZZING_LANGUAGE=go
# ENV SANITIZER=address
# ENV FUZZING_ENGINE=libfuzzer
# ENV PATH="/root/.go/bin:/root/go/bin:${PATH}"
# ENV GOCACHE="/root/.cache/go-build"
# ENV GOMODCACHE="/root/go/pkg/mod"
# ENV CARGO_HOME=/opt/rust/cargo
# ENV RUSTUP_HOME=/opt/rust/rustup

# ============================================================================
# 5. Copy Source Code (EARLY - source exists now)
# ============================================================================
COPY . /rlenv/source/<project-name>/

# IMPORTANT: Use actual project name from metadata.json
# This copies the entire repository to /rlenv/source/<project>/

# ============================================================================
# 6. Make Source World-Writable (REQUIRED for non-root rebuilds)
# ============================================================================
RUN chmod -R 777 /rlenv/source

# Why 777? Validation runs as UID 1000 (unprivileged user)
# Must be able to modify source code and rebuild

# ============================================================================
# 7. Set Working Directory
# ============================================================================
WORKDIR /rlenv/source/<project-name>/

# All subsequent RUN commands execute from this directory

# ============================================================================
# 8. Install Language Dependencies (if any)
# ============================================================================
# Examples:
# RUN go get github.com/AdamKorcz/go-118-fuzz-build/testing
# RUN cargo fetch
# RUN npm install
# RUN pip install -r requirements.txt

# ============================================================================
# 9. Build Application (extract from original Dockerfile)
# ============================================================================
# Copy build commands from original Dockerfile
# For Go with compile_native_go_fuzzer, use two-stage build pattern:
# RUN compile_native_go_fuzzer ... || true
# RUN if [ -f path/to/generated_fuzz.go ]; then \\
#       sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated_fuzz.go; \\
#     fi
# RUN compile_native_go_fuzzer ...

# For Rust:
# RUN cargo +nightly fuzz build --dev
# OR
# RUN cargo +nightly hfuzz build

# For C/C++:
# RUN make
# OR
# RUN mkdir build && cd build && cmake .. && make

# ============================================================================
# 10. Copy Artifacts to Expected Locations (if needed)
# ============================================================================
# If original Dockerfile copies artifacts to specific paths:
# RUN cp target/debug/fuzzer /fuzzer
# RUN cp build/executable /out/executable

# Check metadata.json for target_executable path
# Ensure artifact ends up at correct location

# ============================================================================
# 11. Permission Management (REQUIRED)
# ============================================================================
# Target executable (rwxrw-rw-)
RUN chmod 766 <target-executable-path>

# Build output directory
RUN chmod -R 777 /out 2>/dev/null || true

# Language-specific caches (for offline rebuilds)
RUN chmod -R 777 /root/.cache 2>/dev/null || true

# For Go: Make Go toolchain accessible to non-root users
# RUN chmod 777 /root && \\
#     chmod -R 777 /root/.go /root/go 2>/dev/null || true

# For Rust (global install): Make Rust accessible to all users
# RUN chmod -R 755 /opt/rust

# ============================================================================
# 12. Copy rlenv Directory (MUST BE NEAR END - doesn't exist yet!)
# ============================================================================
COPY rlenv /rlenv

# CRITICAL: This directory doesn't exist when you create this Dockerfile
# It's populated later by the `rlenv patch` command
# That's why it must come AFTER source copy and build

# ============================================================================
# 13. Final Permission Fix (REQUIRED)
# ============================================================================
RUN chmod -R 777 /rlenv/source

# Ensures source remains writable after rlenv directory copy

# ============================================================================
# 14. Set Entry Point
# ============================================================================
CMD ["<target-executable-path>"]

# Use the same path as in metadata.json

# ============================================================================
# 15. Reset Working Directory
# ============================================================================
WORKDIR /
```

### Critical Requirements Checklist

Before considering Dockerfile.rlenv complete, verify:

**Dependencies:**
- [ ] ALL apt-get/apk/yum commands from ALL stages merged
- [ ] jq installed (required)
- [ ] Language-specific tools installed (compilers, build tools)

**MTV Binary:**
- [ ] `COPY --from=...rlenv-mcp-static... /rlenv/bin/mtv` present

**Ordering:**
- [ ] `COPY . /rlenv/source/<project>/` comes EARLY
- [ ] `COPY rlenv /rlenv` comes LATE (before final permission fix)

**Permissions:**
- [ ] `chmod -R 777 /rlenv/source` (appears twice: after source copy and at end)
- [ ] `chmod 766 <target-executable>`
- [ ] `chmod -R 777 /out` (or wherever build artifacts go)
- [ ] Language-specific cache directories chmod 777 (Go) or 755 (Rust)

**Path Consistency:**
- [ ] Target executable path matches metadata.json
- [ ] All paths are absolute (no relative paths)

## Step 3: Update build.sh

Update the template at `rlenv/mayhem/data/scripts/build.sh`:

```bash
#!/bin/bash
set -euo pipefail

# RLENV Build Script
# This script rebuilds the application from source located at /rlenv/source/<project>/
#
# Original image: <from metadata.json>
# Git revision: <from metadata.json>

# ============================================================================
# Environment Variables (copy from Dockerfile.rlenv)
# ============================================================================
# Export same environment variables as in Dockerfile.rlenv

# For Go:
# export PATH="/root/.go/bin:/root/go/bin:${PATH}"
# export PATH="${PATH//\\/rlenv\\/bin:/}"  # Remove /rlenv/bin if present
# export PATH="${PATH//\\/rlenv\\/bin/}"
# export GOPATH="${GOPATH:-/root/go}"
# export GOCACHE="/root/.cache/go-build"
# export GOMODCACHE="/root/go/pkg/mod"
# export GOFLAGS="${GOFLAGS:-} -buildvcs=false"  # Prevent Git errors

# For Rust (global):
# export RUSTUP_HOME=/opt/rust/rustup
# export CARGO_HOME=/opt/rust/cargo
# export PATH="/opt/rust/cargo/bin:${PATH}"

# For C/C++ (OSS-Fuzz style):
# export CXX=clang++
# export CXXFLAGS="-fsanitize=address"
# export LIB_FUZZING_ENGINE="-fsanitize=fuzzer"

# ============================================================================
# REQUIRED: Change to Source Directory
# ============================================================================
cd /rlenv/source/<project-name>/

# ============================================================================
# Clean Previous Build (recommended)
# ============================================================================
# Remove old build artifacts to ensure fresh rebuild
# Examples:
# rm -f *.a *.o
# rm -f <target-executable>
# rm -rf build/

# ============================================================================
# Build Commands (NO NETWORK, NO PACKAGE INSTALLATION)
# ============================================================================
# Extract ONLY the build commands from Dockerfile.rlenv
# DO NOT include:
# - apt-get/apk/yum (dependencies already installed)
# - go get/cargo install (dependencies already fetched)
# - curl/wget (no network access)

# For Go:
# compile_native_go_fuzzer ... || true
# if [ -f path/to/generated_fuzz.go ]; then
#     sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated_fuzz.go
# fi
# compile_native_go_fuzzer ...

# For Rust (cargo-fuzz):
# cargo +nightly fuzz build --dev
# OR cargo +nightly fuzz build

# For Rust (honggfuzz):
# RUSTFLAGS="-Cpasses=sancov-module -Clink-arg=-fuse-ld=lld" \\
#     cargo +nightly hfuzz build

# For C/C++ (make):
# make clean
# make

# For C/C++ (cmake):
# rm -rf build
# mkdir build && cd build
# cmake .. -DCMAKE_BUILD_TYPE="Release"
# make -j1

# ============================================================================
# Copy Artifacts (use 'cat >' for busybox compatibility)
# ============================================================================
# If build artifacts need to be copied to specific locations:
# cat target/debug/fuzzer > /fuzzer
# cat build/executable > /out/executable

# IMPORTANT: Use 'cat >' instead of 'cp' for busybox compatibility
# busybox cp may fail when overwriting files

# ============================================================================
# Set Permissions
# ============================================================================
chmod 777 <target-executable> 2>/dev/null || true

# 777 allows validation script (running as UID 1000) to overwrite during rebuild
# 2>/dev/null || true prevents errors if chmod not available

# ============================================================================
# REQUIRED: Verify Build Succeeded
# ============================================================================
if [ ! -f <target-executable> ]; then
    echo "Error: Build artifact not found at <target-executable>"
    exit 1
fi

# Optional: Verify executable bit
# if [ ! -x <target-executable> ]; then
#     echo "Warning: Build artifact is not executable"
# fi

# Optional: Verify file size
# SIZE=$(stat -c%s <target-executable> 2>/dev/null || stat -f%z <target-executable> 2>/dev/null || echo 0)
# if [ "$SIZE" -lt 1000 ]; then
#     echo "Warning: Build artifact is suspiciously small ($SIZE bytes)"
# fi

echo "Build completed successfully: <target-executable>"
```

### build.sh Critical Constraints

**FORBIDDEN (will cause validation failure):**
- ❌ Network access: `go get`, `cargo install`, `apt-get`, `curl`, `wget`, `git clone`
- ❌ Package installation: `apt-get install`, `apk add`, `yum install`, `pip install`
- ❌ Running on host machine: Only runs inside container

**REQUIRED:**
- ✅ Start with: `cd /rlenv/source/<project>/`
- ✅ Set error handling: `set -euo pipefail`
- ✅ Export environment variables (same as Dockerfile)
- ✅ Use `cat >` instead of `cp` for artifact copying
- ✅ Verify artifact exists before exit
- ✅ All dependencies pre-installed in Dockerfile.rlenv

## Common Edge Cases to Handle

### 1. Go "reflect imported and not used" (20% of Go projects)
If using `compile_native_go_fuzzer`, use two-stage build:
```dockerfile
RUN compile_native_go_fuzzer ... || true
RUN if [ -f path/to/generated.go ]; then \\
      sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated.go; \\
    fi
RUN compile_native_go_fuzzer ...
```

### 2. Rust Cargo.lock conflicts
If Cargo.lock has version conflicts:
```dockerfile
RUN rm -f Cargo.lock fuzz/Cargo.lock
RUN cargo +nightly -Z sparse-registry fuzz build
```

### 3. Old Debian GPG keys
If base image has expired GPG keys:
```dockerfile
RUN apt-get update --allow-insecure-repositories 2>/dev/null || true
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys \\
    648ACFD622F3D138 0E98404D386FA1D9
RUN apt-get update
```

### 4. Platform mismatches (ARM Mac)
If building on ARM Mac for x86_64:
```dockerfile
FROM --platform=linux/amd64 <base-image>
```

### 5. Go VCS stamping errors
In build.sh:
```bash
export GOFLAGS="-buildvcs=false"
```

### 6. GNU grep requirement (Go projects)
If using compile_native_go_fuzzer:
```dockerfile
RUN apt-get install -y grep findutils && \\
    grep --version 2>&1 | grep -q "GNU grep" || exit 1
```

## Language-Specific Quick References

### Go (OSS-Fuzz):
- Base: `gcr.io/oss-fuzz-base/base-builder-go`
- Install: `jq grep findutils`
- Deps: `go get github.com/AdamKorcz/go-118-fuzz-build/testing`
- Build: `compile_libfuzzer && compile_native_go_fuzzer`
- Perms: `chmod 777 /root /root/.go /root/go /root/.cache`

### Rust (cargo-fuzz):
- Base: `ghcr.io/evanrichter/cargo-fuzz` or `rustlang/rust:nightly`
- Install: `jq`
- Build: `cargo +nightly fuzz build --dev` (or without --dev)
- Location: `fuzz/target/.../debug/` or `.../release/`

### Rust (honggfuzz):
- Base: `rustlang/rust:nightly`
- Install: `build-essential binutils-dev libunwind-dev libblocksruntime-dev liblzma-dev jq`
- Global: `ENV RUSTUP_HOME=/opt/rust/rustup CARGO_HOME=/opt/rust/cargo`
- Build: `RUSTFLAGS="-Cpasses=sancov-module" cargo +nightly hfuzz build`
- Perms: `chmod -R 755 /opt/rust`

### C/C++ (Make):
- Base: `debian:bookworm` or `ubuntu:20.04`
- Install: `build-essential clang make jq`
- Build: `make`

### C/C++ (CMake):
- Base: `ubuntu:22.04`
- Install: `build-essential cmake clang jq`
- Build: `mkdir build && cd build && cmake .. && make`

## Final Checklist

Before marking this command complete:

**Dockerfile.rlenv:**
- [ ] Created in repository root
- [ ] Single-stage build (all FROM stages merged)
- [ ] MTV binary included
- [ ] jq installed
- [ ] Source copied to `/rlenv/source/<project>/`
- [ ] Source is chmod 777 (twice: after source copy and at end)
- [ ] rlenv directory copied LATE
- [ ] Target executable path matches metadata.json
- [ ] All permissions set (777 for directories, 766 for executable)
- [ ] CMD points to correct executable

**build.sh:**
- [ ] Updated template (don't overwrite existing content carelessly)
- [ ] Shebang: `#!/bin/bash`
- [ ] Error handling: `set -euo pipefail`
- [ ] Environment variables exported
- [ ] Working directory: `cd /rlenv/source/<project>/`
- [ ] NO network access (no go get, cargo install, apt-get, curl, wget)
- [ ] NO package installation
- [ ] Build commands extracted from Dockerfile
- [ ] Uses `cat >` instead of `cp` for artifact copying
- [ ] Artifact verification before exit
- [ ] Success message at end

**Common Mistakes to Avoid:**
- ❌ Copying rlenv directory before source (wrong order)
- ❌ Forgetting chmod 777 on /rlenv/source
- ❌ Using cp instead of cat > (busybox issue)
- ❌ Including apt-get/go get/cargo install in build.sh
- ❌ Forgetting MTV binary
- ❌ Forgetting jq installation
- ❌ Target executable path mismatch

## Output

1. Create `Dockerfile.rlenv` in repository root
2. Update `rlenv/mayhem/data/scripts/build.sh`

DO NOT build or test the image as part of this command. That will be done separately via `rlenv patch`.

Refer to CLAUDE.md for additional context, edge cases, and language-specific examples.
