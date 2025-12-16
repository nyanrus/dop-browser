"""
    HTMLLowering

Converts HTML & CSS (source language) to Content-- primitives (target language).

## Design Principle

The rendering engine should understand ONLY Content--, not HTML/CSS.
This module performs the complete lowering with:
1. Pre-calculated layout values
2. Flattened CSS cascade (no runtime style lookup)
3. Source mapping for debugging

## Mathematical Mapping (HTML/CSS → Content--)

| HTML/CSS | Content-- | Mathematical Transformation |
|----------|-----------|----------------------------|
| div, section | Stack(Direction: Down) | Container with vertical flow |
| span, a | Span | Inline text unit |
| p, h1-h6 | Paragraph | Text block with line breaking |
| table | Grid | 2D Cartesian layout |
| position: static | flow_type = FLOW_NORMAL | Standard document flow |
| position: relative | flow_type = FLOW_RELATIVE | offset from flow position |
| position: absolute | flow_type = FLOW_ABSOLUTE | positioned relative to containing block |
| margin | offset | Space outside: Offset(top, right, bottom, left) |
| padding | inset | Space inside: Inset(top, right, bottom, left) |
| width/height | size | Size(width, height) in pixels |
| background-color | fill | Color(r, g, b, a) |
| border | stroke | Stroke(width, style, color) |

## Coordinate System

Content-- uses device pixel coordinates:
- Origin (0, 0): Top-left of viewport
- X-axis: Increases rightward
- Y-axis: Increases downward
- All values: Float32 in device pixels
"""
module HTMLLowering

using ..Primitives: NodeTable as CMNodeTable, NodeType, create_node!, node_count as cm_node_count,
                    NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT, NODE_PARAGRAPH, NODE_SPAN
using ..Properties: PropertyTable, Direction, Pack, Align, Color, Inset, Offset, Gap,
                    DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT,
                    PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY,
                    ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH,
                    resize_properties!, parse_color, color_to_rgba
using ..SourceMap: SourceMapTable, SourceLocation, SourceType, add_mapping!,
                   SOURCE_HTML_ELEMENT, SOURCE_HTML_TEXT, SOURCE_CSS_INLINE, SOURCE_CSS_RULE,
                   resize_sourcemap!, add_css_contribution!
using ...HTMLParser.StringInterner: StringPool, intern!, get_string
using ...DOMCSSOM.NodeTable: DOMTable, NodeKind, NODE_ELEMENT, NODE_TEXT, node_count as dom_node_count
using ...CSSParserModule.CSSCore: CSSStyles, parse_inline_style, parse_color as css_parse_color, parse_length,
                    POSITION_STATIC, POSITION_RELATIVE, POSITION_ABSOLUTE, POSITION_FIXED,
                    OVERFLOW_HIDDEN, DISPLAY_NONE, DISPLAY_BLOCK, DISPLAY_INLINE

export HTMLLoweringContext, lower_html_to_content!, LoweredNode

