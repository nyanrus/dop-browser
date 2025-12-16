"""
    Core

Core browser context that ties together all modules.

Maximizes CPU cache efficiency by batching costly operations and
providing a unified API for document processing.
"""
module Core

using ..StringInterner: StringPool, intern!, get_string
using ..TokenTape: TokenType, Token, Tokenizer, tokenize!, get_tokens, 
                   TOKEN_START_TAG, TOKEN_END_TAG, TOKEN_TEXT, TOKEN_COMMENT, 
                   TOKEN_DOCTYPE, TOKEN_SELF_CLOSING, TOKEN_ATTRIBUTE
using ..NodeTable: NodeKind, DOMTable, add_node!, node_count,
                   NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE
using ..StyleArchetypes: ArchetypeTable, get_or_create_archetype!, archetype_count
using ..LayoutArrays: LayoutData, resize_layout!, set_bounds!, set_position!, compute_layout!
using ..RenderBuffer: CommandBuffer, emit_rect!, clear!, command_count, get_commands

export BrowserContext, create_context, parse_html!, apply_styles!, 
       compute_layouts!, generate_render_commands!, process_document!

"""
    BrowserContext

Central context holding all browser engine data structures.

Designed for cache-efficient batch processing of documents.

# Fields
- `strings::StringPool` - Interned string storage
- `tokenizer::Tokenizer` - HTML tokenizer
- `dom::DOMTable` - DOM node table
- `archetypes::ArchetypeTable` - Style archetypes
- `layout::LayoutData` - Layout computation data
- `render_buffer::CommandBuffer` - Render command buffer
- `viewport_width::Float32` - Viewport width in pixels
- `viewport_height::Float32` - Viewport height in pixels
"""
mutable struct BrowserContext
    strings::StringPool
    tokenizer::Tokenizer
    dom::DOMTable
    archetypes::ArchetypeTable
    layout::LayoutData
    render_buffer::CommandBuffer
    viewport_width::Float32
    viewport_height::Float32
    
    function BrowserContext(; viewport_width::Float32 = 1920.0f0, 
                              viewport_height::Float32 = 1080.0f0)
        pool = StringPool()
        new(
            pool,
            Tokenizer(pool),
            DOMTable(pool),
            ArchetypeTable(),
            LayoutData(),
            CommandBuffer(),
            viewport_width,
            viewport_height
        )
    end
end

"""
    create_context(; viewport_width::Float32 = 1920.0f0, 
                    viewport_height::Float32 = 1080.0f0) -> BrowserContext

Create a new browser context with optional viewport dimensions.
"""
function create_context(; viewport_width::Float32 = 1920.0f0, 
                          viewport_height::Float32 = 1080.0f0)::BrowserContext
    return BrowserContext(viewport_width=viewport_width, viewport_height=viewport_height)
end

"""
    parse_html!(ctx::BrowserContext, html::AbstractString) -> Int

Parse HTML into the DOM table.

Returns the number of nodes created.
"""
function parse_html!(ctx::BrowserContext, html::AbstractString)::Int
    # Tokenize HTML
    tokens = tokenize!(ctx.tokenizer, html)
    
    # Build DOM from tokens
    root_id = add_node!(ctx.dom, NODE_DOCUMENT)
    node_stack = UInt32[root_id]
    current_parent = root_id
    
    i = 1
    while i <= length(tokens)
        token = tokens[i]
        
        if token.type == TOKEN_START_TAG || token.type == TOKEN_SELF_CLOSING
            # Create element node
            node_id = add_node!(ctx.dom, NODE_ELEMENT, 
                               tag=token.name_id, parent=current_parent)
            
            # Process attributes (following tokens)
            j = i + 1
            while j <= length(tokens) && tokens[j].type == TOKEN_ATTRIBUTE
                # Store attributes (in a real implementation)
                j += 1
            end
            i = j - 1
            
            # Push to stack for non-self-closing tags
            if token.type == TOKEN_START_TAG
                push!(node_stack, node_id)
                current_parent = node_id
            end
            
        elseif token.type == TOKEN_END_TAG
            # Pop from stack
            if length(node_stack) > 1
                pop!(node_stack)
                current_parent = node_stack[end]
            end
            
        elseif token.type == TOKEN_TEXT
            # Create text node
            add_node!(ctx.dom, NODE_TEXT, 
                     text=token.value_id, parent=current_parent)
            
        elseif token.type == TOKEN_COMMENT
            # Create comment node
            add_node!(ctx.dom, NODE_COMMENT, 
                     text=token.value_id, parent=current_parent)
            
        elseif token.type == TOKEN_DOCTYPE
            # Create doctype node
            add_node!(ctx.dom, NODE_DOCTYPE, parent=current_parent)
        end
        
        i += 1
    end
    
    return node_count(ctx.dom)
