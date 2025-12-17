"""
    Window

Platform windowing abstraction layer for interactive UI applications.

This module provides an abstraction layer for windowing systems, enabling 
the Content-- UI library to run as interactive desktop applications.

## Supported Backends
- **Gtk** (default for onscreen): Native platform windows using Gtk4 with Cairo rendering
- **Cairo**: High-quality 2D rendering with Cairo (headless/offscreen)
- **Software**: In-memory rendering for headless/testing

## Usage

### Onscreen Window with Event Loop (Gtk Backend)

```julia
using DOPBrowser.Window

# Create a window configuration with Gtk backend for real desktop windows
config = WindowConfig(
    title = "My App",
    width = 800,
    height = 600,
    resizable = true,
    backend = :gtk  # Use Gtk for onscreen rendering
)

# Create a window
window = create_window(config)

# Main loop
while is_open(window)
    events = poll_events!(window)
    
    for event in events
        if event.type == EVENT_CLOSE
            close!(window)
        elseif event.type == EVENT_KEY_DOWN
            println("Key pressed: \$(event.key)")
        end
    end
    
    # Render your content
    render!(window, your_ui_context)
    
    sleep(0.016)  # ~60 FPS
end

destroy!(window)
```

### Headless Mode (for Testing)

```julia
using DOPBrowser.Window

# Create a window with software backend for testing
config = WindowConfig(
    title = "Test",
    width = 800,
    height = 600,
    backend = :software  # Use software backend for headless testing
)

window = create_window(config)

# Simulate events for testing
inject_event!(window, WindowEvent(EVENT_KEY_DOWN, key=Int32(65)))  # 'A' key

# Process events
events = poll_events!(window)
for event in events
    println("Received event: \$(event.type)")
end

destroy!(window)
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
    if config.backend == :gtk
        initialize_gtk_backend!(handle)
    elseif config.backend == :cairo
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
Initialize Gtk windowing backend for onscreen rendering.
"""
function initialize_gtk_backend!(handle::WindowHandle)
    try
        # Import Gtk4
        Gtk4 = @eval begin
            import Gtk4 as G
            G
        end
        
        # Import Cairo for rendering
        CairoRenderer = @eval begin
            import ...Renderer.CairoRenderer as CR
            CR
        end
        
        # Create the Gtk application and window
        gtk_data = Dict{Symbol, Any}()
        
        # Create drawing area for Cairo rendering
        drawing_area = Gtk4.GtkDrawingArea()
        Gtk4.content_width(drawing_area, Int(handle.width))
        Gtk4.content_height(drawing_area, Int(handle.height))
        
        # Create the main window
        win = Gtk4.GtkWindow(handle.config.title, Int(handle.width), Int(handle.height))
        
        if !handle.config.resizable
            Gtk4.resizable(win, false)
        end
        
        if !handle.config.decorated
            Gtk4.decorated(win, false)
        end
        
        # Set the drawing area as the window child
        Gtk4.child(win, drawing_area)
        
        # Create Cairo context for rendering
        handle.cairo_context = CairoRenderer.create_cairo_context(
            Int(handle.width), Int(handle.height)
        )
        
        # Store Gtk objects
        gtk_data[:window] = win
        gtk_data[:drawing_area] = drawing_area
        gtk_data[:pending_events] = WindowEvent[]
        gtk_data[:draw_requested] = false
        
        # Set up drawing function
        Gtk4.set_draw_func(drawing_area, (widget, cr, w, h) -> begin
            if handle.cairo_context !== nothing
                # Get the Cairo surface from our render context
                surface = handle.cairo_context.surface
                Gtk4.set_source_surface(cr, surface, 0, 0)
                Gtk4.paint(cr)
            end
        end)
        
        # Set up event controllers for keyboard input
        key_controller = Gtk4.GtkEventControllerKey(drawing_area)
        
        Gtk4.signal_connect(key_controller, "key-pressed") do controller, keyval, keycode, state
            modifiers = _gtk_state_to_modifiers(state)
            event = WindowEvent(EVENT_KEY_DOWN,
                               key=Int32(keyval),
                               scancode=Int32(keycode),
                               modifiers=modifiers)
            push!(gtk_data[:pending_events], event)
            return true
        end
        
        Gtk4.signal_connect(key_controller, "key-released") do controller, keyval, keycode, state
            modifiers = _gtk_state_to_modifiers(state)
            event = WindowEvent(EVENT_KEY_UP,
                               key=Int32(keyval),
                               scancode=Int32(keycode),
                               modifiers=modifiers)
            push!(gtk_data[:pending_events], event)
            return true
        end
        
        # Set up motion controller for mouse events
        motion_controller = Gtk4.GtkEventControllerMotion(drawing_area)
        
        Gtk4.signal_connect(motion_controller, "motion") do controller, x, y
            event = WindowEvent(EVENT_MOUSE_MOVE, x=Float64(x), y=Float64(y))
            push!(gtk_data[:pending_events], event)
            handle.mouse_x = Float64(x)
            handle.mouse_y = Float64(y)
        end
        
        Gtk4.signal_connect(motion_controller, "enter") do controller, x, y
            event = WindowEvent(EVENT_MOUSE_ENTER, x=Float64(x), y=Float64(y))
            push!(gtk_data[:pending_events], event)
        end
        
        Gtk4.signal_connect(motion_controller, "leave") do controller
            event = WindowEvent(EVENT_MOUSE_LEAVE)
            push!(gtk_data[:pending_events], event)
        end
        
        # Set up click controller for mouse button events
        click_controller = Gtk4.GtkGestureClick(drawing_area)
        Gtk4.button(click_controller, 0)  # Listen to all buttons
        
        Gtk4.signal_connect(click_controller, "pressed") do gesture, n_press, x, y
            btn = Gtk4.get_current_button(gesture)
            button = _gtk_button_to_mouse_button(btn)
            event = WindowEvent(EVENT_MOUSE_DOWN, button=button, x=Float64(x), y=Float64(y))
            push!(gtk_data[:pending_events], event)
        end
        
        Gtk4.signal_connect(click_controller, "released") do gesture, n_press, x, y
            btn = Gtk4.get_current_button(gesture)
            button = _gtk_button_to_mouse_button(btn)
            event = WindowEvent(EVENT_MOUSE_UP, button=button, x=Float64(x), y=Float64(y))
            push!(gtk_data[:pending_events], event)
        end
        
        # Set up scroll controller
        scroll_controller = Gtk4.GtkEventControllerScroll(drawing_area,
            Gtk4.EventControllerScrollFlags_VERTICAL | Gtk4.EventControllerScrollFlags_HORIZONTAL)
        
        Gtk4.signal_connect(scroll_controller, "scroll") do controller, dx, dy
            event = WindowEvent(EVENT_MOUSE_SCROLL, 
                               scroll_x=Float64(dx), 
                               scroll_y=Float64(dy),
                               x=handle.mouse_x, 
                               y=handle.mouse_y)
            push!(gtk_data[:pending_events], event)
            return true
        end
        
        # Set up focus controller
        focus_controller = Gtk4.GtkEventControllerFocus(drawing_area)
        
        Gtk4.signal_connect(focus_controller, "enter") do controller
            handle.is_focused = true
            event = WindowEvent(EVENT_FOCUS)
            push!(gtk_data[:pending_events], event)
        end
        
        Gtk4.signal_connect(focus_controller, "leave") do controller
            handle.is_focused = false
            event = WindowEvent(EVENT_BLUR)
            push!(gtk_data[:pending_events], event)
        end
        
        # Handle window close
        Gtk4.signal_connect(win, "close-request") do window
            handle.is_open = false
            event = WindowEvent(EVENT_CLOSE)
            push!(gtk_data[:pending_events], event)
            return false  # Allow the window to close
        end
        
        # Make window focusable for keyboard input
        Gtk4.focusable(drawing_area, true)
        Gtk4.grab_focus(drawing_area)
        
        # Show the window
        Gtk4.show(win)
        
        handle.backend_data = gtk_data
        
    catch e
        @warn "Gtk initialization failed. Native window support will not be available. " *
              "The application will run in headless mode using Cairo for offscreen rendering. " *
              "This is typically caused by missing display server (X11/Wayland) or Gtk libraries." exception=e
        initialize_cairo_backend!(handle)
    end
