"""
Entry point for StaticCompiler-compiled memo application.
This file provides C-compatible entry points that can be compiled without the Julia runtime.
Supports both headless and onscreen (interactive) modes using Rust FFI.
"""

using StaticCompiler
using StaticTools

# Import the basic memo functionality
# Note: For StaticCompiler, we need to use only C-compatible FFI calls

# C types for FFI
const CInt = Int32
const CFloat = Float32
const CDouble = Float64

# Event types from Rust (matching window.rs)
const EVENT_NONE::UInt8 = 0
const EVENT_CLOSE::UInt8 = 1
const EVENT_RESIZE::UInt8 = 2
const EVENT_MOUSE_DOWN::UInt8 = 7
const EVENT_MOUSE_UP::UInt8 = 8
const EVENT_MOUSE_MOVE::UInt8 = 9

# Mouse button IDs
const MOUSE_LEFT::UInt8 = 0
const MOUSE_RIGHT::UInt8 = 1
const MOUSE_MIDDLE::UInt8 = 2

# DopEvent structure (matching Rust's repr)
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

# Opaque handle types
const RendererHandle = Ptr{Cvoid}
const WindowHandle = Ptr{Cvoid}

# Load the Rust library
const LIBRENDERER = "libdop_renderer.so"  # Will be in artifacts or system path

# Renderer FFI functions
function create_renderer_ffi(width::CInt, height::CInt)::RendererHandle
    ccall((:dop_renderer_create, LIBRENDERER), Ptr{Cvoid}, (CInt, CInt), width, height)
end

function destroy_renderer_ffi(renderer::RendererHandle)::Cvoid
    ccall((:dop_renderer_destroy, LIBRENDERER), Cvoid, (Ptr{Cvoid},), renderer)
end

function set_clear_color_ffi(renderer::RendererHandle, r::CFloat, g::CFloat, b::CFloat, a::CFloat)::Cvoid
    ccall((:dop_renderer_set_clear_color, LIBRENDERER), Cvoid, 
          (Ptr{Cvoid}, CFloat, CFloat, CFloat, CFloat), renderer, r, g, b, a)
end

function add_rect_ffi(renderer::RendererHandle, x::CFloat, y::CFloat, 
                      w::CFloat, h::CFloat, r::CFloat, g::CFloat, b::CFloat, a::CFloat)::Cvoid
    ccall((:dop_renderer_add_rect, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, CFloat, CFloat, CFloat, CFloat, CFloat, CFloat, CFloat, CFloat),
          renderer, x, y, w, h, r, g, b, a)
end

function add_text_ffi(renderer::RendererHandle, text::Ptr{UInt8}, x::CFloat, y::CFloat,
                      font_size::CFloat, r::CFloat, g::CFloat, b::CFloat, a::CFloat)::Cvoid
    ccall((:dop_renderer_add_text, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, Ptr{UInt8}, CFloat, CFloat, CFloat, CFloat, CFloat, CFloat, CFloat),
          renderer, text, x, y, font_size, r, g, b, a)
end

function render_ffi(renderer::RendererHandle)::Cvoid
    ccall((:dop_renderer_render, LIBRENDERER), Cvoid, (Ptr{Cvoid},), renderer)
end

function export_png_ffi(renderer::RendererHandle, filename::Ptr{UInt8})::CInt
    ccall((:dop_renderer_export_png, LIBRENDERER), CInt, 
          (Ptr{Cvoid}, Ptr{UInt8}), renderer, filename)
end

function get_framebuffer_ffi(renderer::RendererHandle, out_len::Ptr{Int64})::Ptr{UInt8}
    ccall((:dop_renderer_get_framebuffer, LIBRENDERER), Ptr{UInt8},
          (Ptr{Cvoid}, Ptr{Int64}), renderer, out_len)
end

# Window FFI functions
function create_onscreen_window_ffi(width::CInt, height::CInt, title::Ptr{UInt8})::WindowHandle
    ccall((:dop_window_create_onscreen, LIBRENDERER), Ptr{Cvoid},
          (CInt, CInt, Ptr{UInt8}), width, height, title)
end

function is_window_open_ffi(window::WindowHandle)::CInt
    ccall((:dop_window_is_open_threaded, LIBRENDERER), CInt, (Ptr{Cvoid},), window)
end

function poll_events_ffi(window::WindowHandle, events::Ptr{DopEvent}, max_events::CInt)::CInt
    ccall((:dop_window_poll_events_threaded, LIBRENDERER), CInt,
          (Ptr{Cvoid}, Ptr{DopEvent}, CInt), window, events, max_events)
end

function update_framebuffer_ffi(window::WindowHandle, data::Ptr{UInt8}, 
                                 data_len::Int64, width::CInt, height::CInt)::Cvoid
    ccall((:dop_window_update_framebuffer_threaded, LIBRENDERER), Cvoid,
          (Ptr{Cvoid}, Ptr{UInt8}, Int64, CInt, CInt), window, data, data_len, width, height)
end

function destroy_window_ffi(window::WindowHandle)::Cvoid
    ccall((:dop_window_free_threaded, LIBRENDERER), Cvoid, (Ptr{Cvoid},), window)
end

# Helper to create a C string from a static string
function make_cstring(s::StaticString)::Ptr{UInt8}
    pointer(s.data)
end

