"""
    TextParser

Content-- text format parser for human-readable UI definitions.

## Syntax

The Content-- text format uses a simple, intuitive syntax:

```
NodeType(Prop1: Value1, Prop2: Value2) {
    ChildNode(...) { ... }
    ...
}
```

## Examples

```
Stack(Direction: Down, Fill: #FFFFFF) {
    Rect(Size: (100, 50), Fill: #FF0000);
    Paragraph {
        Span(Text: "Hello World");
    }
}
```

## Supported Node Types
- Stack: Flex container (Direction, Pack, Align, Gap)
- Grid: 2D Cartesian layout (Cols, Rows)
- Scroll: Viewport with overflow
- Rect: Simple colored rectangle
- Paragraph: Text block
- Span: Inline text
- Link: Interactive link

## Properties
- Direction: Down, Up, Right, Left
- Pack: Start, End, Center, Between, Around, Evenly
- Align: Start, End, Center, Stretch, Baseline
- Size: (width, height) or single value
- Inset: (top, right, bottom, left) or single value
- Offset: (top, right, bottom, left) or single value
- Fill: #RRGGBB or named color
- Gap: (row, column) or single value
- Text: "string content"
"""
module TextParser

using ..Primitives: NodeTable, NodeType, create_node!, node_count,
                    NODE_ROOT, NODE_STACK, NODE_GRID, NODE_SCROLL, NODE_RECT,
                    NODE_PARAGRAPH, NODE_SPAN, NODE_LINK
using ..Properties: PropertyTable, Direction, Pack, Align, Color, Inset, Offset, Gap,
                    DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT,
                    PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY,
                    ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE,
                    parse_color, resize_properties!, set_property!

export parse_content_text, ParsedDocument, ParseError
export TextParseContext

"""
    ParseError

Error during Content-- text parsing.
"""
struct ParseError
    message::String
    line::Int
    column::Int
    
    ParseError(msg::String; line::Int=0, column::Int=0) = new(msg, line, column)
end

"""
    ParsedDocument

Result of parsing Content-- text.
"""
struct ParsedDocument
    nodes::NodeTable
    properties::PropertyTable
    strings::Vector{String}  # Interned strings (for text content)
    errors::Vector{ParseError}
    success::Bool
end

"""
    TextParseContext

Context for parsing Content-- text.
"""
mutable struct TextParseContext
    source::String
    pos::Int
    line::Int
    column::Int
    nodes::NodeTable
    properties::PropertyTable
    strings::Vector{String}
    errors::Vector{ParseError}
    
    function TextParseContext(source::String)
        new(source, 1, 1, 1, NodeTable(), PropertyTable(), String[], ParseError[])
    end
end

# ============================================================================
# Tokenization
# ============================================================================

"""
Check if current character matches expected.
"""
function peek(ctx::TextParseContext)::Char
    if ctx.pos > length(ctx.source)
        return '\0'
    end
    return ctx.source[ctx.pos]
end

"""
Advance to next character.
"""
function advance!(ctx::TextParseContext)::Char
    if ctx.pos > length(ctx.source)
        return '\0'
    end
    c = ctx.source[ctx.pos]
    ctx.pos += 1
    if c == '\n'
        ctx.line += 1
        ctx.column = 1
    else
        ctx.column += 1
    end
    return c
end

"""
Skip whitespace and comments.
"""
function skip_whitespace!(ctx::TextParseContext)
    while ctx.pos <= length(ctx.source)
        c = peek(ctx)
        if c == ' ' || c == '\t' || c == '\n' || c == '\r'
            advance!(ctx)
        elseif c == '/' && ctx.pos + 1 <= length(ctx.source) && ctx.source[ctx.pos + 1] == '/'
            # Line comment
            while peek(ctx) != '\n' && peek(ctx) != '\0'
                advance!(ctx)
            end
        elseif c == '/' && ctx.pos + 1 <= length(ctx.source) && ctx.source[ctx.pos + 1] == '*'
            # Block comment
            advance!(ctx)  # /
            advance!(ctx)  # *
            while !(peek(ctx) == '*' && ctx.pos + 1 <= length(ctx.source) && ctx.source[ctx.pos + 1] == '/')
                if peek(ctx) == '\0'
                    push!(ctx.errors, ParseError("Unterminated block comment", line=ctx.line, column=ctx.column))
                    return
                end
                advance!(ctx)
            end
            advance!(ctx)  # *
            advance!(ctx)  # /
        else
            break
        end
    end
