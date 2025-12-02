#!/bin/bash
set -euo pipefail

# RLENV Build Script
# This script rebuilds the application from source located at /rlenv/source/epub2txt2/
#
# Original image: ghcr.io/mayhemheroes/epub2txt2:master
# Git revision: 5890b9b89670524c4ca906866475d6cec0f9556d

# ============================================================================
# Environment Variables
# ============================================================================
# AFL++ environment is pre-configured in the base image
# afl-clang-fast is available via BUILD_FOR_AFL=1 flag

# ============================================================================
# REQUIRED: Change to Source Directory
# ============================================================================
cd /rlenv/source/epub2txt2

# ============================================================================
# Clean Previous Build (recommended)
# ============================================================================
# Remove old build artifacts in source directory to ensure fresh rebuild
make clean 2>/dev/null || true

# ============================================================================
# Build Commands (NO NETWORK, NO PACKAGE INSTALLATION)
# ============================================================================
# Build with AFL++ instrumentation
make -j1 BUILD_FOR_AFL=1

# ============================================================================
# Copy Artifacts (use 'cat >' for busybox compatibility)
# ============================================================================
# Copy the built fuzzer to the expected location
cat epub2txt > /epub2txt

# ============================================================================
# Set Permissions
# ============================================================================
chmod 777 /epub2txt 2>/dev/null || true

# 777 allows validation script (running as UID 1000) to overwrite during rebuild
# 2>/dev/null || true prevents errors if chmod not available

# ============================================================================
# REQUIRED: Verify Build Succeeded
# ============================================================================
if [ ! -f /epub2txt ]; then
    echo "Error: Build artifact not found at /epub2txt"
    exit 1
fi

# Verify executable bit
if [ ! -x /epub2txt ]; then
    echo "Warning: Build artifact is not executable"
fi

# Verify file size
SIZE=$(stat -c%s /epub2txt 2>/dev/null || stat -f%z /epub2txt 2>/dev/null || echo 0)
if [ "$SIZE" -lt 1000 ]; then
    echo "Warning: Build artifact is suspiciously small ($SIZE bytes)"
fi

echo "Build completed successfully: /epub2txt ($SIZE bytes)"
