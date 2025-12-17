//! FFI module for Julia integration
//!
//! This module provides C-compatible functions that can be called from Julia
//! using the `ccall` mechanism.

use std::ffi::{c_char, c_float, c_int, c_uchar, CStr, CString};
use std::ptr;
use std::slice;

use crate::compiler::{
    CompiledUnit, CompilerContext,
    NodeTable, NodeType, PropertyTable, ShapedParagraph, TextShaper,
};
use crate::css_parser::{parse_color, parse_inline_style, parse_length, CssStyles};
use crate::html_parser::{parse_html, HtmlToken};
use crate::string_interner::{StringId, StringPool};

// ============================================================================
// Initialization
// ============================================================================

/// Initialize the parser library
#[no_mangle]
pub extern "C" fn dop_parser_init() {
    let _ = env_logger::try_init();
}

/// Get library version
#[no_mangle]
pub extern "C" fn dop_parser_version() -> *const c_char {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const c_char
}

// ============================================================================
// String Pool FFI
// ============================================================================

/// Create a new string pool
#[no_mangle]
pub extern "C" fn dop_string_pool_new() -> *mut StringPool {
    Box::into_raw(Box::new(StringPool::new()))
}

/// Free a string pool
#[no_mangle]
pub extern "C" fn dop_string_pool_free(pool: *mut StringPool) {
    if !pool.is_null() {
        unsafe {
            drop(Box::from_raw(pool));
        }
    }
}

/// Intern a string and return its ID
#[no_mangle]
pub extern "C" fn dop_string_pool_intern(pool: *mut StringPool, s: *const c_char) -> u32 {
    if pool.is_null() || s.is_null() {
        return 0;
    }
    unsafe {
        let c_str = CStr::from_ptr(s);
        if let Ok(str_slice) = c_str.to_str() {
            (*pool).intern(str_slice).0
        } else {
            0
        }
    }
}

/// Get a string by ID (returns pointer to internal string, valid until pool is modified)
#[no_mangle]
pub extern "C" fn dop_string_pool_get(pool: *const StringPool, id: u32) -> *const c_char {
    if pool.is_null() {
        return ptr::null();
    }
    unsafe {
        if let Some(s) = (*pool).get(StringId(id)) {
            // Create a null-terminated copy
            if let Ok(c_string) = CString::new(s) {
                return c_string.into_raw();
            }
        }
    }
    ptr::null()
}

/// Free a string returned by dop_string_pool_get
#[no_mangle]
pub extern "C" fn dop_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            drop(CString::from_raw(s));
        }
    }
}

/// Get the number of interned strings
#[no_mangle]
pub extern "C" fn dop_string_pool_len(pool: *const StringPool) -> u32 {
    if pool.is_null() {
        return 0;
    }
    unsafe { (*pool).len() as u32 }
}

/// Clear the string pool
#[no_mangle]
pub extern "C" fn dop_string_pool_clear(pool: *mut StringPool) {
    if !pool.is_null() {
        unsafe {
            (*pool).clear();
        }
    }
}

// ============================================================================
// HTML Parser FFI
// ============================================================================

/// HTML parse result handle
pub struct HtmlParseResult {
    tokens: Vec<HtmlToken>,
    strings: StringPool,
}

/// Parse HTML and return a result handle
#[no_mangle]
pub extern "C" fn dop_html_parse(html: *const c_char) -> *mut HtmlParseResult {
    if html.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let c_str = CStr::from_ptr(html);
        if let Ok(html_str) = c_str.to_str() {
            let result = parse_html(html_str);
            Box::into_raw(Box::new(HtmlParseResult {
                tokens: result.tokens,
                strings: result.strings,
            }))
        } else {
            ptr::null_mut()
        }
    }
}

/// Free an HTML parse result
#[no_mangle]
pub extern "C" fn dop_html_result_free(result: *mut HtmlParseResult) {
    if !result.is_null() {
        unsafe {
            drop(Box::from_raw(result));
        }
    }
}

/// Get the number of tokens
#[no_mangle]
pub extern "C" fn dop_html_result_token_count(result: *const HtmlParseResult) -> u32 {
    if result.is_null() {
        return 0;
    }
    unsafe { (*result).tokens.len() as u32 }
}

/// Get token type at index
#[no_mangle]
pub extern "C" fn dop_html_result_token_type(result: *const HtmlParseResult, index: u32) -> u8 {
    if result.is_null() {
        return 0;
    }
    unsafe {
        let r = &*result;
        if let Some(token) = r.tokens.get(index as usize) {
            token.token_type as u8
        } else {
            0
        }
    }
}

