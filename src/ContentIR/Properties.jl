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

## Mathematical Integration

Properties integrates with MathOps for mathematical operations:
```julia
# Using MathOps types
size = Vec2(100, 50)           # Equivalent to Size(width=100, height=50)
inset = Box4(10)               # Equivalent to Inset(10, 10, 10, 10)
position = Vec2(20, 30)        # Position as a 2D vector
bounds = Rect(position, size)  # Rectangle from origin and size
```

## Data Structures
- Scalar: Single value (Number, Color, String)
- Named Tuple: Multi-value properties `(width: 100, height: 50)`
- Value Shorthand: When all tuple members identical `Prop: 50`
"""
module Properties

using ..MathOps: Vec2, Box4, Rect, vec2, box4, rect

export Direction, DIRECTION_DOWN, DIRECTION_UP, DIRECTION_RIGHT, DIRECTION_LEFT
export Pack, PACK_START, PACK_END, PACK_CENTER, PACK_BETWEEN, PACK_AROUND, PACK_EVENLY
export Align, ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH, ALIGN_BASELINE
export Size, SizeSpec, SIZE_AUTO, SIZE_FIXED, SIZE_PERCENT, SIZE_MIN, SIZE_MAX, SIZE_FILL
export Inset, Offset, Gap
export PropertyValue, PropertyTable, set_property!, get_property, resize_properties!
export Color, parse_color, color_to_rgba
export PROPERTY_FIELDS
export direction_to_vec2, to_vec2, to_box4

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

# Named colors - module-level constant for reuse
const NAMED_COLORS = Dict{String, Color}(
    "black" => Color(0x00, 0x00, 0x00, 0xff),
    "white" => Color(0xff, 0xff, 0xff, 0xff),
    "red" => Color(0xff, 0x00, 0x00, 0xff),
    "green" => Color(0x00, 0x80, 0x00, 0xff),
    "blue" => Color(0x00, 0x00, 0xff, 0xff),
    "yellow" => Color(0xff, 0xff, 0x00, 0xff),
    "transparent" => Color(0x00, 0x00, 0x00, 0x00),
)

"""
    parse_color(value::AbstractString) -> Color

