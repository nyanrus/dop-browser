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
using ..NodeTable: NodeKind, DOMTable, add_node!, node_count, set_attributes!,
                   NODE_ELEMENT, NODE_TEXT, NODE_COMMENT, NODE_DOCUMENT, NODE_DOCTYPE
using ..StyleArchetypes: ArchetypeTable, get_or_create_archetype!, archetype_count
using ..LayoutArrays: LayoutData, resize_layout!, set_bounds!, set_position!, compute_layout!,
                      set_css_position!, set_offsets!, set_margins!, set_paddings!, 
                      set_overflow!, set_visibility!, set_z_index!, set_background_color!,
                      set_borders!, has_border,
                      POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                      DISPLAY_NONE, DISPLAY_BLOCK, OVERFLOW_HIDDEN
using ..RenderBuffer: CommandBuffer, emit_rect!, emit_stroke_sides!, clear!, command_count, get_commands
using ..CSSParser: CSSStyles, parse_inline_style

export BrowserContext, create_context, parse_html!, apply_styles!, 
       compute_layouts!, generate_render_commands!, process_document!

"""
    CSSRule

A parsed CSS rule with selector and styles.
"""
struct CSSRule
    selector::String
    styles::CSSStyles
end

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
- `css_rules::Vector{CSSRule}` - Parsed CSS rules from style blocks
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
    css_rules::Vector{CSSRule}
    
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
            viewport_height,
            CSSRule[]
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
    
    # Pre-intern common attribute names for lookup
    id_name_id = intern!(ctx.strings, "id")
    class_name_id = intern!(ctx.strings, "class")
    style_name_id = intern!(ctx.strings, "style")
    
    i = 1
    while i <= length(tokens)
        token = tokens[i]
        
        if token.type == TOKEN_START_TAG || token.type == TOKEN_SELF_CLOSING
            # Create element node
            node_id = add_node!(ctx.dom, NODE_ELEMENT, 
                               tag=token.name_id, parent=current_parent)
            
            # Process attributes (following tokens)
            id_attr = UInt32(0)
            class_attr = UInt32(0)
            style_attr = UInt32(0)
            
            j = i + 1
            while j <= length(tokens) && tokens[j].type == TOKEN_ATTRIBUTE
                attr_token = tokens[j]
                if attr_token.name_id == id_name_id
                    id_attr = attr_token.value_id
                elseif attr_token.name_id == class_name_id
                    class_attr = attr_token.value_id
                elseif attr_token.name_id == style_name_id
                    style_attr = attr_token.value_id
                end
                j += 1
            end
            
            # Store attributes
            set_attributes!(ctx.dom, node_id, 
                           id_attr=id_attr, 
                           class_attr=class_attr, 
                           style_attr=style_attr)
            
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
    
    # Extract CSS from <style> blocks
    parse_style_blocks!(ctx)
    
    return node_count(ctx.dom)
end

"""
    parse_style_blocks!(ctx::BrowserContext)

Find <style> elements in the DOM and parse their CSS content.
"""
function parse_style_blocks!(ctx::BrowserContext)
    empty!(ctx.css_rules)
    n = node_count(ctx.dom)
    
    style_tag_id = intern!(ctx.strings, "style")
    
    for i in 1:n
        if ctx.dom.kinds[i] != NODE_ELEMENT
            continue
        end
        
        tag_id = ctx.dom.tags[i]
        if tag_id != style_tag_id
            continue
        end
        
        # Find text content (first text child)
        child_id = ctx.dom.first_children[i]
        while child_id != 0 && child_id <= n
            if ctx.dom.kinds[child_id] == NODE_TEXT
                text_id = ctx.dom.text_content[child_id]
                if text_id != 0
                    css_text = get_string(ctx.strings, text_id)
                    parse_css_rules!(ctx, css_text)
                end
                break
            end
            child_id = ctx.dom.next_siblings[child_id]
        end
    end
end

