"""
    Application

Application lifecycle management for interactive UI applications.

This module provides the high-level application framework for building
production-ready desktop applications with DOP Browser.

## Features

- **Lifecycle Management**: Initialization, main loop, cleanup
- **Event Dispatching**: Automatic event routing to widgets
- **Render Loop**: Efficient dirty-checking and rendering
- **Error Handling**: Graceful error recovery
- **Resource Management**: Automatic cleanup on exit

## Usage

```julia
using DOPBrowser.Application
using DOPBrowser.Widgets
using DOPBrowser.State

# Create application
app = create_app(
    title = "My App",
    width = 800,
    height = 600
)

# Create state
count = signal(0)

# Define UI
set_ui!(app) do
    column(gap=10) do
        label(text=computed(() -> "Count: \$(count[])"))
        row(gap=5) do
            button(text="-", on_click=() -> count[] -= 1)
            button(text="+", on_click=() -> count[] += 1)
        end
    end
end

# Run application
run!(app)
```

## Headless Mode

```julia
# For testing or server-side rendering
app = create_app(headless=true, width=800, height=600)
set_ui!(app, my_ui_function)

# Render single frame
render_frame!(app)

# Save screenshot
save_screenshot(app, "output.png")
```
"""
module Application

using ..State: Signal, signal, effect, batch, dispose!
using ..Window: WindowHandle, WindowConfig, WindowEvent, EventType,
                create_window, destroy!, is_open, close!,
                poll_events!, inject_event!, render!,
                get_size, set_size!, save_screenshot,
                EVENT_CLOSE, EVENT_RESIZE, EVENT_KEY_DOWN, EVENT_KEY_UP,
                EVENT_MOUSE_DOWN, EVENT_MOUSE_UP, EVENT_MOUSE_MOVE,
                EVENT_FOCUS, EVENT_BLUR
using ..Widgets: Widget, WidgetTree, build_ui, render_widgets!,
                 ContainerWidget, ButtonWidget, TextInputWidget
using ..ContentMM.NativeUI: UIContext

export App, create_app, run!, stop!
export set_ui!, render_frame!
export on_init, on_update, on_cleanup
export is_running, get_fps, get_frame_count

# ============================================================================
# Application State
# ============================================================================

"""
Application lifecycle callbacks.
"""
mutable struct AppCallbacks
    on_init::Union{Function, Nothing}
    on_update::Union{Function, Nothing}
    on_cleanup::Union{Function, Nothing}
    on_error::Union{Function, Nothing}
    ui_builder::Union{Function, Nothing}
end

"""
Application statistics.
"""
mutable struct AppStats
    frame_count::UInt64
    last_frame_time::Float64
    fps::Float64
    total_runtime::Float64
    render_time::Float64
end

"""
    App

Main application instance.
"""
mutable struct App
    # Window
    window::Union{WindowHandle, Nothing}
    config::WindowConfig
    
    # UI
    widget_tree::Union{WidgetTree, Nothing}
    ui_context::Union{UIContext, Nothing}
    
    # State
    is_running::Bool
    is_headless::Bool
    needs_render::Bool
    
    # Callbacks
    callbacks::AppCallbacks
    
    # Statistics
    stats::AppStats
    
    # Effects and subscriptions (for cleanup)
    effects::Vector{Any}
    
    function App(config::WindowConfig; headless::Bool = false)
        new(
            nothing,
            config,
            nothing,
            nothing,
            false,
            headless,
            true,
            AppCallbacks(nothing, nothing, nothing, nothing, nothing),
            AppStats(UInt64(0), 0.0, 0.0, 0.0, 0.0),
            []
        )
    end
end

# ============================================================================
# Application Creation
# ============================================================================

"""
    create_app(; title="DOP Browser", width=800, height=600, kwargs...) -> App

Create a new application instance.
"""
function create_app(;
                    title::String = "DOP Browser",
                    width::Int = 800,
                    height::Int = 600,
                    resizable::Bool = true,
                    vsync::Bool = true,
                    headless::Bool = false,
                    backend::Symbol = :cairo)
    config = WindowConfig(
        title = title,
        width = width,
        height = height,
        resizable = resizable,
        vsync = vsync,
        backend = backend
    )
    
    return App(config; headless = headless)
end

# ============================================================================
# UI Setup
# ============================================================================

"""
    set_ui!(app::App, builder::Function)

Set the UI builder function for the application.
"""
function set_ui!(app::App, builder::Function)
    app.callbacks.ui_builder = builder
    app.needs_render = true
end

"""
    set_ui!(builder::Function, app::App)

Set the UI builder function (do-block syntax).
"""
function set_ui!(builder::Function, app::App)
    set_ui!(app, builder)
