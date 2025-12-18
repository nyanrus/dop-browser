//! FFI module for Julia integration
//!
//! This module provides C-compatible functions that can be called from Julia
//! using the `ccall` mechanism. The Rust library is built using the unified
//! BinaryBuilder configuration for cross-platform distribution.

use std::ffi::{c_char, c_float, c_int, CStr};
use std::ptr;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use winit::event_loop::EventLoopProxy;

use crate::renderer::RenderCommand;
#[cfg(feature = "software")]
use crate::software::{SoftwareRenderer, TextCommand};
#[cfg(not(feature = "software"))]
use crate::text::FontManager;
use crate::text::TextShaper;
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
pub extern "C" fn dop_window_create_headless(width: c_int, height: c_int) -> *mut WindowHandle {
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
    unsafe {
        if (*handle).is_open() {
            1
        } else {
            0
        }
    }
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
// Threaded Window for Onscreen Rendering
// ============================================================================

/// A threaded window handle that runs winit event loop in a separate thread
pub struct ThreadedWindowHandle {
    events: Arc<Mutex<Vec<DopEvent>>>,
    is_open: Arc<Mutex<bool>>,
    size: Arc<Mutex<(u32, u32)>>,
    external_framebuffer: Arc<Mutex<Option<(Vec<u8>, u32, u32)>>>,
    event_proxy: Arc<Mutex<Option<EventLoopProxy<()>>>>,
    thread_handle: Option<thread::JoinHandle<()>>,
}

impl ThreadedWindowHandle {
    pub fn is_open(&self) -> bool {
        *self.is_open.lock().unwrap()
    }

    pub fn poll_events(&self) -> Vec<DopEvent> {
        let mut events = self.events.lock().unwrap();
        std::mem::take(&mut *events)
    }

    pub fn get_size(&self) -> (u32, u32) {
        *self.size.lock().unwrap()
    }
}

/// Request the threaded window to close (sets closed flag and wakes event loop)
#[no_mangle]
pub extern "C" fn dop_window_request_close_threaded(handle: *mut ThreadedWindowHandle) {
    if handle.is_null() {
        return;
    }

    unsafe {
        // Set closed flag
        if let Ok(mut is_open) = (*handle).is_open.lock() {
            *is_open = false;
        }

        // Try to wake the event loop so it can exit promptly
        if let Ok(proxy_lock) = (*handle).event_proxy.lock() {
            if let Some(proxy) = &*proxy_lock {
                let _ = proxy.send_event(());
            }
        }
    }
}

/// Join the threaded window thread, waiting up to `timeout_ms` milliseconds.
/// Returns 1 on success (thread joined or already gone), 0 on timeout/failure.
#[no_mangle]
pub extern "C" fn dop_window_join_threaded_timeout(
    handle: *mut ThreadedWindowHandle,
    timeout_ms: c_int,
) -> c_int {
    if handle.is_null() {
        return 0;
    }

    // Convert timeout to Duration; negative timeout means wait indefinitely
    let timeout = if timeout_ms < 0 {
        None
    } else {
        Some(Duration::from_millis(timeout_ms as u64))
    };

    unsafe {
        let start = Instant::now();

        // Wait for the thread to observe the closed flag (polling). This
        // avoids joining while the thread is still in platform code. If the
        // caller provided a timeout, honor it.
        loop {
            if let Ok(is_open_lock) = (*handle).is_open.lock() {
                if !*is_open_lock {
                    break;
                }
            } else {
                // Couldn't lock; break and try to join as best-effort
                break;
            }

            if let Some(t) = timeout {
                if start.elapsed() >= t {
                    return 0;
                }
            }

            // Sleep a bit before re-checking
            std::thread::sleep(Duration::from_millis(5));
        }

        // Take the join handle and join it. If it's already None, return success.
        if let Some(jh) = (*handle).thread_handle.take() {
            let _ = jh.join();
            1
        } else {
            // Nothing to join; treat as success
            1
        }
    }
}

impl Drop for ThreadedWindowHandle {
    fn drop(&mut self) {
        // Mark as closed so the event loop thread can update its state.
        //
        // NOTE: previously we attempted to join the event-loop thread here.
        // Joining a thread during Drop — particularly across an FFI boundary
        // where the caller (Julia) may hold runtime locks — can lead to
        // deadlocks or crashes. Instead of blocking here, signal the event
        // loop (best-effort) and *detach* the thread by dropping the
        // JoinHandle. The event-loop thread still holds its own clone(s) of
        // the shared Arcs and will exit on its own when appropriate.
        *self.is_open.lock().unwrap() = false;

        // Try to wake the event loop so it can notice the closed flag and exit.
        if let Ok(proxy_lock) = self.event_proxy.lock() {
            if let Some(proxy) = &*proxy_lock {
                let _ = proxy.send_event(());
            }
        }

        // Drop the JoinHandle without joining to avoid potential deadlocks
        // across language runtimes. The spawned thread will continue running
        // and will eventually terminate; its resources will be cleaned up by
        // the OS when it exits.
        let _ = self.thread_handle.take();
    }
}

/// Create an onscreen window (runs in a separate thread)
/// Returns a handle that can be used to poll events
#[no_mangle]
pub extern "C" fn dop_window_create_onscreen(
    width: c_int,
    height: c_int,
    title: *const c_char,
) -> *mut ThreadedWindowHandle {
    let title = if title.is_null() {
        "DOP Browser".to_string()
    } else {
        unsafe {
            CStr::from_ptr(title)
                .to_str()
                .unwrap_or("DOP Browser")
                .to_string()
        }
    };

    let config = WindowConfig {
        title,
        width: width as u32,
        height: height as u32,
        ..Default::default()
    };

    let events = Arc::new(Mutex::new(Vec::new()));
    let is_open = Arc::new(Mutex::new(true));
    let size = Arc::new(Mutex::new((width as u32, height as u32)));
    let external_framebuffer = Arc::new(Mutex::new(None));
    let event_proxy = Arc::new(Mutex::new(None));

    let events_clone = events.clone();
    let is_open_clone = is_open.clone();
    let size_clone = size.clone();
    let external_framebuffer_clone = external_framebuffer.clone();
    let event_proxy_clone = event_proxy.clone();

    // Spawn a thread to run the event loop
    // We'll send the EventLoop proxy back to the creator thread via a channel
    let (proxy_tx, proxy_rx) = std::sync::mpsc::channel();

    let thread_handle = thread::spawn(move || {
        use crate::window::DopApp;
        use winit::event_loop::{ControlFlow, EventLoop, EventLoopBuilder};

        // Create event loop - use builder to enable any_thread on Unix platforms
        // We'll use unit `()` as the user event type so we can receive proxy wakeups.
        let event_loop_result = {
            #[cfg(any(
                target_os = "linux",
                target_os = "dragonfly",
                target_os = "freebsd",
                target_os = "netbsd",
                target_os = "openbsd"
            ))]
            {
                use winit::platform::x11::EventLoopBuilderExtX11;

                let mut builder = EventLoopBuilder::new();
                // Enable any_thread to allow event loop creation on non-main thread
                // Build with user event type = () so we can create a proxy
                builder.with_any_thread(true).build()
            }

            #[cfg(not(any(
                target_os = "linux",
                target_os = "dragonfly",
                target_os = "freebsd",
                target_os = "netbsd",
                target_os = "openbsd"
            )))]
            {
                EventLoop::new()
            }
        };

        let event_loop = match event_loop_result {
            Ok(el) => el,
            Err(e) => {
                log::error!("Failed to create event loop: {:?}", e);
                *is_open_clone.lock().unwrap() = false;
                return;
            }
        };

        // Send the proxy back to the creator thread so it can request redraws
        let proxy = event_loop.create_proxy();
        let _ = proxy_tx.send(proxy);

        event_loop.set_control_flow(ControlFlow::Poll);

        // Create app with shared event queue and external framebuffer
        let mut app = crate::window::DopApp::new_with_shared_events(
            config,
            events_clone.clone(),
            Some(external_framebuffer_clone.clone()),
        );

        // (The event loop host will keep its own copy of the proxy; the creator
        // thread will receive the proxy from the channel and store it into the
        // shared `event_proxy` Arc so it can wake the event loop.)

        // Run the event loop
        let result = event_loop.run_app(&mut app);

        if let Err(e) = result {
            log::error!("Event loop error: {:?}", e);
        }

        // Get the final state from the app
        if let Some(handle) = app.take_handle() {
            // Update size
            let final_size = handle.get_size();
            *size_clone.lock().unwrap() = final_size;
        }

        // Mark as closed
        *is_open_clone.lock().unwrap() = false;
    });

    // Receive the EventLoopProxy from the spawned thread (with timeout)
    use std::time::Duration;
    if let Ok(proxy) = proxy_rx.recv_timeout(Duration::from_millis(5000)) {
        if let Ok(mut p) = event_proxy.lock() {
            *p = Some(proxy);
        }
    } else {
        log::warn!("Failed to receive EventLoopProxy from window thread within timeout");
    }

    Box::into_raw(Box::new(ThreadedWindowHandle {
        events,
        is_open,
        size,
        external_framebuffer,
        event_proxy,
        thread_handle: Some(thread_handle),
    }))
}

