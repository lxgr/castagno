#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
mkdir -p .build
export CLANG_MODULE_CACHE_PATH="$root/.build/clang-module-cache"
# Install once: python3 -m pip install --target .build/icon-tools cairosvg==2.9.1
export PYTHONPATH="$root/.build/icon-tools${PYTHONPATH:+:$PYTHONPATH}"
# CairoSVG uses the system Cairo library (Homebrew: brew install cairo).
for cairo_path in /opt/homebrew/lib /usr/local/lib; do
    if [ -d "$cairo_path" ]; then
        export DYLD_FALLBACK_LIBRARY_PATH="$cairo_path${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
    fi
done
python3 scripts/render-icons.py
swiftc -parse-as-library scripts/generate-icons.swift -o .build/generate-icons
.build/generate-icons "$root"
