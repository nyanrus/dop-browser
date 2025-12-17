"""
    Window

Platform windowing abstraction layer for interactive UI applications.

This module provides an abstraction layer for windowing systems, enabling 
the Content-- UI library to run as interactive desktop applications.

## Supported Backends
- **Software** (default): In-memory rendering for headless/testing
- **Cairo**: High-quality 2D rendering with Cairo
- Future: Native platform windows (X11, Wayland, Win32, Cocoa)

## Usage

```julia
using DOPBrowser.Window

# Create a window configuration
config = WindowConfig(
    title = "My App",
    width = 800,
    height = 600,
    resizable = true,
    vsync = true
)

# Create a window
window = create_window(config)

# Main loop
while is_open(window)
    # Poll events
    events = poll_events!(window)
    
    for event in events
        if event.type == EVENT_CLOSE
            close!(window)
        elseif event.type == EVENT_KEY_DOWN
            # Handle key press
        end
    end
    
    # Render frame
    render!(window, ui_context)
end
```
"""
module Window

export WindowConfig, WindowHandle, WindowEvent, EventType
export create_window, destroy!, is_open, close!
export poll_events!, wait_events!, post_redisplay!
export get_size, set_size!, get_position, set_position!
export set_title!, set_cursor!, get_scale_factor
export get_clipboard, set_clipboard!
export render!, swap_buffers!

# Event types
export EVENT_NONE, EVENT_CLOSE, EVENT_RESIZE, EVENT_MOVE
export EVENT_KEY_DOWN, EVENT_KEY_UP, EVENT_CHAR
export EVENT_MOUSE_DOWN, EVENT_MOUSE_UP, EVENT_MOUSE_MOVE
export EVENT_MOUSE_SCROLL, EVENT_MOUSE_ENTER, EVENT_MOUSE_LEAVE
export EVENT_FOCUS, EVENT_BLUR, EVENT_DROP

# Cursor types
export CURSOR_ARROW, CURSOR_TEXT, CURSOR_POINTER, CURSOR_CROSSHAIR
export CURSOR_RESIZE_NS, CURSOR_RESIZE_EW, CURSOR_RESIZE_NWSE, CURSOR_RESIZE_NESW

# Modifier keys
export MOD_NONE, MOD_SHIFT, MOD_CTRL, MOD_ALT, MOD_SUPER

# ============================================================================
# Enums and Constants
# ============================================================================

"""
Event types for window events.
"""
@enum EventType::UInt8 begin
    EVENT_NONE = 0
    EVENT_CLOSE = 1
    EVENT_RESIZE = 2
    EVENT_MOVE = 3
    EVENT_KEY_DOWN = 4
    EVENT_KEY_UP = 5
    EVENT_CHAR = 6
    EVENT_MOUSE_DOWN = 7
    EVENT_MOUSE_UP = 8
    EVENT_MOUSE_MOVE = 9
    EVENT_MOUSE_SCROLL = 10
    EVENT_MOUSE_ENTER = 11
    EVENT_MOUSE_LEAVE = 12
    EVENT_FOCUS = 13
    EVENT_BLUR = 14
    EVENT_DROP = 15
end

"""
Cursor types.
"""
@enum CursorType::UInt8 begin
    CURSOR_ARROW = 0
    CURSOR_TEXT = 1
    CURSOR_POINTER = 2
    CURSOR_CROSSHAIR = 3
    CURSOR_RESIZE_NS = 4
    CURSOR_RESIZE_EW = 5
    CURSOR_RESIZE_NWSE = 6
    CURSOR_RESIZE_NESW = 7
    CURSOR_WAIT = 8
    CURSOR_HELP = 9
    CURSOR_GRAB = 10
    CURSOR_GRABBING = 11
    CURSOR_NOT_ALLOWED = 12
end

"""
Keyboard modifier flags.
"""
const MOD_NONE  = UInt8(0)
const MOD_SHIFT = UInt8(1)
const MOD_CTRL  = UInt8(2)
const MOD_ALT   = UInt8(4)
const MOD_SUPER = UInt8(8)

