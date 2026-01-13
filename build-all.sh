echo "Building mei-godot"
cargo build --release
cargo build

echo "Building mei-godot (Windows)"
cargo build --target x86_64-pc-windows-gnu
cargo build --target x86_64-pc-windows-gnu --release

echo "Building mei-godot (Android)"
cargo build --target aarch64-linux-android
cargo build --target aarch64-linux-android --release
