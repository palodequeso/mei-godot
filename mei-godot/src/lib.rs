//! MEI Godot Extension
//!
//! This library provides Godot bindings for the Matter-Energy-Information (MEI)
//! procedural galaxy generation system, allowing Godot games to generate and
//! query stellar systems and galactic structures.

use godot::prelude::*;

mod galaxy;

/// The main extension entry point for MEI Godot integration.
struct MeiExtension;

#[gdextension]
unsafe impl ExtensionLibrary for MeiExtension {}
