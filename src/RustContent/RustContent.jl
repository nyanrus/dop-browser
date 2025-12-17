"""
    RustContent

Rust-based Content-- builder with FFI interface.

This module provides a thin Julia wrapper around the Rust Content-- implementation,
replacing the old ContentMM Julia modules.
"""
module RustContent

using Libdl

export ContentBuilder
export begin_stack!, end_container!, rect!, begin_paragraph!, span!
export direction!, pack!, align!, width!, height!, gap!
export fill!, fill_hex!, inset!, inset_trbl!, border_radius!
export font_size!, text_color_hex!, node_count

# Load the Rust library
const LIB = Ref{Ptr{Cvoid}}(C_NULL)
const FUNCTIONS = Dict{Symbol, Ptr{Cvoid}}()

function __init__()
    # Try to find the library
    lib_name = if Sys.iswindows()
        "dop_content.dll"
    elseif Sys.isapple()
        "libdop_content.dylib"
    else
        "libdop_content.so"
    end
    
    # Search in artifacts directory and Rust target directory
    search_paths = [
        joinpath(@__DIR__, "..", "..", "artifacts", "dop-content", lib_name),
        joinpath(@__DIR__, "..", "..", "rust", "dop-content", "target", "release", lib_name),
    ]
    
    lib_path = nothing
    for path in search_paths
        if isfile(path)
            lib_path = path
            break
        end
    end
    
    if lib_path === nothing
        error("Could not find dop-content library. Please build it first using: julia deps/build.jl")
    end
    
    # Load the library
    LIB[] = dlopen(lib_path)
    
    # Load all function symbols
    FUNCTIONS[:new] = dlsym(LIB[], :content_builder_new)
    FUNCTIONS[:free] = dlsym(LIB[], :content_builder_free)
    FUNCTIONS[:begin_stack] = dlsym(LIB[], :content_builder_begin_stack)
    FUNCTIONS[:end] = dlsym(LIB[], :content_builder_end)
    FUNCTIONS[:rect] = dlsym(LIB[], :content_builder_rect)
    FUNCTIONS[:begin_paragraph] = dlsym(LIB[], :content_builder_begin_paragraph)
    FUNCTIONS[:span] = dlsym(LIB[], :content_builder_span)
    FUNCTIONS[:direction] = dlsym(LIB[], :content_builder_direction)
    FUNCTIONS[:pack] = dlsym(LIB[], :content_builder_pack)
    FUNCTIONS[:align] = dlsym(LIB[], :content_builder_align)
    FUNCTIONS[:width] = dlsym(LIB[], :content_builder_width)
    FUNCTIONS[:height] = dlsym(LIB[], :content_builder_height)
    FUNCTIONS[:gap] = dlsym(LIB[], :content_builder_gap)
    FUNCTIONS[:fill_hex] = dlsym(LIB[], :content_builder_fill_hex)
    FUNCTIONS[:fill_rgba] = dlsym(LIB[], :content_builder_fill_rgba)
    FUNCTIONS[:inset] = dlsym(LIB[], :content_builder_inset)
    FUNCTIONS[:inset_trbl] = dlsym(LIB[], :content_builder_inset_trbl)
    FUNCTIONS[:border_radius] = dlsym(LIB[], :content_builder_border_radius)
    FUNCTIONS[:font_size] = dlsym(LIB[], :content_builder_font_size)
    FUNCTIONS[:text_color_hex] = dlsym(LIB[], :content_builder_text_color_hex)
    FUNCTIONS[:node_count] = dlsym(LIB[], :content_builder_node_count)
    
    @info "Loaded RustContent library from: $lib_path"
end

"""
    ContentBuilder

Builder for constructing Content-- trees using Rust backend.
"""
mutable struct ContentBuilder
    handle::Ptr{Cvoid}
    
    function ContentBuilder()
        handle = ccall(FUNCTIONS[:new], Ptr{Cvoid}, ())
        builder = new(handle)
        finalizer(free_builder, builder)
        return builder
    end
end

function free_builder(builder::ContentBuilder)
    if builder.handle != C_NULL
        ccall(FUNCTIONS[:free], Cvoid, (Ptr{Cvoid},), builder.handle)
        builder.handle = C_NULL
    end
end

"""
    begin_stack!(builder::ContentBuilder) -> ContentBuilder

Begin a Stack container.
"""
function begin_stack!(builder::ContentBuilder)
    ccall(FUNCTIONS[:begin_stack], Cvoid, (Ptr{Cvoid},), builder.handle)
    return builder
end

"""
    end_container!(builder::ContentBuilder) -> ContentBuilder

End the current container.
"""
function end_container!(builder::ContentBuilder)
    ccall(FUNCTIONS[:end], Cvoid, (Ptr{Cvoid},), builder.handle)
    return builder
end

"""
    rect!(builder::ContentBuilder) -> ContentBuilder

Add a Rect node.
"""
function rect!(builder::ContentBuilder)
    ccall(FUNCTIONS[:rect], Cvoid, (Ptr{Cvoid},), builder.handle)
    return builder
end

"""
    begin_paragraph!(builder::ContentBuilder) -> ContentBuilder

Begin a Paragraph node.
"""
function begin_paragraph!(builder::ContentBuilder)
    ccall(FUNCTIONS[:begin_paragraph], Cvoid, (Ptr{Cvoid},), builder.handle)
    return builder
end

"""
    span!(builder::ContentBuilder, text::String) -> ContentBuilder

Add a Span node with text.
"""
function span!(builder::ContentBuilder, text::String)
    ccall(FUNCTIONS[:span], Cvoid, (Ptr{Cvoid}, Cstring), builder.handle, text)
    return builder
