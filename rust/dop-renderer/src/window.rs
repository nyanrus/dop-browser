//! Window management module using winit
//!
//! Provides cross-platform window creation and event handling.

use std::sync::{Arc, Mutex};
use winit::{
    application::ApplicationHandler,
    dpi::LogicalSize,
    event::{ElementState, MouseButton, WindowEvent as WinitWindowEvent},
    event_loop::{ActiveEventLoop, ControlFlow, EventLoop},
    keyboard::{Key, NamedKey},
    window::{CursorIcon, Window, WindowAttributes, WindowId},
};

/// Window configuration options
#[derive(Debug, Clone)]
pub struct WindowConfig {
    pub title: String,
    pub width: u32,
    pub height: u32,
    pub resizable: bool,
    pub decorated: bool,
    pub transparent: bool,
    pub min_width: u32,
    pub min_height: u32,
    pub max_width: u32,
    pub max_height: u32,
}

impl Default for WindowConfig {
    fn default() -> Self {
        Self {
            title: "DOP Browser".to_string(),
            width: 800,
            height: 600,
            resizable: true,
            decorated: true,
            transparent: false,
            min_width: 1,
            min_height: 1,
            max_width: u32::MAX,
            max_height: u32::MAX,
        }
    }
}

/// Event types that can be sent to Julia
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EventType {
    None = 0,
    Close = 1,
    Resize = 2,
    Move = 3,
    KeyDown = 4,
    KeyUp = 5,
    Char = 6,
    MouseDown = 7,
    MouseUp = 8,
    MouseMove = 9,
    MouseScroll = 10,
    MouseEnter = 11,
    MouseLeave = 12,
    Focus = 13,
    Blur = 14,
    Redraw = 15,
}

/// Mouse button identifiers
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseButtonId {
    Left = 0,
    Right = 1,
    Middle = 2,
    X1 = 3,
    X2 = 4,
}

impl From<MouseButton> for MouseButtonId {
    fn from(button: MouseButton) -> Self {
        match button {
            MouseButton::Left => MouseButtonId::Left,
            MouseButton::Right => MouseButtonId::Right,
            MouseButton::Middle => MouseButtonId::Middle,
            MouseButton::Back => MouseButtonId::X1,
            MouseButton::Forward => MouseButtonId::X2,
            MouseButton::Other(_) => MouseButtonId::Left,
        }
    }
}

/// Modifier key flags
pub mod modifiers {
    pub const NONE: u8 = 0;
    pub const SHIFT: u8 = 1;
    pub const CTRL: u8 = 2;
    pub const ALT: u8 = 4;
    pub const SUPER: u8 = 8;
}

/// A window event with associated data
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct DopEvent {
    pub event_type: EventType,
    pub key: i32,
    pub scancode: i32,
    pub modifiers: u8,
    pub char_code: u32,
    pub button: MouseButtonId,
    pub x: f64,
    pub y: f64,
    pub scroll_x: f64,
    pub scroll_y: f64,
    pub width: i32,
    pub height: i32,
    pub timestamp: f64,
}

impl Default for DopEvent {
    fn default() -> Self {
        Self {
            event_type: EventType::None,
            key: 0,
            scancode: 0,
            modifiers: modifiers::NONE,
            char_code: 0,
            button: MouseButtonId::Left,
            x: 0.0,
            y: 0.0,
            scroll_x: 0.0,
            scroll_y: 0.0,
            width: 0,
            height: 0,
            timestamp: 0.0,
        }
    }
}

impl DopEvent {
    pub fn close() -> Self {
        Self {
            event_type: EventType::Close,
            ..Default::default()
        }
    }

    pub fn resize(width: u32, height: u32) -> Self {
        Self {
            event_type: EventType::Resize,
            width: width as i32,
            height: height as i32,
            ..Default::default()
        }
    }

    pub fn redraw() -> Self {
        Self {
            event_type: EventType::Redraw,
            ..Default::default()
        }
    }

    pub fn key_down(key: i32, modifiers: u8) -> Self {
        Self {
            event_type: EventType::KeyDown,
            key,
            modifiers,
            ..Default::default()
        }
    }