end

"""
Convert Gtk modifier state to our modifier flags.
"""
function _gtk_state_to_modifiers(state)::UInt8
    mods = MOD_NONE
    # Gtk4 modifier masks
    if (state & 0x01) != 0  # Shift
        mods |= MOD_SHIFT
    end
    if (state & 0x04) != 0  # Control
        mods |= MOD_CTRL
    end
    if (state & 0x08) != 0  # Alt/Mod1
        mods |= MOD_ALT
    end
    if (state & 0x40) != 0  # Super/Mod4
        mods |= MOD_SUPER
    end
    return mods
end

"""
Convert Gtk button number to MouseButton enum.
"""
function _gtk_button_to_mouse_button(gtk_button::Integer)::MouseButton
    if gtk_button == 1
        return MOUSE_LEFT
    elseif gtk_button == 2
        return MOUSE_MIDDLE
    elseif gtk_button == 3
        return MOUSE_RIGHT
    elseif gtk_button == 4
        return MOUSE_X1
    elseif gtk_button == 5
        return MOUSE_X2
    else
        return MOUSE_LEFT
    end
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
    # Close Gtk window if present
    if handle.backend_data isa Dict && haskey(handle.backend_data, :window)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            win = handle.backend_data[:window]
            if win !== nothing
                Gtk4.close(win)
            end
        catch e
            # Ignore errors during cleanup
        end
    end
    
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
    # Process Gtk events if using Gtk backend
    if handle.backend_data isa Dict && haskey(handle.backend_data, :pending_events)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            
            # Process pending Gtk events (non-blocking)
            while Gtk4.events_pending()
                Gtk4.main_iteration()
            end
            
            # Get events from Gtk backend
            gtk_events = handle.backend_data[:pending_events]
            for event in gtk_events
                push!(handle.event_queue, event)
                _update_state_from_event!(handle, event)
            end
            empty!(gtk_events)
            
        catch e
            # Fallback - just return internal queue
        end
    end
    
    events = copy(handle.event_queue)
    empty!(handle.event_queue)
    return events
