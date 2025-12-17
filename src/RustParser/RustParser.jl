"""
    RustParser

Rust-based HTML/CSS parsing and Content-- compilation via FFI.

This module provides Julia bindings to the dop-parser Rust crate, which implements:
- HTML parsing using html5ever
- CSS parsing using cssparser  
- Content-- compiler with zerocopy binary format
- JIT text shaping infrastructure

The Rust library is built using the unified BinaryBuilder configuration in deps/build.jl.

## Usage

```julia
using DOPBrowser.RustParser

# Check if Rust library is available
if RustParser.is_available()
    # Parse HTML
    result = RustParser.parse_html("<div><p>Hello</p></div>")
    
    # Parse CSS
    styles = RustParser.parse_inline_style("width: 100px; background-color: red;")
end
```
"""
module RustParser

export is_available, get_version
export parse_html, parse_inline_style, parse_color, parse_length
export create_string_pool, intern!, get_string

# Include the build utilities
const deps_dir = joinpath(dirname(dirname(@__DIR__)), "deps")
include(joinpath(deps_dir, "build.jl"))

# Library handle
const lib_handle = Ref{Ptr{Cvoid}}(C_NULL)
const lib_path = Ref{String}("")

"""
    find_library() -> Union{String, Nothing}

Find the dop-parser shared library using the unified build system.
"""
function find_library()
    # Use the unified build system to find the library
    path = get_library_path("dop-parser")
    if path !== nothing
        return path
    end
    
    # Fallback: look in various locations relative to the project
    candidates = String[]
    
    # Get the source directory
    src_dir = @__DIR__
    project_dir = dirname(dirname(src_dir))
    rust_dir = joinpath(project_dir, "rust", "dop-parser")
    
    # Check artifacts directory first
    artifacts_dir = joinpath(project_dir, "artifacts", "dop-parser")
    
    # Check for release and debug builds
    if Sys.iswindows()
        push!(candidates, joinpath(artifacts_dir, "dop_parser.dll"))
        push!(candidates, joinpath(rust_dir, "target", "release", "dop_parser.dll"))
        push!(candidates, joinpath(rust_dir, "target", "debug", "dop_parser.dll"))
    elseif Sys.isapple()
        push!(candidates, joinpath(artifacts_dir, "libdop_parser.dylib"))
        push!(candidates, joinpath(rust_dir, "target", "release", "libdop_parser.dylib"))
        push!(candidates, joinpath(rust_dir, "target", "debug", "libdop_parser.dylib"))
    else
        push!(candidates, joinpath(artifacts_dir, "libdop_parser.so"))
        push!(candidates, joinpath(rust_dir, "target", "release", "libdop_parser.so"))
        push!(candidates, joinpath(rust_dir, "target", "debug", "libdop_parser.so"))
    end
    
    for path in candidates
        if isfile(path)
            return path
        end
    end
    
    return nothing
end

"""
    is_available() -> Bool

Check if the Rust parser library is available.
"""
function is_available()::Bool
    if lib_handle[] != C_NULL
        return true
    end
    
    path = find_library()
    if path === nothing
        rust_dir = joinpath("rust", "dop-parser")
        error("Rust parser library not found. Please build it with: cd $(rust_dir) && cargo build --release")
    end
    
    try
        lib_handle[] = Libc.Libdl.dlopen(path)
        lib_path[] = path
        
        # Initialize the library
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_parser_init), Cvoid, ())
        
        return true
    catch e
        error("Failed to load Rust parser library: $e")
    end
end

"""
    get_version() -> String

Get the version of the Rust parser library.
"""
function get_version()::String
    if !is_available()
        return "0.0.0"
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_parser_version), Ptr{Cchar}, ())
    return unsafe_string(ptr)
end

# ============================================================================
# String Pool
# ============================================================================

"""
    StringPoolHandle

Handle to a Rust StringPool.
"""
mutable struct StringPoolHandle
    ptr::Ptr{Cvoid}
    is_valid::Bool
    
    function StringPoolHandle(ptr::Ptr{Cvoid})
        handle = new(ptr, ptr != C_NULL)
        finalizer(destroy!, handle)
        return handle
    end