"""
Mouse button identifiers.
"""
@enum MouseButton::UInt8 begin
    MOUSE_LEFT = 0
    MOUSE_RIGHT = 1
    MOUSE_MIDDLE = 2
    MOUSE_X1 = 3
    MOUSE_X2 = 4
end

export MouseButton, MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_X1, MOUSE_X2

# ============================================================================
# Data Structures
# ============================================================================

"""
    WindowEvent

A window event containing type and associated data.
"""
struct WindowEvent
    type::EventType
    # Keyboard
    key::Int32            # Key code
    scancode::Int32       # Physical scancode
    modifiers::UInt8      # Modifier key flags
    char::Char            # Character for text input
    # Mouse
    button::MouseButton   # Mouse button
    x::Float64            # Mouse X position
    y::Float64            # Mouse Y position
    scroll_x::Float64     # Scroll X delta
    scroll_y::Float64     # Scroll Y delta
    # Window
    width::Int32          # New window width
    height::Int32         # New window height
    # Misc
    timestamp::Float64    # Event timestamp
    
    function WindowEvent(type::EventType;
                         key::Int32 = Int32(0),
                         scancode::Int32 = Int32(0),
                         modifiers::UInt8 = MOD_NONE,
                         char::Char = '\0',
                         button::MouseButton = MOUSE_LEFT,
                         x::Float64 = 0.0,
                         y::Float64 = 0.0,
                         scroll_x::Float64 = 0.0,
                         scroll_y::Float64 = 0.0,
                         width::Int32 = Int32(0),
                         height::Int32 = Int32(0),
                         timestamp::Float64 = time())
        new(type, key, scancode, modifiers, char, button, x, y, 
            scroll_x, scroll_y, width, height, timestamp)
    end
end

"""
    WindowConfig

Configuration for creating a window.
"""
struct WindowConfig
    title::String
    width::Int32
    height::Int32
    x::Union{Int32, Nothing}      # Window X position (nothing for centered)
    y::Union{Int32, Nothing}      # Window Y position (nothing for centered)
    resizable::Bool
    decorated::Bool               # Show title bar and borders
    transparent::Bool             # Transparent background
    always_on_top::Bool
    vsync::Bool
    high_dpi::Bool                # Enable high DPI scaling
    min_width::Int32
    min_height::Int32
    max_width::Int32
    max_height::Int32
    backend::Symbol               # :software, :cairo, :opengl, :vulkan
    
    function WindowConfig(;
                          title::String = "DOP Browser",
                          width::Int = 800,
                          height::Int = 600,
                          x::Union{Int, Nothing} = nothing,
                          y::Union{Int, Nothing} = nothing,
                          resizable::Bool = true,
                          decorated::Bool = true,
                          transparent::Bool = false,
                          always_on_top::Bool = false,
                          vsync::Bool = true,
                          high_dpi::Bool = true,
                          min_width::Integer = 1,
                          min_height::Integer = 1,
                          max_width::Integer = Int(typemax(Int32)),
                          max_height::Integer = Int(typemax(Int32)),
                          backend::Symbol = :cairo)
        new(title, Int32(width), Int32(height),
            x === nothing ? nothing : Int32(x),
            y === nothing ? nothing : Int32(y),
            resizable, decorated, transparent, always_on_top,
            vsync, high_dpi,
            Int32(min_width), Int32(min_height),
            Int32(max_width), Int32(max_height),
            backend)
    end
end

"""
    WindowHandle

Handle to a window instance.
"""
mutable struct WindowHandle
    id::UInt64
    config::WindowConfig
    width::Int32
    height::Int32
    x::Int32
    y::Int32
    scale_factor::Float64
    is_open::Bool
    is_focused::Bool
    is_minimized::Bool
    is_maximized::Bool
    # Input state
    mouse_x::Float64
    mouse_y::Float64
    mouse_buttons::UInt8          # Button state bitmask
    key_states::Set{Int32}        # Pressed keys
    modifiers::UInt8
    # Cursor
    current_cursor::CursorType
    cursor_visible::Bool
    # Clipboard
    clipboard::String
    # Event queue
    event_queue::Vector{WindowEvent}
    # Backend-specific data
    backend_data::Any
    # Cairo context (for Cairo backend)
    cairo_context::Any
    # Framebuffer for software rendering
    framebuffer::Vector{UInt8}
    
    function WindowHandle(config::WindowConfig)
        new(
            rand(UInt64),
            config,
            config.width,
            config.height,
            config.x === nothing ? Int32(0) : config.x,
            config.y === nothing ? Int32(0) : config.y,
            1.0,
            true,
            true,
            false,
            false,
            0.0,
            0.0,
            UInt8(0),
            Set{Int32}(),
            MOD_NONE,
            CURSOR_ARROW,
            true,
            "",
            WindowEvent[],
            nothing,
            nothing,
            UInt8[]
        )
    end
