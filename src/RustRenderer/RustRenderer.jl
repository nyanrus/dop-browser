"""
    RustRenderer

Rust-based rendering engine using winit and wgpu.

This module provides a high-performance rendering backend implemented in Rust,
with window management via winit and GPU rendering via wgpu. It exposes
FFI bindings to Julia for seamless integration with the DOP Browser.

The Rust library can be built using the unified build script in deps/build.jl.

## Features
- Cross-platform window management (Windows, Linux, macOS)
- Hardware-accelerated GPU rendering via wgpu
- Software fallback for headless/testing scenarios
- Compatible FFI interface for Julia integration

## Usage

```julia
using DOPBrowser.RustRenderer

# Create a headless renderer
renderer = create_renderer(800, 600)

# Add render commands
add_rect!(renderer, 10.0, 10.0, 100.0, 50.0, 1.0, 0.0, 0.0, 1.0)

# Render frame
render!(renderer)

# Get framebuffer
buffer = get_framebuffer(renderer)

# Clean up
destroy!(renderer)
```
"""
module RustRenderer

export RustRendererHandle, RustWindowHandle
export create_renderer, create_window, destroy!
export add_rect!, render!, get_framebuffer, get_framebuffer_size
export set_clear_color!, clear!
export is_open, close!, poll_events!
export get_lib_path, is_available

# ============================================================================
# Library Loading
# ============================================================================

# Cache for library handle
const LIB_HANDLE = Ref{Ptr{Nothing}}(C_NULL)

"""
    get_lib_name() -> String

Get the platform-specific library filename.
"""
function get_lib_name()
    if Sys.iswindows()
        return "dop_renderer.dll"
    elseif Sys.isapple()
        return "libdop_renderer.dylib"
    else
        return "libdop_renderer.so"
    end
end

"""
Get the path to the Rust renderer library.
"""
function get_lib_path()::String
    possible_paths = String[]
    
    # Get the source directory
    src_dir = @__DIR__
    project_dir = dirname(dirname(src_dir))
    
    # Artifacts directory first (built by deps/build.jl)
    artifacts_dir = joinpath(project_dir, "artifacts", "dop-renderer")
    
    # Local build path (development)
    rust_dir = joinpath(project_dir, "rust", "dop-renderer")
    
    lib_name = get_lib_name()
    
    # Add candidates in order of preference
    push!(possible_paths, joinpath(artifacts_dir, lib_name))
    push!(possible_paths, joinpath(rust_dir, "target", "release", lib_name))
    push!(possible_paths, joinpath(rust_dir, "target", "debug", lib_name))
    
    # System-installed path
    if Sys.isunix()
        push!(possible_paths, "/usr/local/lib/libdop_renderer.so")
        push!(possible_paths, "/usr/lib/libdop_renderer.so")
    end
    
    for path in possible_paths
        if isfile(path)
            return path
        end
    end
    
    return ""
end

"""
Check if the Rust renderer library is available.
"""
function is_available()::Bool
    path = get_lib_path()
    if isempty(path) || !isfile(path)
        rust_dir = joinpath("rust", "dop-renderer")
        error("Rust renderer library not found. Please build it with: cd $(rust_dir) && cargo build --release")
    end
    return true
end

"""
Load the Rust renderer library.
"""
function load_library()
    if LIB_HANDLE[] != C_NULL
        return LIB_HANDLE[]
    end
    
    path = get_lib_path()
    if isempty(path)
        error("Rust renderer library not found. Please build the library with: " *
              "cd rust/dop-renderer && cargo build --release")
    end
    
    # Load the library
    handle = Libc.Libdl.dlopen(path)
    LIB_HANDLE[] = handle
    
    # Initialize
    ccall(Libc.Libdl.dlsym(handle, :dop_init), Cvoid, ())
    
    return handle
end

"""
Get function pointer from the loaded library.
"""
function get_func(name::Symbol)
    handle = load_library()
    return Libc.Libdl.dlsym(handle, name)
end

# ============================================================================
# Event Types
# ============================================================================

"""
Event types matching the Rust enum.
"""
@enum DopEventType::UInt8 begin
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
    EVENT_REDRAW = 15
end

export DopEventType, EVENT_NONE, EVENT_CLOSE, EVENT_RESIZE, EVENT_MOVE
export EVENT_KEY_DOWN, EVENT_KEY_UP, EVENT_CHAR
export EVENT_MOUSE_DOWN, EVENT_MOUSE_UP, EVENT_MOUSE_MOVE
export EVENT_MOUSE_SCROLL, EVENT_MOUSE_ENTER, EVENT_MOUSE_LEAVE
export EVENT_FOCUS, EVENT_BLUR, EVENT_REDRAW

