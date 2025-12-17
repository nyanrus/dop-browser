"""
    Renderer

Complete rendering pipeline from Content-- to GPU and PNG output.

This module integrates:
- GPURenderer: WebGPU-style GPU rendering
- PNGExport: Lossless PNG image export
- CairoRenderer: Cairo-based native rendering with text support
- RenderPipeline: Orchestrates the full render pass

For high-performance GPU rendering, consider using RustRenderer which provides
Rust-based rendering via winit/wgpu.
"""
module Renderer

include("GPURenderer.jl")
include("PNGExport.jl")
include("CairoRenderer.jl")

using .GPURenderer
using .PNGExport
using .CairoRenderer

export GPURenderer, PNGExport, CairoRenderer
export RenderPipeline, create_pipeline, render_frame!, export_png!

# Import RenderBuffer types
using ..DOMCSSOM.RenderBuffer: CommandBuffer, RenderCommand, get_commands

"""
    RenderPipeline

Orchestrates the complete rendering process.
"""
mutable struct RenderPipeline
    gpu_ctx::GPURenderer.GPUContext
    width::UInt32
    height::UInt32
    clear_color::NTuple{4, Float32}
    
    function RenderPipeline(width::UInt32, height::UInt32)
        new(
            GPURenderer.create_gpu_context(width, height),
            width, height,
            (1.0f0, 1.0f0, 1.0f0, 1.0f0)  # White background
        )
    end
end

"""
    create_pipeline(width::UInt32, height::UInt32) -> RenderPipeline

Create a new render pipeline.
"""
function create_pipeline(width::UInt32, height::UInt32)::RenderPipeline
    return RenderPipeline(width, height)
end

"""
    set_clear_color!(pipeline::RenderPipeline, r::Float32, g::Float32, b::Float32, a::Float32)

Set the background clear color.
"""
function set_clear_color!(pipeline::RenderPipeline, r::Float32, g::Float32, b::Float32, a::Float32)
    pipeline.clear_color = (r, g, b, a)
end

"""
    render_frame!(pipeline::RenderPipeline, commands::CommandBuffer)

Render a frame from the command buffer.
"""
function render_frame!(pipeline::RenderPipeline, commands::CommandBuffer)
    # Begin frame
    GPURenderer.begin_frame(pipeline.gpu_ctx, clear_color=pipeline.clear_color)
    
    # Submit all commands
    cmds = get_commands(commands)
    GPURenderer.submit_commands!(pipeline.gpu_ctx, cmds)
    
    # End frame
    GPURenderer.end_frame(pipeline.gpu_ctx)
    
    # Present
    GPURenderer.present!(pipeline.gpu_ctx)
end

"""
    export_png!(pipeline::RenderPipeline, filename::String)

Export the current framebuffer to a PNG file.
"""
function export_png!(pipeline::RenderPipeline, filename::String)
    framebuffer = GPURenderer.get_framebuffer(pipeline.gpu_ctx)
    PNGExport.write_png_file(filename, framebuffer, pipeline.width, pipeline.height)
end

"""
    get_png_data(pipeline::RenderPipeline) -> Vector{UInt8}

Get PNG-encoded data of the current framebuffer.
"""
function get_png_data(pipeline::RenderPipeline)::Vector{UInt8}
    framebuffer = GPURenderer.get_framebuffer(pipeline.gpu_ctx)
    return PNGExport.encode_png(framebuffer, pipeline.width, pipeline.height)
end

"""
    resize!(pipeline::RenderPipeline, width::UInt32, height::UInt32)

Resize the render pipeline.
"""
function resize!(pipeline::RenderPipeline, width::UInt32, height::UInt32)
    pipeline.width = width
    pipeline.height = height
    pipeline.gpu_ctx = GPURenderer.create_gpu_context(width, height)
end

end # module Renderer
