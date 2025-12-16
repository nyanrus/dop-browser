"""
    Properties

Content-- layout semantics and property types as specified in v6.0.

## Layout Semantics Mapping
| Legacy CSS | Content-- | Description |
| :--- | :--- | :--- |
| flex-direction | Direction | Vector of flow (Up, Down, Right, Left) |
| justify-content | Pack | Distribution along the Direction |
| align-items | Align | Alignment perpendicular to Direction |
| padding | Inset | Space inside the node |
| margin | Offset | Space outside the node |
| width/height | Size | Dimensions with range syntax support |

## Data Structures
- Scalar: Single value (Number, Color, String)
- Named Tuple: Multi-value properties `(width: 100, height: 50)`
- Value Shorthand: When all tuple members identical `Prop: 50`
"""
module Properties

export Direction, DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
export Pack, PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
export Align, ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
export Size, SizeSpec, SIZE_AUTO, SIZE_FIXED, SIZE_PERCENT, SIZE_MIN, SIZE_MAX, SIZE_FILL
export Inset, Offset, Gap
export PropertyValue, PropertyTable, set_property!, get_property
export Color, parse_color, color_to_rgba

"""
    Direction

Flow direction for Stack containers.
"""
@enum Direction::UInt8 begin
    DIRECTION_DOWN = 0   # Column (top to bottom)
    DIRECTION_UP = 1     # Column-reverse (bottom to top)
    DIRECTION_RIGHT = 2  # Row (left to right)
    DIRECTION_LEFT = 3   # Row-reverse (right to left)
end

"""
    Pack

Distribution along the primary axis (like justify-content).
"""
@enum Pack::UInt8 begin
    PACK_START = 0    # Pack to start
    PACK_END = 1      # Pack to end
    PACK_CENTER = 2   # Pack to center
    PACK_BETWEEN = 3  # Space between items
    PACK_AROUND = 4   # Space around items
    PACK_EVENLY = 5   # Equal space distribution
end

"""
    Align

Alignment on the cross axis (like align-items).
"""
@enum Align::UInt8 begin
    ALIGN_START = 0     # Align to start
    ALIGN_END = 1       # Align to end
    ALIGN_CENTER = 2    # Align to center
    ALIGN_STRETCH = 3   # Stretch to fill
    ALIGN_BASELINE = 4  # Align to text baseline
end

"""
    SizeSpec

Size specification type for the Size struct.
"""
@enum SizeSpec::UInt8 begin
    SIZE_AUTO = 0     # Automatic sizing
    SIZE_FIXED = 1    # Fixed pixel value
    SIZE_PERCENT = 2  # Percentage of parent
    SIZE_MIN = 3      # Minimum constraint
    SIZE_MAX = 4      # Maximum constraint
    SIZE_FILL = 5     # Fill available space
end

"""
    Size

Dimension value supporting range syntax (e.g., `100..` for min-width).

# Fields
- `value::Float32` - Numeric value
- `spec::SizeSpec` - How to interpret the value
- `min_value::Float32` - Minimum (for range syntax)
- `max_value::Float32` - Maximum (for range syntax)
"""
struct Size
    value::Float32
    spec::SizeSpec
    min_value::Float32
    max_value::Float32
    
    function Size(value::Float32 = 0.0f0; 
                  spec::SizeSpec = SIZE_AUTO,
                  min_val::Float32 = 0.0f0,
                  max_val::Float32 = typemax(Float32))
        new(value, spec, min_val, max_val)
    end
end

"""
    Inset

Space inside a node (like padding). Named tuple: (top, right, bottom, left).
"""
struct Inset
    top::Float32
    right::Float32
    bottom::Float32
    left::Float32
    
    function Inset(all::Float32 = 0.0f0)
        new(all, all, all, all)
    end
    
    function Inset(vertical::Float32, horizontal::Float32)
        new(vertical, horizontal, vertical, horizontal)
    end
    
    function Inset(top::Float32, right::Float32, bottom::Float32, left::Float32)
        new(top, right, bottom, left)
    end
end

"""
    Offset

Space outside a node (like margin). Named tuple: (top, right, bottom, left).
"""
struct Offset
    top::Float32
    right::Float32
    bottom::Float32
    left::Float32
    
    function Offset(all::Float32 = 0.0f0)
        new(all, all, all, all)
    end
    
    function Offset(vertical::Float32, horizontal::Float32)
        new(vertical, horizontal, vertical, horizontal)
    end
    
    function Offset(top::Float32, right::Float32, bottom::Float32, left::Float32)
        new(top, right, bottom, left)
    end
end

"""
    Gap

Spacing between children in Stack/Grid containers.
"""
struct Gap
    row::Float32     # Gap between rows
    column::Float32  # Gap between columns
    
    function Gap(all::Float32 = 0.0f0)
        new(all, all)
    end
    
    function Gap(row::Float32, column::Float32)
        new(row, column)
    end
end