end

function destroy!(handle::StringPoolHandle)
    if handle.is_valid && handle.ptr != C_NULL && lib_handle[] != C_NULL
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_pool_free), Cvoid, (Ptr{Cvoid},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    create_string_pool() -> StringPoolHandle

Create a new string pool.
"""
function create_string_pool()::StringPoolHandle
    if !is_available()
        return StringPoolHandle(C_NULL)
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_pool_new), Ptr{Cvoid}, ())
    return StringPoolHandle(ptr)
end

"""
    intern!(pool::StringPoolHandle, s::String) -> UInt32

Intern a string and return its ID.
"""
function intern!(pool::StringPoolHandle, s::String)::UInt32
    if !pool.is_valid
        return UInt32(0)
    end
    
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_pool_intern), UInt32,
                 (Ptr{Cvoid}, Cstring), pool.ptr, s)
end

"""
    get_string(pool::StringPoolHandle, id::UInt32) -> String

Get a string by its ID.
"""
function get_string(pool::StringPoolHandle, id::UInt32)::String
    if !pool.is_valid
        return ""
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_pool_get), Ptr{Cchar},
                (Ptr{Cvoid}, UInt32), pool.ptr, id)
    if ptr == C_NULL
        return ""
    end
    
    result = unsafe_string(ptr)
    ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_free), Cvoid, (Ptr{Cchar},), ptr)
    return result
end

# ============================================================================
# HTML Parsing
# ============================================================================

"""
    HtmlParseResult

Result of parsing HTML.
"""
mutable struct HtmlParseResult
    ptr::Ptr{Cvoid}
    is_valid::Bool
    
    function HtmlParseResult(ptr::Ptr{Cvoid})
        handle = new(ptr, ptr != C_NULL)
        finalizer(destroy!, handle)
        return handle
    end
end

function destroy!(result::HtmlParseResult)
    if result.is_valid && result.ptr != C_NULL && lib_handle[] != C_NULL
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_result_free), Cvoid, (Ptr{Cvoid},), result.ptr)
        result.ptr = C_NULL
        result.is_valid = false
    end
end

"""
    parse_html(html::String) -> HtmlParseResult

Parse HTML and return a result handle.
"""
function parse_html(html::String)::HtmlParseResult
    if !is_available()
        return HtmlParseResult(C_NULL)
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_parse), Ptr{Cvoid}, (Cstring,), html)
    return HtmlParseResult(ptr)
end

"""
    token_count(result::HtmlParseResult) -> UInt32

Get the number of tokens in the result.
"""
function token_count(result::HtmlParseResult)::UInt32
    if !result.is_valid
        return UInt32(0)
    end
    
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_result_token_count), UInt32,
                 (Ptr{Cvoid},), result.ptr)
end

"""
    get_token_type(result::HtmlParseResult, index::UInt32) -> UInt8

Get the token type at the given index.
"""
function get_token_type(result::HtmlParseResult, index::UInt32)::UInt8
    if !result.is_valid
        return UInt8(0)
    end
    
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_result_token_type), UInt8,
                 (Ptr{Cvoid}, UInt32), result.ptr, index)
end

"""
    get_token_name_id(result::HtmlParseResult, index::UInt32) -> UInt32

Get the token name ID at the given index.
"""
function get_token_name_id(result::HtmlParseResult, index::UInt32)::UInt32
    if !result.is_valid
        return UInt32(0)
    end
    
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_result_token_name_id), UInt32,
                 (Ptr{Cvoid}, UInt32), result.ptr, index)
end

"""
    get_token_string(result::HtmlParseResult, id::UInt32) -> String

Get a string from the result's string pool.
"""
function get_token_string(result::HtmlParseResult, id::UInt32)::String
    if !result.is_valid || id == 0
        return ""
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_html_result_get_string), Ptr{Cchar},
                (Ptr{Cvoid}, UInt32), result.ptr, id)
    if ptr == C_NULL
        return ""
    end
    
    result_str = unsafe_string(ptr)
    ccall(Libc.Libdl.dlsym(lib_handle[], :dop_string_free), Cvoid, (Ptr{Cchar},), ptr)
    return result_str
end

export HtmlParseResult, token_count, get_token_type, get_token_name_id, get_token_string

# ============================================================================
# CSS Parsing
# ============================================================================

"""
    CssStylesHandle

Handle to parsed CSS styles.
"""
mutable struct CssStylesHandle
    ptr::Ptr{Cvoid}
    is_valid::Bool
    
    function CssStylesHandle(ptr::Ptr{Cvoid})
        handle = new(ptr, ptr != C_NULL)
        finalizer(destroy!, handle)
        return handle
    end
end

function destroy!(handle::CssStylesHandle)
    if handle.is_valid && handle.ptr != C_NULL && lib_handle[] != C_NULL
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_styles_free), Cvoid, (Ptr{Cvoid},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    parse_inline_style(style_str::String) -> CssStylesHandle

Parse inline CSS style string.
"""
function parse_inline_style(style_str::String)::CssStylesHandle
    if !is_available()
        return CssStylesHandle(C_NULL)
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_parse_inline), Ptr{Cvoid},
                (Cstring,), style_str)
    return CssStylesHandle(ptr)