end

"""
    apply_styles!(ctx::BrowserContext) -> Int

Apply style archetypes to all nodes.

Returns the number of unique archetypes.
"""
function apply_styles!(ctx::BrowserContext)::Int
    n = node_count(ctx.dom)
    
    # In a real implementation, this would:
    # 1. Parse CSS
    # 2. Match selectors to nodes
    # 3. Compute and cache archetypes
    # 4. Assign archetype IDs to nodes
    
    # For now, assign a default archetype to all elements
    default_archetype = get_or_create_archetype!(ctx.archetypes, UInt32[])
    
    for i in 1:n
        if ctx.dom.kinds[i] == NODE_ELEMENT
            ctx.dom.archetype_ids[i] = default_archetype
        end
    end
    
    return archetype_count(ctx.archetypes)
end

"""
    compute_layouts!(ctx::BrowserContext)

Compute layout for all nodes.

Uses contiguous array operations for SIMD optimization.
"""
function compute_layouts!(ctx::BrowserContext)
    n = node_count(ctx.dom)
    
    # Resize layout arrays
    resize_layout!(ctx.layout, n)
    
    # Set root node dimensions to viewport
    if n >= 1
        set_bounds!(ctx.layout, 1, ctx.viewport_width, ctx.viewport_height)
        set_position!(ctx.layout, 1, 0.0f0, 0.0f0)
    end
    
    # Compute layout using flat loops
    compute_layout!(ctx.layout, ctx.dom.parents, 
                    ctx.dom.first_children, ctx.dom.next_siblings)
end

"""
    generate_render_commands!(ctx::BrowserContext) -> Int

Generate render commands for all visible nodes.

Returns the number of commands generated.
"""
function generate_render_commands!(ctx::BrowserContext)::Int
    clear!(ctx.render_buffer)
    n = node_count(ctx.dom)
    
    # Traverse nodes and emit render commands
    for i in 1:n
        if ctx.dom.kinds[i] != NODE_ELEMENT
            continue
        end
        
        x = ctx.layout.x[i]
        y = ctx.layout.y[i]
        width = ctx.layout.width[i]
        height = ctx.layout.height[i]
        
        # Skip zero-size nodes
        if width <= 0 || height <= 0
            continue
        end
        
        # Emit background rect (simplified - would use archetype colors)
        emit_rect!(ctx.render_buffer, x, y, width, height,
                   0.9f0, 0.9f0, 0.9f0, 1.0f0)
    end
    
    return command_count(ctx.render_buffer)
end

"""
    process_document!(ctx::BrowserContext, html::AbstractString) -> NamedTuple

Process a complete HTML document through all pipeline stages.

This is the main entry point for document processing, batching all
costly operations for optimal cache efficiency.

# Returns
Named tuple with:
- `node_count::Int` - Number of DOM nodes
- `archetype_count::Int` - Number of unique style archetypes
- `command_count::Int` - Number of render commands
"""
function process_document!(ctx::BrowserContext, html::AbstractString)
    nodes = parse_html!(ctx, html)
    archetypes = apply_styles!(ctx)
    compute_layouts!(ctx)
    commands = generate_render_commands!(ctx)
    
    return (
        node_count = nodes,
        archetype_count = archetypes,
        command_count = commands
    )
end

end # module Core