    pub fn key_up(key: i32, modifiers: u8) -> Self {
        Self {
            event_type: EventType::KeyUp,
            key,
            modifiers,
            ..Default::default()
        }
    }

    pub fn char_input(c: char) -> Self {
        Self {
            event_type: EventType::Char,
            char_code: c as u32,
            ..Default::default()
        }
    }

    pub fn mouse_down(button: MouseButtonId, x: f64, y: f64) -> Self {
        Self {
            event_type: EventType::MouseDown,
            button,
            x,
            y,
            ..Default::default()
        }
    }

    pub fn mouse_up(button: MouseButtonId, x: f64, y: f64) -> Self {
        Self {
            event_type: EventType::MouseUp,
            button,
            x,
            y,
            ..Default::default()
        }
    }

    pub fn mouse_move(x: f64, y: f64) -> Self {
        Self {
            event_type: EventType::MouseMove,
            x,
            y,
            ..Default::default()
        }
    }

    pub fn mouse_scroll(x: f64, y: f64, scroll_x: f64, scroll_y: f64) -> Self {
        Self {
            event_type: EventType::MouseScroll,
            x,
            y,
            scroll_x,
            scroll_y,
            ..Default::default()
        }
    }

    pub fn mouse_enter() -> Self {
        Self {
            event_type: EventType::MouseEnter,
            ..Default::default()
        }
    }

    pub fn mouse_leave() -> Self {
        Self {
            event_type: EventType::MouseLeave,
            ..Default::default()
        }
    }

    pub fn focus() -> Self {
        Self {
            event_type: EventType::Focus,
            ..Default::default()
        }
    }

    pub fn blur() -> Self {
        Self {
            event_type: EventType::Blur,
            ..Default::default()
        }
    }
}

/// Window handle that wraps winit Window
pub struct WindowHandle {
    window: Option<Arc<Window>>,
    config: WindowConfig,
    events: Vec<DopEvent>,
    is_open: bool,
    mouse_x: f64,
    mouse_y: f64,
    current_modifiers: u8,
}

impl WindowHandle {
    pub fn new(config: WindowConfig) -> Self {
        Self {
            window: None,
            config,
            events: Vec::new(),
            is_open: true,
            mouse_x: 0.0,
            mouse_y: 0.0,
            current_modifiers: modifiers::NONE,
        }
    }

    pub fn window(&self) -> Option<&Arc<Window>> {
        self.window.as_ref()
    }

    pub fn is_open(&self) -> bool {
        self.is_open
    }

    pub fn close(&mut self) {
        self.is_open = false;
    }

    pub fn get_size(&self) -> (u32, u32) {
        if let Some(window) = &self.window {
            let size = window.inner_size();
            (size.width, size.height)
        } else {
            (self.config.width, self.config.height)
        }
    }

    pub fn set_size(&self, width: u32, height: u32) {
        if let Some(window) = &self.window {
            let _ = window.request_inner_size(winit::dpi::PhysicalSize::new(width, height));
        }
    }

    pub fn set_title(&self, title: &str) {
        if let Some(window) = &self.window {
            window.set_title(title);
        }
    }

    pub fn set_cursor(&self, cursor: CursorIcon) {
        if let Some(window) = &self.window {
            window.set_cursor(cursor);
        }
    }

    pub fn request_redraw(&self) {
        if let Some(window) = &self.window {
            window.request_redraw();
        }
    }

    pub fn push_event(&mut self, event: DopEvent) {
        self.events.push(event);
    }

    pub fn poll_events(&mut self) -> Vec<DopEvent> {
        std::mem::take(&mut self.events)
    }

    pub fn mouse_position(&self) -> (f64, f64) {
        (self.mouse_x, self.mouse_y)
    }
}

