"""
    GPURenderer

WebGPU-based GPU rendering for Content--.

## Features
- Direct render command buffer upload
- Efficient batching for minimal draw calls
- Support for rectangles, text, and images
- Clip/scissor stack management
"""
module GPURenderer

export GPUContext, GPUBuffer, GPUPipeline
export RenderPassDescriptor, RenderBatch
export create_gpu_context, begin_frame, end_frame
export submit_commands!, present!

"""
    GPUBufferUsage

WebGPU-style buffer usage flags.
"""
const BUFFER_USAGE_VERTEX = UInt32(0x0020)
const BUFFER_USAGE_INDEX = UInt32(0x0040)
const BUFFER_USAGE_UNIFORM = UInt32(0x0080)
const BUFFER_USAGE_STORAGE = UInt32(0x0100)
const BUFFER_USAGE_COPY_SRC = UInt32(0x0004)
const BUFFER_USAGE_COPY_DST = UInt32(0x0008)

"""
    GPUBuffer

A GPU buffer for vertex/index/uniform data.
"""
mutable struct GPUBuffer
    id::UInt64
    size::UInt64
    usage::UInt32
    data::Vector{UInt8}
    mapped::Bool
    
    function GPUBuffer(size::UInt64, usage::UInt32)
        new(rand(UInt64), size, usage, zeros(UInt8, size), false)
    end
end

"""
    write_buffer!(buffer::GPUBuffer, offset::UInt64, data::Vector{UInt8})

Write data to a buffer.
"""
function write_buffer!(buffer::GPUBuffer, offset::UInt64, data::Vector{UInt8})
    n = min(length(data), buffer.size - offset)
    for i in 1:n
        buffer.data[offset + i] = data[i]
    end
end

"""
    Vertex

A vertex for 2D rendering.
"""
struct Vertex
    x::Float32
    y::Float32
    u::Float32
    v::Float32
    r::Float32
    g::Float32
    b::Float32
    a::Float32
end

"""
    GPUTexture

A GPU texture for images and font atlases.
"""
mutable struct GPUTexture
    id::UInt64
    width::UInt32
    height::UInt32
    format::UInt32  # RGBA8, etc.
    data::Vector{UInt8}
    
    function GPUTexture(width::UInt32, height::UInt32)
        new(rand(UInt64), width, height, 0, zeros(UInt8, width * height * 4))
    end
end

"""
    GPUPipeline

A render pipeline configuration.
"""
mutable struct GPUPipeline
    id::UInt64
    vertex_shader::String
    fragment_shader::String
    blend_mode::Symbol  # :alpha, :additive, :none
    
    function GPUPipeline(; blend_mode::Symbol = :alpha)
        new(rand(UInt64), "", "", blend_mode)
    end
end

"""
    DrawCommand

A single draw command in a batch.
"""
struct DrawCommand
    first_vertex::UInt32
    vertex_count::UInt32
    first_index::UInt32
    index_count::UInt32
    texture_id::UInt64
    clip_rect::NTuple{4, Float32}  # x, y, w, h
end

"""
    RenderBatch

A batch of draw commands sharing the same pipeline.
"""
mutable struct RenderBatch
    pipeline::GPUPipeline
    vertex_buffer::GPUBuffer
    index_buffer::GPUBuffer
    vertices::Vector{Vertex}
    indices::Vector{UInt32}
    commands::Vector{DrawCommand}
    current_texture::UInt64
    clip_stack::Vector{NTuple{4, Float32}}
    
    function RenderBatch(pipeline::GPUPipeline)
        new(
            pipeline,
            GPUBuffer(UInt64(1024 * 1024), BUFFER_USAGE_VERTEX),  # 1MB vertex buffer
            GPUBuffer(UInt64(256 * 1024), BUFFER_USAGE_INDEX),   # 256KB index buffer
            Vertex[],
            UInt32[],
            DrawCommand[],
            UInt64(0),
            NTuple{4, Float32}[]
        )
    end
end

