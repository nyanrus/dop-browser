//! FFI module for Julia integration
//!
//! This module provides C-compatible functions that can be called from Julia
//! using the `ccall` mechanism. The Rust library is built using the unified
//! BinaryBuilder configuration for cross-platform distribution.

use std::ffi::{c_char, c_float, c_int, CStr};
use std::ptr;

use crate::renderer::{RenderCommand, WgpuRenderer};
use crate::text::{FontManager, TextShaper};
use crate::window::{DopEvent, MouseButtonId, WindowConfig, WindowHandle};

/// Initialize the rendering engine
#[no_mangle]
pub extern "C" fn dop_init() {
    let _ = env_logger::try_init();
}

/// Create a window configuration
#[no_mangle]
pub extern "C" fn dop_window_config_new() -> *mut WindowConfig {
    Box::into_raw(Box::new(WindowConfig::default()))
}

/// Free a window configuration
#[no_mangle]
pub extern "C" fn dop_window_config_free(config: *mut WindowConfig) {
    if !config.is_null() {
        unsafe {
            drop(Box::from_raw(config));
        }
    }
}

/// Set window title
#[no_mangle]
pub extern "C" fn dop_window_config_set_title(config: *mut WindowConfig, title: *const c_char) {
    if config.is_null() || title.is_null() {
        return;
    }
    unsafe {
        let c_str = CStr::from_ptr(title);
        if let Ok(s) = c_str.to_str() {
            (*config).title = s.to_string();
        }
    }
}

/// Set window size
#[no_mangle]
pub extern "C" fn dop_window_config_set_size(
    config: *mut WindowConfig,
    width: c_int,
    height: c_int,
) {
    if config.is_null() {
        return;
    }
    unsafe {
        (*config).width = width as u32;
        (*config).height = height as u32;
    }
}

/// Set window resizable flag
#[no_mangle]
pub extern "C" fn dop_window_config_set_resizable(config: *mut WindowConfig, resizable: c_int) {
    if config.is_null() {
        return;
    }
    unsafe {
        (*config).resizable = resizable != 0;
    }
}

/// Set window decorated flag
#[no_mangle]
pub extern "C" fn dop_window_config_set_decorated(config: *mut WindowConfig, decorated: c_int) {
    if config.is_null() {
        return;
    }
    unsafe {
        (*config).decorated = decorated != 0;
    }
}

/// Create a window handle (for headless mode without actual window)
#[no_mangle]
pub extern "C" fn dop_window_create_headless(
    width: c_int,
    height: c_int,
) -> *mut WindowHandle {
    let config = WindowConfig {
        width: width as u32,
        height: height as u32,
        ..Default::default()
    };
    Box::into_raw(Box::new(WindowHandle::new(config)))
}

/// Free a window handle
#[no_mangle]
pub extern "C" fn dop_window_free(handle: *mut WindowHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Check if window is open
#[no_mangle]
pub extern "C" fn dop_window_is_open(handle: *const WindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { if (*handle).is_open() { 1 } else { 0 } }
}

/// Close the window
#[no_mangle]
pub extern "C" fn dop_window_close(handle: *mut WindowHandle) {
    if !handle.is_null() {
        unsafe {
            (*handle).close();
        }
    }
}

/// Get window width
#[no_mangle]
pub extern "C" fn dop_window_get_width(handle: *const WindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).get_size().0 as c_int }
}

/// Get window height
#[no_mangle]
pub extern "C" fn dop_window_get_height(handle: *const WindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).get_size().1 as c_int }
}

/// Push an event to the window's event queue
#[no_mangle]
pub extern "C" fn dop_window_push_event(handle: *mut WindowHandle, event: *const DopEvent) {
    if handle.is_null() || event.is_null() {
        return;
    }
    unsafe {
        (*handle).push_event(*event);
    }
}

/// Poll events from the window
/// Returns the number of events available
#[no_mangle]
pub extern "C" fn dop_window_poll_events(
    handle: *mut WindowHandle,
    events: *mut DopEvent,
    max_events: c_int,
) -> c_int {
    if handle.is_null() || events.is_null() || max_events <= 0 {
        return 0;
    }
    unsafe {
        let polled = (*handle).poll_events();
        let count = polled.len().min(max_events as usize);
        for (i, event) in polled.into_iter().take(count).enumerate() {
            *events.add(i) = event;
        }
        count as c_int
    }
}