"""
    LoweredNode

A lowered node combining Content-- type with pre-computed styles.

## Mathematical Model

All layout values are pre-calculated in device pixels (Float32).
The rendering engine only needs to read these values, no CSS computation.

### Box Model

    +--------------------------------------------------+
    |                    offset_top                    |
    |   +------------------------------------------+   |
    |   |              stroke_top                  |   |
    | o |   +----------------------------------+   | o |
    | f | s |           inset_top              | s | f |
    | f | t |   +------------------------+     | t | f |
    | s | r |   |                        |     | r | s |
    | e | o | i |      CONTENT BOX       | i | o | e |
    | t | k | n |      (children)        | n | k | t |
    |   | e | s |                        | s | e |   |
    | l |   | e |                        | e |   | r |
    | e | l | t |                        | t | r | i |
    | f | e |   +------------------------+   | i | g |
    | t | f |           inset_bottom         | g | h |
    |   | t +----------------------------------+ h | t |
    |   |              stroke_bottom           | t |   |
    |   +------------------------------------------+   |
    |                    offset_bottom                 |
    +--------------------------------------------------+

Where:
- offset = margin (space outside the node)
- stroke = border (visual boundary)
- inset = padding (space inside the node)
- content box = where children are placed
"""
mutable struct LoweredNode
    # Content-- node type
    cm_type::NodeType
    
    # Source tracking (for debugging)
    dom_id::UInt32              # Original DOM node ID
    parent_id::UInt32           # Parent Content-- node ID
    
    # Box model (pre-computed in pixels)
    x::Float32
    y::Float32
    width::Float32
    height::Float32
    
    # Inset (padding) - space inside the node
    inset_top::Float32
    inset_right::Float32
    inset_bottom::Float32
    inset_left::Float32
    
    # Offset (margin) - space outside the node
    offset_top::Float32
    offset_right::Float32
    offset_bottom::Float32
    offset_left::Float32
    
    # Fill color (background)
    fill_r::UInt8
    fill_g::UInt8
    fill_b::UInt8
    fill_a::UInt8
    has_fill::Bool
    
    # Stroke (border) - width per side
    stroke_top_width::Float32
    stroke_right_width::Float32
    stroke_bottom_width::Float32
    stroke_left_width::Float32
    
    # Stroke color per side
    stroke_top_r::UInt8
    stroke_top_g::UInt8
    stroke_top_b::UInt8
    stroke_top_a::UInt8
    stroke_right_r::UInt8
    stroke_right_g::UInt8
    stroke_right_b::UInt8
    stroke_right_a::UInt8
    stroke_bottom_r::UInt8
    stroke_bottom_g::UInt8
    stroke_bottom_b::UInt8
    stroke_bottom_a::UInt8
    stroke_left_r::UInt8
    stroke_left_g::UInt8
    stroke_left_b::UInt8
    stroke_left_a::UInt8
    
    # Stroke style per side (0=none, 1=solid, 2=dotted, 3=dashed)
    stroke_top_style::UInt8
    stroke_right_style::UInt8
    stroke_bottom_style::UInt8
    stroke_left_style::UInt8
    
    # Layout (flex/stack properties)
    direction::Direction
    pack::Pack
    align::Align
    
    # Positioning
    position_type::UInt8        # POSITION_*
    css_top::Float32
    css_right::Float32
    css_bottom::Float32
    css_left::Float32
    css_top_auto::Bool
    css_right_auto::Bool
    css_bottom_auto::Bool
    css_left_auto::Bool
    
    # Display/visibility
    display::UInt8
    visible::Bool
    overflow_hidden::Bool
    z_index::Int32
    
    # Text content
    text_content::String
end

"""
    HTMLLoweringContext

Context for lowering HTML/CSS (source) to Content-- (target).

The context maintains:
1. Input: DOM tree and string pool from HTML parsing
2. Output: Content-- node tree with pre-computed values
3. SourceMap: Bidirectional mapping for debugging

After lowering, the rendering engine can process the Content-- output
without any knowledge of HTML or CSS.
"""
mutable struct HTMLLoweringContext
    # Input (source language)
    dom::DOMTable
    strings::StringPool
    
    # CSS from style blocks
    style_rules::Dict{String, CSSStyles}  # selector -> styles
    
    # Output (target language - Content--)
    nodes::Vector{LoweredNode}
    cm_nodes::CMNodeTable
    cm_props::PropertyTable
    
    # Source mapping (for debugging/devtools)
    sourcemap::SourceMapTable
    
    # Mapping
    dom_to_cm::Dict{UInt32, UInt32}  # DOM ID -> Content-- ID
    
    # Viewport (for percentage calculations)
    viewport_width::Float32
    viewport_height::Float32
    
    function HTMLLoweringContext(dom::DOMTable, strings::StringPool;
                                  viewport_width::Float32=800.0f0,
                                  viewport_height::Float32=600.0f0)
        new(
            dom, strings,
            Dict{String, CSSStyles}(),
            LoweredNode[],
            CMNodeTable(),
            PropertyTable(),
            SourceMapTable(),
            Dict{UInt32, UInt32}(),
            viewport_width, viewport_height
        )
    end
end

