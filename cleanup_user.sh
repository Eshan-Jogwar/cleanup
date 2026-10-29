#!/usr/bin/env bash
# ==============================================================================
# Linux Developer Disk Cleanup - User Space Script (No sudo required)
# Safely reclaims user-space package manager caches, IDE caches, and build tools.
# ==============================================================================
set -euo pipefail

echo "=========================================================="
echo " Starting User-Level Disk Cleanup"
echo " Initial Disk Space:"
df -h "$HOME"
echo "=========================================================="

# 1. VS Code C/C++ Extension Precompiled Headers
if [ -d "$HOME/.cache/vscode-cpptools/ipch" ]; then
    echo "--> Clearing VS Code C++ precompiled header cache..."
    rm -rf "$HOME/.cache/vscode-cpptools/ipch"/*
fi

# 2. VS Code Cached Extension Installers
if [ -d "$HOME/.config/Code/CachedExtensionVSIXs" ]; then
    echo "--> Clearing VS Code cached extension VSIXs..."
    rm -rf "$HOME/.config/Code/CachedExtensionVSIXs"/*
fi

# 3. Pip HTTP Download Cache
if [ -d "$HOME/.cache/pip" ]; then
    echo "--> Clearing Pip wheel download cache..."
    rm -rf "$HOME/.cache/pip"
fi

# 4. Bun Package Cache
if [ -d "$HOME/.bun/install/cache" ]; then
    echo "--> Clearing Bun package cache..."
    rm -rf "$HOME/.bun/install/cache"/*
fi

# 5. NPM Cache
if command -v npm &>/dev/null; then
    echo "--> Cleaning NPM cache..."
    npm cache clean --force || true
fi

# 6. Go Build & Module Cache
if command -v go &>/dev/null; then
    echo "--> Cleaning Go build cache..."
    go clean -cache
fi

# 7. Browser Web Caches (Keeps user profiles, passwords, bookmarks intact)
if [ -d "$HOME/.cache/BraveSoftware/Brave-Browser/Default/Cache" ]; then
    echo "--> Clearing Brave browser cache..."
    rm -rf "$HOME/.cache/BraveSoftware/Brave-Browser/Default/Cache"/*
fi
if [ -d "$HOME/.cache/google-chrome/Default/Cache" ]; then
    echo "--> Clearing Google Chrome browser cache..."
    rm -rf "$HOME/.cache/google-chrome/Default/Cache"/*
fi

# 8. Downloaded .deb packages in ~/Downloads
if compgen -G "$HOME/Downloads/*.deb" > /dev/null; then
    echo "--> Removing downloaded .deb packages from Downloads..."
    rm -f "$HOME"/Downloads/*.deb
fi

echo "=========================================================="
echo " User-Level Cleanup Complete!"
echo " Updated Disk Space:"
df -h "$HOME"
echo "=========================================================="
