//! FFI module for Julia integration
//!
//! This module provides C-compatible functions that can be called from Julia
//! using the `ccall` mechanism.

use std::ffi::{c_char, c_float, c_int, CStr};
use std::ptr;

use crate::renderer::{RenderCommand, WgpuRenderer};
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
    framebuffer: Vec<u8>,
    width: u32,
    height: u32,
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
        framebuffer,
        width: w,
        height: h,
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
    
    // Software rasterize each command
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