/// Get mouse X position
#[no_mangle]
pub extern "C" fn dop_window_get_mouse_x(handle: *const WindowHandle) -> c_float {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { (*handle).mouse_position().0 as c_float }
}

/// Get mouse Y position
#[no_mangle]
pub extern "C" fn dop_window_get_mouse_y(handle: *const WindowHandle) -> c_float {
    if handle.is_null() {
        return 0.0;
    }
    unsafe { (*handle).mouse_position().1 as c_float }
}

// ============================================================================
// Renderer FFI
// ============================================================================

/// Renderer handle for FFI
#[allow(dead_code)]
pub struct RendererHandle {
    renderer: Option<WgpuRenderer>,
    commands: Vec<RenderCommand>,
    text_commands: Vec<TextCommandFFI>,
    framebuffer: Vec<u8>,
    width: u32,
    height: u32,
    font_manager: FontManager,
}

/// Text command for FFI
#[derive(Debug, Clone)]
struct TextCommandFFI {
    text: String,
    x: f32,
    y: f32,
    font_size: f32,
    color_r: f32,
    color_g: f32,
    color_b: f32,
    color_a: f32,
    font_id: u32,
}

/// Create a headless renderer (software rendering for PNG export)
#[no_mangle]
pub extern "C" fn dop_renderer_create_headless(width: c_int, height: c_int) -> *mut RendererHandle {
    let w = width as u32;
    let h = height as u32;
    let framebuffer = vec![255u8; (w * h * 4) as usize]; // White background

    Box::into_raw(Box::new(RendererHandle {
        renderer: None,
        commands: Vec::new(),
        text_commands: Vec::new(),
        framebuffer,
        width: w,
        height: h,
        font_manager: FontManager::new(),
    }))
}

/// Free a renderer
#[no_mangle]
pub extern "C" fn dop_renderer_free(handle: *mut RendererHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Clear the renderer
#[no_mangle]
pub extern "C" fn dop_renderer_clear(handle: *mut RendererHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        (*handle).commands.clear();
        (*handle).text_commands.clear();
    }
}

/// Set clear color
#[no_mangle]
pub extern "C" fn dop_renderer_set_clear_color(
    handle: *mut RendererHandle,
    r: c_float,
    g: c_float,
    b: c_float,
    a: c_float,
) {
    if handle.is_null() {
        return;
    }
    let handle = unsafe { &mut *handle };
    
    // Fill framebuffer with clear color
    let w = handle.width;
    let h = handle.height;
    let rb = (r * 255.0) as u8;
    let gb = (g * 255.0) as u8;
    let bb = (b * 255.0) as u8;
    let ab = (a * 255.0) as u8;

    for i in 0..(w * h) as usize {
        let idx = i * 4;
        handle.framebuffer[idx] = rb;
        handle.framebuffer[idx + 1] = gb;
        handle.framebuffer[idx + 2] = bb;
        handle.framebuffer[idx + 3] = ab;
    }
}

/// Add a rectangle render command
#[no_mangle]
pub extern "C" fn dop_renderer_add_rect(
    handle: *mut RendererHandle,
    x: c_float,
    y: c_float,
    width: c_float,
    height: c_float,
    r: c_float,
    g: c_float,
    b: c_float,
    a: c_float,
    z_index: c_int,
) {
    if handle.is_null() {
        return;
    }
    unsafe {
        (*handle).commands.push(RenderCommand {
            x,
            y,
            width,
            height,
            color_r: r,
            color_g: g,
            color_b: b,
            color_a: a,
            texture_id: 0,
            z_index,
        });
    }
}

