#!/bin/bash
# Build an AppImage locally
# Prerequisites: appimagetool (download from https://github.com/AppImage/AppImageKit/releases)
# Usage: ./scripts/build-appimage.sh [version]

set -e

VERSION=${1:-"dev"}
EXPORT_NAME="godot-mei-viewer"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Building AppImage for $EXPORT_NAME $VERSION ==="

# Check for appimagetool
if ! command -v appimagetool &> /dev/null; then
    echo "appimagetool not found. Downloading..."
    wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O /tmp/appimagetool
    chmod +x /tmp/appimagetool
    APPIMAGETOOL="/tmp/appimagetool"
else
    APPIMAGETOOL="appimagetool"
fi

# Check if Linux build exists
if [ ! -f "$PROJECT_ROOT/builds/linux/$EXPORT_NAME.x86_64" ]; then
    echo "Error: Linux build not found at builds/linux/$EXPORT_NAME.x86_64"
    echo "Run: godot --headless --export-release 'Linux' builds/linux/$EXPORT_NAME.x86_64"
    exit 1
fi

# Create AppDir structure
APPDIR="$PROJECT_ROOT/builds/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"
mkdir -p "$APPDIR/usr/share/applications"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Copy executable and pck
cp "$PROJECT_ROOT/builds/linux/$EXPORT_NAME.x86_64" "$APPDIR/usr/bin/$EXPORT_NAME"
chmod +x "$APPDIR/usr/bin/$EXPORT_NAME"

if [ -f "$PROJECT_ROOT/builds/linux/$EXPORT_NAME.pck" ]; then
    cp "$PROJECT_ROOT/builds/linux/$EXPORT_NAME.pck" "$APPDIR/usr/bin/"
fi

# Copy GDExtension library from export directory (Godot exports it there)
if [ -f "$PROJECT_ROOT/builds/linux/libmei_godot.so" ]; then
    cp "$PROJECT_ROOT/builds/linux/libmei_godot.so" "$APPDIR/usr/bin/"
    echo "Included GDExtension: libmei_godot.so (from export)"
elif [ -f "$PROJECT_ROOT/target/release/libmei_godot.so" ]; then
    cp "$PROJECT_ROOT/target/release/libmei_godot.so" "$APPDIR/usr/bin/"
    echo "Included GDExtension: libmei_godot.so (from target/release)"
else
    echo "Warning: GDExtension library not found"
    echo "Run: godot --headless --export-release 'Linux' builds/linux/$EXPORT_NAME.x86_64"
fi

# Copy .gdextension file
if [ -f "$PROJECT_ROOT/mei.gdextension" ]; then
    cp "$PROJECT_ROOT/mei.gdextension" "$APPDIR/usr/bin/"
fi

# Copy generator config if it exists
if [ -f "$PROJECT_ROOT/generator_config.toml" ]; then
    cp "$PROJECT_ROOT/generator_config.toml" "$APPDIR/usr/bin/"
fi

# Copy icon
cp "$PROJECT_ROOT/icon.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/$EXPORT_NAME.png"
cp "$PROJECT_ROOT/icon.png" "$APPDIR/$EXPORT_NAME.png"

# Create desktop file
cat > "$APPDIR/$EXPORT_NAME.desktop" << EOF
[Desktop Entry]
Name=MEI Galaxy Viewer
Exec=$EXPORT_NAME
Icon=$EXPORT_NAME
Type=Application
Categories=Game;Simulation;
Comment=Procedural galaxy viewer powered by MEI
EOF

cp "$APPDIR/$EXPORT_NAME.desktop" "$APPDIR/usr/share/applications/"

# Create AppRun
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
cd "${HERE}/usr/bin"
exec "./godot-mei-viewer" --xr-mode off "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Build AppImage
cd "$PROJECT_ROOT/builds"
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run AppDir "$EXPORT_NAME-$VERSION-x86_64.AppImage"

echo ""
echo "=== AppImage created: builds/$EXPORT_NAME-$VERSION-x86_64.AppImage ==="