/// Update the threaded window external framebuffer with an RGBA buffer (copied).
#[no_mangle]
pub extern "C" fn dop_window_update_framebuffer_threaded(
    handle: *mut ThreadedWindowHandle,
    data: *const u8,
    size: c_int,
    width: c_int,
    height: c_int,
) {
    if handle.is_null() || data.is_null() || size <= 0 || width <= 0 || height <= 0 {
        return;
    }
    unsafe {
        log::debug!(
            "ffi: dop_window_update_framebuffer_threaded called (data_len={} width={} height={})",
            size,
            width,
            height
        );

        // If the window has been closed, skip updating the framebuffer
        if let Ok(is_open) = (*handle).is_open.lock() {
            if !*is_open {
                log::debug!("ffi: window handle not open; skipping framebuffer update");
                return;
            }
        }

        let slice = std::slice::from_raw_parts(data, size as usize);
        // Copy the provided data into the shared external_framebuffer
        if let Ok(mut guard) = (*handle).external_framebuffer.lock() {
            *guard = Some((slice.to_vec(), width as u32, height as u32));
        } else {
            log::warn!("ffi: failed to lock external_framebuffer mutex");
            return;
        }

        // Notify event loop to present the new framebuffer (best-effort).
        // Clone the proxy out of the mutex so we don't hold the lock while sending.
        if let Ok(proxy_lock) = (*handle).event_proxy.lock() {
            if let Some(proxy) = &*proxy_lock {
                match proxy.send_event(()) {
                    Ok(_) => log::debug!("ffi: sent user event to event loop proxy"),
                    Err(e) => log::debug!("ffi: failed to send user event to proxy: {:?}", e),
                }
            } else {
                log::debug!("ffi: event_proxy is None; cannot wake event loop");
            }
        } else {
            log::warn!("ffi: failed to lock event_proxy mutex");
        }
        log::debug!("ffi: dop_window_update_framebuffer_threaded returning");
    }
}