end

# ============================================================================
# Window Management
# ============================================================================

"""
    create_window(config::WindowConfig = WindowConfig()) -> WindowHandle

Create a new window with the given configuration.
"""
function create_window(config::WindowConfig = WindowConfig())::WindowHandle
    handle = WindowHandle(config)
    
    # Initialize backend
    if config.backend == :cairo
        initialize_cairo_backend!(handle)
    elseif config.backend == :software
        initialize_software_backend!(handle)
    else
        # Default to software backend
        initialize_software_backend!(handle)
    end
    
    return handle
end

"""
Initialize Cairo rendering backend.
"""
function initialize_cairo_backend!(handle::WindowHandle)
    try
        # Import Cairo module
        CairoRenderer = @eval begin
            import ...Renderer.CairoRenderer as CR
            CR
        end
        
        # Create Cairo context
        handle.cairo_context = CairoRenderer.create_cairo_context(
            Int(handle.width), Int(handle.height)
        )
        handle.backend_data = :cairo
    catch e
        @warn "Cairo initialization failed, falling back to software" exception=e
        initialize_software_backend!(handle)
    end
end

"""
Initialize software rendering backend.
"""
function initialize_software_backend!(handle::WindowHandle)
    # Allocate framebuffer
    handle.framebuffer = zeros(UInt8, handle.width * handle.height * 4)
    handle.backend_data = :software
end

"""
    destroy!(handle::WindowHandle)

Destroy a window and release its resources.
"""
function destroy!(handle::WindowHandle)
    handle.is_open = false
    handle.backend_data = nothing
    handle.cairo_context = nothing
    empty!(handle.framebuffer)
    empty!(handle.event_queue)
end

"""
    is_open(handle::WindowHandle) -> Bool

Check if the window is still open.
"""
is_open(handle::WindowHandle)::Bool = handle.is_open

"""
    close!(handle::WindowHandle)

Request the window to close.
"""
function close!(handle::WindowHandle)
    push!(handle.event_queue, WindowEvent(EVENT_CLOSE))
    handle.is_open = false
end

# ============================================================================
# Event Handling
# ============================================================================

"""
    poll_events!(handle::WindowHandle) -> Vector{WindowEvent}

Poll for pending events without blocking. Returns a copy of pending events
and clears the event queue.
"""
function poll_events!(handle::WindowHandle)::Vector{WindowEvent}
    events = copy(handle.event_queue)
    empty!(handle.event_queue)
    return events
end

"""
    wait_events!(handle::WindowHandle; timeout::Float64 = Inf) -> Vector{WindowEvent}

Wait for events with optional timeout. In the software/Cairo backends,
this is equivalent to poll_events! since there's no actual window.
"""
function wait_events!(handle::WindowHandle; timeout::Float64 = Inf)::Vector{WindowEvent}
    # For software backend, just return current events
    return poll_events!(handle)
end

"""
    post_redisplay!(handle::WindowHandle)

Request a redisplay of the window.
"""
function post_redisplay!(handle::WindowHandle)
    # For software backend, this is a no-op
    # In a real windowing backend, this would mark the window as needing redraw
end

