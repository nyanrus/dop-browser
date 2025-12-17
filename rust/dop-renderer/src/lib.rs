//! DOP Renderer - Rust-based rendering engine using winit, wgpu and tiny-skia
//!
//! This crate provides window management and rendering functionality
//! for the DOP Browser project, exposed via FFI for Julia integration.
//!
//! ## Features
//!
//! - **software** (default): CPU-based rendering using tiny-skia and softbuffer
//! - **gpu**: Hardware-accelerated rendering using wgpu

pub mod window;
pub mod renderer;
pub mod text;
#[cfg(feature = "software")]
pub mod software;
pub mod ffi;

pub use window::*;
pub use renderer::*;
pub use text::*;

// Note: software module exports are accessed via crate::software to avoid
// name conflicts with text::TextCommand