"""
Mouse button identifiers.
"""
@enum DopMouseButton::UInt8 begin
    MOUSE_LEFT = 0
    MOUSE_RIGHT = 1
    MOUSE_MIDDLE = 2
    MOUSE_X1 = 3
    MOUSE_X2 = 4
end

export DopMouseButton, MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE, MOUSE_X1, MOUSE_X2

"""
Modifier key flags.
"""
const MOD_NONE = UInt8(0)
const MOD_SHIFT = UInt8(1)
const MOD_CTRL = UInt8(2)
const MOD_ALT = UInt8(4)
const MOD_SUPER = UInt8(8)

export MOD_NONE, MOD_SHIFT, MOD_CTRL, MOD_ALT, MOD_SUPER

"""
    DopEvent

An event from the Rust window system.
"""
struct DopEvent
    event_type::DopEventType
    key::Int32
    scancode::Int32
    modifiers::UInt8
    char_code::UInt32
    button::DopMouseButton
    x::Float64
    y::Float64
    scroll_x::Float64
    scroll_y::Float64
    width::Int32
    height::Int32
    timestamp::Float64
end

export DopEvent

# ============================================================================
# Window Handle
# ============================================================================

"""
    RustWindowHandle

Handle to a Rust-based window.
"""
mutable struct RustWindowHandle
    ptr::Ptr{Nothing}
    is_valid::Bool
    
    function RustWindowHandle(ptr::Ptr{Nothing})
        h = new(ptr, ptr != C_NULL)
        finalizer(h) do handle
            if handle.is_valid && handle.ptr != C_NULL
                destroy!(handle)
            end
        end
        return h
    end
end

"""
    create_window(; width=800, height=600, title="DOP Browser") -> RustWindowHandle

Create a new window (headless mode - actual windowing requires event loop integration).
"""
function create_window(; width::Integer=800, height::Integer=600, title::String="DOP Browser")::RustWindowHandle
    ptr = ccall(get_func(:dop_window_create_headless), 
                Ptr{Nothing}, (Cint, Cint), 
                width, height)
    return RustWindowHandle(ptr)
end