end

# CSS style getters
function get_position(handle::CssStylesHandle)::UInt8
    if !handle.is_valid
        return UInt8(0)
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_position), UInt8, (Ptr{Cvoid},), handle.ptr)
end

function get_display(handle::CssStylesHandle)::UInt8
    if !handle.is_valid
        return UInt8(1)
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_display), UInt8, (Ptr{Cvoid},), handle.ptr)
end

function get_width(handle::CssStylesHandle)::Float32
    if !handle.is_valid
        return 0.0f0
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_width), Float32, (Ptr{Cvoid},), handle.ptr)
end

function get_width_is_auto(handle::CssStylesHandle)::Bool
    if !handle.is_valid
        return true
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_width_is_auto), Cint, (Ptr{Cvoid},), handle.ptr) != 0
end

function get_height(handle::CssStylesHandle)::Float32
    if !handle.is_valid
        return 0.0f0
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_height), Float32, (Ptr{Cvoid},), handle.ptr)
end

function get_height_is_auto(handle::CssStylesHandle)::Bool
    if !handle.is_valid
        return true
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_height_is_auto), Cint, (Ptr{Cvoid},), handle.ptr) != 0
end

function get_background_color(handle::CssStylesHandle)::Tuple{UInt8, UInt8, UInt8, UInt8}
    if !handle.is_valid
        return (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    end
    r = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_background_r), UInt8, (Ptr{Cvoid},), handle.ptr)
    g = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_background_g), UInt8, (Ptr{Cvoid},), handle.ptr)
    b = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_background_b), UInt8, (Ptr{Cvoid},), handle.ptr)
    a = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_background_a), UInt8, (Ptr{Cvoid},), handle.ptr)
    return (r, g, b, a)
end

function has_background(handle::CssStylesHandle)::Bool
    if !handle.is_valid
        return false
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_get_has_background), Cint, (Ptr{Cvoid},), handle.ptr) != 0
end

export CssStylesHandle, get_position, get_display, get_width, get_width_is_auto
export get_height, get_height_is_auto, get_background_color, has_background

"""
    parse_color(color_str::String) -> Tuple{UInt8, UInt8, UInt8, UInt8}

Parse a CSS color string into RGBA values.
"""
function parse_color(color_str::String)::Tuple{UInt8, UInt8, UInt8, UInt8}
    if !is_available()
        return (UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    end
    
    r = Ref{UInt8}(0)
    g = Ref{UInt8}(0)
    b = Ref{UInt8}(0)
    a = Ref{UInt8}(0)
    
    ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_parse_color), Cvoid,
          (Cstring, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}, Ptr{UInt8}),
          color_str, r, g, b, a)
    
    return (r[], g[], b[], a[])
end

