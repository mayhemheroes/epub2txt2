# RLENV Patch Playground

## Run Information
- Mayhem Run: mayhemheroes/epub2txt2/epub2txt-fuzz/3
- Git Commit: 5890b9b89670524c4ca906866475d6cec0f9556d
- Original Image: ghcr.io/mayhemheroes/epub2txt2:master
- Target Executable: /epub2txt
- CI URL: https://github.com:443/mayhemheroes/epub2txt2/actions/runs/2884437224

## Build Configuration
- Dockerfile: Dockerfile
- Build Context: .
- Build Command: `docker build -f Dockerfile .`

## Directory Structure After `rlenv patch`

After running `rlenv patch`, the repository will have this structure:
```
epub2txt2/
├── Dockerfile.rlenv          # Single-stage patch playground (YOU CREATE THIS)
├── rlenv/
│   ├── metadata.json         # Run metadata
│   ├── problem/
│   │   ├── id               # Problem ID or "nodata"
│   │   ├── type             # "patch"
│   │   └── prompt           # LLM patching instructions
│   ├── mayhem/
│   │   ├── meta             # Mayhem metadata (JSON)
│   │   ├── url              # Mayhem run URL
│   │   └── data/
│   │       ├── scripts/
│   │       │   ├── build.sh      # Rebuild script (YOU CREATE THIS)
│   │       │   └── validate.sh   # MTV-based validation (auto-generated)
│   │       └── testsuite/        # Downloaded during `rlenv patch`
│   │           ├── all/          # All test cases (SHA256 named)
│   │           ├── crashing/     # Symlinks to crashing tests
│   │           ├── testsuite/    # Symlinks to non-crashing tests
│   │           ├── defects/      # Organized by defect ID
│   │           └── metadata/     # Per-testcase JSON metadata
│   └── source/
│       ├── commit           # Git commit hash
│       └── license          # License name
└── .claude/
    ├── config.json
    └── commands/
        └── prepare-patch.md
```

**Inside the Docker container**, paths are:
- Source code: `/rlenv/source/epub2txt2/`
- Test cases: `/rlenv/mayhem/data/testsuite/`
- MTV binary: `/rlenv/bin/mtv`
- Mayhemfile: `/rlenv/source/Mayhemfile`
- Target executable: `/epub2txt`

## Your Tasks

### 1. Analyze the Original Dockerfile

Look at `Dockerfile` and identify:
- **Base images**: All FROM stages
- **Dependencies**: Every apt-get/apk/yum/cargo install command
- **Build commands**: RUN commands that compile/build (not just install)
- **Environment variables**: All ENV directives
- **Target executable**: Where the final binary is placed
- **Multi-stage artifacts**: COPY --from operations

### 2. Create Dockerfile.rlenv (Single-Stage Build)

**CRITICAL ORDERING - Follow this exact structure:**

```dockerfile
# 1. Base Image Selection
FROM <appropriate-base-image>

# 2. System Dependencies (merge ALL stages)
RUN apt-get update && apt-get install -y \\
    <all-build-dependencies> \\
    <all-runtime-dependencies> \\
    jq \\
    && rm -rf /var/lib/apt/lists/*

# 3. Copy MTV Binary (REQUIRED for validation)
COPY --from="us-east4-docker.pkg.dev/forallsecure-1/rlenv-staging/rlenv-mcp-static:latest" \\
     /rlenv/bin/mtv /rlenv/bin/mtv

# 4. Language-Specific Setup
ENV FUZZING_LANGUAGE=<language>
ENV PATH="<toolchain-paths>:${PATH}"

# 5. Copy Source Code
COPY . /rlenv/source/epub2txt2/

# 6. Make Source World-Writable (REQUIRED)
RUN chmod -R 777 /rlenv/source

# 7. Set Working Directory
WORKDIR /rlenv/source/epub2txt2/

# 8. Install Language Dependencies
RUN <go get / cargo fetch / npm install>

# 9. Build Application
RUN <build-commands>

# 10. Copy Artifacts to Expected Locations
RUN cp <build-artifact> /epub2txt

# 11. Permission Management (REQUIRED)
RUN chmod 766 /epub2txt
RUN chmod -R 777 /out 2>/dev/null || true
RUN chmod -R 777 /root/.cache 2>/dev/null || true

# 12. Copy rlenv Directory (MUST BE NEAR END)
# This directory doesn't exist yet - it's populated by `rlenv patch`
COPY rlenv /rlenv

# 13. Final Permission Fix (REQUIRED)
RUN chmod -R 777 /rlenv/source

# 14. Set Entry Point
CMD ["/epub2txt"]

# 15. Reset Working Directory
WORKDIR /
```