"""
    Color

RGBA color with 8-bit components.
"""
struct Color
    r::UInt8
    g::UInt8
    b::UInt8
    a::UInt8
    
    function Color(r::UInt8=0x00, g::UInt8=0x00, b::UInt8=0x00, a::UInt8=0xff)
        new(r, g, b, a)
    end
end

"""
    parse_color(value::AbstractString) -> Color

Parse a color from hex (#RGB, #RRGGBB) or named colors.
"""
function parse_color(value::AbstractString)::Color
    val = strip(lowercase(value))
    
    # Named colors
    named = Dict{String, Color}(
        "black" => Color(0x00, 0x00, 0x00, 0xff),
        "white" => Color(0xff, 0xff, 0xff, 0xff),
        "red" => Color(0xff, 0x00, 0x00, 0xff),
        "green" => Color(0x00, 0x80, 0x00, 0xff),
        "blue" => Color(0x00, 0x00, 0xff, 0xff),
        "yellow" => Color(0xff, 0xff, 0x00, 0xff),
        "transparent" => Color(0x00, 0x00, 0x00, 0x00),
    )
    
    if haskey(named, val)
        return named[val]
    end
    
    # Hex colors
    if startswith(val, "#")
        hex = val[2:end]
        if length(hex) == 3
            r = parse(UInt8, hex[1:1] * hex[1:1], base=16)
            g = parse(UInt8, hex[2:2] * hex[2:2], base=16)
            b = parse(UInt8, hex[3:3] * hex[3:3], base=16)
            return Color(r, g, b, 0xff)
        elseif length(hex) == 6
            r = parse(UInt8, hex[1:2], base=16)
            g = parse(UInt8, hex[3:4], base=16)
            b = parse(UInt8, hex[5:6], base=16)
            return Color(r, g, b, 0xff)
        end
    end
    
    return Color()  # Default black
end

"""
    color_to_rgba(c::Color) -> NTuple{4, Float32}

Convert Color to RGBA floats (0-1 range).
"""
function color_to_rgba(c::Color)::NTuple{4, Float32}
    return (
        Float32(c.r) / 255.0f0,
        Float32(c.g) / 255.0f0,
        Float32(c.b) / 255.0f0,
        Float32(c.a) / 255.0f0
    )
end

"""
    PropertyValue

Union type for all property values.
"""
const PropertyValue = Union{Direction, Pack, Align, Size, Inset, Offset, Gap, Color, 
                            Float32, Int32, Bool, String, Nothing}

"""
    PropertyTable

Structure of Arrays for node properties.
Enables efficient batch processing and SIMD operations.
"""
mutable struct PropertyTable
    # Stack/Grid properties
    direction::Vector{Direction}
    pack::Vector{Pack}
    align::Vector{Align}
    gap_row::Vector{Float32}
    gap_col::Vector{Float32}
    
    # Size properties  
    width::Vector{Float32}
    height::Vector{Float32}
    width_spec::Vector{SizeSpec}
    height_spec::Vector{SizeSpec}
    min_width::Vector{Float32}
    min_height::Vector{Float32}
    max_width::Vector{Float32}
    max_height::Vector{Float32}
    
    # Box model
    inset_top::Vector{Float32}
    inset_right::Vector{Float32}
    inset_bottom::Vector{Float32}
    inset_left::Vector{Float32}
    offset_top::Vector{Float32}
    offset_right::Vector{Float32}
    offset_bottom::Vector{Float32}
    offset_left::Vector{Float32}
    
    # Colors
    fill_r::Vector{UInt8}
    fill_g::Vector{UInt8}
    fill_b::Vector{UInt8}
    fill_a::Vector{UInt8}
    
    # Border radius (Round in Content--)
    round_tl::Vector{Float32}
    round_tr::Vector{Float32}
    round_br::Vector{Float32}
    round_bl::Vector{Float32}
    
    # Grid-specific
    grid_cols::Vector{UInt16}
    grid_rows::Vector{UInt16}
    
    # Scroll-specific
    scroll_x::Vector{Float32}
    scroll_y::Vector{Float32}
    
    function PropertyTable(capacity::Int = 0)
        new(
            Vector{Direction}(undef, capacity),
            Vector{Pack}(undef, capacity),
            Vector{Align}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{SizeSpec}(undef, capacity),
            Vector{SizeSpec}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{UInt8}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{UInt16}(undef, capacity),
            Vector{UInt16}(undef, capacity),
            Vector{Float32}(undef, capacity),
            Vector{Float32}(undef, capacity)
        )
    end
end

