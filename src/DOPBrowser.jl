"""
    DOPBrowser

A Data-Oriented Programming (DOP) browser engine base implementation in Julia.

This module provides a render-friendly Intermediate Representation (IR) that replaces
traditional DOM & CSSOM with cache-efficient, SIMD-friendly data structures.

## Key Design Principles

- **Structure of Arrays (SoA)**: DOM treated as flat arrays, not object trees
- **Zero-Copy Parsing**: Flat token tape with immediate string interning
- **Index-based Nodes**: Use UInt32 indices instead of pointers
- **Archetype System**: Solve unique style combinations once, memcpy to nodes
- **SIMD-friendly Layout**: Contiguous float arrays for vectorized computation
- **Linear Render Buffer**: Direct WebGPU upload-ready command buffer
- **Cache Maximization**: Batch costly operations for optimal CPU cache usage
"""
module DOPBrowser

# Core modules
include("StringInterner.jl")
include("TokenTape.jl")
include("NodeTable.jl")
include("StyleArchetypes.jl")
include("LayoutArrays.jl")
include("RenderBuffer.jl")
include("CSSParser.jl")
include("Core.jl")

# Re-exports from submodules
using .StringInterner: StringPool, intern!, get_string, get_id
using .TokenTape: TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
using .NodeTable: NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling, get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count,
                  NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
                  get_id_attr, get_class_attr, get_style_attr, set_attributes!
using .StyleArchetypes: StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
using .LayoutArrays: LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!,
                    set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!,
                    set_background_color!, get_background_color
using .RenderBuffer: RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, clear!, get_commands, command_count
using .CSSParser: CSSStyles, parse_inline_style, parse_color, parse_length,
                  POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                  OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
                  DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE

export StringPool, intern!, get_string, get_id
export TokenType, Token, Tokenizer, tokenize!, reset!, get_tokens
export NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling, get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count,
       NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
       get_id_attr, get_class_attr, get_style_attr, set_attributes!
export StyleProperty, Archetype, ArchetypeTable, get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count
export LayoutData, resize_layout!, set_bounds!, get_bounds, set_position!, get_position, compute_layout!,
       set_css_position!, set_offsets!, set_margins!, set_paddings!, set_overflow!, set_visibility!, set_z_index!,
       set_background_color!, get_background_color
export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!, clear!, get_commands, command_count
export CSSStyles, parse_inline_style, parse_color, parse_length,
       POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
       OVERFLOW_VISIBLE, OVERFLOW_HIDDEN,
       DISPLAY_BLOCK, DISPLAY_INLINE, DISPLAY_NONE

# Core API
using .Core: BrowserContext, create_context, parse_html!, apply_styles!, compute_layouts!, generate_render_commands!, process_document!
export BrowserContext, create_context, parse_html!, apply_styles!, compute_layouts!, generate_render_commands!, process_document!

end # module DOPBrowser