"""
    add_rect!(batch::RenderBatch, x::Float32, y::Float32, 
              w::Float32, h::Float32,
              r::Float32, g::Float32, b::Float32, a::Float32;
              texture_id::UInt64 = UInt64(0))

Add a rectangle to the batch.
"""
function add_rect!(batch::RenderBatch, x::Float32, y::Float32,
                   w::Float32, h::Float32,
                   r::Float32, g::Float32, b::Float32, a::Float32;
                   texture_id::UInt64 = UInt64(0))
    first_vertex = UInt32(length(batch.vertices))
    first_index = UInt32(length(batch.indices))
    
    # Add 4 vertices (quad)
    push!(batch.vertices, Vertex(x,     y,     0.0f0, 0.0f0, r, g, b, a))
    push!(batch.vertices, Vertex(x + w, y,     1.0f0, 0.0f0, r, g, b, a))
    push!(batch.vertices, Vertex(x + w, y + h, 1.0f0, 1.0f0, r, g, b, a))
    push!(batch.vertices, Vertex(x,     y + h, 0.0f0, 1.0f0, r, g, b, a))
    
    # Add 6 indices (2 triangles)
    push!(batch.indices, first_vertex)
    push!(batch.indices, first_vertex + 1)
    push!(batch.indices, first_vertex + 2)
    push!(batch.indices, first_vertex)
    push!(batch.indices, first_vertex + 2)
    push!(batch.indices, first_vertex + 3)
    
    # Get clip rect
    clip = isempty(batch.clip_stack) ? 
           (0.0f0, 0.0f0, typemax(Float32), typemax(Float32)) :
           batch.clip_stack[end]
    
    # Add draw command
    push!(batch.commands, DrawCommand(
        first_vertex, UInt32(4),
        first_index, UInt32(6),
        texture_id, clip
    ))
end

"""
    push_clip!(batch::RenderBatch, x::Float32, y::Float32, w::Float32, h::Float32)

Push a clip rectangle.
"""
function push_clip!(batch::RenderBatch, x::Float32, y::Float32, w::Float32, h::Float32)
    if isempty(batch.clip_stack)
        push!(batch.clip_stack, (x, y, w, h))
    else
        # Intersect with current clip
        (cx, cy, cw, ch) = batch.clip_stack[end]
        nx = max(x, cx)
        ny = max(y, cy)
        nr = min(x + w, cx + cw)
        nb = min(y + h, cy + ch)
        push!(batch.clip_stack, (nx, ny, max(0.0f0, nr - nx), max(0.0f0, nb - ny)))
    end
end

"""
    pop_clip!(batch::RenderBatch)

Pop the clip rectangle stack.
"""
function pop_clip!(batch::RenderBatch)
    if !isempty(batch.clip_stack)
        pop!(batch.clip_stack)
    end
end

"""
    clear_batch!(batch::RenderBatch)

Clear all data from a batch.
"""
function clear_batch!(batch::RenderBatch)
    empty!(batch.vertices)
    empty!(batch.indices)
    empty!(batch.commands)
    empty!(batch.clip_stack)
    batch.current_texture = UInt64(0)
end

"""
    GPUContext

Main GPU rendering context.
"""
mutable struct GPUContext
    # Device info
    device_id::UInt64
    
    # Render targets
    width::UInt32
    height::UInt32
    framebuffer::Vector{UInt8}  # CPU-side for PNG export
    
    # Pipelines
    rect_pipeline::GPUPipeline
    text_pipeline::GPUPipeline
    image_pipeline::GPUPipeline
    
    # Current batch
    current_batch::RenderBatch
    
    # Textures
    textures::Dict{UInt64, GPUTexture}
    
    # Stats
    draw_calls::UInt32
    vertices_submitted::UInt32
    
    function GPUContext(width::UInt32, height::UInt32)
        rect_pipe = GPUPipeline(blend_mode=:alpha)
        
        new(
            rand(UInt64),
            width, height,
            zeros(UInt8, width * height * 4),
            rect_pipe,
            GPUPipeline(blend_mode=:alpha),
            GPUPipeline(blend_mode=:alpha),
            RenderBatch(rect_pipe),
            Dict{UInt64, GPUTexture}(),
            UInt32(0),
            UInt32(0)
        )
    end
end

"""
    create_gpu_context(width::UInt32, height::UInt32) -> GPUContext

Create a new GPU context.
"""
function create_gpu_context(width::UInt32, height::UInt32)::GPUContext
    return GPUContext(width, height)
end

"""
    begin_frame(ctx::GPUContext; clear_color::NTuple{4, Float32} = (0.0f0, 0.0f0, 0.0f0, 1.0f0))

Begin a new frame.
"""
function begin_frame(ctx::GPUContext; 
                     clear_color::NTuple{4, Float32} = (0.0f0, 0.0f0, 0.0f0, 1.0f0))
    # Reset stats
    ctx.draw_calls = UInt32(0)
    ctx.vertices_submitted = UInt32(0)
    
    # Clear batch
    clear_batch!(ctx.current_batch)
    
    # Clear framebuffer
    r = round(UInt8, clear_color[1] * 255)
    g = round(UInt8, clear_color[2] * 255)
    b = round(UInt8, clear_color[3] * 255)
    a = round(UInt8, clear_color[4] * 255)
    
    for i in 0:(ctx.width * ctx.height - 1)
        idx = i * 4 + 1
        ctx.framebuffer[idx] = r
        ctx.framebuffer[idx + 1] = g
        ctx.framebuffer[idx + 2] = b
        ctx.framebuffer[idx + 3] = a
    end