/// Render the frame (software rasterization for headless mode)
#[no_mangle]
pub extern "C" fn dop_renderer_render(handle: *mut RendererHandle) {
    if handle.is_null() {
        return;
    }
    let handle = unsafe { &mut *handle };
    
    let w = handle.width;
    let h = handle.height;

    // Sort commands by z-index
    handle.commands.sort_by_key(|c| c.z_index);

    // Clone commands to iterate over them
    let commands: Vec<RenderCommand> = handle.commands.clone();
    
    // Software rasterize each rectangle command
    for cmd in &commands {
        // Calculate rectangle bounds
        let x0 = (cmd.x.max(0.0) as u32).min(w);
        let y0 = (cmd.y.max(0.0) as u32).min(h);
        let x1 = ((cmd.x + cmd.width).ceil() as u32).min(w);
        let y1 = ((cmd.y + cmd.height).ceil() as u32).min(h);

        let rb = (cmd.color_r * 255.0) as u8;
        let gb = (cmd.color_g * 255.0) as u8;
        let bb = (cmd.color_b * 255.0) as u8;
        let ab = (cmd.color_a * 255.0) as u8;
        let alpha = cmd.color_a;
        let inv_alpha = 1.0 - alpha;

        // Fill the rectangle
        for y in y0..y1 {
            for x in x0..x1 {
                let idx = ((y * w + x) * 4) as usize;
                if idx + 3 < handle.framebuffer.len() {
                    // Alpha blend
                    let dst_r = handle.framebuffer[idx] as f32;
                    let dst_g = handle.framebuffer[idx + 1] as f32;
                    let dst_b = handle.framebuffer[idx + 2] as f32;
                    let dst_a = handle.framebuffer[idx + 3];

                    handle.framebuffer[idx] =
                        ((rb as f32 * alpha + dst_r * inv_alpha) as u8).min(255);
                    handle.framebuffer[idx + 1] =
                        ((gb as f32 * alpha + dst_g * inv_alpha) as u8).min(255);
                    handle.framebuffer[idx + 2] =
                        ((bb as f32 * alpha + dst_b * inv_alpha) as u8).min(255);
                    handle.framebuffer[idx + 3] = (dst_a as u16 + ab as u16).min(255) as u8;
                }
            }
        }
    }
    
    // Render text commands
    let text_commands: Vec<TextCommandFFI> = handle.text_commands.clone();
    for text_cmd in &text_commands {
        let color = (
            (text_cmd.color_r * 255.0) as u8,
            (text_cmd.color_g * 255.0) as u8,
            (text_cmd.color_b * 255.0) as u8,
            (text_cmd.color_a * 255.0) as u8,
        );
        
        let (text_buffer, text_w, text_h) = handle.font_manager.rasterize_text(
            &text_cmd.text,
            text_cmd.font_size,
            text_cmd.font_id,
            color,
        );
        
        if text_buffer.is_empty() || text_w == 0 || text_h == 0 {
            continue;
        }
        
        // Blit text to framebuffer
        let tx = text_cmd.x as i32;
        let ty = text_cmd.y as i32;
        
        for ty_off in 0..text_h as i32 {
            for tx_off in 0..text_w as i32 {
                let px = tx + tx_off;
                let py = ty + ty_off;
                
                if px >= 0 && py >= 0 && (px as u32) < w && (py as u32) < h {
                    let src_idx = ((ty_off as u32 * text_w + tx_off as u32) * 4) as usize;
                    let dst_idx = ((py as u32 * w + px as u32) * 4) as usize;
                    
                    if src_idx + 3 < text_buffer.len() && dst_idx + 3 < handle.framebuffer.len() {
                        let src_a = text_buffer[src_idx + 3] as f32 / 255.0;
                        if src_a > 0.0 {
                            let inv_a = 1.0 - src_a;
                            handle.framebuffer[dst_idx] = ((text_buffer[src_idx] as f32 * src_a + handle.framebuffer[dst_idx] as f32 * inv_a) as u8).min(255);
                            handle.framebuffer[dst_idx + 1] = ((text_buffer[src_idx + 1] as f32 * src_a + handle.framebuffer[dst_idx + 1] as f32 * inv_a) as u8).min(255);
                            handle.framebuffer[dst_idx + 2] = ((text_buffer[src_idx + 2] as f32 * src_a + handle.framebuffer[dst_idx + 2] as f32 * inv_a) as u8).min(255);
                            handle.framebuffer[dst_idx + 3] = ((src_a * 255.0 + handle.framebuffer[dst_idx + 3] as f32 * inv_a) as u8).min(255);
                        }
                    }
                }
            }
        }
    }
}

/// Get framebuffer pointer
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer(handle: *const RendererHandle) -> *const u8 {
    if handle.is_null() {
        return ptr::null();
    }
    unsafe { (*handle).framebuffer.as_ptr() }
}

/// Get framebuffer size
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer_size(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).framebuffer.len() as c_int }
}

/// Resize the renderer
#[no_mangle]
pub extern "C" fn dop_renderer_resize(handle: *mut RendererHandle, width: c_int, height: c_int) {
    if handle.is_null() {
        return;
    }
    unsafe {
        let w = width as u32;
        let h = height as u32;
        (*handle).width = w;
        (*handle).height = h;
        (*handle).framebuffer = vec![255u8; (w * h * 4) as usize];
    }
}