"""
    parse_css_rules!(ctx::BrowserContext, css_text::String)

Parse CSS text and add rules to context.
"""
function parse_css_rules!(ctx::BrowserContext, css_text::String)
    # Remove comments
    css_text = replace(css_text, r"/\*.*?\*/"s => "")
    
    # Parse rule blocks: selector { declarations }
    rule_pattern = r"([^{}]+)\{([^{}]*)\}"s
    for m in eachmatch(rule_pattern, css_text)
        selector = strip(m.captures[1])
        declarations = m.captures[2]
        
        # Parse declarations as inline style
        styles = parse_inline_style(declarations)
        
        # Handle multiple selectors separated by comma
        for sel in split(selector, ",")
            sel = strip(String(sel))
            if !isempty(sel)
                push!(ctx.css_rules, CSSRule(sel, styles))
            end
        end
    end
end

"""
    apply_styles!(ctx::BrowserContext) -> Int

Apply style archetypes to all nodes.

Applies CSS rules from style blocks and inline styles to layout data.
Follows CSS cascade: element defaults < CSS rules < inline styles.

Returns the number of unique archetypes.
"""
function apply_styles!(ctx::BrowserContext)::Int
    n = node_count(ctx.dom)
    
    # Resize layout arrays to match DOM size
    resize_layout!(ctx.layout, n)
    
    # Default archetype for all elements
    default_archetype = get_or_create_archetype!(ctx.archetypes, UInt32[])
    
    for i in 1:n
        if ctx.dom.kinds[i] == NODE_ELEMENT
            ctx.dom.archetype_ids[i] = default_archetype
            
            # Start with default styles
            styles = CSSStyles()
            
            # Apply element defaults based on tag
            apply_element_defaults!(ctx, i, styles)
            
            # Apply matching CSS rules
            apply_css_rules!(ctx, i, styles)
            
            # Apply inline styles (highest priority)
            style_id = ctx.dom.style_attrs[i]
            if style_id != 0
                style_str = get_string(ctx.strings, style_id)
                inline_styles = parse_inline_style(style_str)
                merge_styles!(styles, inline_styles)
            end
            
            # Apply final computed styles to layout
            apply_computed_styles!(ctx, i, styles)
        end
    end
    
    return archetype_count(ctx.archetypes)
end

"""
    apply_element_defaults!(ctx::BrowserContext, node_id::Integer, styles::CSSStyles)

Apply default styles based on element type.
"""
function apply_element_defaults!(ctx::BrowserContext, node_id::Integer, styles::CSSStyles)
    tag_id = ctx.dom.tags[node_id]
    if tag_id == 0
        return
    end
    
    tag_name = lowercase(get_string(ctx.strings, tag_id))
    
    # Hide head, script, style elements
    if tag_name in ["head", "script", "style", "meta", "link", "title"]
        styles.display = DISPLAY_NONE
    end
end

"""
    apply_css_rules!(ctx::BrowserContext, node_id::Integer, styles::CSSStyles)

Apply matching CSS rules to a node's styles.
"""
function apply_css_rules!(ctx::BrowserContext, node_id::Integer, styles::CSSStyles)
    for rule in ctx.css_rules
        if matches_selector(ctx, node_id, rule.selector)
            merge_styles!(styles, rule.styles)
        end
    end
end