"""
    lower_html_to_content!(ctx::HTMLLoweringContext) -> CMNodeTable

Lower the DOM tree (source: HTML/CSS) to Content-- primitives (target).

After this function, the Content-- node tree contains all pre-computed
values. The rendering engine can process it without any HTML/CSS knowledge.

Returns the Content-- node table.
"""
function lower_html_to_content!(ctx::HTMLLoweringContext)::CMNodeTable
    n = dom_node_count(ctx.dom)
    if n == 0
        return ctx.cm_nodes
    end
    
    # Parse style blocks first
    parse_style_blocks!(ctx)
    
    # Lower each DOM node
    for i in 1:n
        lower_node!(ctx, UInt32(i))
    end
    
    # Resize properties and sourcemap to match node count
    cm_count = cm_node_count(ctx.cm_nodes)
    resize_properties!(ctx.cm_props, cm_count)
    resize_sourcemap!(ctx.sourcemap, cm_count)
    
    # Apply computed properties
    apply_properties!(ctx)
    
    return ctx.cm_nodes
end

"""
    parse_style_blocks!(ctx::HTMLLoweringContext)

Parse <style> blocks from the DOM and extract CSS rules.
"""
function parse_style_blocks!(ctx::HTMLLoweringContext)
    n = dom_node_count(ctx.dom)
    style_tag_id = get_style_tag_id(ctx)
    
    for i in 1:n
        if ctx.dom.kinds[i] != NODE_ELEMENT
            continue
        end
        
        tag_id = ctx.dom.tags[i]
        if tag_id == 0
            continue
        end
        
        tag_name = get_string(ctx.strings, tag_id)
        if lowercase(tag_name) == "style"
            # Get text content (first child if it's a text node)
            child_id = ctx.dom.first_children[i]
            if child_id != 0 && child_id <= n && ctx.dom.kinds[child_id] == NODE_TEXT
                text_id = ctx.dom.text_content[child_id]
                if text_id != 0
                    css_text = get_string(ctx.strings, text_id)
                    parse_css_text!(ctx, css_text)
                end
            end
        end
    end
end

"""
    get_style_tag_id(ctx::HTMLLoweringContext) -> UInt32

Get the interned ID for "style" tag.
"""
function get_style_tag_id(ctx::HTMLLoweringContext)::UInt32
    return intern!(ctx.strings, "style")
end

"""
    parse_css_text!(ctx::HTMLLoweringContext, css_text::String)

Parse CSS text and add rules to context.
"""
function parse_css_text!(ctx::HTMLLoweringContext, css_text::String)
    # Remove comments
    css_text = replace(css_text, r"/\*.*?\*/"s => "")
    
    # Parse rule blocks
    rule_pattern = r"([^{}]+)\{([^{}]*)\}"s
    for m in eachmatch(rule_pattern, css_text)
        selector = strip(m.captures[1])
        declarations = m.captures[2]
        
        # Parse declarations as inline style
        styles = parse_inline_style(declarations)
        
        # Handle multiple selectors separated by comma
        for sel in split(selector, ",")
            sel = strip(sel)
            if !isempty(sel)
                ctx.style_rules[sel] = styles
            end
        end
    end
end

"""
    lower_node!(ctx::HTMLLoweringContext, dom_id::UInt32)

Lower a single DOM node to Content--.
"""
function lower_node!(ctx::HTMLLoweringContext, dom_id::UInt32)
    if dom_id == 0 || dom_id > dom_node_count(ctx.dom)
        return
    end
    
    kind = ctx.dom.kinds[dom_id]
    
    if kind == NODE_ELEMENT
        lower_element!(ctx, dom_id)
    elseif kind == NODE_TEXT
        lower_text!(ctx, dom_id)
    end
    # Skip comments, doctype, etc.
end

