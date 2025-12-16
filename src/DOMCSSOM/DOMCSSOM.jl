"""
    DOMCSSOM

Virtual DOM and CSSOM module representing the browser's document model.

This module provides the Structure of Arrays (SoA) representation of:
- DOM nodes (NodeTable)
- Style archetypes (StyleArchetypes) 
- Render commands (RenderBuffer)

Note: StringInterner is imported from HTMLParser module to avoid duplication.

## Architecture

The module represents the "view" of Content-- as a virtual DOM/CSSOM:
- No actual DOM objects - just typed arrays
- Index-based references (UInt32) instead of pointers
- Cache-friendly traversal patterns
- SIMD-ready data layouts

## Usage

```julia
using DOPBrowser.DOMCSSOM
using DOPBrowser.HTMLParser: StringPool

pool = StringPool()
dom = DOMTable(pool)
root_id = add_node!(dom, NODE_DOCUMENT)
```
"""
module DOMCSSOM

# Import StringInterner from HTMLParser to avoid duplication
using ..HTMLParser.StringInterner: StringPool, intern!, get_string, get_id

# Include modules
include("NodeTable.jl")
include("StyleArchetypes.jl")
include("RenderBuffer.jl")

# Re-export from submodules
using .NodeTable: NodeKind, DOMTable, add_node!, get_parent, get_first_child, 
                  get_next_sibling, get_tag, set_parent!, set_first_child!, 
                  set_next_sibling!, node_count,
                  NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE,
                  get_id_attr, get_class_attr, get_style_attr, set_attributes!
using .StyleArchetypes: StyleProperty, Archetype, ArchetypeTable, 
                        get_or_create_archetype!, apply_archetype!, 
                        get_archetype, archetype_count
using .RenderBuffer: RenderCommand, CommandBuffer, emit_rect!, emit_text!, 
                     emit_image!, emit_stroke!, emit_stroke_sides!, clear!, 
                     get_commands, command_count

# Export StringInterner API (re-exported from HTMLParser)
export StringPool, intern!, get_string, get_id

# Export NodeTable API
export NodeKind, DOMTable, add_node!, get_parent, get_first_child, get_next_sibling
export get_tag, set_parent!, set_first_child!, set_next_sibling!, node_count
export NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE
export get_id_attr, get_class_attr, get_style_attr, set_attributes!

# Export StyleArchetypes API
export StyleProperty, Archetype, ArchetypeTable
export get_or_create_archetype!, apply_archetype!, get_archetype, archetype_count

# Export RenderBuffer API
export RenderCommand, CommandBuffer, emit_rect!, emit_text!, emit_image!
export emit_stroke!, emit_stroke_sides!, clear!, get_commands, command_count

# Re-export submodules
export NodeTable, StyleArchetypes, RenderBuffer

end # module DOMCSSOM
