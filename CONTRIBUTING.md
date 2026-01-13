# Contributing to MEI-Godot

Thank you for your interest in contributing to MEI-Godot! This is a pre-alpha project (v0.0.1) and contributions are very welcome.

## Project Status

**Current State:** Pre-alpha, actively developed, API unstable

This is the Godot 4 GDExtension plugin for the [MEI (Matter, Energy, Information)](https://github.com/palodequeso/mei) procedural galaxy generator. Expect breaking changes, rough edges, and missing features. See [README.md](README.md#known-issues--limitations) for known issues.

## How to Contribute

### Reporting Bugs

- Check existing [Issues](https://github.com/palodequeso/mei-godot/issues) first
- Include MEI-Godot version, Godot version, OS, and steps to reproduce
- Specify if the bug is in VR mode, desktop mode, or both
- For generation bugs: include the galaxy seed if relevant

### Feature Requests

See [TODO.md](TODO.md) for planned features. If your idea isn't there, open an issue to discuss!

### Pull Requests

1. **Fork** the repository
2. **Create a branch** from `main` (`feature/your-feature-name`)
3. **Make your changes** with clear, atomic commits
4. **Test** your changes in Godot
5. **Document** new features or API changes
6. **Submit** a PR with a clear description

### Code Style

- **Rust** (mei-godot/): Follow `rustfmt` defaults (`cargo fmt`)
- **GDScript**: Follow Godot style guide (4 spaces, snake_case)
- **Comments**: Explain *why*, not *what*
- **Commits**: Use descriptive messages (not "fix bug" or "update")

### Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/mei-godot
cd mei-godot

# Build the GDExtension
./build-all.sh

# Open in Godot 4.3+
godot .
```

### Architecture Guidelines

- **GDExtension layer** (`mei-godot/`) should be a thin wrapper around MEI core
- **GDScript** handles rendering, UI, and Godot-specific logic
- **Determinism is sacred** - same seed must always produce same results
- **Performance matters** - this needs to run in real-time, especially in VR

### Areas That Need Help

See [TODO.md](TODO.md) for full list. High-priority areas:

- **VR polish** - better hand interactions, menu positioning
- **Planet textures** - procedural or astrophysically accurate assignment
- **Star selection** - improve 3D picking accuracy
- **Performance** - LOD system, caching, optimization
- **Documentation** - inline docs, tutorials

### Questions?

Open an issue or discussion! This is an experimental project - all ideas welcome.

## Code of Conduct

Be respectful, constructive, and kind. This is a learning project and everyone is welcome regardless of experience level.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
