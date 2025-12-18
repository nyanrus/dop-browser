//! DOP Parser - HTML/CSS parsers and Content IR compiler
//!
//! This crate provides:
//! - HTML parsing using html5ever
//! - CSS parsing using cssparser
//! - Content IR compiler with zerocopy binary format
//! - JIT text shaping infrastructure
//!
//! All modules expose FFI functions for Julia integration.

pub mod html_parser;
pub mod css_parser;
pub mod compiler;
pub mod string_interner;
pub mod ffi;

pub use html_parser::*;
pub use css_parser::*;
pub use compiler::*;
pub use string_interner::*;
