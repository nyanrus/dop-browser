"""
    RustRenderer

Rust-based rendering engine using winit and wgpu.

This module provides a high-performance rendering backend implemented in Rust,
with window management via winit and GPU rendering via wgpu. It exposes
FFI bindings to Julia for seamless integration with the DOP Browser.

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
Get the path to the Rust renderer library.
"""
function get_lib_path()::String
    # Try different possible locations
    possible_paths = String[]
    
    # Local build path (development)
    local_path = joinpath(@__DIR__, "..", "..", "rust", "dop-renderer", "target", "release")
    if Sys.iswindows()
        push!(possible_paths, joinpath(local_path, "dop_renderer.dll"))
    elseif Sys.isapple()
        push!(possible_paths, joinpath(local_path, "libdop_renderer.dylib"))
    else
        push!(possible_paths, joinpath(local_path, "libdop_renderer.so"))
    end
    
    # Debug build path
    debug_path = joinpath(@__DIR__, "..", "..", "rust", "dop-renderer", "target", "debug")
    if Sys.iswindows()
        push!(possible_paths, joinpath(debug_path, "dop_renderer.dll"))
    elseif Sys.isapple()
        push!(possible_paths, joinpath(debug_path, "libdop_renderer.dylib"))
    else
        push!(possible_paths, joinpath(debug_path, "libdop_renderer.so"))
    end
    
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
        error("Rust renderer library not found. Please build it with: cd rust/dop-renderer && cargo build --release")
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