/// Convert winit Key to a key code
fn key_to_code(key: &Key) -> i32 {
    match key {
        Key::Named(named) => match named {
            NamedKey::Escape => 27,
            NamedKey::Enter => 13,
            NamedKey::Tab => 9,
            NamedKey::Backspace => 8,
            NamedKey::Delete => 127,
            NamedKey::Insert => 155,
            NamedKey::Home => 36,
            NamedKey::End => 35,
            NamedKey::PageUp => 33,
            NamedKey::PageDown => 34,
            NamedKey::ArrowUp => 38,
            NamedKey::ArrowDown => 40,
            NamedKey::ArrowLeft => 37,
            NamedKey::ArrowRight => 39,
            NamedKey::Space => 32,
            NamedKey::F1 => 112,
            NamedKey::F2 => 113,
            NamedKey::F3 => 114,
            NamedKey::F4 => 115,
            NamedKey::F5 => 116,
            NamedKey::F6 => 117,
            NamedKey::F7 => 118,
            NamedKey::F8 => 119,
            NamedKey::F9 => 120,
            NamedKey::F10 => 121,
            NamedKey::F11 => 122,
            NamedKey::F12 => 123,
            NamedKey::Shift => 16,
            NamedKey::Control => 17,
            NamedKey::Alt => 18,
            NamedKey::Super => 91,
            _ => 0,
        },
        Key::Character(c) => {
            if let Some(ch) = c.chars().next() {
                ch.to_ascii_uppercase() as i32
            } else {
                0
            }
        }
        _ => 0,
    }
}

/// Application handler for winit event loop
pub struct DopApp {
    handle: Option<WindowHandle>,
    renderer: Option<crate::renderer::WgpuRenderer>,
    event_queue: Option<Arc<Mutex<Vec<DopEvent>>>>,
}

impl DopApp {
    pub fn new(config: WindowConfig) -> Self {
        Self {
            handle: Some(WindowHandle::new(config)),
            renderer: None,
            event_queue: None,
        }
    }

    pub fn new_with_shared_events(config: WindowConfig, event_queue: Arc<Mutex<Vec<DopEvent>>>) -> Self {
        Self {
            handle: Some(WindowHandle::new(config)),
            renderer: None,
            event_queue: Some(event_queue),
        }
    }

    pub fn take_handle(&mut self) -> Option<WindowHandle> {
        self.handle.take()
    }

    pub fn take_renderer(&mut self) -> Option<crate::renderer::WgpuRenderer> {
        self.renderer.take()
    }

    /// Push event to either local handle or shared queue
    fn push_event(&mut self, event: DopEvent) {
        if let Some(queue) = &self.event_queue {
            if let Ok(mut q) = queue.lock() {
                q.push(event);
            }
        } else if let Some(handle) = &mut self.handle {
            handle.push_event(event);
        }
    }
}

impl ApplicationHandler for DopApp {
    fn resumed(&mut self, event_loop: &ActiveEventLoop) {
        if self.handle.is_none() {
            return;
        }

        let handle = self.handle.as_ref().unwrap();
        let config = &handle.config;

        let window_attrs = WindowAttributes::default()
            .with_title(&config.title)
            .with_inner_size(LogicalSize::new(config.width, config.height))
            .with_resizable(config.resizable)
            .with_decorations(config.decorated)
            .with_transparent(config.transparent)
            .with_min_inner_size(LogicalSize::new(config.min_width, config.min_height));

        match event_loop.create_window(window_attrs) {
            Ok(window) => {
                let window = Arc::new(window);
                let size = window.inner_size();

                // Create renderer
                let renderer =
                    pollster::block_on(crate::renderer::WgpuRenderer::new(window.clone()));

                if let Some(handle) = &mut self.handle {
                    handle.window = Some(window);
                }
                self.push_event(DopEvent::resize(size.width, size.height));
                self.renderer = Some(renderer);
            }
            Err(e) => {
                log::error!("Failed to create window: {:?}", e);
                event_loop.exit();
            }
        }
    }