"""
    resize_properties!(table::PropertyTable, new_size::Int)

Resize property arrays and initialize new entries with defaults.
"""
function resize_properties!(table::PropertyTable, new_size::Int)
    old_size = length(table.direction)
    
    # Resize all arrays
    resize!(table.direction, new_size)
    resize!(table.pack, new_size)
    resize!(table.align, new_size)
    resize!(table.gap_row, new_size)
    resize!(table.gap_col, new_size)
    resize!(table.width, new_size)
    resize!(table.height, new_size)
    resize!(table.width_spec, new_size)
    resize!(table.height_spec, new_size)
    resize!(table.min_width, new_size)
    resize!(table.min_height, new_size)
    resize!(table.max_width, new_size)
    resize!(table.max_height, new_size)
    resize!(table.inset_top, new_size)
    resize!(table.inset_right, new_size)
    resize!(table.inset_bottom, new_size)
    resize!(table.inset_left, new_size)
    resize!(table.offset_top, new_size)
    resize!(table.offset_right, new_size)
    resize!(table.offset_bottom, new_size)
    resize!(table.offset_left, new_size)
    resize!(table.fill_r, new_size)
    resize!(table.fill_g, new_size)
    resize!(table.fill_b, new_size)
    resize!(table.fill_a, new_size)
    resize!(table.round_tl, new_size)
    resize!(table.round_tr, new_size)
    resize!(table.round_br, new_size)
    resize!(table.round_bl, new_size)
    resize!(table.grid_cols, new_size)
    resize!(table.grid_rows, new_size)
    resize!(table.scroll_x, new_size)
    resize!(table.scroll_y, new_size)
    
    # Initialize defaults for new entries
    for i in (old_size + 1):new_size
        table.direction[i] = DIRECTION_DOWN
        table.pack[i] = PACK_START
        table.align[i] = ALIGN_STRETCH
        table.gap_row[i] = 0.0f0
        table.gap_col[i] = 0.0f0
        table.width[i] = 0.0f0
        table.height[i] = 0.0f0
        table.width_spec[i] = SIZE_AUTO
        table.height_spec[i] = SIZE_AUTO
        table.min_width[i] = 0.0f0
        table.min_height[i] = 0.0f0
        table.max_width[i] = typemax(Float32)
        table.max_height[i] = typemax(Float32)
        table.inset_top[i] = 0.0f0
        table.inset_right[i] = 0.0f0
        table.inset_bottom[i] = 0.0f0
        table.inset_left[i] = 0.0f0
        table.offset_top[i] = 0.0f0
        table.offset_right[i] = 0.0f0
        table.offset_bottom[i] = 0.0f0
        table.offset_left[i] = 0.0f0
        table.fill_r[i] = 0x00
        table.fill_g[i] = 0x00
        table.fill_b[i] = 0x00
        table.fill_a[i] = 0x00  # Transparent
        table.round_tl[i] = 0.0f0
        table.round_tr[i] = 0.0f0
        table.round_br[i] = 0.0f0
        table.round_bl[i] = 0.0f0
        table.grid_cols[i] = UInt16(1)
        table.grid_rows[i] = UInt16(1)
        table.scroll_x[i] = 0.0f0
        table.scroll_y[i] = 0.0f0
    end
end

"""
    set_property!(table::PropertyTable, id::Int, prop::Symbol, value)

Set a property value for a node.
"""
function set_property!(table::PropertyTable, id::Int, prop::Symbol, value)
    if id < 1 || id > length(table.direction)
        return
    end
    
    if prop == :direction
        table.direction[id] = value
    elseif prop == :pack
        table.pack[id] = value
    elseif prop == :align
        table.align[id] = value
    elseif prop == :gap_row
        table.gap_row[id] = Float32(value)
    elseif prop == :gap_col
        table.gap_col[id] = Float32(value)
    elseif prop == :width
        table.width[id] = Float32(value)
    elseif prop == :height
        table.height[id] = Float32(value)
    elseif prop == :fill
        c = value::Color
        table.fill_r[id] = c.r
        table.fill_g[id] = c.g
        table.fill_b[id] = c.b
        table.fill_a[id] = c.a
    elseif prop == :inset
        i = value::Inset
        table.inset_top[id] = i.top
        table.inset_right[id] = i.right
        table.inset_bottom[id] = i.bottom
        table.inset_left[id] = i.left
    elseif prop == :offset
        o = value::Offset
        table.offset_top[id] = o.top
        table.offset_right[id] = o.right
        table.offset_bottom[id] = o.bottom
        table.offset_left[id] = o.left
    end
end

"""
    get_property(table::PropertyTable, id::Int, prop::Symbol) -> PropertyValue

Get a property value for a node.
"""
function get_property(table::PropertyTable, id::Int, prop::Symbol)::PropertyValue
    if id < 1 || id > length(table.direction)
        return nothing
    end
    
    if prop == :direction
        return table.direction[id]
    elseif prop == :pack
        return table.pack[id]
    elseif prop == :align
        return table.align[id]
    elseif prop == :width
        return table.width[id]
    elseif prop == :height
        return table.height[id]
    elseif prop == :fill
        return Color(table.fill_r[id], table.fill_g[id], 
                     table.fill_b[id], table.fill_a[id])
    elseif prop == :inset
        return Inset(table.inset_top[id], table.inset_right[id],
                     table.inset_bottom[id], table.inset_left[id])
    elseif prop == :offset
        return Offset(table.offset_top[id], table.offset_right[id],
                      table.offset_bottom[id], table.offset_left[id])
    end
    
    return nothing
end

end # module Properties