// ============================================================================
// Event creation helpers
// ============================================================================

/// Create a close event
#[no_mangle]
pub extern "C" fn dop_event_close() -> DopEvent {
    DopEvent::close()
}

/// Create a resize event
#[no_mangle]
pub extern "C" fn dop_event_resize(width: c_int, height: c_int) -> DopEvent {
    DopEvent::resize(width as u32, height as u32)
}

/// Create a key down event
#[no_mangle]
pub extern "C" fn dop_event_key_down(key: c_int, modifiers: u8) -> DopEvent {
    DopEvent::key_down(key, modifiers)
}

/// Create a key up event
#[no_mangle]
pub extern "C" fn dop_event_key_up(key: c_int, modifiers: u8) -> DopEvent {
    DopEvent::key_up(key, modifiers)
}

/// Create a mouse down event
#[no_mangle]
pub extern "C" fn dop_event_mouse_down(button: u8, x: c_float, y: c_float) -> DopEvent {
    let btn = match button {
        0 => MouseButtonId::Left,
        1 => MouseButtonId::Right,
        2 => MouseButtonId::Middle,
        3 => MouseButtonId::X1,
        4 => MouseButtonId::X2,
        _ => MouseButtonId::Left,
    };
    DopEvent::mouse_down(btn, x as f64, y as f64)
}

/// Create a mouse up event
#[no_mangle]
pub extern "C" fn dop_event_mouse_up(button: u8, x: c_float, y: c_float) -> DopEvent {
    let btn = match button {
        0 => MouseButtonId::Left,
        1 => MouseButtonId::Right,
        2 => MouseButtonId::Middle,
        3 => MouseButtonId::X1,
        4 => MouseButtonId::X2,
        _ => MouseButtonId::Left,
    };
    DopEvent::mouse_up(btn, x as f64, y as f64)
}

/// Create a mouse move event
#[no_mangle]
pub extern "C" fn dop_event_mouse_move(x: c_float, y: c_float) -> DopEvent {
    DopEvent::mouse_move(x as f64, y as f64)
}

/// Create a mouse scroll event
#[no_mangle]
pub extern "C" fn dop_event_mouse_scroll(
    x: c_float,
    y: c_float,
    scroll_x: c_float,
    scroll_y: c_float,
) -> DopEvent {
    DopEvent::mouse_scroll(x as f64, y as f64, scroll_x as f64, scroll_y as f64)
}

// ============================================================================
// Utility functions
// ============================================================================

/// Get the size of DopEvent struct for Julia
#[no_mangle]
pub extern "C" fn dop_event_size() -> c_int {
    std::mem::size_of::<DopEvent>() as c_int
}

/// Get the size of RenderCommand struct for Julia
#[no_mangle]
pub extern "C" fn dop_render_command_size() -> c_int {
    std::mem::size_of::<RenderCommand>() as c_int
}

/// Get library version
#[no_mangle]
pub extern "C" fn dop_version() -> *const c_char {
    static VERSION: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION.as_ptr() as *const c_char
}

// ============================================================================
// Text rendering FFI
// ============================================================================

/// Add a text render command
#[no_mangle]
pub extern "C" fn dop_renderer_add_text(
    handle: *mut RendererHandle,
    text: *const c_char,
    x: c_float,
    y: c_float,
    font_size: c_float,
    r: c_float,
    g: c_float,
    b: c_float,
    a: c_float,
    font_id: c_int,
) {
    if handle.is_null() || text.is_null() {
        return;
    }
    
    let text_str = unsafe {
        match CStr::from_ptr(text).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return,
        }
    };
    
    unsafe {
        (*handle).text_commands.push(TextCommandFFI {
            text: text_str,
            x,
            y,
            font_size,
            color_r: r,
            color_g: g,
            color_b: b,
            color_a: a,
            font_id: font_id as u32,
        });
    }
}