Parse a color from hex (#RGB, #RRGGBB) or named colors.
"""
function parse_color(value::AbstractString)::Color
    val = strip(lowercase(value))
    
    haskey(NAMED_COLORS, val) && return NAMED_COLORS[val]
    
    # Hex colors - more concise parsing
    startswith(val, "#") || return Color()  # Default black
    
    hex = val[2:end]
    length(hex) == 3 && return Color(
        parse(UInt8, hex[1:1] * hex[1:1], base=16),
        parse(UInt8, hex[2:2] * hex[2:2], base=16),
        parse(UInt8, hex[3:3] * hex[3:3], base=16),
        0xff
    )
    
    length(hex) == 6 && return Color(
        parse(UInt8, hex[1:2], base=16),
        parse(UInt8, hex[3:4], base=16),
        parse(UInt8, hex[5:6], base=16),
        0xff
    )
    
    Color()  # Default black
end

"""
    color_to_rgba(c::Color) -> NTuple{4, Float32}

Convert Color to RGBA floats (0-1 range).
"""
@inline color_to_rgba(c::Color)::NTuple{4, Float32} = (
    Float32(c.r) / 255.0f0,
    Float32(c.g) / 255.0f0,
    Float32(c.b) / 255.0f0,
    Float32(c.a) / 255.0f0
)

"""
    PropertyValue

Union type for all property values.
"""
const PropertyValue = Union{Direction, Pack, Align, Size, Inset, Offset, Gap, Color, Float32, Int32, Bool, String, Nothing}

# Property field definitions: (name, type, default_value)
const PROPERTY_FIELDS = [
    (:direction, Direction, DIRECTION_DOWN), (:pack, Pack, PACK_START), (:align, Align, ALIGN_STRETCH),
    (:gap_row, Float32, 0.0f0), (:gap_col, Float32, 0.0f0),
    (:width, Float32, 0.0f0), (:height, Float32, 0.0f0),
    (:width_spec, SizeSpec, SIZE_AUTO), (:height_spec, SizeSpec, SIZE_AUTO),
    (:min_width, Float32, 0.0f0), (:min_height, Float32, 0.0f0),
    (:max_width, Float32, typemax(Float32)), (:max_height, Float32, typemax(Float32)),
    (:inset_top, Float32, 0.0f0), (:inset_right, Float32, 0.0f0), (:inset_bottom, Float32, 0.0f0), (:inset_left, Float32, 0.0f0),
    (:offset_top, Float32, 0.0f0), (:offset_right, Float32, 0.0f0), (:offset_bottom, Float32, 0.0f0), (:offset_left, Float32, 0.0f0),
    (:fill_r, UInt8, 0x00), (:fill_g, UInt8, 0x00), (:fill_b, UInt8, 0x00), (:fill_a, UInt8, 0x00),
    (:round_tl, Float32, 0.0f0), (:round_tr, Float32, 0.0f0), (:round_br, Float32, 0.0f0), (:round_bl, Float32, 0.0f0),
    (:grid_cols, UInt16, UInt16(1)), (:grid_rows, UInt16, UInt16(1)),
    (:scroll_x, Float32, 0.0f0), (:scroll_y, Float32, 0.0f0),
    (:font_size, Float32, 16.0f0),
    (:text_color_r, UInt8, 0x00), (:text_color_g, UInt8, 0x00), (:text_color_b, UInt8, 0x00), (:text_color_a, UInt8, 0xff)
]

"PropertyTable - Structure of Arrays for node properties (SIMD-friendly)."
mutable struct PropertyTable
    direction::Vector{Direction}; pack::Vector{Pack}; align::Vector{Align}
    gap_row::Vector{Float32}; gap_col::Vector{Float32}
    width::Vector{Float32}; height::Vector{Float32}
    width_spec::Vector{SizeSpec}; height_spec::Vector{SizeSpec}
    min_width::Vector{Float32}; min_height::Vector{Float32}
    max_width::Vector{Float32}; max_height::Vector{Float32}
    inset_top::Vector{Float32}; inset_right::Vector{Float32}; inset_bottom::Vector{Float32}; inset_left::Vector{Float32}
    offset_top::Vector{Float32}; offset_right::Vector{Float32}; offset_bottom::Vector{Float32}; offset_left::Vector{Float32}
    fill_r::Vector{UInt8}; fill_g::Vector{UInt8}; fill_b::Vector{UInt8}; fill_a::Vector{UInt8}
    round_tl::Vector{Float32}; round_tr::Vector{Float32}; round_br::Vector{Float32}; round_bl::Vector{Float32}
    grid_cols::Vector{UInt16}; grid_rows::Vector{UInt16}
    scroll_x::Vector{Float32}; scroll_y::Vector{Float32}
    font_size::Vector{Float32}
    text_color_r::Vector{UInt8}; text_color_g::Vector{UInt8}; text_color_b::Vector{UInt8}; text_color_a::Vector{UInt8}
    
    function PropertyTable(capacity::Int = 0)
        args = [Vector{t}(undef, capacity) for (_, t, _) in PROPERTY_FIELDS]
        new(args...)
    end
end

"Resize property arrays and initialize new entries with defaults."
function resize_properties!(table::PropertyTable, new_size::Int)
    old_size = length(table.direction)
    for (name, _, _) in PROPERTY_FIELDS
        resize!(getfield(table, name), new_size)
    end
    for i in (old_size + 1):new_size
        for (name, _, default) in PROPERTY_FIELDS
            getfield(table, name)[i] = default
        end
    end
end

@inline valid_prop_id(table, id) = id >= 1 && id <= length(table.direction)

"Set a property value for a node."
function set_property!(table::PropertyTable, id::Int, prop::Symbol, value)
    valid_prop_id(table, id) || return
    
    # Handle compound properties
    if prop == :fill
        c = value::Color
        table.fill_r[id], table.fill_g[id], table.fill_b[id], table.fill_a[id] = c.r, c.g, c.b, c.a
    elseif prop == :inset
        i = value::Inset
        table.inset_top[id], table.inset_right[id], table.inset_bottom[id], table.inset_left[id] = i.top, i.right, i.bottom, i.left
    elseif prop == :offset
        o = value::Offset
        table.offset_top[id], table.offset_right[id], table.offset_bottom[id], table.offset_left[id] = o.top, o.right, o.bottom, o.left
    # Handle simple properties with explicit type conversion
    elseif hasfield(PropertyTable, prop)
        field = getfield(table, prop)
        # Convert numeric types explicitly to match field type
        converted_val = eltype(field) <: Number ? convert(eltype(field), value) : value
        field[id] = converted_val
    end
end

"Get a property value for a node."
function get_property(table::PropertyTable, id::Int, prop::Symbol)::PropertyValue
    valid_prop_id(table, id) || return nothing
    
    # Handle compound properties
    if prop == :fill
        return Color(table.fill_r[id], table.fill_g[id], table.fill_b[id], table.fill_a[id])
    elseif prop == :inset
        return Inset(table.inset_top[id], table.inset_right[id], table.inset_bottom[id], table.inset_left[id])
    elseif prop == :offset
        return Offset(table.offset_top[id], table.offset_right[id], table.offset_bottom[id], table.offset_left[id])
    # Handle simple properties
    elseif hasfield(PropertyTable, prop)
        return getfield(table, prop)[id]
    end
    
    nothing
end

# =============================================================================
# Mathematical Integration with MathOps
# =============================================================================

"""
    direction_to_vec2(dir::Direction) -> Vec2

Convert a Direction enum to a unit vector representing the flow direction.

Mathematical interpretation:
- `DIRECTION_DOWN`  → Vec2(0, 1)   # Y+ (downward)
- `DIRECTION_UP`    → Vec2(0, -1)  # Y- (upward)
- `DIRECTION_RIGHT` → Vec2(1, 0)   # X+ (rightward)
- `DIRECTION_LEFT`  → Vec2(-1, 0)  # X- (leftward)

# Example
```julia
dir = DIRECTION_DOWN
flow = direction_to_vec2(dir)  # Vec2(0.0, 1.0)
position += flow * child_height  # Move down by child height
```
"""
@inline function direction_to_vec2(dir::Direction)::Vec2{Float32}
    if dir == DIRECTION_DOWN
        Vec2(0.0f0, 1.0f0)
    elseif dir == DIRECTION_UP
        Vec2(0.0f0, -1.0f0)
    elseif dir == DIRECTION_RIGHT
        Vec2(1.0f0, 0.0f0)
    else  # DIRECTION_LEFT
        Vec2(-1.0f0, 0.0f0)
    end
end

"""
    to_vec2(inset::Inset, axis::Symbol) -> Vec2
    to_vec2(offset::Offset, axis::Symbol) -> Vec2

Extract a Vec2 from box values along an axis.

- `:start` → Vec2(left, top)
- `:end` → Vec2(right, bottom)
- `:total` → Vec2(left+right, top+bottom)

# Example
```julia
inset = Inset(10.0f0, 20.0f0, 30.0f0, 40.0f0)
start_offset = to_vec2(inset, :start)  # Vec2(40.0, 10.0) - (left, top)
total_inset = to_vec2(inset, :total)   # Vec2(60.0, 40.0) - (horizontal, vertical)
```
"""
@inline function to_vec2(box::Inset, axis::Symbol)::Vec2{Float32}
    if axis == :start
        Vec2(box.left, box.top)
    elseif axis == :end
        Vec2(box.right, box.bottom)
    else  # :total
        Vec2(box.left + box.right, box.top + box.bottom)
    end
end

@inline function to_vec2(box::Offset, axis::Symbol)::Vec2{Float32}
    if axis == :start
        Vec2(box.left, box.top)
    elseif axis == :end
        Vec2(box.right, box.bottom)
    else  # :total
        Vec2(box.left + box.right, box.top + box.bottom)
    end
end

"""
    to_box4(inset::Inset) -> Box4
    to_box4(offset::Offset) -> Box4

Convert Inset/Offset to MathOps Box4 for mathematical operations.

# Example
```julia
inset = Inset(10.0f0)
box = to_box4(inset)  # Box4(10.0, 10.0, 10.0, 10.0)
doubled = box * 2     # Box4(20.0, 20.0, 20.0, 20.0)
```
"""
@inline to_box4(i::Inset)::Box4{Float32} = Box4(i.top, i.right, i.bottom, i.left)
@inline to_box4(o::Offset)::Box4{Float32} = Box4(o.top, o.right, o.bottom, o.left)

end # module Properties
