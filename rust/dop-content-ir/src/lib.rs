//! Content IR (Intermediate Representation) and Builder
//!
//! This library provides a Rust implementation of the Content IR,
//! including node primitives, properties, and a builder API for constructing
//! Content IR trees from Julia.

pub mod primitives;
pub mod properties;
pub mod builder;
pub mod ffi;
pub mod render;

pub use primitives::{NodeType, NodeTable, ContentNode};
pub use properties::{PropertyTable, Direction, Pack, Align, Color};
pub use builder::ContentBuilder;