end

"""
Update internal state from an event.
"""
function _update_state_from_event!(handle::WindowHandle, event::WindowEvent)
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
    elseif event.type == EVENT_FOCUS
        handle.is_focused = true
    elseif event.type == EVENT_BLUR
        handle.is_focused = false
    end
end

"""
    wait_events!(handle::WindowHandle; timeout::Float64 = Inf) -> Vector{WindowEvent}

Wait for events with optional timeout. 
"""
function wait_events!(handle::WindowHandle; timeout::Float64 = Inf)::Vector{WindowEvent}
    # For Gtk backend, wait for events
    if handle.backend_data isa Dict && haskey(handle.backend_data, :pending_events)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            
            # Wait for events with timeout
            start_time = time()
            while isempty(handle.backend_data[:pending_events]) && (time() - start_time) < timeout
                Gtk4.main_iteration_do(true)  # Wait for events
            end
        catch e
            # Fallback
        end
    end
    
    return poll_events!(handle)
end

"""
    post_redisplay!(handle::WindowHandle)

Request a redisplay of the window.
"""
function post_redisplay!(handle::WindowHandle)
    # For Gtk backend, queue a redraw
    if handle.backend_data isa Dict && haskey(handle.backend_data, :drawing_area)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            Gtk4.queue_draw(handle.backend_data[:drawing_area])
        catch e
            # Ignore
        end
    end
end

"""
    inject_event!(handle::WindowHandle, event::WindowEvent)

Inject an event into the window's event queue. Useful for testing
or programmatic event generation.
"""
function inject_event!(handle::WindowHandle, event::WindowEvent)
    push!(handle.event_queue, event)
    _update_state_from_event!(handle, event)
    
    # Handle resize specially
    if event.type == EVENT_RESIZE
        resize_backend!(handle)
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
    elseif handle.backend_data isa Dict  # Gtk backend
        try
            CairoRenderer = @eval begin
                import ...Renderer.CairoRenderer as CR
                CR
            end
            handle.cairo_context = CairoRenderer.create_cairo_context(
                Int(handle.width), Int(handle.height)
            )
        catch e
            @warn "Failed to resize Cairo context for Gtk" exception=e
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
    if handle.backend_data isa Dict && haskey(handle.backend_data, :window)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            Gtk4.title(handle.backend_data[:window], title)
        catch e
            # Ignore errors
        end
    end
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
    if handle.backend_data isa Dict  # Gtk backend
        # Render to Cairo context, then update the Gtk drawing area
        render_gtk!(handle, ui_context)
    elseif handle.backend_data == :cairo && handle.cairo_context !== nothing
        # Use Cairo rendering (headless)
        render_cairo!(handle, ui_context)
    else
        # Use software rendering
        render_software!(handle, ui_context)
    end
end

"""
Render using Gtk backend with Cairo.
"""
function render_gtk!(handle::WindowHandle, ui_context)
    try
        NativeUI = @eval begin
            import ...ContentMM.NativeUI as NUI
            NUI
        end
        
        # Render to our Cairo context
        if handle.cairo_context !== nothing
            NativeUI.render_cairo!(ui_context, 
                                   width=Int(handle.width), 
                                   height=Int(handle.height),
                                   cairo_context=handle.cairo_context)
        end
        
        # Queue a redraw of the Gtk drawing area
        if haskey(handle.backend_data, :drawing_area)
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            Gtk4.queue_draw(handle.backend_data[:drawing_area])
        end
    catch e
        @warn "Gtk rendering failed" exception=e
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
"""
function swap_buffers!(handle::WindowHandle)
    # For Gtk backend, process pending events and update display
    if handle.backend_data isa Dict && haskey(handle.backend_data, :drawing_area)
        try
            Gtk4 = @eval begin
                import Gtk4 as G
                G
            end
            # Process any pending Gtk events
            while Gtk4.events_pending()
                Gtk4.main_iteration()
            end
        catch e
            # Ignore
        end
    end
end

"""
    get_framebuffer(handle::WindowHandle) -> Vector{UInt8}

Get the current framebuffer contents.
"""
function get_framebuffer(handle::WindowHandle)::Vector{UInt8}
    if handle.backend_data isa Dict && handle.cairo_context !== nothing
        # Gtk backend with Cairo
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
    elseif handle.backend_data == :cairo && handle.cairo_context !== nothing
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
    if handle.cairo_context !== nothing
        # Use Cairo's PNG export
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
        # Use software framebuffer
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

# ============================================================================
# Gtk Utility Functions
# ============================================================================

"""
    is_gtk_available() -> Bool

Check if Gtk backend is available.
"""
function is_gtk_available()::Bool
    try
        @eval import Gtk4
        return true
    catch
        return false
    end
end

export is_gtk_available

end # module Window