/// Free a threaded window handle
#[no_mangle]
pub extern "C" fn dop_window_free_threaded(handle: *mut ThreadedWindowHandle) {
    if !handle.is_null() {
        unsafe {
            drop(Box::from_raw(handle));
        }
    }
}

/// Check if threaded window is open
#[no_mangle]
pub extern "C" fn dop_window_is_open_threaded(handle: *const ThreadedWindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe {
        if (*handle).is_open() {
            1
        } else {
            0
        }
    }
}

/// Poll events from threaded window
#[no_mangle]
pub extern "C" fn dop_window_poll_events_threaded(
    handle: *mut ThreadedWindowHandle,
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

/// Get threaded window width
#[no_mangle]
pub extern "C" fn dop_window_get_width_threaded(handle: *const ThreadedWindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).get_size().0 as c_int }
}

/// Get threaded window height
#[no_mangle]
pub extern "C" fn dop_window_get_height_threaded(handle: *const ThreadedWindowHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).get_size().1 as c_int }
}

// ============================================================================
// Renderer FFI
// ============================================================================

/// Renderer handle for FFI - uses software rendering by default
#[cfg(feature = "software")]
pub struct RendererHandle {
    renderer: SoftwareRenderer,
}

/// Renderer handle for FFI - fallback when software feature is disabled
#[cfg(not(feature = "software"))]
#[allow(dead_code)]
pub struct RendererHandle {
    commands: Vec<RenderCommand>,
    text_commands: Vec<TextCommandFFI>,
    framebuffer: Vec<u8>,
    width: u32,
    height: u32,
    font_manager: FontManager,
}