end

"""
Read an identifier (alphanumeric + underscore).
"""
function read_identifier!(ctx::TextParseContext)::String
    start = ctx.pos
    while ctx.pos <= length(ctx.source)
        c = peek(ctx)
        if isletter(c) || isdigit(c) || c == '_'
            advance!(ctx)
        else
            break
        end
    end
    return ctx.source[start:ctx.pos-1]
end

"""
Read a number (integer or float).
"""
function read_number!(ctx::TextParseContext)::String
    start = ctx.pos
    has_dot = false
    has_sign = false
    
    # Handle optional sign
    if peek(ctx) == '-' || peek(ctx) == '+'
        advance!(ctx)
        has_sign = true
    end
    
    while ctx.pos <= length(ctx.source)
        c = peek(ctx)
        if isdigit(c)
            advance!(ctx)
        elseif c == '.' && !has_dot
            has_dot = true
            advance!(ctx)
        else
            break
        end
    end
    return ctx.source[start:ctx.pos-1]
end

"""
Read a string literal.
"""
function read_string!(ctx::TextParseContext)::String
    quote_char = advance!(ctx)  # Opening quote
    start = ctx.pos
    while peek(ctx) != quote_char && peek(ctx) != '\0'
        if peek(ctx) == '\\'
            advance!(ctx)  # Skip escape char
            if peek(ctx) != '\0'
                advance!(ctx)  # Skip escaped char
            end
        else
            advance!(ctx)
        end
    end
    str = ctx.source[start:ctx.pos-1]
    if peek(ctx) == quote_char
        advance!(ctx)  # Closing quote
    else
        push!(ctx.errors, ParseError("Unterminated string", line=ctx.line, column=ctx.column))
    end
    # Handle escape sequences
    str = replace(str, "\\n" => "\n")
    str = replace(str, "\\t" => "\t")
    str = replace(str, "\\\"" => "\"")
    str = replace(str, "\\'" => "'")
    str = replace(str, "\\\\" => "\\")
    return str
end

"""
Read a hex color.
"""
function read_hex_color!(ctx::TextParseContext)::String
    advance!(ctx)  # #
    start = ctx.pos
    while ctx.pos <= length(ctx.source)
        c = peek(ctx)
        if isdigit(c) || c in "abcdefABCDEF"
            advance!(ctx)
        else
            break
        end
    end
    return "#" * ctx.source[start:ctx.pos-1]
end

"""
Check if next token matches expected and consume it.
"""
function expect!(ctx::TextParseContext, expected::Char)::Bool
    skip_whitespace!(ctx)
    if peek(ctx) == expected
        advance!(ctx)
        return true
    end
    push!(ctx.errors, ParseError("Expected '$expected', got '$(peek(ctx))'", 
                                  line=ctx.line, column=ctx.column))
    return false
end

# ============================================================================
# Parsing
# ============================================================================

"""
    parse_content_text(source::String) -> ParsedDocument

Parse Content-- text format into a document structure.
"""
function parse_content_text(source::String)::ParsedDocument
    ctx = TextParseContext(source)
    
    # Create root node
    root_id = create_node!(ctx.nodes, NODE_ROOT)
    
    # Parse top-level nodes
    skip_whitespace!(ctx)
    while peek(ctx) != '\0' && isempty(ctx.errors)
        child_id = parse_node!(ctx, root_id)
        if child_id == UInt32(0)
            break
        end
        skip_whitespace!(ctx)
    end
    
    # Resize properties to match node count
    n = node_count(ctx.nodes)
    resize_properties!(ctx.properties, n)
    
    return ParsedDocument(
        ctx.nodes,
        ctx.properties,
        ctx.strings,
        ctx.errors,
        isempty(ctx.errors)
    )