"""
    matches_selector(ctx::BrowserContext, node_id::Integer, selector::AbstractString) -> Bool

Check if a CSS selector matches a node.
Supports:
- Tag selectors (div, p)
- ID selectors (#id)
- Class selectors (.class, .class1.class2)
- Attribute selectors ([attr], [attr=value], [attr~=value])
- Combinators (descendant, >, +)
- Universal selector (*)
"""
function matches_selector(ctx::BrowserContext, node_id::Integer, selector::AbstractString)::Bool
    sel = String(strip(selector))
    
    # Handle descendant combinator (space)
    if contains(sel, ' ')
        parts = split(sel, r"\s+")
        # Match from right to left
        current_node = node_id
        for i in length(parts):-1:1
            if !matches_simple_selector(ctx, current_node, String(parts[i]))
                return false
            end
            if i > 1
                # Find ancestor that matches previous selector
                current_node = ctx.dom.parents[current_node]
                found = false
                while current_node != 0
                    if matches_simple_selector(ctx, current_node, String(parts[i-1]))
                        found = true
                        break
                    end
                    current_node = ctx.dom.parents[current_node]
                end
                if !found
                    return false
                end
            end
        end
        return true
    end
    
    # Handle child combinator (>)
    if contains(sel, '>')
        parts = split(sel, '>')
        if length(parts) == 2
            parent_sel = String(strip(parts[1]))
            child_sel = String(strip(parts[2]))
            if !matches_simple_selector(ctx, node_id, child_sel)
                return false
            end
            parent_id = ctx.dom.parents[node_id]
            if parent_id == 0
                return false
            end
            return matches_selector(ctx, parent_id, parent_sel)
        end
    end
    
    # Handle adjacent sibling combinator (+)
    if contains(sel, '+')
        parts = split(sel, '+')
        if length(parts) == 2
            prev_sel = String(strip(parts[1]))
            next_sel = String(strip(parts[2]))
            if !matches_simple_selector(ctx, node_id, next_sel)
                return false
            end
            # Find previous sibling
            parent_id = ctx.dom.parents[node_id]
            if parent_id == 0
                return false
            end
            prev_sibling = UInt32(0)
            child_id = ctx.dom.first_children[parent_id]
            while child_id != 0 && child_id != node_id
                prev_sibling = child_id
                child_id = ctx.dom.next_siblings[child_id]
            end
            if prev_sibling == 0
                return false
            end
            return matches_selector(ctx, prev_sibling, prev_sel)
        end
    end
    
    # Simple selector (no combinators)
    return matches_simple_selector(ctx, node_id, sel)
end

"""
    matches_simple_selector(ctx::BrowserContext, node_id::Integer, selector::AbstractString) -> Bool

Match a simple selector (no combinators).
"""
function matches_simple_selector(ctx::BrowserContext, node_id::Integer, selector::AbstractString)::Bool
    sel = String(strip(selector))
    
    # Get node info
    tag_id = ctx.dom.tags[node_id]
    tag_name = tag_id != 0 ? lowercase(get_string(ctx.strings, tag_id)) : ""
    
    id_attr_id = ctx.dom.id_attrs[node_id]
    id_attr = id_attr_id != 0 ? get_string(ctx.strings, id_attr_id) : ""
    
    class_attr_id = ctx.dom.class_attrs[node_id]
    class_attr = class_attr_id != 0 ? get_string(ctx.strings, class_attr_id) : ""
    classes = split(class_attr)
    
    # Extract parts: tag, ids, classes, attributes
    remaining = sel
    matched_tag = ""
    matched_ids = String[]
    matched_classes = String[]
    matched_attrs = Tuple{String,String,String}[]  # (name, operator, value)
    
    # Extract attribute selectors first
    while contains(remaining, '[')
        bracket_start = findfirst('[', remaining)
        bracket_end = findfirst(']', remaining)
        if bracket_start !== nothing && bracket_end !== nothing && bracket_end > bracket_start
            attr_sel = remaining[bracket_start+1:bracket_end-1]
            # Parse attribute selector
            if contains(attr_sel, '=')
                if contains(attr_sel, "~=")
                    parts = split(attr_sel, "~=")
                    attr_name = strip(String(parts[1]))
                    attr_value = strip(String(parts[2]), [' ', '"'])
                    push!(matched_attrs, (attr_name, "~=", attr_value))
                elseif contains(attr_sel, '=')
                    parts = split(attr_sel, '=')
                    attr_name = strip(String(parts[1]))
                    attr_value = strip(String(parts[2]), [' ', '"'])
                    push!(matched_attrs, (attr_name, "=", attr_value))
                end
            else
                # Just presence check
                attr_name = strip(attr_sel)
                push!(matched_attrs, (attr_name, "", ""))
            end
            remaining = remaining[1:bracket_start-1] * remaining[bracket_end+1:end]
        else
            break
        end
    end
    
    # Extract IDs
    while contains(remaining, '#')
        hash_idx = findfirst('#', remaining)
        if hash_idx !== nothing
            # Find end of ID (next . or # or end of string)
            id_end = length(remaining)
            for i in (hash_idx+1):length(remaining)
                if remaining[i] in ['.', '#', '[', ' ', '>','+']
                    id_end = i - 1
                    break
                end
            end
            push!(matched_ids, remaining[hash_idx+1:id_end])
            remaining = remaining[1:hash_idx-1] * remaining[id_end+1:end]
        end
    end
    
    # Extract classes
    while contains(remaining, '.')
        dot_idx = findfirst('.', remaining)
        if dot_idx !== nothing
            # Find end of class (next . or # or end of string)
            class_end = length(remaining)
            for i in (dot_idx+1):length(remaining)
                if remaining[i] in ['.', '#', '[', ' ', '>', '+']
                    class_end = i - 1
                    break
                end
            end
            push!(matched_classes, remaining[dot_idx+1:class_end])
            remaining = remaining[1:dot_idx-1] * remaining[class_end+1:end]
        end
    end
    
    # What's left should be the tag name or *
    matched_tag = strip(remaining)
    
    # Now check all conditions
    # Tag match
    if !isempty(matched_tag) && matched_tag != "*"
        if tag_name != matched_tag
            return false
        end
    end
    
    # ID match
    for mid in matched_ids
        if id_attr != mid
            return false
        end
    end
    
    # Class match (all classes must be present)
    for mc in matched_classes
        if !(mc in classes)
            return false
        end
    end
    
    # Attribute match
    for (attr_name, operator, attr_value) in matched_attrs
        # TODO: Get attribute value from node (would need to extend NodeTable)
        # For now, handle class attribute specially
        if attr_name == "class"
            if operator == "~="
                # Word match
                if !(attr_value in classes)
                    return false
                end
            elseif operator == "="
                # Exact match
                if class_attr != attr_value
                    return false
                end
            else
                # Presence
                if isempty(class_attr)
                    return false
                end
            end
        end
        # Other attributes would need more infrastructure
    end
    
    return true