"""
    parse_length(length_str::String, container_size::Float32 = 0.0f0) -> Tuple{Float32, Bool}

Parse a CSS length string. Returns (value, is_auto).
"""
function parse_length(length_str::String, container_size::Float32 = 0.0f0)::Tuple{Float32, Bool}
    if !is_available()
        return (0.0f0, true)
    end
    
    value = Ref{Float32}(0.0f0)
    is_auto = Ref{Cint}(1)
    
    ccall(Libc.Libdl.dlsym(lib_handle[], :dop_css_parse_length), Cvoid,
          (Cstring, Float32, Ptr{Float32}, Ptr{Cint}),
          length_str, container_size, value, is_auto)
    
    return (value[], is_auto[] != 0)
end

# ============================================================================
# Text Shaping
# ============================================================================

"""
    TextShaperHandle

Handle to a Rust TextShaper.
"""
mutable struct TextShaperHandle
    ptr::Ptr{Cvoid}
    is_valid::Bool
    
    function TextShaperHandle(ptr::Ptr{Cvoid})
        handle = new(ptr, ptr != C_NULL)
        finalizer(destroy!, handle)
        return handle
    end
end

function destroy!(handle::TextShaperHandle)
    if handle.is_valid && handle.ptr != C_NULL && lib_handle[] != C_NULL
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_text_shaper_free), Cvoid, (Ptr{Cvoid},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    create_text_shaper() -> TextShaperHandle

Create a new text shaper.
"""
function create_text_shaper()::TextShaperHandle
    if !is_available()
        return TextShaperHandle(C_NULL)
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_text_shaper_new), Ptr{Cvoid}, ())
    return TextShaperHandle(ptr)
end

"""
    ShapedParagraphHandle

Handle to a shaped paragraph.
"""
mutable struct ShapedParagraphHandle
    ptr::Ptr{Cvoid}
    is_valid::Bool
    
    function ShapedParagraphHandle(ptr::Ptr{Cvoid})
        handle = new(ptr, ptr != C_NULL)
        finalizer(destroy!, handle)
        return handle
    end
end

function destroy!(handle::ShapedParagraphHandle)
    if handle.is_valid && handle.ptr != C_NULL && lib_handle[] != C_NULL
        ccall(Libc.Libdl.dlsym(lib_handle[], :dop_shaped_paragraph_free), Cvoid, (Ptr{Cvoid},), handle.ptr)
        handle.ptr = C_NULL
        handle.is_valid = false
    end
end

"""
    shape_paragraph(shaper::TextShaperHandle, text::String, max_width::Float32) -> ShapedParagraphHandle

Shape a paragraph of text.
"""
function shape_paragraph(shaper::TextShaperHandle, text::String, max_width::Float32)::ShapedParagraphHandle
    if !shaper.is_valid
        return ShapedParagraphHandle(C_NULL)
    end
    
    ptr = ccall(Libc.Libdl.dlsym(lib_handle[], :dop_text_shaper_shape), Ptr{Cvoid},
                (Ptr{Cvoid}, Cstring, Float32), shaper.ptr, text, max_width)
    return ShapedParagraphHandle(ptr)
end

function get_shaped_width(handle::ShapedParagraphHandle)::Float32
    if !handle.is_valid
        return 0.0f0
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_shaped_paragraph_width), Float32, (Ptr{Cvoid},), handle.ptr)
end

function get_shaped_height(handle::ShapedParagraphHandle)::Float32
    if !handle.is_valid
        return 0.0f0
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_shaped_paragraph_height), Float32, (Ptr{Cvoid},), handle.ptr)
end

function get_shaped_line_count(handle::ShapedParagraphHandle)::UInt32
    if !handle.is_valid
        return UInt32(0)
    end
    return ccall(Libc.Libdl.dlsym(lib_handle[], :dop_shaped_paragraph_line_count), UInt32, (Ptr{Cvoid},), handle.ptr)
end

export TextShaperHandle, ShapedParagraphHandle, create_text_shaper, shape_paragraph
export get_shaped_width, get_shaped_height, get_shaped_line_count

end # module RustParser