end

"""
Parse a single node.
"""
function parse_node!(ctx::TextParseContext, parent_id::UInt32)::UInt32
    skip_whitespace!(ctx)
    
    if peek(ctx) == '\0'
        return UInt32(0)
    end
    
    # Read node type
    type_name = read_identifier!(ctx)
    if isempty(type_name)
        return UInt32(0)
    end
    
    node_type = parse_node_type(type_name)
    if node_type === nothing
        push!(ctx.errors, ParseError("Unknown node type: $type_name", 
                                      line=ctx.line, column=ctx.column))
        return UInt32(0)
    end
    
    # Create node
    node_id = create_node!(ctx.nodes, node_type, parent=parent_id)
    
    # Resize properties to include this new node
    resize_properties!(ctx.properties, node_count(ctx.nodes))
    
    skip_whitespace!(ctx)
    
    # Parse properties (optional)
    if peek(ctx) == '('
        parse_properties!(ctx, node_id)
    end
    
    skip_whitespace!(ctx)
    
    # Parse children (optional)
    if peek(ctx) == '{'
        parse_children!(ctx, node_id)
    end
    
    skip_whitespace!(ctx)
    
    # Optional semicolon
    if peek(ctx) == ';'
        advance!(ctx)
    end
    
    return node_id
end

"""
Map type name to NodeType.
"""
function parse_node_type(name::String)::Union{NodeType, Nothing}
    name_lower = lowercase(name)
    if name_lower == "stack"
        return NODE_STACK
    elseif name_lower == "grid"
        return NODE_GRID
    elseif name_lower == "scroll"
        return NODE_SCROLL
    elseif name_lower == "rect"
        return NODE_RECT
    elseif name_lower == "paragraph"
        return NODE_PARAGRAPH
    elseif name_lower == "span"
        return NODE_SPAN
    elseif name_lower == "link"
        return NODE_LINK
    elseif name_lower == "root"
        return NODE_ROOT
    end
    return nothing
end

"""
Parse property list.
"""
function parse_properties!(ctx::TextParseContext, node_id::UInt32)
    expect!(ctx, '(')
    
    skip_whitespace!(ctx)
    while peek(ctx) != ')' && peek(ctx) != '\0' && isempty(ctx.errors)
        # Read property name
        prop_name = read_identifier!(ctx)
        if isempty(prop_name)
            break
        end
        
        skip_whitespace!(ctx)
        if !expect!(ctx, ':')
            break
        end
        
        skip_whitespace!(ctx)
        
        # Read property value
        value = parse_value!(ctx)
        
        # Apply property
        apply_property!(ctx, node_id, prop_name, value)
        
        skip_whitespace!(ctx)
        
        # Optional comma
        if peek(ctx) == ','
            advance!(ctx)
            skip_whitespace!(ctx)
        end
    end
    
    expect!(ctx, ')')
end

"""
Parse a property value.
"""
function parse_value!(ctx::TextParseContext)::Any
    c = peek(ctx)
    
    if c == '"' || c == '\''
        # String
        return read_string!(ctx)
    elseif c == '#'
        # Color
        return read_hex_color!(ctx)
    elseif c == '('
        # Tuple
        return parse_tuple!(ctx)
    elseif isdigit(c) || c == '-' || c == '+'
        # Number
        num_str = read_number!(ctx)
        if contains(num_str, ".")
            return parse(Float32, num_str)
        else
            return parse(Int, num_str)
        end
    else
        # Identifier (enum value or named color)
        return read_identifier!(ctx)
    end
end