"""
    inject_event!(handle::WindowHandle, event::WindowEvent)

Inject an event into the window's event queue. Useful for testing
or programmatic event generation.
"""
function inject_event!(handle::WindowHandle, event::WindowEvent)
    push!(handle.event_queue, event)
    
    # Update internal state based on event
    if event.type == EVENT_KEY_DOWN
        push!(handle.key_states, event.key)
        handle.modifiers = event.modifiers
    elseif event.type == EVENT_KEY_UP
        delete!(handle.key_states, event.key)
        handle.modifiers = event.modifiers
    elseif event.type == EVENT_MOUSE_MOVE
        handle.mouse_x = event.x
        handle.mouse_y = event.y
    elseif event.type == EVENT_MOUSE_DOWN
        button_bit = UInt8(1) << UInt8(event.button)
        handle.mouse_buttons |= button_bit
    elseif event.type == EVENT_MOUSE_UP
        button_bit = UInt8(1) << UInt8(event.button)
        handle.mouse_buttons &= ~button_bit
    elseif event.type == EVENT_RESIZE
        handle.width = event.width
        handle.height = event.height
        resize_backend!(handle)
    elseif event.type == EVENT_FOCUS
        handle.is_focused = true
    elseif event.type == EVENT_BLUR
        handle.is_focused = false
    end
end

export inject_event!

"""
Resize the backend buffers when window size changes.
"""
function resize_backend!(handle::WindowHandle)
    if handle.backend_data == :software
        resize!(handle.framebuffer, handle.width * handle.height * 4)
        fill!(handle.framebuffer, 0)
    elseif handle.backend_data == :cairo && handle.cairo_context !== nothing
        try
            CairoRenderer = @eval begin
                import ...Renderer.CairoRenderer as CR
                CR
            end
            handle.cairo_context = CairoRenderer.create_cairo_context(
                Int(handle.width), Int(handle.height)
            )
        catch e
            @warn "Failed to resize Cairo context" exception=e
        end
    end
end

# ============================================================================
# Window Properties
# ============================================================================

"""
    get_size(handle::WindowHandle) -> Tuple{Int32, Int32}

Get the current window size (width, height).
"""
get_size(handle::WindowHandle) = (handle.width, handle.height)

"""
    set_size!(handle::WindowHandle, width::Int, height::Int)

Set the window size.
"""
function set_size!(handle::WindowHandle, width::Int, height::Int)
    old_width, old_height = handle.width, handle.height
    handle.width = Int32(width)
    handle.height = Int32(height)
    
    if old_width != width || old_height != height
        resize_backend!(handle)
        inject_event!(handle, WindowEvent(EVENT_RESIZE, 
                                          width=Int32(width), height=Int32(height)))
    end
end

"""
    get_position(handle::WindowHandle) -> Tuple{Int32, Int32}

Get the window position (x, y).
"""
get_position(handle::WindowHandle) = (handle.x, handle.y)

"""
    set_position!(handle::WindowHandle, x::Int, y::Int)

Set the window position.
"""
function set_position!(handle::WindowHandle, x::Int, y::Int)
    handle.x = Int32(x)
    handle.y = Int32(y)
    inject_event!(handle, WindowEvent(EVENT_MOVE))
end

"""
    set_title!(handle::WindowHandle, title::String)

Set the window title.
"""
function set_title!(handle::WindowHandle, title::String)
    # Note: For software backend, this just updates the config
    # A real backend would update the native window title
end

"""
    set_cursor!(handle::WindowHandle, cursor::CursorType)

Set the mouse cursor type.
"""
function set_cursor!(handle::WindowHandle, cursor::CursorType)
    handle.current_cursor = cursor
end

"""
    get_scale_factor(handle::WindowHandle) -> Float64

Get the window's scale factor for high DPI displays.
"""
get_scale_factor(handle::WindowHandle)::Float64 = handle.scale_factor

"""
    get_clipboard(handle::WindowHandle) -> String

Get the clipboard contents.
"""
get_clipboard(handle::WindowHandle)::String = handle.clipboard

"""
    set_clipboard!(handle::WindowHandle, text::String)

Set the clipboard contents.
"""
function set_clipboard!(handle::WindowHandle, text::String)
    handle.clipboard = text
end

# ============================================================================
# Input State Queries
# ============================================================================

"""
    is_key_pressed(handle::WindowHandle, key::Int32) -> Bool

Check if a key is currently pressed.
"""
is_key_pressed(handle::WindowHandle, key::Int32)::Bool = key in handle.key_states