/// Get token name ID at index
#[no_mangle]
pub extern "C" fn dop_html_result_token_name_id(result: *const HtmlParseResult, index: u32) -> u32 {
    if result.is_null() {
        return 0;
    }
    unsafe {
        let r = &*result;
        if let Some(token) = r.tokens.get(index as usize) {
            token.name_id.0
        } else {
            0
        }
    }
}

/// Get token value ID at index
#[no_mangle]
pub extern "C" fn dop_html_result_token_value_id(result: *const HtmlParseResult, index: u32) -> u32 {
    if result.is_null() {
        return 0;
    }
    unsafe {
        let r = &*result;
        if let Some(token) = r.tokens.get(index as usize) {
            token.value_id.0
        } else {
            0
        }
    }
}

/// Get string from result's string pool
#[no_mangle]
pub extern "C" fn dop_html_result_get_string(result: *const HtmlParseResult, id: u32) -> *const c_char {
    if result.is_null() {
        return ptr::null();
    }
    unsafe {
        let r = &*result;
        if let Some(s) = r.strings.get(StringId(id)) {
            if let Ok(c_string) = CString::new(s) {
                return c_string.into_raw();
            }
        }
    }
    ptr::null()
}

// ============================================================================
// CSS Parser FFI
// ============================================================================

/// CSS styles handle
pub struct CssStylesHandle {
    styles: CssStyles,
}

/// Parse inline CSS style
#[no_mangle]
pub extern "C" fn dop_css_parse_inline(style_str: *const c_char) -> *mut CssStylesHandle {
    if style_str.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let c_str = CStr::from_ptr(style_str);
        if let Ok(str_slice) = c_str.to_str() {
            let styles = parse_inline_style(str_slice);
            Box::into_raw(Box::new(CssStylesHandle { styles }))
        } else {
            ptr::null_mut()
        }
    }
}

/// Free CSS styles
#[no_mangle]
pub extern "C" fn dop_css_styles_free(handle: *mut CssStylesHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

// CSS style getters
#[no_mangle]
pub extern "C" fn dop_css_get_position(handle: *const CssStylesHandle) -> u8 {
    if handle.is_null() { return 0; }
    unsafe { (*handle).styles.position }
}

#[no_mangle]
pub extern "C" fn dop_css_get_display(handle: *const CssStylesHandle) -> u8 {
    if handle.is_null() { return 1; }
    unsafe { (*handle).styles.display }
}

#[no_mangle]
pub extern "C" fn dop_css_get_width(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.width.value }
}

#[no_mangle]
pub extern "C" fn dop_css_get_width_is_auto(handle: *const CssStylesHandle) -> c_int {
    if handle.is_null() { return 1; }
    unsafe { if (*handle).styles.width.is_auto { 1 } else { 0 } }
}

#[no_mangle]
pub extern "C" fn dop_css_get_height(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.height.value }
}

#[no_mangle]
pub extern "C" fn dop_css_get_height_is_auto(handle: *const CssStylesHandle) -> c_int {
    if handle.is_null() { return 1; }
    unsafe { if (*handle).styles.height.is_auto { 1 } else { 0 } }
}

#[no_mangle]
pub extern "C" fn dop_css_get_margin_top(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.margin_top }
}

#[no_mangle]
pub extern "C" fn dop_css_get_margin_right(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.margin_right }
}

#[no_mangle]
pub extern "C" fn dop_css_get_margin_bottom(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.margin_bottom }
}

#[no_mangle]
pub extern "C" fn dop_css_get_margin_left(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.margin_left }
}

#[no_mangle]
pub extern "C" fn dop_css_get_padding_top(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.padding_top }
}

#[no_mangle]
pub extern "C" fn dop_css_get_padding_right(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.padding_right }
}

#[no_mangle]
pub extern "C" fn dop_css_get_padding_bottom(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.padding_bottom }
}

#[no_mangle]
pub extern "C" fn dop_css_get_padding_left(handle: *const CssStylesHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).styles.padding_left }
}

#[no_mangle]
pub extern "C" fn dop_css_get_background_r(handle: *const CssStylesHandle) -> c_uchar {
    if handle.is_null() { return 0; }
    unsafe { (*handle).styles.background_color.r }
}

#[no_mangle]
pub extern "C" fn dop_css_get_background_g(handle: *const CssStylesHandle) -> c_uchar {
    if handle.is_null() { return 0; }
    unsafe { (*handle).styles.background_color.g }
}

#[no_mangle]
pub extern "C" fn dop_css_get_background_b(handle: *const CssStylesHandle) -> c_uchar {
    if handle.is_null() { return 0; }
    unsafe { (*handle).styles.background_color.b }
}

#[no_mangle]
pub extern "C" fn dop_css_get_background_a(handle: *const CssStylesHandle) -> c_uchar {
    if handle.is_null() { return 0; }
    unsafe { (*handle).styles.background_color.a }
}

