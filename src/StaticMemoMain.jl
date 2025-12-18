"""
Entry point for StaticCompiler-compiled memo application.
This file provides entry points that can be compiled without the Julia runtime.
Supports both headless and onscreen (interactive) modes using Rust FFI.

Note: StaticCompiler allows normal Julia code, but requires:
- Type stability
- No GC allocations (use stack allocation or manual memory management)
- Native return types for exported functions
"""

using StaticCompiler
using StaticTools

# Import types for FFI (these will be inlined/optimized away)
const CInt = Int32
const CFloat = Float32

# Event types from Rust (matching window.rs)
const EVENT_NONE = UInt8(0)
const EVENT_CLOSE = UInt8(1)
const EVENT_RESIZE = UInt8(2)
const EVENT_MOUSE_DOWN = UInt8(7)
const EVENT_MOUSE_UP = UInt8(8)
const EVENT_MOUSE_MOVE = UInt8(9)

# DopEvent structure (matching Rust's C representation)
struct DopEvent
    event_type::UInt8
    key::Int32
    scancode::Int32
    modifiers::UInt8
    char_code::UInt32
    button::UInt8
    x::Float64
    y::Float64
    scroll_x::Float64
    scroll_y::Float64
    width::Int32
    height::Int32
    timestamp::Float64
end

# Opaque handle types (just pointers)
const RendererHandle = Ptr{Cvoid}
const WindowHandle = Ptr{Cvoid}

# Rust library path (will be resolved at link time or runtime)
# For static compilation, the library should be linked directly
# For development/testing with ccall, use platform-specific extension
const LIBRENDERER = if Sys.iswindows()
    c"dop_renderer.dll"
elseif Sys.isapple()
    c"libdop_renderer.dylib"
else
    c"libdop_renderer.so"
end

# ============================================================================
# Renderer FFI - Direct ccall wrappers
# ============================================================================

function create_renderer(width::Int32, height::Int32)::RendererHandle
    ccall((:dop_renderer_create, LIBRENDERER), Ptr{Cvoid}, (Int32, Int32), width, height)
end

function destroy_renderer(renderer::RendererHandle)::Nothing
    ccall((:dop_renderer_destroy, LIBRENDERER), Cvoid, (Ptr{Cvoid},), renderer)
    nothing
end

function set_clear_color(renderer::RendererHandle, r::Float32, g::Float32, b::Float32, a::Float32)::Nothing
    ccall((:dop_renderer_set_clear_color, LIBRENDERER), Cvoid, 
          (Ptr{Cvoid}, Float32, Float32, Float32, Float32), renderer, r, g, b, a)
    nothing
end

function add_rect(renderer::RendererHandle, x::Float32, y::Float32, w::Float32, h::Float32,
                  r::Float32, g::Float32, b::Float32, a::Float32)::Nothing
    ccall((:dop_renderer_add_rect, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Float32),
          renderer, x, y, w, h, r, g, b, a)
    nothing
end

function add_text(renderer::RendererHandle, text::Ptr{UInt8}, x::Float32, y::Float32,
                  font_size::Float32, r::Float32, g::Float32, b::Float32, a::Float32)::Nothing
    ccall((:dop_renderer_add_text, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, Ptr{UInt8}, Float32, Float32, Float32, Float32, Float32, Float32, Float32),
          renderer, text, x, y, font_size, r, g, b, a)
    nothing
end

function render(renderer::RendererHandle)::Nothing
    ccall((:dop_renderer_render, LIBRENDERER), Cvoid, (Ptr{Cvoid},), renderer)
    nothing
end

function export_png(renderer::RendererHandle, filename::Ptr{UInt8})::Int32
    ccall((:dop_renderer_export_png, LIBRENDERER), Int32, (Ptr{Cvoid}, Ptr{UInt8}), renderer, filename)
end

function get_framebuffer(renderer::RendererHandle, out_len::Ptr{Int64})::Ptr{UInt8}
    ccall((:dop_renderer_get_framebuffer, LIBRENDERER), Ptr{UInt8}, (Ptr{Cvoid}, Ptr{Int64}), renderer, out_len)
end

# ============================================================================
# Window FFI
# ============================================================================

function create_onscreen_window(width::Int32, height::Int32, title::Ptr{UInt8})::WindowHandle
    ccall((:dop_window_create_onscreen, LIBRENDERER), Ptr{Cvoid}, (Int32, Int32, Ptr{UInt8}), width, height, title)
end

function is_window_open(window::WindowHandle)::Int32
    ccall((:dop_window_is_open_threaded, LIBRENDERER), Int32, (Ptr{Cvoid},), window)
end

function poll_events(window::WindowHandle, events::Ptr{DopEvent}, max_events::Int32)::Int32
    ccall((:dop_window_poll_events_threaded, LIBRENDERER), Int32, (Ptr{Cvoid}, Ptr{DopEvent}, Int32), 
          window, events, max_events)
end

function update_framebuffer(window::WindowHandle, data::Ptr{UInt8}, data_len::Int64, 
                             width::Int32, height::Int32)::Nothing
    ccall((:dop_window_update_framebuffer_threaded, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, Ptr{UInt8}, Int64, Int32, Int32), window, data, data_len, width, height)
    nothing