end

"""
Build the UI from the builder function.
"""
function build_app_ui!(app::App)
    if app.callbacks.ui_builder !== nothing
        app.widget_tree = build_ui(app.callbacks.ui_builder)
    end
end

# ============================================================================
# Lifecycle Callbacks
# ============================================================================

"""
    on_init(app::App, callback::Function)

Register initialization callback.
"""
function on_init(app::App, callback::Function)
    app.callbacks.on_init = callback
end

"""
    on_update(app::App, callback::Function)

Register update callback (called every frame).
"""
function on_update(app::App, callback::Function)
    app.callbacks.on_update = callback
end

"""
    on_cleanup(app::App, callback::Function)

Register cleanup callback.
"""
function on_cleanup(app::App, callback::Function)
    app.callbacks.on_cleanup = callback
end

# ============================================================================
# Application Lifecycle
# ============================================================================

"""
    run!(app::App)

Run the application main loop.
"""
function run!(app::App)
    try
        # Initialize
        initialize!(app)
        
        # Main loop
        app.is_running = true
        main_loop!(app)
        
    catch e
        if app.callbacks.on_error !== nothing
            app.callbacks.on_error(e)
        else
            @error "Application error" exception=(e, catch_backtrace())
        end
    finally
        # Cleanup
        cleanup!(app)
    end
end

"""
Initialize the application.
"""
function initialize!(app::App)
    # Create window (unless headless)
    if !app.is_headless
        app.window = create_window(app.config)
    end
    
    # Build initial UI
    build_app_ui!(app)
    
    # Call init callback
    if app.callbacks.on_init !== nothing
        app.callbacks.on_init()
    end
    
    app.stats.last_frame_time = time()
end

"""
Main application loop.
"""
function main_loop!(app::App)
    target_frame_time = 1.0 / 60.0  # 60 FPS
    
    while app.is_running
        frame_start = time()
        
        # Process events
        if app.window !== nothing
            events = poll_events!(app.window)
            for event in events
                handle_event!(app, event)
            end
            
            # Check if window closed
            if !is_open(app.window)
                app.is_running = false
                break
            end
        end
        
        # Update callback
        if app.callbacks.on_update !== nothing
            app.callbacks.on_update(frame_start - app.stats.last_frame_time)
        end
        
        # Render if needed
        if app.needs_render
            render_frame!(app)
        end
        
        # Update stats
        frame_end = time()
        frame_time = frame_end - frame_start
        app.stats.frame_count += 1
        app.stats.fps = 1.0 / max(frame_time, 0.001)
        app.stats.total_runtime += frame_time
        app.stats.last_frame_time = frame_end
        
        # Frame limiting
        elapsed = frame_time
        if elapsed < target_frame_time
            sleep(target_frame_time - elapsed)
        end
        
        # For headless mode, run only one frame
        if app.is_headless
            break
        end
    end
end

"""
Handle a window event.
"""
function handle_event!(app::App, event::WindowEvent)
    if event.type == EVENT_CLOSE
        app.is_running = false
    elseif event.type == EVENT_RESIZE
        app.needs_render = true
    elseif event.type == EVENT_MOUSE_DOWN
        handle_mouse_down!(app, event)
    elseif event.type == EVENT_MOUSE_UP
        handle_mouse_up!(app, event)
    elseif event.type == EVENT_MOUSE_MOVE
        handle_mouse_move!(app, event)
    elseif event.type == EVENT_KEY_DOWN
        handle_key_down!(app, event)
    elseif event.type == EVENT_KEY_UP
        handle_key_up!(app, event)
    end
end

"""
Handle mouse down event.
"""
function handle_mouse_down!(app::App, event::WindowEvent)
    # Find widget at position and dispatch click
    if app.widget_tree !== nothing
        widget = find_widget_at(app.widget_tree.root, event.x, event.y)
        if widget !== nothing && widget isa ButtonWidget
            widget.is_pressed = true
            app.needs_render = true
        end
    end
end

"""
Handle mouse up event.
"""
function handle_mouse_up!(app::App, event::WindowEvent)
    if app.widget_tree !== nothing
        widget = find_widget_at(app.widget_tree.root, event.x, event.y)
        if widget !== nothing && widget isa ButtonWidget
            if widget.is_pressed && widget.on_click !== nothing
                widget.on_click()
            end
            widget.is_pressed = false
            app.needs_render = true
        end
        
        # Clear pressed state on all buttons
        clear_pressed_state!(app.widget_tree.root)
    end
end