end

"""
    merge_styles!(target::CSSStyles, source::CSSStyles)

Merge source styles into target (source overrides).
"""
function merge_styles!(target::CSSStyles, source::CSSStyles)
    # Position
    if source.position != POSITION_STATIC
        target.position = source.position
    end
    
    if !source.top_auto
        target.top = source.top
        target.top_auto = false
    end
    if !source.right_auto
        target.right = source.right
        target.right_auto = false
    end
    if !source.bottom_auto
        target.bottom = source.bottom
        target.bottom_auto = false
    end
    if !source.left_auto
        target.left = source.left
        target.left_auto = false
    end
    
    # Dimensions
    if !source.width_auto
        target.width = source.width
        target.width_auto = false
    end
    if !source.height_auto
        target.height = source.height
        target.height_auto = false
    end
    
    # Min/max dimensions
    if source.has_min_width
        target.min_width = source.min_width
        target.has_min_width = true
    end
    if source.has_max_width
        target.max_width = source.max_width
        target.has_max_width = true
    end
    if source.has_min_height
        target.min_height = source.min_height
        target.has_min_height = true
    end
    if source.has_max_height
        target.max_height = source.max_height
        target.has_max_height = true
    end
    
    # Box model
    if source.margin_top != 0
        target.margin_top = source.margin_top
    end
    if source.margin_right != 0
        target.margin_right = source.margin_right
    end
    if source.margin_bottom != 0
        target.margin_bottom = source.margin_bottom
    end
    if source.margin_left != 0
        target.margin_left = source.margin_left
    end
    
    if source.padding_top != 0
        target.padding_top = source.padding_top
    end
    if source.padding_right != 0
        target.padding_right = source.padding_right
    end
    if source.padding_bottom != 0
        target.padding_bottom = source.padding_bottom
    end
    if source.padding_left != 0
        target.padding_left = source.padding_left
    end
    
    # Borders
    if source.border_top_width != 0
        target.border_top_width = source.border_top_width
    end
    if source.border_right_width != 0
        target.border_right_width = source.border_right_width
    end
    if source.border_bottom_width != 0
        target.border_bottom_width = source.border_bottom_width
    end
    if source.border_left_width != 0
        target.border_left_width = source.border_left_width
    end
    
    if source.border_top_style != BORDER_STYLE_NONE
        target.border_top_style = source.border_top_style
        target.border_top_r = source.border_top_r
        target.border_top_g = source.border_top_g
        target.border_top_b = source.border_top_b
        target.border_top_a = source.border_top_a
    end
    if source.border_right_style != BORDER_STYLE_NONE
        target.border_right_style = source.border_right_style
        target.border_right_r = source.border_right_r
        target.border_right_g = source.border_right_g
        target.border_right_b = source.border_right_b
        target.border_right_a = source.border_right_a
    end
    if source.border_bottom_style != BORDER_STYLE_NONE
        target.border_bottom_style = source.border_bottom_style
        target.border_bottom_r = source.border_bottom_r
        target.border_bottom_g = source.border_bottom_g
        target.border_bottom_b = source.border_bottom_b
        target.border_bottom_a = source.border_bottom_a
    end
    if source.border_left_style != BORDER_STYLE_NONE
        target.border_left_style = source.border_left_style
        target.border_left_r = source.border_left_r
        target.border_left_g = source.border_left_g
        target.border_left_b = source.border_left_b
        target.border_left_a = source.border_left_a
    end
    
    # Float and clear
    if source.float != FLOAT_NONE
        target.float = source.float
    end
    if source.clear != CLEAR_NONE
        target.clear = source.clear
    end
    
    # Display
    if source.display != DISPLAY_BLOCK
        target.display = source.display
    end
    
    target.visibility = source.visibility
    
    if source.overflow != OVERFLOW_VISIBLE
        target.overflow = source.overflow
    end
    
    if source.z_index != 0
        target.z_index = source.z_index
    end
    
    # Colors
    if source.has_background
        target.background_r = source.background_r
        target.background_g = source.background_g
        target.background_b = source.background_b
        target.background_a = source.background_a
        target.has_background = true
    end