"""
    is_mouse_button_pressed(handle::WindowHandle, button::MouseButton) -> Bool

Check if a mouse button is currently pressed.
"""
function is_mouse_button_pressed(handle::WindowHandle, button::MouseButton)::Bool
    button_bit = UInt8(1) << UInt8(button)
    return (handle.mouse_buttons & button_bit) != 0
end

"""
    get_mouse_position(handle::WindowHandle) -> Tuple{Float64, Float64}

Get the current mouse position.
"""
get_mouse_position(handle::WindowHandle) = (handle.mouse_x, handle.mouse_y)

"""
    get_modifiers(handle::WindowHandle) -> UInt8

Get the current modifier key state.
"""
get_modifiers(handle::WindowHandle)::UInt8 = handle.modifiers

export is_key_pressed, is_mouse_button_pressed, get_mouse_position, get_modifiers

# ============================================================================
# Rendering
# ============================================================================

"""
    render!(handle::WindowHandle, ui_context)

Render the UI context to the window.
"""
function render!(handle::WindowHandle, ui_context)
    if handle.backend_data == :cairo && handle.cairo_context !== nothing
        # Use Cairo rendering
        render_cairo!(handle, ui_context)
    else
        # Use software rendering
        render_software!(handle, ui_context)
    end
end

"""
Render using Cairo backend.
"""
function render_cairo!(handle::WindowHandle, ui_context)
    try
        NativeUI = @eval begin
            import ...ContentMM.NativeUI as NUI
            NUI
        end
        
        # Render using NativeUI's Cairo rendering
        NativeUI.render_cairo!(ui_context, 
                               width=Int(handle.width), 
                               height=Int(handle.height))
    catch e
        @warn "Cairo rendering failed" exception=e
    end
end

"""
Render using software backend.
"""
function render_software!(handle::WindowHandle, ui_context)
    try
        NativeUI = @eval begin
            import ...ContentMM.NativeUI as NUI
            NUI
        end
        
        # Render to buffer
        buffer = NativeUI.render_to_buffer(ui_context, 
                                           width=Int(handle.width), 
                                           height=Int(handle.height))
        
        # Copy to framebuffer
        if length(buffer) == length(handle.framebuffer)
            copyto!(handle.framebuffer, buffer)
        end
    catch e
        @warn "Software rendering failed" exception=e
    end
end

"""
    swap_buffers!(handle::WindowHandle)

Swap front and back buffers (for double-buffered rendering).
For software backend, this is a no-op.
"""
function swap_buffers!(handle::WindowHandle)
    # No-op for software backend
end

"""
    get_framebuffer(handle::WindowHandle) -> Vector{UInt8}

Get the current framebuffer contents.
"""
function get_framebuffer(handle::WindowHandle)::Vector{UInt8}
    if handle.backend_data == :cairo && handle.cairo_context !== nothing
        try
            CairoRenderer = @eval begin
                import ...Renderer.CairoRenderer as CR
                CR
            end
            return CairoRenderer.get_surface_data(handle.cairo_context)
        catch e
            @warn "Failed to get Cairo framebuffer" exception=e
            return UInt8[]
        end
    else
        return handle.framebuffer
    end
end

export get_framebuffer

"""
    save_screenshot(handle::WindowHandle, filename::String)

Save the current framebuffer to a PNG file.
"""
function save_screenshot(handle::WindowHandle, filename::String)
    if handle.backend_data == :cairo && handle.cairo_context !== nothing
        try
            CairoRenderer = @eval begin
                import ...Renderer.CairoRenderer as CR
                CR
            end
            CairoRenderer.save_png(handle.cairo_context, filename)
        catch e
            @warn "Failed to save Cairo screenshot" exception=e
        end
    else
        try
            PNGExport = @eval begin
                import ...Renderer.PNGExport as PNG
                PNG
            end
            PNGExport.write_png_file(filename, handle.framebuffer, 
                                     UInt32(handle.width), UInt32(handle.height))
        catch e
            @warn "Failed to save software screenshot" exception=e
        end
    end
end

export save_screenshot

end # module Window
