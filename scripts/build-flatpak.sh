#!/bin/bash
# Build a Flatpak locally
# Prerequisites: flatpak, flatpak-builder
# Usage: ./scripts/build-flatpak.sh [--install]

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLATPAK_DIR="$PROJECT_ROOT/flatpak"
APP_ID="com.palodequeso.MeiGalaxyViewer"
INSTALL_FLAG=""

if [ "$1" = "--install" ]; then
    INSTALL_FLAG="--user --install"
fi

echo "=== Building Flatpak for $APP_ID ==="

# Check prerequisites
if ! command -v flatpak-builder &> /dev/null; then
    echo "Error: flatpak-builder not found"
    echo "Install with: sudo apt install flatpak-builder"
    exit 1
fi

# Check if Linux build exists
if [ ! -f "$PROJECT_ROOT/builds/linux/godot-mei-viewer.x86_64" ]; then
    echo "Error: Linux build not found at builds/linux/godot-mei-viewer.x86_64"
    echo "Run: godot --headless --export-release 'Linux' builds/linux/godot-mei-viewer.x86_64"
    exit 1
fi

# Install runtime and SDK if needed
echo "Checking for Freedesktop runtime and SDK..."
if ! flatpak info org.freedesktop.Platform//23.08 &> /dev/null || ! flatpak info org.freedesktop.Sdk//23.08 &> /dev/null; then
    echo "Installing org.freedesktop.Platform and Sdk 23.08..."
    flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
    flatpak install --user -y flathub org.freedesktop.Platform//23.08 org.freedesktop.Sdk//23.08
fi

# Build
cd "$FLATPAK_DIR"
flatpak-builder --force-clean $INSTALL_FLAG build-dir "$APP_ID.yml"

if [ -n "$INSTALL_FLAG" ]; then
    echo ""
    echo "=== Flatpak installed! Run with: flatpak run $APP_ID ==="
else
    echo ""
    echo "=== Flatpak built in $FLATPAK_DIR/build-dir ==="
    echo "To install: ./scripts/build-flatpak.sh --install"
    echo "Or: flatpak-builder --user --install --force-clean build-dir $APP_ID.yml"
fi