"""
    lower_element!(ctx::HTMLLoweringContext, dom_id::UInt32)

Lower an element node to Content--.
Creates source mapping for debugging.
"""
function lower_element!(ctx::HTMLLoweringContext, dom_id::UInt32)
    tag_id = ctx.dom.tags[dom_id]
    tag_name = ""
    if tag_id != 0
        tag_name = lowercase(get_string(ctx.strings, tag_id))
    end
    
    # Compute styles (CSS cascade: element defaults < style rules < inline)
    styles = compute_element_styles(ctx, dom_id, tag_name)
    
    # Skip display:none elements
    if styles.display == DISPLAY_NONE
        return
    end
    
    # Determine Content-- node type based on element
    cm_type = element_to_cm_type(tag_name, styles)
    
    # Get parent Content-- node
    parent_dom_id = ctx.dom.parents[dom_id]
    parent_cm_id = get(ctx.dom_to_cm, parent_dom_id, UInt32(0))
    
    # Create Content-- node
    cm_id = create_node!(ctx.cm_nodes, cm_type, parent=parent_cm_id)
    ctx.dom_to_cm[dom_id] = cm_id
    
    # Create lowered node record with all pre-computed values
    node = create_lowered_node(cm_type, dom_id, parent_cm_id, styles, tag_name)
    push!(ctx.nodes, node)
    
    # Add source mapping
    # TODO: Track actual source line/column during HTML parsing for proper source mapping.
    # Currently using DOM ID as a placeholder index. In a full implementation,
    # the HTML parser would record (line, column) for each element start tag.
    source_loc = SourceLocation(
        source_type = SOURCE_HTML_ELEMENT,
        line = UInt32(dom_id),  # Placeholder: should be actual source line
        column = UInt32(1),     # Placeholder: should be actual source column
        file_id = UInt32(0)
    )
    add_mapping!(ctx.sourcemap, cm_id, source_loc)
end

"""
    lower_text!(ctx::HTMLLoweringContext, dom_id::UInt32)

Lower a text node to Content--.
Creates source mapping for debugging.
"""
function lower_text!(ctx::HTMLLoweringContext, dom_id::UInt32)
    text_id = ctx.dom.text_content[dom_id]
    if text_id == 0
        return
    end
    
    text = get_string(ctx.strings, text_id)
    text = strip(text)
    if isempty(text)
        return
    end
    
    # Get parent
    parent_dom_id = ctx.dom.parents[dom_id]
    parent_cm_id = get(ctx.dom_to_cm, parent_dom_id, UInt32(0))
    
    # Create Span node for text
    cm_id = create_node!(ctx.cm_nodes, NODE_SPAN, parent=parent_cm_id)
    ctx.dom_to_cm[dom_id] = cm_id
    
    # Create lowered node with text content
    styles = CSSStyles()
    node = create_lowered_node(NODE_SPAN, dom_id, parent_cm_id, styles, "")
    node.text_content = text
    push!(ctx.nodes, node)
    
    # Add source mapping
    source_loc = SourceLocation(
        source_type = SOURCE_HTML_TEXT,
        line = UInt32(dom_id),
        column = UInt32(1),
        file_id = UInt32(0)
    )
    add_mapping!(ctx.sourcemap, cm_id, source_loc)
end

"""
    compute_element_styles(ctx::HTMLLoweringContext, dom_id::UInt32, 
                           tag_name::String) -> CSSStyles

Compute final styles by cascading defaults, CSS rules, and inline styles.
"""
function compute_element_styles(ctx::HTMLLoweringContext, dom_id::UInt32,
                                 tag_name::String)::CSSStyles
    styles = CSSStyles()
    
    # Apply element defaults
    apply_element_defaults!(styles, tag_name)
    
    # Apply matching CSS rules
    apply_matching_rules!(ctx, styles, dom_id, tag_name)
    
    # Apply inline styles (highest priority)
    style_id = ctx.dom.style_attrs[dom_id]
    if style_id != 0
        inline_css = get_string(ctx.strings, style_id)
        inline_styles = parse_inline_style(inline_css)
        merge_styles!(styles, inline_styles)
    end
    
    return styles
end

"""
    apply_element_defaults!(styles::CSSStyles, tag_name::String)

Apply default styles based on element type.
"""
function apply_element_defaults!(styles::CSSStyles, tag_name::String)
    # Block elements
    if tag_name in ["div", "p", "h1", "h2", "h3", "h4", "h5", "h6", 
                    "section", "article", "header", "footer", "main",
                    "ul", "ol", "li", "table", "tr", "td", "th"]
        styles.display = DISPLAY_BLOCK
    end
    
    # Inline elements
    if tag_name in ["span", "a", "em", "strong", "b", "i", "u", "code"]
        styles.display = DISPLAY_INLINE
    end
    
    # Special elements
    if tag_name in ["head", "script", "style", "meta", "link", "title"]
        styles.display = DISPLAY_NONE
    end