/// Measure text width and height
#[no_mangle]
pub extern "C" fn dop_renderer_measure_text(
    handle: *const RendererHandle,
    text: *const c_char,
    font_size: c_float,
    font_id: c_int,
    out_width: *mut c_float,
    out_height: *mut c_float,
) {
    if handle.is_null() || text.is_null() || out_width.is_null() || out_height.is_null() {
        return;
    }
    
    let text_str = unsafe {
        match CStr::from_ptr(text).to_str() {
            Ok(s) => s,
            Err(_) => {
                *out_width = 0.0;
                *out_height = 0.0;
                return;
            }
        }
    };
    
    unsafe {
        let (w, h) = (*handle).font_manager.measure_text(text_str, font_size, font_id as u32);
        *out_width = w;
        *out_height = h;
    }
}

/// Load a font from file, returns font ID or -1 on failure
#[no_mangle]
pub extern "C" fn dop_renderer_load_font(
    handle: *mut RendererHandle,
    path: *const c_char,
) -> c_int {
    if handle.is_null() || path.is_null() {
        return -1;
    }
    
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };
    
    unsafe {
        match (*handle).font_manager.load_font(path_str) {
            Some(id) => id as c_int,
            None => -1,
        }
    }
}

/// Check if a default font is available
#[no_mangle]
pub extern "C" fn dop_renderer_has_default_font(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe {
        if (*handle).font_manager.get_font(0).is_some() { 1 } else { 0 }
    }
}

// ============================================================================
// Text shaper FFI
// ============================================================================

/// Text shaper handle for paragraph layout
pub struct TextShaperHandle {
    shaper: TextShaper,
}

/// Create a text shaper
#[no_mangle]
pub extern "C" fn dop_text_shaper_create() -> *mut TextShaperHandle {
    Box::into_raw(Box::new(TextShaperHandle {
        shaper: TextShaper::new(),
    }))
}

/// Free a text shaper
#[no_mangle]
pub extern "C" fn dop_text_shaper_free(handle: *mut TextShaperHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Shaped text result for FFI
#[repr(C)]
pub struct ShapedTextFFI {
    pub width: c_float,
    pub height: c_float,
    pub line_count: c_int,
}

/// Shape a paragraph
#[no_mangle]
pub extern "C" fn dop_text_shaper_shape(
    handle: *mut TextShaperHandle,
    text: *const c_char,
    max_width: c_float,
    font_size: c_float,
) -> ShapedTextFFI {
    if handle.is_null() || text.is_null() {
        return ShapedTextFFI {
            width: 0.0,
            height: 0.0,
            line_count: 0,
        };
    }
    
    let text_str = unsafe {
        match CStr::from_ptr(text).to_str() {
            Ok(s) => s,
            Err(_) => return ShapedTextFFI {
                width: 0.0,
                height: 0.0,
                line_count: 0,
            },
        }
    };
    
    unsafe {
        let shaped = (*handle).shaper.shape_paragraph(text_str, max_width, font_size);
        ShapedTextFFI {
            width: shaped.width,
            height: shaped.height,
            line_count: shaped.line_count as c_int,
        }
    }
}

/// Load font into shaper
#[no_mangle]
pub extern "C" fn dop_text_shaper_load_font(
    handle: *mut TextShaperHandle,
    path: *const c_char,
) -> c_int {
    if handle.is_null() || path.is_null() {
        return -1;
    }
    
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        }
    };
    
    unsafe {
        match (*handle).shaper.font_manager_mut().load_font(path_str) {
            Some(id) => id as c_int,
            None => -1,
        }
    }
}

/// Check if shaper has default font
#[no_mangle]
pub extern "C" fn dop_text_shaper_has_font(handle: *const TextShaperHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe {
        if (*handle).shaper.font_manager().get_font(0).is_some() { 1 } else { 0 }
    }
}

// ============================================================================
// PNG export FFI
// ============================================================================

/// Export framebuffer to PNG file
#[no_mangle]
pub extern "C" fn dop_renderer_export_png(
    handle: *const RendererHandle,
    path: *const c_char,
) -> c_int {
    if handle.is_null() || path.is_null() {
        return 0;
    }
    
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return 0,
        }
    };
    
    unsafe {
        let h = &*handle;
        
        // Use the png crate to write the file
        let file = match std::fs::File::create(path_str) {
            Ok(f) => f,
            Err(_) => return 0,
        };
        
        let w = std::io::BufWriter::new(file);
        let mut encoder = png::Encoder::new(w, h.width, h.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        
        let mut writer = match encoder.write_header() {
            Ok(w) => w,
            Err(_) => return 0,
        };
        
        if writer.write_image_data(&h.framebuffer).is_err() {
            return 0;
        }
        
        1
    }
}