#[no_mangle]
pub extern "C" fn dop_css_get_has_background(handle: *const CssStylesHandle) -> c_int {
    if handle.is_null() { return 0; }
    unsafe { if (*handle).styles.has_background { 1 } else { 0 } }
}

/// Parse a color string and return RGBA values
#[no_mangle]
pub extern "C" fn dop_css_parse_color(
    color_str: *const c_char,
    r: *mut c_uchar,
    g: *mut c_uchar,
    b: *mut c_uchar,
    a: *mut c_uchar,
) {
    if color_str.is_null() || r.is_null() || g.is_null() || b.is_null() || a.is_null() {
        return;
    }
    
    unsafe {
        let c_str = CStr::from_ptr(color_str);
        if let Ok(str_slice) = c_str.to_str() {
            let color = parse_color(str_slice);
            *r = color.r;
            *g = color.g;
            *b = color.b;
            *a = color.a;
        }
    }
}

/// Parse a length string
#[no_mangle]
pub extern "C" fn dop_css_parse_length(
    length_str: *const c_char,
    container_size: c_float,
    value: *mut c_float,
    is_auto: *mut c_int,
) {
    if length_str.is_null() || value.is_null() || is_auto.is_null() {
        return;
    }
    
    unsafe {
        let c_str = CStr::from_ptr(length_str);
        if let Ok(str_slice) = c_str.to_str() {
            let len = parse_length(str_slice, container_size);
            *value = len.value;
            *is_auto = if len.is_auto { 1 } else { 0 };
        }
    }
}

// ============================================================================
// Compiler FFI
// ============================================================================

/// Create a new compiler context
#[no_mangle]
pub extern "C" fn dop_compiler_new() -> *mut CompilerContext {
    Box::into_raw(Box::new(CompilerContext::new()))
}

/// Free a compiler context
#[no_mangle]
pub extern "C" fn dop_compiler_free(ctx: *mut CompilerContext) {
    if !ctx.is_null() {
        unsafe {
            drop(Box::from_raw(ctx));
        }
    }
}

/// Create a new node table
#[no_mangle]
pub extern "C" fn dop_node_table_new() -> *mut NodeTable {
    Box::into_raw(Box::new(NodeTable::new()))
}

/// Free a node table
#[no_mangle]
pub extern "C" fn dop_node_table_free(table: *mut NodeTable) {
    if !table.is_null() {
        unsafe {
            drop(Box::from_raw(table));
        }
    }
}

/// Create a node in the table
#[no_mangle]
pub extern "C" fn dop_node_table_create(
    table: *mut NodeTable,
    node_type: u8,
    parent: u32,
    style_id: u32,
) -> u32 {
    if table.is_null() {
        return 0;
    }
    unsafe {
        let nt = match node_type {
            0 => NodeType::Root,
            1 => NodeType::Stack,
            2 => NodeType::Grid,
            3 => NodeType::Scroll,
            4 => NodeType::Rect,
            5 => NodeType::Paragraph,
            6 => NodeType::Span,
            7 => NodeType::Link,
            8 => NodeType::TextCluster,
            _ => NodeType::Root,
        };
        (*table).create_node(nt, parent, style_id)
    }
}

/// Get node count
#[no_mangle]
pub extern "C" fn dop_node_table_len(table: *const NodeTable) -> u32 {
    if table.is_null() {
        return 0;
    }
    unsafe { (*table).len() as u32 }
}

/// Create a new property table
#[no_mangle]
pub extern "C" fn dop_property_table_new() -> *mut PropertyTable {
    Box::into_raw(Box::new(PropertyTable::new()))
}

/// Free a property table
#[no_mangle]
pub extern "C" fn dop_property_table_free(table: *mut PropertyTable) {
    if !table.is_null() {
        unsafe {
            drop(Box::from_raw(table));
        }
    }
}

/// Resize property table
#[no_mangle]
pub extern "C" fn dop_property_table_resize(table: *mut PropertyTable, n: u32) {
    if !table.is_null() {
        unsafe {
            (*table).resize(n as usize);
        }
    }
}

/// Create a new text shaper
#[no_mangle]
pub extern "C" fn dop_text_shaper_new() -> *mut TextShaper {
    Box::into_raw(Box::new(TextShaper::new()))
}

/// Free a text shaper
#[no_mangle]
pub extern "C" fn dop_text_shaper_free(shaper: *mut TextShaper) {
    if !shaper.is_null() {
        unsafe {
            drop(Box::from_raw(shaper));
        }
    }
}

/// Shape paragraph result handle
pub struct ShapedParagraphHandle {
    result: ShapedParagraph,
}