end

"""
    apply_matching_rules!(ctx::HTMLLoweringContext, styles::CSSStyles,
                           dom_id::UInt32, tag_name::String)

Apply CSS rules that match this element.
"""
function apply_matching_rules!(ctx::HTMLLoweringContext, styles::CSSStyles,
                                dom_id::UInt32, tag_name::String)
    # Get element's id and class
    id_attr = ""
    class_attr = ""
    
    id_attr_id = ctx.dom.id_attrs[dom_id]
    if id_attr_id != 0
        id_attr = get_string(ctx.strings, id_attr_id)
    end
    
    class_attr_id = ctx.dom.class_attrs[dom_id]
    if class_attr_id != 0
        class_attr = get_string(ctx.strings, class_attr_id)
    end
    
    classes = split(class_attr)
    
    # Check each rule for match
    for (selector, rule_styles) in ctx.style_rules
        if matches_selector(selector, tag_name, id_attr, classes)
            merge_styles!(styles, rule_styles)
        end
    end
end

"""
    matches_selector(selector::String, tag_name::String, 
                     id_attr::String, classes::Vector{SubString{String}}) -> Bool

Check if a CSS selector matches an element.
Supports: tag, #id, .class, tag.class, tag#id
"""
function matches_selector(selector::AbstractString, tag_name::String,
                          id_attr::String, classes)::Bool
    sel = strip(selector)
    
    # ID selector: #id
    if startswith(sel, "#")
        sel_id = sel[2:end]
        return id_attr == sel_id
    end
    
    # Class selector: .class
    if startswith(sel, ".")
        sel_class = sel[2:end]
        return sel_class in classes
    end
    
    # Combined selector: tag.class or tag#id
    if contains(sel, ".")
        parts = split(sel, ".", limit=2)
        sel_tag = parts[1]
        sel_class = parts[2]
        return (isempty(sel_tag) || tag_name == sel_tag) && sel_class in classes
    end
    
    if contains(sel, "#")
        parts = split(sel, "#", limit=2)
        sel_tag = parts[1]
        sel_id = parts[2]
        return (isempty(sel_tag) || tag_name == sel_tag) && id_attr == sel_id
    end
    
    # Tag selector
    return tag_name == sel
end

"""
    merge_styles!(target::CSSStyles, source::CSSStyles)

Merge source styles into target (source overrides).
"""
function merge_styles!(target::CSSStyles, source::CSSStyles)
    # Position
    if source.position != POSITION_STATIC || target.position == POSITION_STATIC
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
    
    # Display
    if source.display != DISPLAY_BLOCK
        target.display = source.display
    end
    
    target.visibility = source.visibility
    target.overflow = source.overflow
    target.z_index = source.z_index
    
    # Colors
    if source.has_background
        target.background_r = source.background_r
        target.background_g = source.background_g
        target.background_b = source.background_b
        target.background_a = source.background_a
        target.has_background = true
    end
end

"""
    element_to_cm_type(tag_name::String, styles::CSSStyles) -> NodeType

Map HTML element to Content-- node type.
"""
function element_to_cm_type(tag_name::String, styles::CSSStyles)::NodeType
    # Scroll elements with overflow:hidden
    if styles.overflow == OVERFLOW_HIDDEN
        return NODE_SCROLL
    end
    
    # Text elements
    if tag_name in ["p", "h1", "h2", "h3", "h4", "h5", "h6"]
        return NODE_PARAGRAPH
    end
    
    if tag_name in ["span", "a", "em", "strong", "b", "i", "u"]
        return NODE_SPAN
    end
    
    # Grid for tables
    if tag_name in ["table"]
        return NODE_GRID
    end
    
    # Simple colored rectangles when only used for color/positioning
    if styles.has_background && tag_name in ["hr", "br"]
        return NODE_RECT
    end
    
    # Default: Stack (flex/block container)
    return NODE_STACK
