"""
    RenderBuffer

Linear command buffer for direct WebGPU upload.

Generates a sequence of render commands that can be uploaded directly
to the GPU without intermediate processing. Commands are stored in a
contiguous buffer for optimal cache performance.
"""
module RenderBuffer

export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, emit_stroke!, emit_stroke_sides!
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
    CMD_STROKE = 8  # Border/stroke rendering
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

"""
    emit_stroke!(buffer::CommandBuffer, x::Float32, y::Float32,
                 width::Float32, height::Float32,
                 stroke_width::Float32,
                 r::Float32, g::Float32, b::Float32, a::Float32)

Emit a stroke (border) draw command.
Draws a rectangular outline.

# Arguments
- `buffer::CommandBuffer` - Target command buffer
- `x, y` - Position of the stroke box (outer edge)
- `width, height` - Dimensions of the stroke box (outer edge)
- `stroke_width` - Width of the stroke line
- `r, g, b, a` - Stroke color components (0-1)

# Mathematical Model

The stroke is drawn as 4 rectangles forming a frame:
    - Top:    (x, y, width, stroke_width)
    - Right:  (x + width - stroke_width, y, stroke_width, height)
    - Bottom: (x, y + height - stroke_width, width, stroke_width)
    - Left:   (x, y, stroke_width, height)
"""
function emit_stroke!(buffer::CommandBuffer, x::Float32, y::Float32,
                      width::Float32, height::Float32,
                      stroke_width::Float32,
                      r::Float32, g::Float32, b::Float32, a::Float32)
    if stroke_width <= 0.0f0
        return buffer
    end
    
    # Encode stroke_width as extra_data (multiplied by 100 to preserve precision)
    extra = UInt32(round(stroke_width * 100))
    
    cmd = RenderCommand(CMD_STROKE, x, y, width, height, r, g, b, a, UInt32(0), extra)
    push!(buffer.commands, cmd)
    return buffer
end

"""
    emit_stroke_sides!(buffer::CommandBuffer, x::Float32, y::Float32,
                       width::Float32, height::Float32,
                       top_width::Float32, right_width::Float32,
                       bottom_width::Float32, left_width::Float32,
                       top_r::Float32, top_g::Float32, top_b::Float32, top_a::Float32,
                       right_r::Float32, right_g::Float32, right_b::Float32, right_a::Float32,
                       bottom_r::Float32, bottom_g::Float32, bottom_b::Float32, bottom_a::Float32,
                       left_r::Float32, left_g::Float32, left_b::Float32, left_a::Float32)

Emit individual border sides with different widths and colors.
This is the more complete version for Acid2 compliance where each side
can have different styling.
"""
function emit_stroke_sides!(buffer::CommandBuffer, x::Float32, y::Float32,
                            width::Float32, height::Float32,
                            top_width::Float32, right_width::Float32,
                            bottom_width::Float32, left_width::Float32,
                            top_r::Float32, top_g::Float32, top_b::Float32, top_a::Float32,
                            right_r::Float32, right_g::Float32, right_b::Float32, right_a::Float32,
                            bottom_r::Float32, bottom_g::Float32, bottom_b::Float32, bottom_a::Float32,
                            left_r::Float32, left_g::Float32, left_b::Float32, left_a::Float32)
    # Top border
    if top_width > 0.0f0 && top_a > 0.0f0
        emit_rect!(buffer, x, y, width, top_width, top_r, top_g, top_b, top_a)
    end
    
    # Right border
    if right_width > 0.0f0 && right_a > 0.0f0
        emit_rect!(buffer, x + width - right_width, y + top_width, 
                   right_width, height - top_width - bottom_width,
                   right_r, right_g, right_b, right_a)
    end
    
    # Bottom border
    if bottom_width > 0.0f0 && bottom_a > 0.0f0
        emit_rect!(buffer, x, y + height - bottom_width, width, bottom_width,
                   bottom_r, bottom_g, bottom_b, bottom_a)
    end
    
    # Left border
    if left_width > 0.0f0 && left_a > 0.0f0
        emit_rect!(buffer, x, y + top_width, left_width, 
                   height - top_width - bottom_width,
                   left_r, left_g, left_b, left_a)
    end
    
    return buffer
end

end # module RenderBuffer