"""
    destroy!(handle::RustWindowHandle)

Destroy a window and release resources.
"""
function destroy!(handle::RustWindowHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_window_free), Cvoid, (Ptr{Nothing},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    is_open(handle::RustWindowHandle) -> Bool

Check if the window is still open.
"""
function is_open(handle::RustWindowHandle)::Bool
    if !handle.is_valid
        return false
    end
    return ccall(get_func(:dop_window_is_open), Cint, (Ptr{Nothing},), handle.ptr) != 0
end

"""
    close!(handle::RustWindowHandle)

Close the window.
"""
function close!(handle::RustWindowHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_window_close), Cvoid, (Ptr{Nothing},), handle.ptr)
    end
end

"""
    get_size(handle::RustWindowHandle) -> Tuple{Int, Int}

Get the window size.
"""
function get_size(handle::RustWindowHandle)::Tuple{Int, Int}
    if !handle.is_valid
        return (0, 0)
    end
    width = ccall(get_func(:dop_window_get_width), Cint, (Ptr{Nothing},), handle.ptr)
    height = ccall(get_func(:dop_window_get_height), Cint, (Ptr{Nothing},), handle.ptr)
    return (Int(width), Int(height))
end

export get_size

# ============================================================================
# Threaded Window Handle (for onscreen rendering)
# ============================================================================

"""
    RustThreadedWindowHandle

Handle to a Rust-based onscreen window running in a separate thread.
"""
mutable struct RustThreadedWindowHandle
    ptr::Ptr{Nothing}
    is_valid::Bool
    
    function RustThreadedWindowHandle(ptr::Ptr{Nothing})
        h = new(ptr, ptr != C_NULL)
        finalizer(h) do handle
            if handle.is_valid && handle.ptr != C_NULL
                destroy_threaded!(handle)
            end
        end
        return h
    end
end

export RustThreadedWindowHandle

"""
    create_onscreen_window(; width=800, height=600, title="DOP Browser") -> RustThreadedWindowHandle

Create a new onscreen window running in a separate thread with its own event loop.
"""
function create_onscreen_window(; width::Integer=800, height::Integer=600, title::String="DOP Browser")::RustThreadedWindowHandle
    ptr = ccall(get_func(:dop_window_create_onscreen), 
                Ptr{Nothing}, (Cint, Cint, Cstring), 
                width, height, title)
    return RustThreadedWindowHandle(ptr)
end

export create_onscreen_window

"""
    destroy_threaded!(handle::RustThreadedWindowHandle)

Destroy a threaded window and release resources.
"""
function destroy_threaded!(handle::RustThreadedWindowHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_window_free_threaded), Cvoid, (Ptr{Nothing},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

export destroy_threaded!

"""
    is_open_threaded(handle::RustThreadedWindowHandle) -> Bool

Check if the threaded window is still open.
"""
function is_open_threaded(handle::RustThreadedWindowHandle)::Bool
    if !handle.is_valid
        return false
    end
    return ccall(get_func(:dop_window_is_open_threaded), Cint, (Ptr{Nothing},), handle.ptr) != 0
end

export is_open_threaded

"""
    poll_events_threaded!(handle::RustThreadedWindowHandle; max_events::Integer=100) -> Vector{DopEvent}

Poll events from the threaded window.
"""
function poll_events_threaded!(handle::RustThreadedWindowHandle; max_events::Integer=100)::Vector{DopEvent}
    if !handle.is_valid || handle.ptr == C_NULL
        return DopEvent[]
    end
    
    # Allocate buffer for events
    events = Vector{DopEvent}(undef, max_events)
    
    count = ccall(get_func(:dop_window_poll_events_threaded),
                  Cint, (Ptr{Nothing}, Ptr{DopEvent}, Cint),
                  handle.ptr, pointer(events), max_events)
    
    # Return only the events that were actually filled
    return events[1:count]
end

export poll_events_threaded!

"""
    get_size_threaded(handle::RustThreadedWindowHandle) -> Tuple{Int, Int}

Get the size of the threaded window.
"""
function get_size_threaded(handle::RustThreadedWindowHandle)::Tuple{Int, Int}
    if !handle.is_valid
        return (0, 0)
    end
    width = ccall(get_func(:dop_window_get_width_threaded), Cint, (Ptr{Nothing},), handle.ptr)
    height = ccall(get_func(:dop_window_get_height_threaded), Cint, (Ptr{Nothing},), handle.ptr)
    return (Int(width), Int(height))
end

export get_size_threaded

# ============================================================================
# Renderer Handle
# ============================================================================

"""
    RustRendererHandle

Handle to a Rust-based renderer.
"""
mutable struct RustRendererHandle
    ptr::Ptr{Nothing}
    width::UInt32
    height::UInt32
    is_valid::Bool
    
    function RustRendererHandle(ptr::Ptr{Nothing}, width::UInt32, height::UInt32)
        h = new(ptr, width, height, ptr != C_NULL)
        finalizer(h) do handle
            if handle.is_valid && handle.ptr != C_NULL
                destroy!(handle)
            end
        end
        return h
    end
end

"""
    create_renderer(width::Integer, height::Integer) -> RustRendererHandle

Create a new headless renderer.
"""
function create_renderer(width::Integer, height::Integer)::RustRendererHandle
    ptr = ccall(get_func(:dop_renderer_create_headless), 
                Ptr{Nothing}, (Cint, Cint), 
                width, height)
    return RustRendererHandle(ptr, UInt32(width), UInt32(height))
end

"""
    destroy!(handle::RustRendererHandle)

Destroy a renderer and release resources.
"""
function destroy!(handle::RustRendererHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_free), Cvoid, (Ptr{Nothing},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    clear!(handle::RustRendererHandle)

Clear all render commands.
"""
function clear!(handle::RustRendererHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_clear), Cvoid, (Ptr{Nothing},), handle.ptr)
    end
end

"""
    set_clear_color!(handle::RustRendererHandle, r::Float32, g::Float32, b::Float32, a::Float32)

Set the clear color.
"""
function set_clear_color!(handle::RustRendererHandle, 
                          r::Real, g::Real, b::Real, a::Real=1.0)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_set_clear_color), 
              Cvoid, (Ptr{Nothing}, Cfloat, Cfloat, Cfloat, Cfloat), 
              handle.ptr, Float32(r), Float32(g), Float32(b), Float32(a))
    end
end