end

"""
    create_lowered_node(cm_type::NodeType, dom_id::UInt32, parent_cm_id::UInt32,
                        styles::CSSStyles, tag_name::String) -> LoweredNode

Create a LoweredNode from computed styles.

This function performs the final CSS-to-Content-- lowering:
- margin → offset (outside spacing)
- padding → inset (inside spacing)
- border → stroke (visual boundary)
- background-color → fill (background color)
- position/display → layout type

All values are pre-computed in device pixels.
"""
function create_lowered_node(cm_type::NodeType, dom_id::UInt32, parent_cm_id::UInt32,
                             styles::CSSStyles, tag_name::String)::LoweredNode
    return LoweredNode(
        cm_type, dom_id, parent_cm_id,
        0.0f0, 0.0f0,                              # x, y (computed later)
        styles.width, styles.height,               # width, height
        # Inset (padding)
        styles.padding_top, styles.padding_right,
        styles.padding_bottom, styles.padding_left,
        # Offset (margin)
        styles.margin_top, styles.margin_right,
        styles.margin_bottom, styles.margin_left,
        # Fill color
        styles.background_r, styles.background_g,
        styles.background_b, styles.background_a,
        styles.has_background,
        # Stroke widths (border)
        styles.border_top_width, styles.border_right_width,
        styles.border_bottom_width, styles.border_left_width,
        # Stroke top color
        styles.border_top_r, styles.border_top_g,
        styles.border_top_b, styles.border_top_a,
        # Stroke right color
        styles.border_right_r, styles.border_right_g,
        styles.border_right_b, styles.border_right_a,
        # Stroke bottom color
        styles.border_bottom_r, styles.border_bottom_g,
        styles.border_bottom_b, styles.border_bottom_a,
        # Stroke left color
        styles.border_left_r, styles.border_left_g,
        styles.border_left_b, styles.border_left_a,
        # Stroke styles
        styles.border_top_style, styles.border_right_style,
        styles.border_bottom_style, styles.border_left_style,
        # Layout
        DIRECTION_DOWN, PACK_START, ALIGN_STRETCH,
        # Position
        styles.position,
        styles.top, styles.right,
        styles.bottom, styles.left,
        styles.top_auto, styles.right_auto,
        styles.bottom_auto, styles.left_auto,
        # Display
        styles.display, styles.visibility,
        styles.overflow == OVERFLOW_HIDDEN,
        styles.z_index,
        # Text
        ""
    )
end

"""
    apply_properties!(ctx::HTMLLoweringContext)

Apply lowered node properties to Content-- property table.
"""
function apply_properties!(ctx::HTMLLoweringContext)
    n = length(ctx.nodes)
    if n == 0
        return
    end
    
    resize_properties!(ctx.cm_props, n)
    
    for (i, node) in enumerate(ctx.nodes)
        # Layout
        ctx.cm_props.direction[i] = node.direction
        ctx.cm_props.pack[i] = node.pack
        ctx.cm_props.align[i] = node.align
        
        # Dimensions
        ctx.cm_props.width[i] = node.width
        ctx.cm_props.height[i] = node.height
        
        # Box model
        ctx.cm_props.inset_top[i] = node.inset_top
        ctx.cm_props.inset_right[i] = node.inset_right
        ctx.cm_props.inset_bottom[i] = node.inset_bottom
        ctx.cm_props.inset_left[i] = node.inset_left
        ctx.cm_props.offset_top[i] = node.offset_top
        ctx.cm_props.offset_right[i] = node.offset_right
        ctx.cm_props.offset_bottom[i] = node.offset_bottom
        ctx.cm_props.offset_left[i] = node.offset_left
        
        # Colors
        ctx.cm_props.fill_r[i] = node.fill_r
        ctx.cm_props.fill_g[i] = node.fill_g
        ctx.cm_props.fill_b[i] = node.fill_b
        ctx.cm_props.fill_a[i] = node.fill_a
    end
end

end # module HTMLLowering