"""
Handle mouse move event.
"""
function handle_mouse_move!(app::App, event::WindowEvent)
    if app.widget_tree !== nothing
        # Update hover states
        old_hover = app.widget_tree.hover_widget
        new_hover = find_widget_at(app.widget_tree.root, event.x, event.y)
        
        if old_hover !== new_hover
            # Leave old widget
            if old_hover !== nothing && old_hover isa ButtonWidget
                old_hover.is_hovered = false
            end
            
            # Enter new widget
            if new_hover !== nothing && new_hover isa ButtonWidget
                new_hover.is_hovered = true
                if new_hover.on_hover !== nothing
                    new_hover.on_hover()
                end
            end
            
            app.widget_tree.hover_widget = new_hover
            app.needs_render = true
        end
    end
end

"""
Handle key down event.
"""
function handle_key_down!(app::App, event::WindowEvent)
    # Handle text input
    if app.widget_tree !== nothing
        focused = app.widget_tree.focused_widget
        if focused !== nothing && focused isa TextInputWidget
            # Handle character input
            if event.char != '\0'
                current = focused.value[]
                focused.value[] = current * string(event.char)
                if focused.on_change !== nothing
                    focused.on_change(focused.value[])
                end
                app.needs_render = true
            end
        end
    end
end

"""
Handle key up event.
"""
function handle_key_up!(app::App, event::WindowEvent)
    # Currently no-op
end

"""
Find widget at a given position (simple hit testing).
"""
function find_widget_at(widget::Widget, x::Float64, y::Float64)::Union{Widget, Nothing}
    # Simple implementation - would need proper layout info in production
    return nothing
end

function find_widget_at(widget::ContainerWidget, x::Float64, y::Float64)::Union{Widget, Nothing}
    # Check children in reverse order (top-most first)
    for child in reverse(widget.children)
        result = find_widget_at(child, x, y)
        if result !== nothing
            return result
        end
    end
    return nothing
end

"""
Clear pressed state on all buttons.
"""
function clear_pressed_state!(widget::Widget)
    if widget isa ButtonWidget
        widget.is_pressed = false
    end
    if widget isa ContainerWidget
        for child in widget.children
            clear_pressed_state!(child)
        end
    end
end

"""
Cleanup the application.
"""
function cleanup!(app::App)
    # Call cleanup callback
    if app.callbacks.on_cleanup !== nothing
        try
            app.callbacks.on_cleanup()
        catch e
            @warn "Error in cleanup callback" exception=e
        end
    end
    
    # Dispose effects
    for eff in app.effects
        try
            dispose!(eff)
        catch e
            @warn "Error disposing effect" exception=e
        end
    end
    empty!(app.effects)
    
    # Destroy window
    if app.window !== nothing
        destroy!(app.window)
        app.window = nothing
    end
    
    app.is_running = false
end

"""
    stop!(app::App)

Stop the application.
"""
function stop!(app::App)
    app.is_running = false
end

# ============================================================================
# Rendering
# ============================================================================

"""
    render_frame!(app::App)

Render a single frame.
"""
function render_frame!(app::App)
    render_start = time()
    
    # Get window size
    width, height = if app.window !== nothing
        get_size(app.window)
    else
        (app.config.width, app.config.height)
    end
    
    # Render widget tree
    if app.widget_tree !== nothing
        render_widgets!(app.widget_tree, width=Int(width), height=Int(height))
        
        # Render to window
        if app.window !== nothing && app.widget_tree.ui_context !== nothing
            render!(app.window, app.widget_tree.ui_context)
        end
    end
    
    app.stats.render_time = time() - render_start
    app.needs_render = false
end

"""
    save_app_screenshot(app::App, filename::String)

Save a screenshot of the current frame.
"""
function save_app_screenshot(app::App, filename::String)
    if app.window !== nothing
        Window.save_screenshot(app.window, filename)
    end
end

export save_app_screenshot

# ============================================================================
# Queries
# ============================================================================

"""
    is_running(app::App) -> Bool

Check if the application is running.
"""
is_running(app::App)::Bool = app.is_running

"""
    get_fps(app::App) -> Float64

Get the current frames per second.
"""
get_fps(app::App)::Float64 = app.stats.fps

"""
    get_frame_count(app::App) -> UInt64

Get the total frame count.
"""
get_frame_count(app::App)::UInt64 = app.stats.frame_count

# ============================================================================
# Convenience Functions
# ============================================================================

"""
    request_render!(app::App)

Request a render on the next frame.
"""
function request_render!(app::App)
    app.needs_render = true
end

export request_render!

"""
    resize!(app::App, width::Int, height::Int)

Resize the application window.
"""
function resize!(app::App, width::Int, height::Int)
    if app.window !== nothing
        set_size!(app.window, width, height)
    end
    app.needs_render = true
end

end # module Application