"""
    add_rect!(handle::RustRendererHandle, x, y, width, height, r, g, b, a; z_index=0)

Add a rectangle render command.
"""
function add_rect!(handle::RustRendererHandle,
                   x::Real, y::Real, width::Real, height::Real,
                   r::Real, g::Real, b::Real, a::Real;
                   z_index::Integer=0)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_add_rect), 
              Cvoid, (Ptr{Nothing}, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cint), 
              handle.ptr, 
              Float32(x), Float32(y), Float32(width), Float32(height),
              Float32(r), Float32(g), Float32(b), Float32(a),
              Int32(z_index))
    end
end

"""
    render!(handle::RustRendererHandle)

Render the current frame.
"""
function render!(handle::RustRendererHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_render), Cvoid, (Ptr{Nothing},), handle.ptr)
    end
end

"""
    get_framebuffer(handle::RustRendererHandle) -> Vector{UInt8}

Get the framebuffer as a copy.
"""
function get_framebuffer(handle::RustRendererHandle)::Vector{UInt8}
    if !handle.is_valid || handle.ptr == C_NULL
        return UInt8[]
    end
    
    ptr = ccall(get_func(:dop_renderer_get_framebuffer), 
                Ptr{UInt8}, (Ptr{Nothing},), 
                handle.ptr)
    size = ccall(get_func(:dop_renderer_get_framebuffer_size), 
                 Cint, (Ptr{Nothing},), 
                 handle.ptr)
    
    if ptr == C_NULL || size <= 0
        return UInt8[]
    end
    
    # Copy the data to Julia-owned array
    buffer = Vector{UInt8}(undef, size)
    unsafe_copyto!(pointer(buffer), ptr, size)
    return buffer
end

"""
    get_framebuffer_size(handle::RustRendererHandle) -> Int

Get the framebuffer size in bytes.
"""
function get_framebuffer_size(handle::RustRendererHandle)::Int
    if !handle.is_valid || handle.ptr == C_NULL
        return 0
    end
    return Int(ccall(get_func(:dop_renderer_get_framebuffer_size), 
                     Cint, (Ptr{Nothing},), 
                     handle.ptr))
end

"""
    renderer_resize!(handle::RustRendererHandle, width::Integer, height::Integer)

Resize the renderer.
"""
function renderer_resize!(handle::RustRendererHandle, width::Integer, height::Integer)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_resize), 
              Cvoid, (Ptr{Nothing}, Cint, Cint), 
              handle.ptr, width, height)
        handle.width = UInt32(width)
        handle.height = UInt32(height)
    end
end

export renderer_resize!

# ============================================================================
# Text Rendering Functions
# ============================================================================

"""
    add_text!(handle::RustRendererHandle, text::String, x, y; 
              font_size=16.0, r=0.0, g=0.0, b=0.0, a=1.0, font_id=0)

Add a text render command.
"""
function add_text!(handle::RustRendererHandle, text::String,
                   x::Real, y::Real;
                   font_size::Real=16.0,
                   r::Real=0.0, g::Real=0.0, b::Real=0.0, a::Real=1.0,
                   font_id::Integer=0)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_renderer_add_text), 
              Cvoid, (Ptr{Nothing}, Cstring, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cfloat, Cint), 
              handle.ptr, text,
              Float32(x), Float32(y), Float32(font_size),
              Float32(r), Float32(g), Float32(b), Float32(a),
              Int32(font_id))
    end
end

export add_text!

"""
    measure_text(handle::RustRendererHandle, text::String; font_size=16.0, font_id=0) -> Tuple{Float32, Float32}

Measure text width and height.
"""
function measure_text(handle::RustRendererHandle, text::String;
                      font_size::Real=16.0, font_id::Integer=0)::Tuple{Float32, Float32}
    if !handle.is_valid || handle.ptr == C_NULL
        return (Float32(0), Float32(0))
    end
    
    width = Ref{Cfloat}(0.0)
    height = Ref{Cfloat}(0.0)
    
    ccall(get_func(:dop_renderer_measure_text), 
          Cvoid, (Ptr{Nothing}, Cstring, Cfloat, Cint, Ptr{Cfloat}, Ptr{Cfloat}), 
          handle.ptr, text, Float32(font_size), Int32(font_id),
          width, height)
    
    return (Float32(width[]), Float32(height[]))
end

export measure_text

"""
    load_font!(handle::RustRendererHandle, path::String) -> Int

Load a font from file. Returns font ID or -1 on failure.
"""
function load_font!(handle::RustRendererHandle, path::String)::Int
    if !handle.is_valid || handle.ptr == C_NULL
        return -1
    end
    
    result = ccall(get_func(:dop_renderer_load_font), 
                   Cint, (Ptr{Nothing}, Cstring), 
                   handle.ptr, path)
    return Int(result)