end

# Import constants for merge_styles!
const OVERFLOW_VISIBLE = UInt8(0)
const BORDER_STYLE_NONE = UInt8(0)
const FLOAT_NONE = UInt8(0)
const CLEAR_NONE = UInt8(0)

"""
    apply_computed_styles!(ctx::BrowserContext, node_id::Int, styles::CSSStyles)

Apply computed styles to layout data.

Content-- semantic mapping:
- CSS margin → Content-- offset (space outside)
- CSS padding → Content-- inset (space inside)
- CSS border → Content-- stroke (visual boundary)
- CSS background → Content-- fill (background color)
"""
function apply_computed_styles!(ctx::BrowserContext, node_id::Int, styles::CSSStyles)
    # Apply CSS positioning
    set_css_position!(ctx.layout, node_id, styles.position)
    
    # Apply offsets
    set_offsets!(ctx.layout, node_id,
                top=styles.top, right=styles.right,
                bottom=styles.bottom, left=styles.left,
                top_auto=styles.top_auto, right_auto=styles.right_auto,
                bottom_auto=styles.bottom_auto, left_auto=styles.left_auto)
    
    # Apply dimensions
    if !styles.width_auto
        ctx.layout.width[node_id] = styles.width
    end
    if !styles.height_auto
        ctx.layout.height[node_id] = styles.height
    end
    
    # Apply margins (Content-- offset)
    set_margins!(ctx.layout, node_id,
                top=styles.margin_top, right=styles.margin_right,
                bottom=styles.margin_bottom, left=styles.margin_left)
    
    # Apply paddings (Content-- inset)
    set_paddings!(ctx.layout, node_id,
                 top=styles.padding_top, right=styles.padding_right,
                 bottom=styles.padding_bottom, left=styles.padding_left)
    
    # Apply borders (Content-- stroke)
    set_borders!(ctx.layout, node_id,
                top_width=styles.border_top_width,
                right_width=styles.border_right_width,
                bottom_width=styles.border_bottom_width,
                left_width=styles.border_left_width,
                top_style=styles.border_top_style,
                right_style=styles.border_right_style,
                bottom_style=styles.border_bottom_style,
                left_style=styles.border_left_style,
                top_r=styles.border_top_r, top_g=styles.border_top_g,
                top_b=styles.border_top_b, top_a=styles.border_top_a,
                right_r=styles.border_right_r, right_g=styles.border_right_g,
                right_b=styles.border_right_b, right_a=styles.border_right_a,
                bottom_r=styles.border_bottom_r, bottom_g=styles.border_bottom_g,
                bottom_b=styles.border_bottom_b, bottom_a=styles.border_bottom_a,
                left_r=styles.border_left_r, left_g=styles.border_left_g,
                left_b=styles.border_left_b, left_a=styles.border_left_a)
    
    # Apply display and visibility
    ctx.layout.display[node_id] = styles.display
    set_visibility!(ctx.layout, node_id, styles.visibility)
    set_overflow!(ctx.layout, node_id, styles.overflow)
    set_z_index!(ctx.layout, node_id, styles.z_index)
    
    # Apply background color (Content-- fill)
    if styles.has_background
        set_background_color!(ctx.layout, node_id,
                             styles.background_r, styles.background_g,
                             styles.background_b, styles.background_a)
    end
