"""
    RustContent

Rust-based Content-- builder with FFI interface.

This module provides a thin Julia wrapper around the Rust Content-- implementation,
replacing the old ContentMM Julia modules.
"""
module RustContent

using Libdl

export ContentBuilder
export begin_stack!, end!, rect!, begin_paragraph!, span!
export direction!, pack!, align!, width!, height!, gap!
export fill!, fill_hex!, inset!, inset_trbl!, border_radius!
export font_size!, text_color_hex!, node_count

# Load the Rust library
const LIBPATH = Ref{String}("")

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
    
    for path in search_paths
        if isfile(path)
            LIBPATH[] = path
            @info "Loaded RustContent library from: $path"
            return
        end
    end
    
    error("Could not find dop-content library. Please build it first using: julia deps/build.jl")
end

"""
    ContentBuilder

Builder for constructing Content-- trees using Rust backend.
"""
mutable struct ContentBuilder
    handle::Ptr{Cvoid}
    
    function ContentBuilder()
        handle = @ccall $(LIBPATH[]).content_builder_new()::Ptr{Cvoid}
        builder = new(handle)
        finalizer(free_builder, builder)
        return builder
    end
end

function free_builder(builder::ContentBuilder)
    if builder.handle != C_NULL
        @ccall $(LIBPATH[]).content_builder_free(builder.handle::Ptr{Cvoid})::Cvoid
        builder.handle = C_NULL
    end
end

"""
    begin_stack!(builder::ContentBuilder) -> ContentBuilder

Begin a Stack container.
"""
function begin_stack!(builder::ContentBuilder)
    @ccall $(LIBPATH[]).content_builder_begin_stack(builder.handle::Ptr{Cvoid})::Cvoid
    return builder
end

"""
    end!(builder::ContentBuilder) -> ContentBuilder

End the current container.
"""
function Base.end!(builder::ContentBuilder)
    @ccall $(LIBPATH[]).content_builder_end(builder.handle::Ptr{Cvoid})::Cvoid
    return builder
end

"""
    rect!(builder::ContentBuilder) -> ContentBuilder

Add a Rect node.
"""
function rect!(builder::ContentBuilder)
    @ccall $(LIBPATH[]).content_builder_rect(builder.handle::Ptr{Cvoid})::Cvoid
    return builder
end

"""
    begin_paragraph!(builder::ContentBuilder) -> ContentBuilder

Begin a Paragraph node.
"""
function begin_paragraph!(builder::ContentBuilder)
    @ccall $(LIBPATH[]).content_builder_begin_paragraph(builder.handle::Ptr{Cvoid})::Cvoid
    return builder
end

"""
    span!(builder::ContentBuilder, text::String) -> ContentBuilder

Add a Span node with text.
"""
function span!(builder::ContentBuilder, text::String)
    @ccall $(LIBPATH[]).content_builder_span(builder.handle::Ptr{Cvoid}, text::Cstring)::Cvoid
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
    @ccall $(LIBPATH[]).content_builder_direction(builder.handle::Ptr{Cvoid}, dir_code::UInt8)::Cvoid
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
    @ccall $(LIBPATH[]).content_builder_pack(builder.handle::Ptr{Cvoid}, pack_code::UInt8)::Cvoid
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
    @ccall $(LIBPATH[]).content_builder_align(builder.handle::Ptr{Cvoid}, align_code::UInt8)::Cvoid
    return builder
end

"""
    width!(builder::ContentBuilder, w::Real) -> ContentBuilder

Set width.
"""
function width!(builder::ContentBuilder, w::Real)
    @ccall $(LIBPATH[]).content_builder_width(builder.handle::Ptr{Cvoid}, Float32(w)::Float32)::Cvoid
    return builder
end

"""
    height!(builder::ContentBuilder, h::Real) -> ContentBuilder

Set height.
"""
function height!(builder::ContentBuilder, h::Real)
    @ccall $(LIBPATH[]).content_builder_height(builder.handle::Ptr{Cvoid}, Float32(h)::Float32)::Cvoid
    return builder
end

"""
    gap!(builder::ContentBuilder, g::Real) -> ContentBuilder

Set gap.
"""
function gap!(builder::ContentBuilder, g::Real)
    @ccall $(LIBPATH[]).content_builder_gap(builder.handle::Ptr{Cvoid}, Float32(g)::Float32)::Cvoid
    return builder
end

"""
    fill_hex!(builder::ContentBuilder, hex::String) -> ContentBuilder

Set fill color from hex string (e.g., "#FF0000").
"""
function fill_hex!(builder::ContentBuilder, hex::String)
    @ccall $(LIBPATH[]).content_builder_fill_hex(builder.handle::Ptr{Cvoid}, hex::Cstring)::Cvoid
    return builder
end

"""
    fill!(builder::ContentBuilder, r::Integer, g::Integer, b::Integer, a::Integer=255) -> ContentBuilder

Set fill color from RGBA values.
"""
function fill!(builder::ContentBuilder, r::Integer, g::Integer, b::Integer, a::Integer=255)
    @ccall $(LIBPATH[]).content_builder_fill_rgba(
        builder.handle::Ptr{Cvoid}, 
        UInt8(r)::UInt8, 
        UInt8(g)::UInt8, 
        UInt8(b)::UInt8, 
        UInt8(a)::UInt8
    )::Cvoid
    return builder
end

"""
    inset!(builder::ContentBuilder, i::Real) -> ContentBuilder

Set inset (padding) on all sides.
"""
function inset!(builder::ContentBuilder, i::Real)
    @ccall $(LIBPATH[]).content_builder_inset(builder.handle::Ptr{Cvoid}, Float32(i)::Float32)::Cvoid
    return builder
end

"""
    inset_trbl!(builder::ContentBuilder, top::Real, right::Real, bottom::Real, left::Real) -> ContentBuilder

Set inset (padding) with individual sides.
"""
function inset_trbl!(builder::ContentBuilder, top::Real, right::Real, bottom::Real, left::Real)
    @ccall $(LIBPATH[]).content_builder_inset_trbl(
        builder.handle::Ptr{Cvoid}, 
        Float32(top)::Float32, 
        Float32(right)::Float32, 
        Float32(bottom)::Float32, 
        Float32(left)::Float32
    )::Cvoid
    return builder
end

"""
    border_radius!(builder::ContentBuilder, r::Real) -> ContentBuilder

Set border radius.
"""
function border_radius!(builder::ContentBuilder, r::Real)
    @ccall $(LIBPATH[]).content_builder_border_radius(builder.handle::Ptr{Cvoid}, Float32(r)::Float32)::Cvoid
    return builder
end

"""
    font_size!(builder::ContentBuilder, size::Real) -> ContentBuilder

Set font size.
"""
function font_size!(builder::ContentBuilder, size::Real)
    @ccall $(LIBPATH[]).content_builder_font_size(builder.handle::Ptr{Cvoid}, Float32(size)::Float32)::Cvoid
    return builder
end

"""
    text_color_hex!(builder::ContentBuilder, hex::String) -> ContentBuilder

Set text color from hex string (e.g., "#000000").
"""
function text_color_hex!(builder::ContentBuilder, hex::String)
    @ccall $(LIBPATH[]).content_builder_text_color_hex(builder.handle::Ptr{Cvoid}, hex::Cstring)::Cvoid
    return builder
end

"""
    node_count(builder::ContentBuilder) -> Int

Get the number of nodes in the builder.
"""
function node_count(builder::ContentBuilder)
    return @ccall $(LIBPATH[]).content_builder_node_count(builder.handle::Ptr{Cvoid})::Csize_t
end

end # module RustContent