end

export load_font!

"""
    has_default_font(handle::RustRendererHandle) -> Bool

Check if a default font is available.
"""
function has_default_font(handle::RustRendererHandle)::Bool
    if !handle.is_valid || handle.ptr == C_NULL
        return false
    end
    
    result = ccall(get_func(:dop_renderer_has_default_font), 
                   Cint, (Ptr{Nothing},), 
                   handle.ptr)
    return result != 0
end

export has_default_font

"""
    export_png!(handle::RustRendererHandle, path::String) -> Bool

Export the framebuffer to a PNG file.
"""
function export_png!(handle::RustRendererHandle, path::String)::Bool
    if !handle.is_valid || handle.ptr == C_NULL
        return false
    end
    
    result = ccall(get_func(:dop_renderer_export_png), 
                   Cint, (Ptr{Nothing}, Cstring), 
                   handle.ptr, path)
    return result != 0
end

export export_png!

# ============================================================================
# Text Shaper
# ============================================================================

"""
    TextShaperHandle

Handle to a text shaper for paragraph layout.
"""
mutable struct TextShaperHandle
    ptr::Ptr{Nothing}
    is_valid::Bool
    
    function TextShaperHandle(ptr::Ptr{Nothing})
        h = new(ptr, ptr != C_NULL)
        finalizer(h) do handle
            if handle.is_valid && handle.ptr != C_NULL
                destroy_shaper!(handle)
            end
        end
        return h
    end
end

export TextShaperHandle

"""
    create_text_shaper() -> TextShaperHandle

Create a new text shaper.
"""
function create_text_shaper()::TextShaperHandle
    ptr = ccall(get_func(:dop_text_shaper_create), Ptr{Nothing}, ())
    return TextShaperHandle(ptr)
end

export create_text_shaper

"""
    destroy_shaper!(handle::TextShaperHandle)

Destroy a text shaper.
"""
function destroy_shaper!(handle::TextShaperHandle)
    if handle.is_valid && handle.ptr != C_NULL
        ccall(get_func(:dop_text_shaper_free), Cvoid, (Ptr{Nothing},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

export destroy_shaper!

"""
    ShapedTextResult

Result of text shaping.
"""
struct ShapedTextResult
    width::Float32
    height::Float32
    line_count::Int32
end

export ShapedTextResult

"""
    shape_paragraph(handle::TextShaperHandle, text::String, max_width::Real; font_size::Real=16.0) -> ShapedTextResult

Shape a paragraph with word wrapping.
"""
function shape_paragraph(handle::TextShaperHandle, text::String, max_width::Real;
                         font_size::Real=16.0)::ShapedTextResult
    if !handle.is_valid || handle.ptr == C_NULL
        return ShapedTextResult(0.0f0, 0.0f0, 0)
    end
    
    # The FFI returns a struct, we need to call and get the result
    result = ccall(get_func(:dop_text_shaper_shape), 
                   NTuple{3, Cfloat}, (Ptr{Nothing}, Cstring, Cfloat, Cfloat), 
                   handle.ptr, text, Float32(max_width), Float32(font_size))
    
    return ShapedTextResult(result[1], result[2], Int32(result[3]))
end

export shape_paragraph

"""
    shaper_load_font!(handle::TextShaperHandle, path::String) -> Int

Load a font into the text shaper.
"""
function shaper_load_font!(handle::TextShaperHandle, path::String)::Int
    if !handle.is_valid || handle.ptr == C_NULL
        return -1
    end
    
    result = ccall(get_func(:dop_text_shaper_load_font), 
                   Cint, (Ptr{Nothing}, Cstring), 
                   handle.ptr, path)
    return Int(result)
end

export shaper_load_font!

"""
    shaper_has_font(handle::TextShaperHandle) -> Bool

Check if the shaper has a font loaded.
"""
function shaper_has_font(handle::TextShaperHandle)::Bool
    if !handle.is_valid || handle.ptr == C_NULL
        return false
    end
    
    result = ccall(get_func(:dop_text_shaper_has_font), 
                   Cint, (Ptr{Nothing},), 
                   handle.ptr)
    return result != 0
end

export shaper_has_font

# ============================================================================
# Utility Functions
# ============================================================================

"""
    get_version() -> String

Get the library version.
"""
function get_version()::String
    ptr = ccall(get_func(:dop_version), Cstring, ())
    return unsafe_string(ptr)
end

export get_version

end # module RustRenderer