"""
Parse a tuple value (e.g., (100, 50)).
"""
function parse_tuple!(ctx::TextParseContext)::Vector{Any}
    expect!(ctx, '(')
    values = Any[]
    
    skip_whitespace!(ctx)
    while peek(ctx) != ')' && peek(ctx) != '\0'
        value = parse_value!(ctx)
        push!(values, value)
        
        skip_whitespace!(ctx)
        if peek(ctx) == ','
            advance!(ctx)
            skip_whitespace!(ctx)
        end
    end
    
    expect!(ctx, ')')
    return values
end

"""
Parse children block.
"""
function parse_children!(ctx::TextParseContext, parent_id::UInt32)
    expect!(ctx, '{')
    
    skip_whitespace!(ctx)
    while peek(ctx) != '}' && peek(ctx) != '\0' && isempty(ctx.errors)
        child_id = parse_node!(ctx, parent_id)
        if child_id == UInt32(0)
            # Skip to next valid position
            while peek(ctx) != '}' && peek(ctx) != '\0' && !isletter(peek(ctx))
                advance!(ctx)
            end
            if !isletter(peek(ctx))
                break
            end
        end
        skip_whitespace!(ctx)
    end
    
    expect!(ctx, '}')
end

"""
Apply a parsed property to a node.
"""
function apply_property!(ctx::TextParseContext, node_id::UInt32, 
                         prop_name::String, value::Any)
    prop_lower = lowercase(prop_name)
    
    # Direction
    if prop_lower == "direction"
        dir = parse_direction(value)
        if dir !== nothing
            set_property!(ctx.properties, Int(node_id), :direction, dir)
        end
    
    # Pack (justify-content equivalent)
    elseif prop_lower == "pack"
        pack = parse_pack(value)
        if pack !== nothing
            set_property!(ctx.properties, Int(node_id), :pack, pack)
        end
    
    # Align (align-items equivalent)
    elseif prop_lower == "align"
        align = parse_align(value)
        if align !== nothing
            set_property!(ctx.properties, Int(node_id), :align, align)
        end
    
    # Size (width, height)
    elseif prop_lower == "size"
        if value isa Vector
            if length(value) >= 2
                set_property!(ctx.properties, Int(node_id), :width, Float32(value[1]))
                set_property!(ctx.properties, Int(node_id), :height, Float32(value[2]))
            end
        elseif value isa Number
            set_property!(ctx.properties, Int(node_id), :width, Float32(value))
            set_property!(ctx.properties, Int(node_id), :height, Float32(value))
        end
    
    # Width
    elseif prop_lower == "width"
        if value isa Number
            set_property!(ctx.properties, Int(node_id), :width, Float32(value))
        end
    
    # Height
    elseif prop_lower == "height"
        if value isa Number
            set_property!(ctx.properties, Int(node_id), :height, Float32(value))
        end
    
    # Inset (padding equivalent)
    elseif prop_lower == "inset"
        apply_box_property!(ctx, node_id, :inset, value)
    
    # Offset (margin equivalent)
    elseif prop_lower == "offset"
        apply_box_property!(ctx, node_id, :offset, value)
    
    # Fill (background color)
    elseif prop_lower == "fill"
        color = parse_color_value(value)
        if color !== nothing
            set_property!(ctx.properties, Int(node_id), :fill_r, color.r)
            set_property!(ctx.properties, Int(node_id), :fill_g, color.g)
            set_property!(ctx.properties, Int(node_id), :fill_b, color.b)
            set_property!(ctx.properties, Int(node_id), :fill_a, color.a)
        end
    
    # Gap
    elseif prop_lower == "gap"
        if value isa Vector
            if length(value) >= 2
                set_property!(ctx.properties, Int(node_id), :gap_row, Float32(value[1]))
                set_property!(ctx.properties, Int(node_id), :gap_col, Float32(value[2]))
            end
        elseif value isa Number
            set_property!(ctx.properties, Int(node_id), :gap_row, Float32(value))
            set_property!(ctx.properties, Int(node_id), :gap_col, Float32(value))
        end
    
    # Text content
    elseif prop_lower == "text"
        if value isa String
            push!(ctx.strings, value)
            # Store text ID in node table
            ctx.nodes.text_ids[node_id] = UInt32(length(ctx.strings))
        end
    
    # Grid columns
    elseif prop_lower == "cols"
        if value isa Number
            set_property!(ctx.properties, Int(node_id), :grid_cols, UInt16(value))
        end
    
    # Grid rows
    elseif prop_lower == "rows"
        if value isa Number
            set_property!(ctx.properties, Int(node_id), :grid_rows, UInt16(value))
        end
    
    # Border radius
    elseif prop_lower == "round"
        if value isa Number
            set_property!(ctx.properties, Int(node_id), :round_tl, Float32(value))
            set_property!(ctx.properties, Int(node_id), :round_tr, Float32(value))
            set_property!(ctx.properties, Int(node_id), :round_br, Float32(value))
            set_property!(ctx.properties, Int(node_id), :round_bl, Float32(value))
        end
    end