end

function destroy_window(window::WindowHandle)::Nothing
    ccall((:dop_window_free_threaded, LIBRENDERER), Cvoid, (Ptr{Cvoid},), window)
    nothing
end

# ============================================================================
# Application Logic
# ============================================================================

"""
Render a simple memo UI to the renderer.
Uses natural Julia code - StaticCompiler will optimize it.
"""
function render_simple_memo(renderer::RendererHandle)::Nothing
    # Set background color (light gray)
    set_clear_color(renderer, 0.96f0, 0.96f0, 0.96f0, 1.0f0)
    
    # Add title
    add_text(renderer, c"Static Memo App", 20.0f0, 20.0f0, 24.0f0, 0.13f0, 0.13f0, 0.13f0, 1.0f0)
    
    # Add card background
    add_rect(renderer, 20.0f0, 60.0f0, 360.0f0, 100.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
    
    # Add card title (blue)
    add_text(renderer, c"Interactive Note", 35.0f0, 75.0f0, 18.0f0, 0.1f0, 0.46f0, 0.82f0, 1.0f0)
    
    # Add card content lines
    add_text(renderer, c"Statically compiled with", 35.0f0, 100.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    add_text(renderer, c"StaticCompiler.jl!", 35.0f0, 118.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    add_text(renderer, c"Using Rust FFI for window", 35.0f0, 136.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    
    # Add button
    add_rect(renderer, 20.0f0, 170.0f0, 360.0f0, 40.0f0, 0.13f0, 0.59f0, 0.95f0, 1.0f0)
    add_text(renderer, c"+ Add New Note", 140.0f0, 182.0f0, 16.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
    
    # Render
    render(renderer)
    nothing
end

"""
Headless rendering mode - renders to PNG file.
Returns 0 on success, non-zero on failure.
"""
function run_headless()::Int32
    renderer = create_renderer(Int32(400), Int32(600))
    renderer == C_NULL && return Int32(1)
    
    render_simple_memo(renderer)
    
    # Export to PNG
    success = export_png(renderer, c"static_memo_output.png")
    
    # Cleanup
    destroy_renderer(renderer)
    
    # StaticCompiler FFI returns 0 on success, so invert
    success == Int32(0) ? Int32(0) : Int32(1)
end

"""
Interactive onscreen mode - creates a window and handles events.
Returns 0 on success, non-zero on failure.
"""
function run_onscreen()::Int32
    # Create window
    window = create_onscreen_window(Int32(400), Int32(600), c"Static Memo App")
    window == C_NULL && return Int32(1)
    
    # Create renderer for offscreen rendering
    renderer = create_renderer(Int32(400), Int32(600))
    if renderer == C_NULL
        destroy_window(window)
        return Int32(1)
    end
    
    # Event buffer (stack allocated)
    events = MallocArray{DopEvent}(undef, 10)
    fb_len = Ref(Int64(0))
    
    # Main loop
    while is_window_open(window) != Int32(0)
        # Poll events
        num_events = poll_events(window, pointer(events), Int32(10))
        
        # Process events
        for i in 1:num_events
            event = events[i]
            event.event_type == EVENT_CLOSE && break
        end
        
        # Render frame
        render_simple_memo(renderer)
        
        # Get framebuffer and update window
        fb_data = get_framebuffer(renderer, pointer_from_objref(fb_len))
        if fb_data != C_NULL && fb_len[] > 0
            update_framebuffer(window, fb_data, fb_len[], Int32(400), Int32(600))
        end
    end
    
    # Cleanup
    free(events)
    destroy_renderer(renderer)
    destroy_window(window)
    
    Int32(0)
end

# ============================================================================
# Exported Entry Points
# ============================================================================

"""
C-compatible main entry point with command-line argument support.
"""
Base.@ccallable function c_main(argc::Int32, argv::Ptr{Ptr{UInt8}})::Int32
    # Default to headless mode
    onscreen = false
    
    # Check for --onscreen flag
    if argc > Int32(1)
        arg_ptr = unsafe_load(argv, 2)  # argv[1] in C notation
        # Check for --onscreen (simple string matching for static compilation)
        # Format: --onscreen or -o
        c1 = unsafe_load(arg_ptr, 1)
        if c1 == UInt8('-')
            c2 = unsafe_load(arg_ptr, 2)
            if c2 == UInt8('-')
                # Check for --onscreen (check 'o', 'n', 's')
                c3 = unsafe_load(arg_ptr, 3)
                c4 = unsafe_load(arg_ptr, 4)
                c5 = unsafe_load(arg_ptr, 5)
                if c3 == UInt8('o') && c4 == UInt8('n') && c5 == UInt8('s')
                    onscreen = true
                end
            elseif c2 == UInt8('o')
                # Short form: -o
                onscreen = true
            end
        end
    end
    
    onscreen ? run_onscreen() : run_headless()
end

"""
Simple entry point without arguments (defaults to headless mode).
"""
Base.@ccallable function c_main_simple()::Int32
    run_headless()
end