**Why this order matters:**
- `COPY . /rlenv/source/epub2txt2/` happens early (source exists)
- `COPY rlenv /rlenv` happens late (populated by `rlenv patch` command)

### 3. Create/Update build.sh

Extract build commands into `rlenv/mayhem/data/scripts/build.sh`:

```bash
#!/bin/bash
set -euo pipefail

# RLENV Build Script
# Original image: ghcr.io/mayhemheroes/epub2txt2:master
# Git revision: 5890b9b89670524c4ca906866475d6cec0f9556d

# Export environment variables (if needed)
export PATH="/root/.go/bin:/root/go/bin:${PATH}"  # Go example
export GOCACHE="/root/.cache/go-build"
export GOMODCACHE="/root/go/pkg/mod"
export GOFLAGS="-buildvcs=false"

# REQUIRED: Change to source directory
cd /rlenv/source/epub2txt2/

# Clean previous build (recommended)
rm -f *.a /epub2txt

# Build commands (NO apt-get, NO go get, NO cargo install, NO network)
<actual-build-commands>

# Copy artifacts (use 'cat >' for busybox compatibility)
cat build/fuzzer > /epub2txt
chmod 777 /epub2txt 2>/dev/null || true

# REQUIRED: Verify build succeeded
if [ ! -f /epub2txt ]; then
    echo "Error: Build artifact not found"
    exit 1
fi

echo "Build completed successfully"
```

**CRITICAL CONSTRAINTS:**
- ❌ NO network access (no go get, cargo install, apt-get, curl, wget)
- ❌ NO package installation (dependencies go in Dockerfile.rlenv)
- ❌ NO running on host (only runs inside container)
- ✅ All dependencies pre-installed in Dockerfile.rlenv
- ✅ Use `cat >` instead of `cp` for busybox compatibility
- ✅ Must work from `/rlenv/source/epub2txt2/`

## Critical Requirements Checklist

### Permissions (REQUIRED)
- [ ] Source directory: `chmod -R 777 /rlenv/source`
- [ ] Target executable: `chmod 766 /epub2txt`
- [ ] Build output dir: `chmod -R 777 /out` (or wherever artifacts go)
- [ ] Go cache (if Go): `chmod -R 777 /root/.cache /root/.go /root/go`
- [ ] Rust cache (if Rust): `chmod -R 755 /opt/rust`

**Why 777?** Validation runs as unprivileged user (UID 1000). Without write access, rebuilds fail.

### MTV Binary (REQUIRED)
- [ ] Must include: `COPY --from="us-east4-docker.pkg.dev/forallsecure-1/rlenv-staging/rlenv-mcp-static:latest" /rlenv/bin/mtv /rlenv/bin/mtv`
- [ ] Used by validate.sh for crash triage

### jq Installation (REQUIRED)
- [ ] Must install jq: `apt-get install -y jq`
- [ ] Used by validate.sh to parse metadata.json

### Path Consistency (REQUIRED)
- [ ] Target executable in Dockerfile.rlenv: `/epub2txt`
- [ ] Target executable in build.sh: `/epub2txt`
- [ ] Target executable in metadata.json: `/epub2txt`
- [ ] All must match for validation to work

### COPY Order (REQUIRED)
- [ ] `COPY . /rlenv/source/epub2txt2/` - EARLY (source exists now)
- [ ] `COPY rlenv /rlenv` - LATE (populated by `rlenv patch` later)

## Language-Specific Patterns

### Go (OSS-Fuzz with compile_native_go_fuzzer)

**Base Image:** `gcr.io/oss-fuzz-base/base-builder-go`

