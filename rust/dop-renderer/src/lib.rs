//! DOP Renderer - Rust-based rendering engine using winit and wgpu
//!
//! This crate provides window management and GPU rendering functionality
//! for the DOP Browser project, exposed via FFI for Julia integration.

pub mod window;
pub mod renderer;
pub mod ffi;

pub use window::*;
pub use renderer::*;