end

"""
    submit_commands!(ctx::GPUContext, commands::Vector{<:Any})

Submit render commands from the RenderBuffer.
"""
function submit_commands!(ctx::GPUContext, commands::Vector{<:Any})
    for cmd in commands
        # Process each command type
        if hasproperty(cmd, :cmd_type)
            cmd_type = cmd.cmd_type
            if UInt8(cmd_type) == 1  # CMD_RECT
                add_rect!(ctx.current_batch, 
                         cmd.x, cmd.y, cmd.width, cmd.height,
                         cmd.color_r, cmd.color_g, cmd.color_b, cmd.color_a;
                         texture_id=UInt64(cmd.texture_id))
            end
        end
    end
end

"""
    end_frame(ctx::GPUContext)

End the frame and flush batches.
"""
function end_frame(ctx::GPUContext)
    # Rasterize all commands to framebuffer (software rendering for CPU-side output)
    for cmd in ctx.current_batch.commands
        rasterize_command!(ctx, cmd)
    end
    
    ctx.draw_calls = UInt32(length(ctx.current_batch.commands))
    ctx.vertices_submitted = UInt32(length(ctx.current_batch.vertices))
end

"""
    rasterize_command!(ctx::GPUContext, cmd::DrawCommand)

Software rasterize a command (for CPU-side framebuffer).
"""
function rasterize_command!(ctx::GPUContext, cmd::DrawCommand)
    # Get vertices for this command
    for i in 0:(cmd.vertex_count - 4)÷4
        base_idx = cmd.first_vertex + i * 4
        if base_idx + 3 > length(ctx.current_batch.vertices)
            continue
        end
        
        v0 = ctx.current_batch.vertices[base_idx + 1]
        v2 = ctx.current_batch.vertices[base_idx + 3]
        
        # Rectangle bounds
        x0 = max(0, min(Int(floor(v0.x)), Int(ctx.width) - 1))
        y0 = max(0, min(Int(floor(v0.y)), Int(ctx.height) - 1))
        x1 = max(0, min(Int(ceil(v2.x)), Int(ctx.width)))
        y1 = max(0, min(Int(ceil(v2.y)), Int(ctx.height)))
        
        # Apply clip
        (cx, cy, cw, ch) = cmd.clip_rect
        if cw < typemax(Float32) - 1
            x0 = max(x0, Int(floor(cx)))
            y0 = max(y0, Int(floor(cy)))
            x1 = min(x1, Int(ceil(cx + cw)))
            y1 = min(y1, Int(ceil(cy + ch)))
        end
        
        # Fill rectangle
        r = round(UInt8, v0.r * 255)
        g = round(UInt8, v0.g * 255)
        b = round(UInt8, v0.b * 255)
        a = round(UInt8, v0.a * 255)
        
        for y in y0:(y1-1)
            for x in x0:(x1-1)
                idx = (y * Int(ctx.width) + x) * 4 + 1
                if idx > 0 && idx + 3 <= length(ctx.framebuffer)
                    # Simple alpha blend
                    alpha = Float32(a) / 255.0f0
                    inv_alpha = 1.0f0 - alpha
                    ctx.framebuffer[idx] = round(UInt8, Float32(r) * alpha + Float32(ctx.framebuffer[idx]) * inv_alpha)
                    ctx.framebuffer[idx + 1] = round(UInt8, Float32(g) * alpha + Float32(ctx.framebuffer[idx + 1]) * inv_alpha)
                    ctx.framebuffer[idx + 2] = round(UInt8, Float32(b) * alpha + Float32(ctx.framebuffer[idx + 2]) * inv_alpha)
                    ctx.framebuffer[idx + 3] = round(UInt8, min(255, Int(ctx.framebuffer[idx + 3]) + Int(a)))
                end
            end
        end
    end
end

"""
    present!(ctx::GPUContext)

Present the frame (swap buffers in real GPU impl).
"""
function present!(ctx::GPUContext)
    # In real implementation, would swap GPU buffers
    # Here, data is already in framebuffer for CPU access
end

"""
    get_framebuffer(ctx::GPUContext) -> Vector{UInt8}

Get the CPU-side framebuffer for PNG export.
"""
function get_framebuffer(ctx::GPUContext)::Vector{UInt8}
    return ctx.framebuffer
end

end # module GPURenderer