**Dockerfile.rlenv additions:**
```dockerfile
# Install GNU grep (compile_native_go_fuzzer needs it, not busybox grep)
RUN apt-get update && apt-get install -y jq grep findutils && \\
    rm -rf /var/lib/apt/lists/* && \\
    grep --version 2>&1 | grep -q "GNU grep" || (echo "ERROR: GNU grep not installed" && exit 1)

ENV FUZZING_LANGUAGE=go
ENV SANITIZER=address
ENV FUZZING_ENGINE=libfuzzer
ENV PATH="/root/.go/bin:/root/go/bin:${PATH}"
ENV GOCACHE="/root/.cache/go-build"
ENV GOMODCACHE="/root/go/pkg/mod"

WORKDIR /rlenv/source/epub2txt2/
RUN go get github.com/AdamKorcz/go-118-fuzz-build/testing
RUN compile_libfuzzer

# Two-stage build for "reflect imported and not used" issue
RUN compile_native_go_fuzzer ... || true
RUN if [ -f path/to/generated_fuzz.go ]; then \\
      sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated_fuzz.go; \\
    fi
RUN compile_native_go_fuzzer ...

# Make Go toolchain accessible to non-root
RUN chmod 777 /root && chmod -R 777 /root/.go /root/go 2>/dev/null || true
RUN chmod -R 777 /root/.cache 2>/dev/null || true
```

**build.sh additions:**
```bash
export PATH="/root/.go/bin:/root/go/bin:${PATH}"
export GOCACHE="/root/.cache/go-build"
export GOMODCACHE="/root/go/pkg/mod"
export GOFLAGS="-buildvcs=false"

# Two-stage build
compile_native_go_fuzzer ... || true
if [ -f path/to/generated_fuzz.go ]; then
    sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated_fuzz.go
fi
compile_native_go_fuzzer ...
```

### Rust (cargo-fuzz)

**Base Image:** `ghcr.io/evanrichter/cargo-fuzz` or `rustlang/rust:nightly`

**Dockerfile.rlenv additions:**
```dockerfile
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# For debug builds (useful for stack exhaustion)
WORKDIR /rlenv/source/epub2txt2/fuzz
RUN cargo +nightly fuzz build --dev

# Or for release builds
# RUN cargo +nightly fuzz build

# Handle Cargo.lock conflicts if needed
# RUN rm -f Cargo.lock fuzz/Cargo.lock
# RUN cargo +nightly -Z sparse-registry fuzz build
```

### Rust (honggfuzz)

**Base Image:** `rustlang/rust:nightly`

**Dockerfile.rlenv additions:**
```dockerfile
RUN apt-get update && apt-get install -y \\
    build-essential binutils-dev libunwind-dev \\
    libblocksruntime-dev liblzma-dev jq \\
    && rm -rf /var/lib/apt/lists/*

# Install Rust globally (accessible to all users)
ENV RUSTUP_HOME=/opt/rust/rustup
ENV CARGO_HOME=/opt/rust/cargo
ENV PATH="/opt/rust/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \\
    sh -s -- -y --no-modify-path --default-toolchain nightly
RUN cargo install honggfuzz --version "0.5.55"

# Copy honggwrap for replay
COPY --from=us-east4-docker.pkg.dev/forallsecure-1/rlenv-staging/honggfuzz-static:latest \\
     /honggwrap /usr/local/bin/

RUN RUSTFLAGS="-Cpasses=sancov-module -Clink-arg=-fuse-ld=lld" \\
    cargo +nightly hfuzz build

RUN chmod -R 755 /opt/rust
```

### C/C++ (Make)

**Base Image:** `debian:bookworm` or `ubuntu:20.04`

**Dockerfile.rlenv additions:**
```dockerfile
RUN apt-get update && apt-get install -y \\
    build-essential clang make jq \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /rlenv/source/epub2txt2/
RUN make
```

### C/C++ (CMake)

**Base Image:** `ubuntu:22.04`

**Dockerfile.rlenv additions:**
```dockerfile
RUN apt-get update && apt-get install -y \\
    build-essential cmake clang jq \\
    && rm -rf /var/lib/apt/lists/*

ENV CXX=clang++
ENV CXXFLAGS="-fsanitize=address"
ENV LIB_FUZZING_ENGINE="-fsanitize=fuzzer"

RUN mkdir build && cd build && \\
    cmake .. -DCMAKE_BUILD_TYPE="Release" && \\
    make -j$(nproc)
```

## Common Edge Cases & Solutions

### 1. Go "reflect imported and not used"
**Problem:** compile_native_go_fuzzer generates code with unused reflect import (occurs in ~20% of Go projects)

**Solution:** Two-stage build with sed fix
```dockerfile
RUN compile_native_go_fuzzer ... || true
RUN if [ -f path/to/generated_fuzz.go ]; then \\
      sed -i '/^[[:space:]]*"reflect"$/d' path/to/generated_fuzz.go; \\
    fi
RUN compile_native_go_fuzzer ...
```

### 2. Rust Cargo.lock Conflicts
**Problem:** Locked dependencies incompatible with current nightly