end

"""
    direction!(builder::ContentBuilder, dir::Symbol) -> ContentBuilder

Set direction (:down, :up, :right, :left).
"""
function direction!(builder::ContentBuilder, dir::Symbol)
    dir_code = if dir == :down
        UInt8(0)
    elseif dir == :up
        UInt8(1)
    elseif dir == :right
        UInt8(2)
    elseif dir == :left
        UInt8(3)
    else
        UInt8(0)
    end
    ccall(FUNCTIONS[:direction], Cvoid, (Ptr{Cvoid}, UInt8), builder.handle, dir_code)
    return builder
end

"""
    pack!(builder::ContentBuilder, pack::Symbol) -> ContentBuilder

Set pack (:start, :end, :center, :space_between, :space_around, :space_evenly).
"""
function pack!(builder::ContentBuilder, pack::Symbol)
    pack_code = if pack == :start
        UInt8(0)
    elseif pack == :end
        UInt8(1)
    elseif pack == :center
        UInt8(2)
    elseif pack == :space_between
        UInt8(3)
    elseif pack == :space_around
        UInt8(4)
    elseif pack == :space_evenly
        UInt8(5)
    else
        UInt8(0)
    end
    ccall(FUNCTIONS[:pack], Cvoid, (Ptr{Cvoid}, UInt8), builder.handle, pack_code)
    return builder
end

"""
    align!(builder::ContentBuilder, align::Symbol) -> ContentBuilder

Set align (:start, :end, :center, :stretch).
"""
function align!(builder::ContentBuilder, align::Symbol)
    align_code = if align == :start
        UInt8(0)
    elseif align == :end
        UInt8(1)
    elseif align == :center
        UInt8(2)
    elseif align == :stretch
        UInt8(3)
    else
        UInt8(0)
    end
    ccall(FUNCTIONS[:align], Cvoid, (Ptr{Cvoid}, UInt8), builder.handle, align_code)
    return builder
end

"""
    width!(builder::ContentBuilder, w::Real) -> ContentBuilder

Set width.
"""
function width!(builder::ContentBuilder, w::Real)
    ccall(FUNCTIONS[:width], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(w))
    return builder
end

"""
    height!(builder::ContentBuilder, h::Real) -> ContentBuilder

Set height.
"""
function height!(builder::ContentBuilder, h::Real)
    ccall(FUNCTIONS[:height], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(h))
    return builder
end

"""
    gap!(builder::ContentBuilder, g::Real) -> ContentBuilder

Set gap.
"""
function gap!(builder::ContentBuilder, g::Real)
    ccall(FUNCTIONS[:gap], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(g))
    return builder
end

"""
    fill_hex!(builder::ContentBuilder, hex::String) -> ContentBuilder

Set fill color from hex string (e.g., "#FF0000").
"""
function fill_hex!(builder::ContentBuilder, hex::String)
    ccall(FUNCTIONS[:fill_hex], Cvoid, (Ptr{Cvoid}, Cstring), builder.handle, hex)
    return builder
end

"""
    fill!(builder::ContentBuilder, r::Integer, g::Integer, b::Integer, a::Integer=255) -> ContentBuilder

Set fill color from RGBA values.
"""
function fill!(builder::ContentBuilder, r::Integer, g::Integer, b::Integer, a::Integer=255)
    ccall(FUNCTIONS[:fill_rgba], Cvoid, (Ptr{Cvoid}, UInt8, UInt8, UInt8, UInt8),
          builder.handle, UInt8(r), UInt8(g), UInt8(b), UInt8(a))
    return builder
end

"""
    inset!(builder::ContentBuilder, i::Real) -> ContentBuilder

Set inset (padding) on all sides.
"""
function inset!(builder::ContentBuilder, i::Real)
    ccall(FUNCTIONS[:inset], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(i))
    return builder
end

"""
    inset_trbl!(builder::ContentBuilder, top::Real, right::Real, bottom::Real, left::Real) -> ContentBuilder

Set inset (padding) with individual sides.
"""
function inset_trbl!(builder::ContentBuilder, top::Real, right::Real, bottom::Real, left::Real)
    ccall(FUNCTIONS[:inset_trbl], Cvoid, (Ptr{Cvoid}, Float32, Float32, Float32, Float32),
          builder.handle, Float32(top), Float32(right), Float32(bottom), Float32(left))
    return builder
end

"""
    border_radius!(builder::ContentBuilder, r::Real) -> ContentBuilder

Set border radius.
"""
function border_radius!(builder::ContentBuilder, r::Real)
    ccall(FUNCTIONS[:border_radius], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(r))
    return builder
end

"""
    font_size!(builder::ContentBuilder, size::Real) -> ContentBuilder

Set font size.
"""
function font_size!(builder::ContentBuilder, size::Real)
    ccall(FUNCTIONS[:font_size], Cvoid, (Ptr{Cvoid}, Float32), builder.handle, Float32(size))
    return builder
end

"""
    text_color_hex!(builder::ContentBuilder, hex::String) -> ContentBuilder

Set text color from hex string (e.g., "#000000").
"""
function text_color_hex!(builder::ContentBuilder, hex::String)
    ccall(FUNCTIONS[:text_color_hex], Cvoid, (Ptr{Cvoid}, Cstring), builder.handle, hex)
    return builder
end

"""
    node_count(builder::ContentBuilder) -> Int

Get the number of nodes in the builder.
"""
function node_count(builder::ContentBuilder)
    return ccall(FUNCTIONS[:node_count], Csize_t, (Ptr{Cvoid},), builder.handle)
end

end # module RustContent