/// Text command for FFI (used when software feature is disabled)
#[cfg(not(feature = "software"))]
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

/// Create a headless renderer using software rendering (tiny-skia)
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_create_headless(width: c_int, height: c_int) -> *mut RendererHandle {
    let renderer = SoftwareRenderer::new(width as u32, height as u32);
    Box::into_raw(Box::new(RendererHandle { renderer }))
}

/// Create a headless renderer (fallback implementation)
#[cfg(not(feature = "software"))]
#[no_mangle]
pub extern "C" fn dop_renderer_create_headless(width: c_int, height: c_int) -> *mut RendererHandle {
    let w = width as u32;
    let h = height as u32;
    let framebuffer = vec![255u8; (w * h * 4) as usize]; // White background

    Box::into_raw(Box::new(RendererHandle {
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
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_clear(handle: *mut RendererHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        (*handle).renderer.clear();
    }
}

/// Clear the renderer (fallback)
#[cfg(not(feature = "software"))]
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
#[cfg(feature = "software")]
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
    unsafe {
        (*handle).renderer.set_clear_color(r, g, b, a);
    }
}

/// Set clear color (fallback)
#[cfg(not(feature = "software"))]
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
#[cfg(feature = "software")]
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
        (*handle).renderer.add_rect(RenderCommand {
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

/// Add a rectangle render command (fallback)
#[cfg(not(feature = "software"))]
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

/// Render the frame using software rendering (tiny-skia)
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_render(handle: *mut RendererHandle) {
    if handle.is_null() {
        return;
    }
    unsafe {
        (*handle).renderer.render();
    }
}

/// Render the frame (fallback software rasterization)
#[cfg(not(feature = "software"))]
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
                            handle.framebuffer[dst_idx] = ((text_buffer[src_idx] as f32 * src_a
                                + handle.framebuffer[dst_idx] as f32 * inv_a)
                                as u8)
                                .min(255);
                            handle.framebuffer[dst_idx + 1] = ((text_buffer[src_idx + 1] as f32
                                * src_a
                                + handle.framebuffer[dst_idx + 1] as f32 * inv_a)
                                as u8)
                                .min(255);
                            handle.framebuffer[dst_idx + 2] = ((text_buffer[src_idx + 2] as f32
                                * src_a
                                + handle.framebuffer[dst_idx + 2] as f32 * inv_a)
                                as u8)
                                .min(255);
                            handle.framebuffer[dst_idx + 3] = ((src_a * 255.0
                                + handle.framebuffer[dst_idx + 3] as f32 * inv_a)
                                as u8)
                                .min(255);
                        }
                    }
                }
            }
        }
    }
}