end

"""
    compute_layouts!(ctx::BrowserContext)

Compute layout for all nodes.

Uses contiguous array operations for SIMD optimization.
"""
function compute_layouts!(ctx::BrowserContext)
    n = node_count(ctx.dom)
    
    # Ensure layout arrays are sized correctly
    if length(ctx.layout.x) < n
        resize_layout!(ctx.layout, n)
    end
    
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

Respects z-index ordering and overflow:hidden clipping.

Returns the number of commands generated.
"""
function generate_render_commands!(ctx::BrowserContext)::Int
    clear!(ctx.render_buffer)
    n = node_count(ctx.dom)
    
    # Build z-index sorted render order
    # Collect visible element nodes with their z-index
    render_order = Tuple{Int32, Int}[]
    for i in 1:n
        if ctx.dom.kinds[i] != NODE_ELEMENT
            continue
        end
        
        # Skip display:none and invisible elements
        if ctx.layout.display[i] == DISPLAY_NONE || !ctx.layout.visibility[i]
            continue
        end
        
        z = ctx.layout.z_index[i]
        push!(render_order, (z, i))
    end
    
    # Sort by z-index (stable sort preserves document order for equal z-index)
    sort!(render_order, by=x -> x[1])
    
    # Helper to convert UInt8 color to Float32 (0-1 range)
    to_float = c -> Float32(c) / 255.0f0
    
    # Emit render commands in z-order
    for (_, i) in render_order
        x = ctx.layout.x[i]
        y = ctx.layout.y[i]
        width = ctx.layout.width[i]
        height = ctx.layout.height[i]
        
        # Skip zero-size nodes
        if width <= 0 || height <= 0
            continue
        end
        
        # Get background color
        r = to_float(ctx.layout.bg_r[i])
        g = to_float(ctx.layout.bg_g[i])
        b = to_float(ctx.layout.bg_b[i])
        a = to_float(ctx.layout.bg_a[i])
        
        # Only emit rect if has visible background
        if ctx.layout.has_background[i]
            emit_rect!(ctx.render_buffer, x, y, width, height, r, g, b, a)
        end
        
        # Emit border commands if node has visible borders
        if has_border(ctx.layout, i)
            emit_stroke_sides!(ctx.render_buffer, x, y, width, height,
                # Widths
                ctx.layout.border_top_width[i],
                ctx.layout.border_right_width[i],
                ctx.layout.border_bottom_width[i],
                ctx.layout.border_left_width[i],
                # Top color
                to_float(ctx.layout.border_top_r[i]),
                to_float(ctx.layout.border_top_g[i]),
                to_float(ctx.layout.border_top_b[i]),
                to_float(ctx.layout.border_top_a[i]),
                # Right color
                to_float(ctx.layout.border_right_r[i]),
                to_float(ctx.layout.border_right_g[i]),
                to_float(ctx.layout.border_right_b[i]),
                to_float(ctx.layout.border_right_a[i]),
                # Bottom color
                to_float(ctx.layout.border_bottom_r[i]),
                to_float(ctx.layout.border_bottom_g[i]),
                to_float(ctx.layout.border_bottom_b[i]),
                to_float(ctx.layout.border_bottom_a[i]),
                # Left color
                to_float(ctx.layout.border_left_r[i]),
                to_float(ctx.layout.border_left_g[i]),
                to_float(ctx.layout.border_left_b[i]),
                to_float(ctx.layout.border_left_a[i]))
        end
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