/// Shape a paragraph
#[no_mangle]
pub extern "C" fn dop_text_shaper_shape(
    shaper: *mut TextShaper,
    text: *const c_char,
    max_width: c_float,
) -> *mut ShapedParagraphHandle {
    if shaper.is_null() || text.is_null() {
        return ptr::null_mut();
    }
    
    unsafe {
        let c_str = CStr::from_ptr(text);
        if let Ok(text_str) = c_str.to_str() {
            let result = (*shaper).shape_paragraph(text_str, max_width);
            Box::into_raw(Box::new(ShapedParagraphHandle { result }))
        } else {
            ptr::null_mut()
        }
    }
}

/// Free shaped paragraph
#[no_mangle]
pub extern "C" fn dop_shaped_paragraph_free(handle: *mut ShapedParagraphHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Get shaped paragraph width
#[no_mangle]
pub extern "C" fn dop_shaped_paragraph_width(handle: *const ShapedParagraphHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).result.width }
}

/// Get shaped paragraph height
#[no_mangle]
pub extern "C" fn dop_shaped_paragraph_height(handle: *const ShapedParagraphHandle) -> c_float {
    if handle.is_null() { return 0.0; }
    unsafe { (*handle).result.height }
}

/// Get shaped paragraph line count
#[no_mangle]
pub extern "C" fn dop_shaped_paragraph_line_count(handle: *const ShapedParagraphHandle) -> u32 {
    if handle.is_null() { return 0; }
    unsafe { (*handle).result.line_count }
}

/// Get shaped paragraph text hash
#[no_mangle]
pub extern "C" fn dop_shaped_paragraph_text_hash(handle: *const ShapedParagraphHandle) -> u64 {
    if handle.is_null() { return 0; }
    unsafe { (*handle).result.text_hash }
}

// ============================================================================
// Compiled Unit FFI
// ============================================================================

/// Create a new compiled unit
#[no_mangle]
pub extern "C" fn dop_compiled_unit_new() -> *mut CompiledUnit {
    Box::into_raw(Box::new(CompiledUnit::new()))
}

/// Free a compiled unit
#[no_mangle]
pub extern "C" fn dop_compiled_unit_free(unit: *mut CompiledUnit) {
    if !unit.is_null() {
        unsafe {
            drop(Box::from_raw(unit));
        }
    }
}

/// Write compiled unit to binary buffer
#[no_mangle]
pub extern "C" fn dop_compiled_unit_write_binary(
    unit: *const CompiledUnit,
    buffer: *mut *mut c_uchar,
    length: *mut u32,
) -> c_int {
    if unit.is_null() || buffer.is_null() || length.is_null() {
        return 0;
    }
    
    unsafe {
        let bytes = (*unit).write_binary();
        *length = bytes.len() as u32;
        
        // Allocate buffer for the data
        let ptr = libc::malloc(bytes.len()) as *mut c_uchar;
        if ptr.is_null() {
            return 0;
        }
        
        ptr::copy_nonoverlapping(bytes.as_ptr(), ptr, bytes.len());
        *buffer = ptr;
        1
    }
}

/// Read compiled unit from binary buffer
#[no_mangle]
pub extern "C" fn dop_compiled_unit_read_binary(
    data: *const c_uchar,
    length: u32,
) -> *mut CompiledUnit {
    if data.is_null() || length == 0 {
        return ptr::null_mut();
    }
    
    unsafe {
        let slice = slice::from_raw_parts(data, length as usize);
        if let Some(unit) = CompiledUnit::read_binary(slice) {
            Box::into_raw(Box::new(unit))
        } else {
            ptr::null_mut()
        }
    }
}

/// Free binary buffer allocated by dop_compiled_unit_write_binary
#[no_mangle]
pub extern "C" fn dop_binary_buffer_free(buffer: *mut c_uchar) {
    if !buffer.is_null() {
        unsafe {
            libc::free(buffer as *mut libc::c_void);
        }
    }
}

/// Get compiled unit node count
#[no_mangle]
pub extern "C" fn dop_compiled_unit_node_count(unit: *const CompiledUnit) -> u32 {
    if unit.is_null() { return 0; }
    unsafe { (*unit).nodes.len() as u32 }
}

/// Get compiled unit style count
#[no_mangle]
pub extern "C" fn dop_compiled_unit_style_count(unit: *const CompiledUnit) -> u32 {
    if unit.is_null() { return 0; }
    unsafe { (*unit).styles.len() as u32 }
}

/// Get compiled unit checksum
#[no_mangle]
pub extern "C" fn dop_compiled_unit_checksum(unit: *const CompiledUnit) -> u64 {
    if unit.is_null() { return 0; }
    unsafe { (*unit).checksum }
}
