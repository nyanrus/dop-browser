//! FFI layer for Julia interop
//!
//! This module provides C-compatible FFI functions for calling from Julia.

use std::ffi::CStr;
use std::os::raw::c_char;

use crate::builder::ContentBuilder;
use crate::properties::{Direction, Pack, Align, Color};

/// Opaque handle for ContentBuilder
pub struct BuilderHandle {
    builder: Box<ContentBuilder>,
}

/// Create a new ContentBuilder
#[no_mangle]
pub extern "C" fn content_builder_new() -> *mut BuilderHandle {
    let builder = Box::new(ContentBuilder::new());
    Box::into_raw(Box::new(BuilderHandle { builder }))
}

/// Free a ContentBuilder
#[no_mangle]
pub extern "C" fn content_builder_free(handle: *mut BuilderHandle) {
    if !handle.is_null() {
        unsafe {
            let _ = Box::from_raw(handle);
        }
    }
}

/// Begin a Stack container
#[no_mangle]
pub extern "C" fn content_builder_begin_stack(handle: *mut BuilderHandle) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.begin_stack();
    }
}

/// End the current container
#[no_mangle]
pub extern "C" fn content_builder_end(handle: *mut BuilderHandle) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.end();
    }
}

/// Add a Rect node
#[no_mangle]
pub extern "C" fn content_builder_rect(handle: *mut BuilderHandle) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.rect();
    }
}

/// Begin a Paragraph node
#[no_mangle]
pub extern "C" fn content_builder_begin_paragraph(handle: *mut BuilderHandle) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.begin_paragraph();
    }
}

/// Add a Span node with text
#[no_mangle]
pub extern "C" fn content_builder_span(handle: *mut BuilderHandle, text: *const c_char) {
    if let Some(h) = unsafe { handle.as_mut() } {
        if !text.is_null() {
            if let Ok(text_str) = unsafe { CStr::from_ptr(text) }.to_str() {
                h.builder.span(text_str);
            }
        }
    }
}

/// Set direction
#[no_mangle]
pub extern "C" fn content_builder_direction(handle: *mut BuilderHandle, dir: u8) {
    if let Some(h) = unsafe { handle.as_mut() } {
        let direction = match dir {
            0 => Direction::Down,
            1 => Direction::Up,
            2 => Direction::Right,
            3 => Direction::Left,
            _ => Direction::Down,
        };
        h.builder.direction(direction);
    }
}

/// Set pack
#[no_mangle]
pub extern "C" fn content_builder_pack(handle: *mut BuilderHandle, pack: u8) {
    if let Some(h) = unsafe { handle.as_mut() } {
        let pack_val = match pack {
            0 => Pack::Start,
            1 => Pack::End,
            2 => Pack::Center,
            3 => Pack::SpaceBetween,
            4 => Pack::SpaceAround,
            5 => Pack::SpaceEvenly,
            _ => Pack::Start,
        };
        h.builder.pack(pack_val);
    }
}

/// Set align
#[no_mangle]
pub extern "C" fn content_builder_align(handle: *mut BuilderHandle, align: u8) {
    if let Some(h) = unsafe { handle.as_mut() } {
        let align_val = match align {
            0 => Align::Start,
            1 => Align::End,
            2 => Align::Center,
            3 => Align::Stretch,
            _ => Align::Start,
        };
        h.builder.align(align_val);
    }
}

/// Set width
#[no_mangle]
pub extern "C" fn content_builder_width(handle: *mut BuilderHandle, width: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.width(width);
    }
}

/// Set height
#[no_mangle]
pub extern "C" fn content_builder_height(handle: *mut BuilderHandle, height: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.height(height);
    }
}

/// Set gap
#[no_mangle]
pub extern "C" fn content_builder_gap(handle: *mut BuilderHandle, gap: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.gap(gap);
    }
}

/// Set fill color from hex string
#[no_mangle]
pub extern "C" fn content_builder_fill_hex(handle: *mut BuilderHandle, hex: *const c_char) {
    if let Some(h) = unsafe { handle.as_mut() } {
        if !hex.is_null() {
            if let Ok(hex_str) = unsafe { CStr::from_ptr(hex) }.to_str() {
                h.builder.fill_hex(hex_str);
            }
        }
    }
}

/// Set fill color from RGBA
#[no_mangle]
pub extern "C" fn content_builder_fill_rgba(handle: *mut BuilderHandle, r: u8, g: u8, b: u8, a: u8) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.fill(Color::new(r, g, b, a));
    }
}

/// Set inset (padding)
#[no_mangle]
pub extern "C" fn content_builder_inset(handle: *mut BuilderHandle, inset: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.inset(inset);
    }
}

/// Set inset with individual sides
#[no_mangle]
pub extern "C" fn content_builder_inset_trbl(handle: *mut BuilderHandle, top: f32, right: f32, bottom: f32, left: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.inset_trbl(top, right, bottom, left);
    }
}

/// Set border radius
#[no_mangle]
pub extern "C" fn content_builder_border_radius(handle: *mut BuilderHandle, radius: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.border_radius(radius);
    }
}

/// Set font size
#[no_mangle]
pub extern "C" fn content_builder_font_size(handle: *mut BuilderHandle, size: f32) {
    if let Some(h) = unsafe { handle.as_mut() } {
        h.builder.font_size(size);
    }
}

/// Set text color from hex string
#[no_mangle]
pub extern "C" fn content_builder_text_color_hex(handle: *mut BuilderHandle, hex: *const c_char) {
    if let Some(h) = unsafe { handle.as_mut() } {
        if !hex.is_null() {
            if let Ok(hex_str) = unsafe { CStr::from_ptr(hex) }.to_str() {
                h.builder.text_color_hex(hex_str);
            }
        }
    }
}

/// Get node count
#[no_mangle]
pub extern "C" fn content_builder_node_count(handle: *const BuilderHandle) -> usize {
    if let Some(h) = unsafe { handle.as_ref() } {
        h.builder.tables().0.len()
    } else {
        0
    }
}