/// Get framebuffer pointer
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer(handle: *const RendererHandle) -> *const u8 {
    if handle.is_null() {
        return ptr::null();
    }
    unsafe { (*handle).renderer.get_framebuffer().as_ptr() }
}

/// Get framebuffer pointer (fallback)
#[cfg(not(feature = "software"))]
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer(handle: *const RendererHandle) -> *const u8 {
    if handle.is_null() {
        return ptr::null();
    }
    unsafe { (*handle).framebuffer.as_ptr() }
}

/// Get framebuffer size
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer_size(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).renderer.get_framebuffer_size() as c_int }
}

/// Get framebuffer size (fallback)
#[cfg(not(feature = "software"))]
#[no_mangle]
pub extern "C" fn dop_renderer_get_framebuffer_size(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe { (*handle).framebuffer.len() as c_int }
}

/// Resize the renderer
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_resize(handle: *mut RendererHandle, width: c_int, height: c_int) {
    if handle.is_null() {
        return;
    }
    unsafe {
        (*handle).renderer.resize(width as u32, height as u32);
    }
}

/// Resize the renderer (fallback)
#[cfg(not(feature = "software"))]
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

/// Add a text render command (software)
#[cfg(feature = "software")]
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
    _font_id: c_int,
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
        (*handle).renderer.add_text(TextCommand {
            text: text_str,
            x,
            y,
            font_size,
            color_r: r,
            color_g: g,
            color_b: b,
            color_a: a,
            font_id: _font_id as u32,
        });
    }
}

/// Add a text render command (fallback)
#[cfg(not(feature = "software"))]
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

/// Measure text width and height (software)
#[cfg(feature = "software")]
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
        let (w, h) =
            (*handle)
                .renderer
                .font_manager()
                .measure_text(text_str, font_size, font_id as u32);
        *out_width = w;
        *out_height = h;
    }
}

/// Measure text width and height (fallback)
#[cfg(not(feature = "software"))]
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
        let (w, h) = (*handle)
            .font_manager
            .measure_text(text_str, font_size, font_id as u32);
        *out_width = w;
        *out_height = h;
    }
}

/// Load a font from file, returns font ID or -1 on failure (software)
#[cfg(feature = "software")]
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
        match (*handle).renderer.font_manager_mut().load_font(path_str) {
            Some(id) => id as c_int,
            None => -1,
        }
    }
}

/// Load a font from file, returns font ID or -1 on failure (fallback)
#[cfg(not(feature = "software"))]
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

/// Check if a default font is available (software)
#[cfg(feature = "software")]
#[no_mangle]
pub extern "C" fn dop_renderer_has_default_font(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe {
        if (*handle).renderer.font_manager().get_font(0).is_some() {
            1
        } else {
            0
        }
    }
}

/// Check if a default font is available (fallback)
#[cfg(not(feature = "software"))]
#[no_mangle]
pub extern "C" fn dop_renderer_has_default_font(handle: *const RendererHandle) -> c_int {
    if handle.is_null() {
        return 0;
    }
    unsafe {
        if (*handle).font_manager.get_font(0).is_some() {
            1
        } else {
            0
        }
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
            Err(_) => {
                return ShapedTextFFI {
                    width: 0.0,
                    height: 0.0,
                    line_count: 0,
                }
            }
        }
    };

    unsafe {
        let shaped = (*handle)
            .shaper
            .shape_paragraph(text_str, max_width, font_size);
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
        if (*handle).shaper.font_manager().get_font(0).is_some() {
            1
        } else {
            0
        }
    }
}

// ============================================================================
// PNG export FFI
// ============================================================================

/// Export framebuffer to PNG file (software)
#[cfg(feature = "software")]
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
        match (*handle).renderer.export_png(path_str) {
            Ok(_) => 1,
            Err(_) => 0,
        }
    }
}

/// Export framebuffer to PNG file (fallback)
#[cfg(not(feature = "software"))]
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