"""
    render_simple_memo(renderer::RendererHandle) -> Nothing

Render a simple memo UI to the renderer.
"""
function render_simple_memo(renderer::RendererHandle)::Cvoid
    # Set background color (light gray)
    set_clear_color_ffi(renderer, 0.96f0, 0.96f0, 0.96f0, 1.0f0)
    
    # Add title
    title_text = c"Static Memo App"
    add_text_ffi(renderer, pointer(title_text), 20.0f0, 20.0f0, 24.0f0, 0.13f0, 0.13f0, 0.13f0, 1.0f0)
    
    # Add card background
    add_rect_ffi(renderer, 20.0f0, 60.0f0, 360.0f0, 100.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
    
    # Add card title (blue)
    card_title = c"Interactive Note"
    add_text_ffi(renderer, pointer(card_title), 35.0f0, 75.0f0, 18.0f0, 0.1f0, 0.46f0, 0.82f0, 1.0f0)
    
    # Add card content
    line1 = c"This memo app is statically"
    line2 = c"compiled with StaticCompiler!"
    line3 = c"Click to interact (Rust FFI)"
    add_text_ffi(renderer, pointer(line1), 35.0f0, 100.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    add_text_ffi(renderer, pointer(line2), 35.0f0, 118.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    add_text_ffi(renderer, pointer(line3), 35.0f0, 136.0f0, 14.0f0, 0.26f0, 0.26f0, 0.26f0, 1.0f0)
    
    # Add button
    add_rect_ffi(renderer, 20.0f0, 170.0f0, 360.0f0, 40.0f0, 0.13f0, 0.59f0, 0.95f0, 1.0f0)
    button_text = c"+ Add New Note"
    add_text_ffi(renderer, pointer(button_text), 140.0f0, 182.0f0, 16.0f0, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
    
    # Render
    render_ffi(renderer)
    
    return nothing
end

"""
    static_render_memo_headless() -> Int32

Headless rendering mode - renders to PNG file.
Returns 0 on success, 1 on failure.
"""
function static_render_memo_headless()::Int32
    renderer = create_renderer_ffi(400, 600)
    if renderer == C_NULL
        return Int32(1)
    end
    
    render_simple_memo(renderer)
    
    # Export to PNG
    filename = c"static_memo_output.png"
    success = export_png_ffi(renderer, pointer(filename))
    
    # Cleanup
    destroy_renderer_ffi(renderer)
    
    return success == 0 ? Int32(1) : Int32(0)
end

"""
    static_render_memo_onscreen() -> Int32

Interactive onscreen mode - creates a window and handles events.
Returns 0 on success, 1 on failure.
"""
function static_render_memo_onscreen()::Int32
    # Create window
    title = c"Static Memo App"
    window = create_onscreen_window_ffi(400, 600, pointer(title))
    if window == C_NULL
        return Int32(1)
    end
    
    # Create renderer for offscreen rendering
    renderer = create_renderer_ffi(400, 600)
    if renderer == C_NULL
        destroy_window_ffi(window)
        return Int32(1)
    end
    
    # Event buffer
    events = Vector{DopEvent}(undef, 10)
    
    # Main loop
    frame_count = Int32(0)
    while is_window_open_ffi(window) != 0
        # Poll events
        num_events = poll_events_ffi(window, pointer(events), 10)
        
        # Process events
        for i in 1:num_events
            event = events[i]
            if event.event_type == EVENT_CLOSE
                break
            elseif event.event_type == EVENT_MOUSE_DOWN
                # Could handle button clicks here
                # For now, just log that we got a click
            end
        end
        
        # Render frame
        render_simple_memo(renderer)
        
        # Get framebuffer
        fb_len = Ref{Int64}(0)
        fb_data = get_framebuffer_ffi(renderer, Base.unsafe_convert(Ptr{Int64}, fb_len))
        
        if fb_data != C_NULL && fb_len[] > 0
            # Update window
            update_framebuffer_ffi(window, fb_data, fb_len[], 400, 600)
        end
        
        frame_count += 1
        
        # Sleep a bit to avoid hogging CPU
        # Note: sleep is not available in StaticCompiler, so we'd need to use a Rust FFI
        # For now, we'll just continue
    end
    
    # Cleanup
    destroy_renderer_ffi(renderer)
    destroy_window_ffi(window)
    
    return Int32(0)
end

"""
    c_main(argc::Int32, argv::Ptr{Ptr{UInt8}}) -> Int32

C-compatible main entry point for static compilation.
Supports command-line arguments:
  --headless : Run in headless mode (default)
  --onscreen : Run in interactive onscreen mode
"""
Base.@ccallable function c_main(argc::Int32, argv::Ptr{Ptr{UInt8}})::Int32
    # Check for onscreen flag
    onscreen = false
    if argc > 1
        # Check first argument
        arg_ptr = unsafe_load(argv, 2)  # argv[1] (0-indexed in C)
        # Simple check: if it contains 'o' it's probably --onscreen
        # (proper string comparison is complex in StaticCompiler)
        first_char = unsafe_load(arg_ptr, 1)
        if first_char == UInt8('-')
            second_char = unsafe_load(arg_ptr, 2)
            if second_char == UInt8('-')
                third_char = unsafe_load(arg_ptr, 3)
                if third_char == UInt8('o')  # --onscreen
                    onscreen = true
                end
            end
        end
    end
    
    if onscreen
        return static_render_memo_onscreen()
    else
        return static_render_memo_headless()
    end
end

# Alternative simpler entry point (no args)
Base.@ccallable function c_main_simple()::Int32
    return static_render_memo_headless()
end