    fn window_event(
        &mut self,
        event_loop: &ActiveEventLoop,
        _window_id: WindowId,
        event: WinitWindowEvent,
    ) {
        // First, extract needed data from handle without keeping the borrow
        let (current_modifiers, mouse_x, mouse_y) = if let Some(handle) = &self.handle {
            (handle.current_modifiers, handle.mouse_x, handle.mouse_y)
        } else {
            return;
        };

        match event {
            WinitWindowEvent::CloseRequested => {
                self.push_event(DopEvent::close());
                if let Some(handle) = &mut self.handle {
                    handle.is_open = false;
                }
                event_loop.exit();
            }
            WinitWindowEvent::Resized(size) => {
                self.push_event(DopEvent::resize(size.width, size.height));
                if let Some(renderer) = &mut self.renderer {
                    renderer.resize(size.width, size.height);
                }
            }
            WinitWindowEvent::RedrawRequested => {
                self.push_event(DopEvent::redraw());
                if let Some(renderer) = &mut self.renderer {
                    let (width, height) = if let Some(handle) = &self.handle {
                        handle.get_size()
                    } else {
                        (0, 0)
                    };
                    
                    match renderer.render() {
                        Ok(_) => {}
                        Err(wgpu::SurfaceError::Lost) => {
                            renderer.resize(width, height);
                        }
                        Err(wgpu::SurfaceError::OutOfMemory) => {
                            log::error!("Out of GPU memory");
                            event_loop.exit();
                        }
                        Err(e) => log::warn!("Surface error: {:?}", e),
                    }
                }
            }
            WinitWindowEvent::KeyboardInput { event, .. } => {
                let key_code = key_to_code(&event.logical_key);
                match event.state {
                    ElementState::Pressed => {
                        self.push_event(DopEvent::key_down(key_code, current_modifiers));
                    }
                    ElementState::Released => {
                        self.push_event(DopEvent::key_up(key_code, current_modifiers));
                    }
                }

                // Handle text input
                if event.state == ElementState::Pressed {
                    if let Key::Character(c) = &event.logical_key {
                        for ch in c.chars() {
                            self.push_event(DopEvent::char_input(ch));
                        }
                    }
                }
            }
            WinitWindowEvent::ModifiersChanged(state) => {
                let state = state.state();
                let mut mods = modifiers::NONE;
                if state.shift_key() {
                    mods |= modifiers::SHIFT;
                }
                if state.control_key() {
                    mods |= modifiers::CTRL;
                }
                if state.alt_key() {
                    mods |= modifiers::ALT;
                }
                if state.super_key() {
                    mods |= modifiers::SUPER;
                }
                if let Some(handle) = &mut self.handle {
                    handle.current_modifiers = mods;
                }
            }
            WinitWindowEvent::CursorMoved { position, .. } => {
                if let Some(handle) = &mut self.handle {
                    handle.mouse_x = position.x;
                    handle.mouse_y = position.y;
                }
                self.push_event(DopEvent::mouse_move(position.x, position.y));
            }
            WinitWindowEvent::MouseInput { state, button, .. } => {
                let btn = MouseButtonId::from(button);
                match state {
                    ElementState::Pressed => {
                        self.push_event(DopEvent::mouse_down(btn, mouse_x, mouse_y));
                    }
                    ElementState::Released => {
                        self.push_event(DopEvent::mouse_up(btn, mouse_x, mouse_y));
                    }
                }
            }
            WinitWindowEvent::MouseWheel { delta, .. } => {
                let (dx, dy) = match delta {
                    winit::event::MouseScrollDelta::LineDelta(x, y) => (x as f64, y as f64),
                    winit::event::MouseScrollDelta::PixelDelta(pos) => (pos.x, pos.y),
                };
                self.push_event(DopEvent::mouse_scroll(mouse_x, mouse_y, dx, dy));
            }
            WinitWindowEvent::CursorEntered { .. } => {
                self.push_event(DopEvent::mouse_enter());
            }
            WinitWindowEvent::CursorLeft { .. } => {
                self.push_event(DopEvent::mouse_leave());
            }
            WinitWindowEvent::Focused(focused) => {
                if focused {
                    self.push_event(DopEvent::focus());
                } else {
                    self.push_event(DopEvent::blur());
                }
            }
            _ => {}
        }
    }
}

/// Create and run a window with the event loop
pub fn run_window(config: WindowConfig) -> Result<(), Box<dyn std::error::Error>> {
    env_logger::init();

    let event_loop = EventLoop::new()?;
    event_loop.set_control_flow(ControlFlow::Poll);

    let mut app = DopApp::new(config);
    event_loop.run_app(&mut app)?;

    Ok(())
}