**Solution:** Remove lock files
```dockerfile
RUN rm -f Cargo.lock fuzz/Cargo.lock
RUN cargo +nightly -Z sparse-registry fuzz build
```

### 3. Old Debian GPG Keys
**Problem:** Expired GPG keys in old OSS-Fuzz base images

**Solution:** Update keyring
```dockerfile
RUN apt-get update --allow-insecure-repositories 2>/dev/null || true
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys \\
    648ACFD622F3D138 0E98404D386FA1D9
RUN apt-get update
```

### 4. Busybox cp Limitations
**Problem:** Busybox cp can't overwrite files

**Solution:** Use cat > instead
```bash
# ✗ May fail
cp build/fuzzer /fuzzer

# ✓ Always works
cat build/fuzzer > /fuzzer
```

### 5. Platform Mismatches (ARM Mac)
**Problem:** Building on ARM Mac for x86_64 Linux

**Solution:** Specify platform
```dockerfile
FROM --platform=linux/amd64 ubuntu:20.04
```

### 6. Git VCS Stamping Errors
**Problem:** Go build tries to embed git info but .git/ is modified

**Solution:** Disable VCS stamping
```bash
export GOFLAGS="-buildvcs=false"
```

### 7. Root Directory Permissions (Go)
**Problem:** Go toolchain in /root/ inaccessible to non-root

**Solution:** Make /root/ world-accessible
```dockerfile
RUN chmod 777 /root && chmod -R 777 /root/.go /root/go
```

### 8. Removing Sanitizer Libraries (Optional)
**Use case:** Prevent accidental sanitizer recompilation

**Solution:**
```dockerfile
RUN apt-get remove -y libasan5 libubsan1 liblsan0 libtsan0 && \\
    rm -f /usr/lib/x86_64-linux-gnu/libasan.so* \\
          /usr/lib/x86_64-linux-gnu/libubsan.so*
```

## Testing Your Changes

### After creating Dockerfile.rlenv and build.sh:

```bash
# 1. Build the patch playground image
rlenv patch

# 2. The command will:
#    - Download testsuite from Mayhem
#    - Build Docker image using Dockerfile.rlenv
#    - Run validate.sh to verify functionality

# 3. Manual testing (optional):
docker build -f Dockerfile.rlenv -t test-patch-env .

# Test MTV works
docker run --rm test-patch-env /rlenv/bin/mtv --help

# Test build script (as unprivileged user)
docker run --rm --user 1000 test-patch-env /rlenv/mayhem/data/scripts/build.sh

# Test validation (after rlenv patch)
docker run --rm --user 1000 --network none \\
  --security-opt seccomp=unconfined --cap-add SYS_PTRACE \\
  IMAGE /rlenv/mayhem/data/scripts/validate.sh
```

## Validation Success Criteria

The validate.sh script will check:
1. ✅ MTV binary exists and is functional
2. ✅ Mayhemfile exists at /rlenv/source/Mayhemfile
3. ✅ Problem test case crashes (if PROBLEM_ID set)
4. ✅ Build script exits successfully
5. ✅ Target executable timestamp updated after rebuild
6. ✅ Crash behavior consistent before/after rebuild

## Available Commands

- `/prepare-patch` - LLM command to create Dockerfile.rlenv and build.sh

## Quick Reference

**Must have in Dockerfile.rlenv:**
- MTV binary: `COPY --from=...rlenv-mcp-static... /rlenv/bin/mtv /rlenv/bin/mtv`
- jq: `apt-get install -y jq`
- Source copy: `COPY . /rlenv/source/epub2txt2/`
- Source permissions: `chmod -R 777 /rlenv/source`
- rlenv copy (late): `COPY rlenv /rlenv`
- Final permission fix: `chmod -R 777 /rlenv/source`

**Must have in build.sh:**
- Shebang: `#!/bin/bash`
- Error handling: `set -euo pipefail`
- Working directory: `cd /rlenv/source/epub2txt2/`
- No network access
- No package installation
- Artifact verification: Check file exists before exit

**Common mistakes:**
- ❌ Copying rlenv too early (before source copy)
- ❌ Forgetting chmod 777 on /rlenv/source
- ❌ Using cp instead of cat > (busybox issue)
- ❌ Installing packages in build.sh (goes in Dockerfile)
- ❌ Forgetting MTV binary or jq
- ❌ Target executable path mismatch between Dockerfile and build.sh