end

"""
Apply box property (inset/offset with 1, 2, or 4 values).
"""
function apply_box_property!(ctx::TextParseContext, node_id::UInt32, 
                              prop::Symbol, value::Any)
    prefix = prop == :inset ? :inset : :offset
    
    if value isa Vector
        if length(value) == 1
            # All sides same
            v = Float32(value[1])
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_top), v)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_right), v)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_bottom), v)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_left), v)
        elseif length(value) == 2
            # Vertical, Horizontal
            v = Float32(value[1])
            h = Float32(value[2])
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_top), v)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_right), h)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_bottom), v)
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_left), h)
        elseif length(value) >= 4
            # Top, Right, Bottom, Left
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_top), Float32(value[1]))
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_right), Float32(value[2]))
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_bottom), Float32(value[3]))
            set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_left), Float32(value[4]))
        end
    elseif value isa Number
        v = Float32(value)
        set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_top), v)
        set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_right), v)
        set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_bottom), v)
        set_property!(ctx.properties, Int(node_id), Symbol(prefix, :_left), v)
    end
end

"""
Parse direction value.
"""
function parse_direction(value::Any)::Union{Direction, Nothing}
    if value isa String
        val_lower = lowercase(value)
        if val_lower == "down" || val_lower == "column"
            return DIRECTION_DOWN
        elseif val_lower == "up" || val_lower == "columnreverse"
            return DIRECTION_UP
        elseif val_lower == "right" || val_lower == "row"
            return DIRECTION_RIGHT
        elseif val_lower == "left" || val_lower == "rowreverse"
            return DIRECTION_LEFT
        end
    end
    return nothing
end

"""
Parse pack value.
"""
function parse_pack(value::Any)::Union{Pack, Nothing}
    if value isa String
        val_lower = lowercase(value)
        if val_lower == "start"
            return PACK_START
        elseif val_lower == "end"
            return PACK_END
        elseif val_lower == "center"
            return PACK_CENTER
        elseif val_lower == "between" || val_lower == "spacebetween"
            return PACK_BETWEEN
        elseif val_lower == "around" || val_lower == "spacearound"
            return PACK_AROUND
        elseif val_lower == "evenly" || val_lower == "spaceevenly"
            return PACK_EVENLY
        end
    end
    return nothing
end

"""
Parse align value.
"""
function parse_align(value::Any)::Union{Align, Nothing}
    if value isa String
        val_lower = lowercase(value)
        if val_lower == "start"
            return ALIGN_START
        elseif val_lower == "end"
            return ALIGN_END
        elseif val_lower == "center"
            return ALIGN_CENTER
        elseif val_lower == "stretch"
            return ALIGN_STRETCH
        elseif val_lower == "baseline"
            return ALIGN_BASELINE
        end
    end
    return nothing
end

"""
Parse color value (hex or named).
"""
function parse_color_value(value::Any)::Union{Color, Nothing}
    if value isa String
        return parse_color(value)
    end
    return nothing
end

end # module TextParser
