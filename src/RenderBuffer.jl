"""
    RenderBuffer

Linear command buffer for direct WebGPU upload.

Generates a sequence of render commands that can be uploaded directly
to the GPU without intermediate processing. Commands are stored in a
contiguous buffer for optimal cache performance.
"""
module RenderBuffer

export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!
export clear!, get_commands, command_count

"""
    RenderCommandType

Types of render commands.
"""
@enum RenderCommandType::UInt8 begin
    CMD_RECT = 1
    CMD_TEXT = 2
    CMD_IMAGE = 3
    CMD_CLIP_PUSH = 4
    CMD_CLIP_POP = 5
    CMD_TRANSFORM_PUSH = 6
    CMD_TRANSFORM_POP = 7
end

"""
    RenderCommand

A single render command in the command buffer.

Commands are designed for direct GPU upload, with all data in a flat format.

# Fields
- `cmd_type::RenderCommandType` - Type of command
- `x::Float32` - X position
- `y::Float32` - Y position
- `width::Float32` - Width
- `height::Float32` - Height
- `color_r::Float32` - Red component (0-1)
- `color_g::Float32` - Green component (0-1)
- `color_b::Float32` - Blue component (0-1)
- `color_a::Float32` - Alpha component (0-1)
- `texture_id::UInt32` - Texture/font atlas ID (0 if none)
- `extra_data::UInt32` - Command-specific extra data
"""
struct RenderCommand
    cmd_type::RenderCommandType
    x::Float32
    y::Float32
    width::Float32
    height::Float32
    color_r::Float32
    color_g::Float32
    color_b::Float32
    color_a::Float32
    texture_id::UInt32
    extra_data::UInt32
end

"""
    CommandBuffer

Linear buffer of render commands for GPU upload.

# Fields
- `commands::Vector{RenderCommand}` - The command buffer
- `clip_stack::Vector{NTuple{4, Float32}}` - Current clip rect stack
"""
mutable struct CommandBuffer
    commands::Vector{RenderCommand}
    clip_stack::Vector{NTuple{4, Float32}}
    
    function CommandBuffer(capacity::Int = 1024)
        new(
            sizehint!(RenderCommand[], capacity),
            NTuple{4, Float32}[]
        )
    end
end

"""
    command_count(buffer::CommandBuffer) -> Int

Return the number of commands in the buffer.
"""
function command_count(buffer::CommandBuffer)::Int
    return length(buffer.commands)
end

"""
    clear!(buffer::CommandBuffer)

Clear all commands from the buffer.
"""
function clear!(buffer::CommandBuffer)
    empty!(buffer.commands)
    empty!(buffer.clip_stack)
    return buffer
end

"""
    get_commands(buffer::CommandBuffer) -> Vector{RenderCommand}

Get the command buffer for GPU upload.
"""
function get_commands(buffer::CommandBuffer)::Vector{RenderCommand}
    return buffer.commands
end

"""
    emit_rect!(buffer::CommandBuffer, x::Float32, y::Float32, 
               width::Float32, height::Float32,
               r::Float32, g::Float32, b::Float32, a::Float32)

Emit a rectangle draw command.

# Arguments
- `buffer::CommandBuffer` - Target command buffer
- `x, y` - Position
- `width, height` - Dimensions
- `r, g, b, a` - Color components (0-1)
"""
function emit_rect!(buffer::CommandBuffer, x::Float32, y::Float32, 
                    width::Float32, height::Float32,
                    r::Float32, g::Float32, b::Float32, a::Float32)
    cmd = RenderCommand(CMD_RECT, x, y, width, height, r, g, b, a, UInt32(0), UInt32(0))
    push!(buffer.commands, cmd)
    return buffer
end

"""
    emit_text!(buffer::CommandBuffer, x::Float32, y::Float32,
               width::Float32, height::Float32,
               r::Float32, g::Float32, b::Float32, a::Float32,
               font_atlas_id::UInt32, glyph_offset::UInt32)

Emit a text draw command.

# Arguments
- `buffer::CommandBuffer` - Target command buffer
- `x, y` - Position
- `width, height` - Text bounds
- `r, g, b, a` - Text color
- `font_atlas_id` - Font atlas texture ID
- `glyph_offset` - Offset into glyph buffer
"""
function emit_text!(buffer::CommandBuffer, x::Float32, y::Float32,
                    width::Float32, height::Float32,
                    r::Float32, g::Float32, b::Float32, a::Float32,
                    font_atlas_id::UInt32, glyph_offset::UInt32)
    cmd = RenderCommand(CMD_TEXT, x, y, width, height, r, g, b, a, font_atlas_id, glyph_offset)
    push!(buffer.commands, cmd)
    return buffer
end

"""
    emit_image!(buffer::CommandBuffer, x::Float32, y::Float32,
                width::Float32, height::Float32,
                texture_id::UInt32)

Emit an image draw command.

# Arguments
- `buffer::CommandBuffer` - Target command buffer
- `x, y` - Position
- `width, height` - Dimensions
- `texture_id` - Image texture ID
"""
function emit_image!(buffer::CommandBuffer, x::Float32, y::Float32,
                     width::Float32, height::Float32,
                     texture_id::UInt32)
    cmd = RenderCommand(CMD_IMAGE, x, y, width, height, 
                        1.0f0, 1.0f0, 1.0f0, 1.0f0, texture_id, UInt32(0))
    push!(buffer.commands, cmd)
    return buffer
end

"""
    push_clip!(buffer::CommandBuffer, x::Float32, y::Float32, 
               width::Float32, height::Float32)

Push a clip rectangle onto the stack and emit clip command.
"""
function push_clip!(buffer::CommandBuffer, x::Float32, y::Float32, 
                    width::Float32, height::Float32)
    push!(buffer.clip_stack, (x, y, width, height))
    cmd = RenderCommand(CMD_CLIP_PUSH, x, y, width, height, 
                        0.0f0, 0.0f0, 0.0f0, 0.0f0, UInt32(0), UInt32(0))
    push!(buffer.commands, cmd)
    return buffer
end

"""
    pop_clip!(buffer::CommandBuffer)

Pop the clip rectangle stack and emit pop command.
"""
function pop_clip!(buffer::CommandBuffer)
    if !isempty(buffer.clip_stack)
        pop!(buffer.clip_stack)
        cmd = RenderCommand(CMD_CLIP_POP, 0.0f0, 0.0f0, 0.0f0, 0.0f0, 
                            0.0f0, 0.0f0, 0.0f0, 0.0f0, UInt32(0), UInt32(0))
        push!(buffer.commands, cmd)
    end
    return buffer
end

end # module RenderBuffer
