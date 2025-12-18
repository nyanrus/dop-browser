"""
    MathOps

Mathematical operators for Content-- layout computation using mature Julia libraries.

Content-- uses a mathematically intuitive approach leveraging:
- **StaticArrays.jl** for high-performance immutable vectors
- **LinearAlgebra** for standard mathematical operations
- **Unicode operators** for expressive mathematical notation

## Vector Operations

Layout positions and sizes are represented as 2D vectors:
- `Vec2(x, y)` - A 2D point or size (backed by SVector{2,T})
- `Box4(top, right, bottom, left)` - A 4-sided box value (backed by SVector{4,T})

## Operators

| Operator | Unicode | Meaning | Example |
|----------|---------|---------|---------|
| `+` | | Addition | `Vec2(10, 20) + Vec2(5, 5) = Vec2(15, 25)` |
| `-` | | Subtraction | `Vec2(10, 20) - Vec2(5, 5) = Vec2(5, 15)` |
| `*` | | Scaling | `Vec2(10, 20) * 2 = Vec2(20, 40)` |
| `/` | | Division | `Vec2(10, 20) / 2 = Vec2(5, 10)` |
| `⊕` | oplus | Box merge | Combine two Box4 values |
| `⊗` | otimes | Hadamard product | Component-wise multiply |
| `⊙` | odot | Dot product | `Vec2(1,0) ⊙ Vec2(0,1) = 0` |
| `‖·‖` | norm | Norm/magnitude | `‖Vec2(3,4)‖ = 5` |
| `∘` | circ | Function composition | For transforms |

## Intuitive Property Syntax

Properties can be expressed in a math-like concise format:
```julia
size = (100, 50)      # Equivalent to Size(width=100, height=50)
inset = 10            # Equivalent to Inset(10, 10, 10, 10)
inset = (10, 20)      # Equivalent to Inset(10, 20, 10, 20)
```

## Layout Equations

The layout follows simple mathematical rules:
```
child.position = parent.content_origin + Σ(preceding_sibling.size) + child.offset
parent.content_origin = parent.position + parent.inset
```
"""
module MathOps

using StaticArrays
using LinearAlgebra

export Vec2, Box4, Rect, Transform2D
export vec2, box4, rect
export lerp, clamp01, remap, smoothstep
export ⊕, ⊗, ⊙, box_merge, hadamard, dot_product
export ZERO_VEC2, UNIT_VEC2, ZERO_BOX4, ZERO_RECT
export norm, normalize  # Re-export from LinearAlgebra
export magnitude, dot  # Backward compatibility aliases
export horizontal, vertical, total  # Box4 utility functions

# =============================================================================
# Core Mathematical Types (Using StaticArrays for Performance)
# =============================================================================

"""
    Vec2{T}

2D vector for positions, sizes, and offsets.
Backed by StaticArrays.SVector{2,T} for high performance.
Supports intuitive mathematical operations.

# Examples
```julia
pos = Vec2(100.0f0, 200.0f0)
size = Vec2(50.0f0, 30.0f0)
end_pos = pos + size  # Vec2(150.0, 230.0)

# Using Unicode operators
v₁ = Vec2(3.0f0, 4.0f0)
‖v₁‖ = norm(v₁)  # 5.0
v₂ = Vec2(1.0f0, 0.0f0)
v₁ ⊙ v₂  # Dot product: 3.0
```
"""
struct Vec2{T<:Number}
    data::SVector{2,T}
    
    function Vec2{T}(x::T, y::T) where T<:Number
        new{T}(SVector{2,T}(x, y))
    end
    
    function Vec2(x::Number, y::Number)
        T = promote_type(typeof(x), typeof(y))
        new{T}(SVector{2,T}(convert(T, x), convert(T, y)))
    end
    
    # Constructor from SVector
    function Vec2(v::SVector{2,T}) where T<:Number
        new{T}(v)
    end
end

# Property accessors for backward compatibility
Base.getproperty(v::Vec2, s::Symbol) = s === :x ? getfield(v, :data)[1] :
                                        s === :y ? getfield(v, :data)[2] :
                                        getfield(v, s)

# Convenient constructors
vec2(x::Number, y::Number) = Vec2(Float32(x), Float32(y))
vec2(v::Number) = Vec2(Float32(v), Float32(v))
vec2(t::Tuple{<:Number, <:Number}) = Vec2(Float32(t[1]), Float32(t[2]))

# Zero and unit vectors
const ZERO_VEC2 = Vec2(0.0f0, 0.0f0)
const UNIT_VEC2 = Vec2(1.0f0, 1.0f0)

# Arithmetic operations (leveraging SVector's optimized operations)
Base.:+(a::Vec2, b::Vec2) = Vec2(a.data + b.data)
Base.:-(a::Vec2, b::Vec2) = Vec2(a.data - b.data)
Base.:-(a::Vec2) = Vec2(-a.data)
Base.:*(a::Vec2, s::Number) = Vec2(a.data * s)
Base.:*(s::Number, a::Vec2) = Vec2(s * a.data)
Base.:/(a::Vec2, s::Number) = Vec2(a.data / s)

# Component-wise operations (Hadamard product)
Base.:*(a::Vec2, b::Vec2) = Vec2(a.data .* b.data)
Base.:/(a::Vec2, b::Vec2) = Vec2(a.data ./ b.data)

# Comparison
Base.:(==)(a::Vec2, b::Vec2) = a.data == b.data
Base.isapprox(a::Vec2, b::Vec2; kwargs...) = isapprox(a.data, b.data; kwargs...)

# Conversion and indexing
Base.Tuple(v::Vec2) = (v.x, v.y)
Base.convert(::Type{Vec2{T}}, v::Vec2) where T = Vec2{T}(convert(T, v.x), convert(T, v.y))
Base.getindex(v::Vec2, i::Int) = getfield(v, :data)[i]
Base.length(::Vec2) = 2
Base.eltype(::Type{Vec2{T}}) where T = T

# Utility functions
Base.zero(::Type{Vec2{T}}) where T = Vec2{T}(zero(T), zero(T))
Base.one(::Type{Vec2{T}}) where T = Vec2{T}(one(T), one(T))

# Extend LinearAlgebra's norm and normalize to work with Vec2
# These delegate to SVector's implementations (which call LinearAlgebra)
LinearAlgebra.norm(v::Vec2) = LinearAlgebra.norm(v.data)
LinearAlgebra.normalize(v::Vec2) = Vec2(LinearAlgebra.normalize(v.data))

# Keep magnitude as an alias for norm (for backward compatibility)
"""
    magnitude(v::Vec2) -> Number

Euclidean magnitude (length) of the vector.
Alias for `norm(v)`.
"""
magnitude(v::Vec2) = norm(v)

# Dot product using LinearAlgebra
"""
    dot(a::Vec2, b::Vec2) -> Number

Dot product of two vectors using LinearAlgebra.
"""
LinearAlgebra.dot(a::Vec2, b::Vec2) = dot(a.data, b.data)

"""
    Box4{T}

4-sided box value for inset (padding), offset (margin), and stroke (border).
Values follow CSS order: top, right, bottom, left.
Backed by StaticArrays.SVector{4,T} for high performance.

# Examples
```julia
inset = Box4(10.0f0)           # All sides = 10
inset = Box4(10.0f0, 20.0f0)   # Vertical = 10, Horizontal = 20
inset = Box4(1.0f0, 2.0f0, 3.0f0, 4.0f0)  # Top, Right, Bottom, Left

# Using Unicode operators
b₁ = Box4(10.0f0, 20.0f0, 10.0f0, 20.0f0)
b₂ = Box4(5.0f0)
b₃ = b₁ ⊕ b₂  # Box merge (max of each side)
```
"""
struct Box4{T<:Number}
    data::SVector{4,T}
    
    # All sides equal
    function Box4{T}(all::T) where T<:Number
        new{T}(SVector{4,T}(all, all, all, all))
    end
    
    # Vertical/Horizontal
    function Box4{T}(vertical::T, horizontal::T) where T<:Number
        new{T}(SVector{4,T}(vertical, horizontal, vertical, horizontal))
    end
    
    # All four sides
    function Box4{T}(top::T, right::T, bottom::T, left::T) where T<:Number
        new{T}(SVector{4,T}(top, right, bottom, left))
    end
    
    # Auto-convert
    function Box4(all::Number)
        T = Float32
        v = convert(T, all)
        new{T}(SVector{4,T}(v, v, v, v))
    end
    
    function Box4(vertical::Number, horizontal::Number)
        T = Float32
        v, h = convert(T, vertical), convert(T, horizontal)
        new{T}(SVector{4,T}(v, h, v, h))
    end
    
    function Box4(top::Number, right::Number, bottom::Number, left::Number)
        T = Float32
        new{T}(SVector{4,T}(convert(T, top), convert(T, right), convert(T, bottom), convert(T, left)))
    end
    
    # Constructor from SVector
    function Box4(v::SVector{4,T}) where T<:Number
        new{T}(v)
    end
end

# Property accessors for backward compatibility
Base.getproperty(b::Box4, s::Symbol) = s === :top ? getfield(b, :data)[1] :
                                        s === :right ? getfield(b, :data)[2] :
                                        s === :bottom ? getfield(b, :data)[3] :
                                        s === :left ? getfield(b, :data)[4] :
                                        getfield(b, s)

# Convenient constructors
box4(all::Number) = Box4(Float32(all))
box4(v::Number, h::Number) = Box4(Float32(v), Float32(h))
box4(t::Number, r::Number, b::Number, l::Number) = Box4(Float32(t), Float32(r), Float32(b), Float32(l))

"""
    box4(t::Tuple) -> Box4

Construct Box4 from a tuple. Supported tuple lengths:
- 1 element: all sides equal
- 2 elements: (vertical, horizontal)
- 4 elements: (top, right, bottom, left)

Throws ArgumentError for unsupported tuple lengths.
"""
function box4(t::Tuple)
    if length(t) == 1
        box4(t[1])
    elseif length(t) == 2
        box4(t[1], t[2])
    elseif length(t) == 4
        box4(t[1], t[2], t[3], t[4])
    else
        throw(ArgumentError("Box4 tuple must have 1, 2, or 4 elements, got $(length(t))"))
    end
end

const ZERO_BOX4 = Box4(0.0f0)

# Arithmetic operations (leveraging SVector's optimized operations)
Base.:+(a::Box4, b::Box4) = Box4(a.data + b.data)
Base.:-(a::Box4, b::Box4) = Box4(a.data - b.data)
Base.:*(a::Box4, s::Number) = Box4(a.data * s)
Base.:*(s::Number, a::Box4) = Box4(s * a.data)
Base.:/(a::Box4, s::Number) = Box4(a.data / s)

# Comparison
Base.:(==)(a::Box4, b::Box4) = a.data == b.data

# Conversion and indexing
Base.Tuple(b::Box4) = (b.top, b.right, b.bottom, b.left)
Base.getindex(b::Box4, i::Int) = getfield(b, :data)[i]
Base.length(::Box4) = 4
Base.eltype(::Type{Box4{T}}) where T = T

"""
    horizontal(b::Box4) -> Number

Sum of left and right values.
"""
horizontal(b::Box4) = b.left + b.right

"""
    vertical(b::Box4) -> Number

Sum of top and bottom values.
"""
vertical(b::Box4) = b.top + b.bottom

"""
    total(b::Box4) -> Vec2

Total size contribution as Vec2(horizontal, vertical).
"""
total(b::Box4) = Vec2(horizontal(b), vertical(b))

"""
    Rect{T}

Rectangle defined by position and size.
Represents a node's bounding box in the layout.

# Examples
```julia
rect = Rect(Vec2(10, 20), Vec2(100, 50))
rect.x  # 10
rect.y  # 20
rect.width  # 100
rect.height  # 50
rect.right  # 110
rect.bottom  # 70
```
"""
struct Rect{T<:Number}
    origin::Vec2{T}
    size::Vec2{T}
    
    function Rect{T}(origin::Vec2{T}, size::Vec2{T}) where T<:Number
        new{T}(origin, size)
    end
    
    function Rect(origin::Vec2, size::Vec2)
        T = Float32
        new{T}(Vec2{T}(T(origin.x), T(origin.y)), Vec2{T}(T(size.x), T(size.y)))
    end
    
    function Rect(x::Number, y::Number, width::Number, height::Number)
        T = Float32
        new{T}(Vec2{T}(T(x), T(y)), Vec2{T}(T(width), T(height)))
    end
end

# Convenient constructor
rect(x::Number, y::Number, w::Number, h::Number) = Rect(Float32(x), Float32(y), Float32(w), Float32(h))
rect(origin::Vec2, size::Vec2) = Rect(origin, size)

# Zero rect constant
const ZERO_RECT = Rect(0.0f0, 0.0f0, 0.0f0, 0.0f0)

# Property accessors
Base.getproperty(r::Rect, s::Symbol) = 
    s == :x ? getfield(r, :origin).x :
    s == :y ? getfield(r, :origin).y :
    s == :width ? getfield(r, :size).x :
    s == :height ? getfield(r, :size).y :
    s == :left ? getfield(r, :origin).x :
    s == :top ? getfield(r, :origin).y :
    s == :right ? getfield(r, :origin).x + getfield(r, :size).x :
    s == :bottom ? getfield(r, :origin).y + getfield(r, :size).y :
    getfield(r, s)

# Rect operations
Base.:+(r::Rect, offset::Vec2) = Rect(r.origin + offset, r.size)
Base.:-(r::Rect, offset::Vec2) = Rect(r.origin - offset, r.size)

"""
    contains(r::Rect, point::Vec2) -> Bool

Check if a point is inside the rectangle.
"""
contains(r::Rect, point::Vec2) = 
    point.x >= r.left && point.x <= r.right && 
    point.y >= r.top && point.y <= r.bottom

"""
    intersects(a::Rect, b::Rect) -> Bool

Check if two rectangles overlap.
"""
function intersects(a::Rect, b::Rect)
    a.left < b.right && a.right > b.left &&
    a.top < b.bottom && a.bottom > b.top
end

"""
    intersection(a::Rect, b::Rect) -> Rect

Compute the intersection of two rectangles.
Returns ZERO_RECT if the rectangles don't overlap.
"""
function intersection(a::Rect, b::Rect)
    left = max(a.left, b.left)
    top = max(a.top, b.top)
    right = min(a.right, b.right)
    bottom = min(a.bottom, b.bottom)
    
    if right <= left || bottom <= top
        return ZERO_RECT
    end
    
    return Rect(left, top, right - left, bottom - top)
end

"""
    inset_rect(r::Rect, box::Box4) -> Rect

Shrink a rectangle by a box amount (apply padding).
"""
function inset_rect(r::Rect, box::Box4)
    Rect(
        r.x + box.left,
        r.y + box.top,
        r.width - horizontal(box),
        r.height - vertical(box)
    )
end

"""
    outset_rect(r::Rect, box::Box4) -> Rect

Expand a rectangle by a box amount (apply margin).
"""
function outset_rect(r::Rect, box::Box4)
    Rect(
        r.x - box.left,
        r.y - box.top,
        r.width + horizontal(box),
        r.height + vertical(box)
    )
end

# =============================================================================
# 2D Transform
# =============================================================================

"""
    Transform2D{T}

2D affine transformation matrix.
Supports translation, rotation, and scale.

Layout transformation equation:
```
world_pos = transform * local_pos
```
"""
struct Transform2D{T<:Number}
    # 2x3 matrix: [a b tx; c d ty]
    a::T   # Scale X / Rotation
    b::T   # Skew Y
    c::T   # Skew X
    d::T   # Scale Y / Rotation
    tx::T  # Translate X
    ty::T  # Translate Y
    
    function Transform2D{T}(a::T, b::T, c::T, d::T, tx::T, ty::T) where T<:Number
        new{T}(a, b, c, d, tx, ty)
    end
    
    function Transform2D(a::Number, b::Number, c::Number, d::Number, tx::Number, ty::Number)
        T = Float32
        new{T}(T(a), T(b), T(c), T(d), T(tx), T(ty))
    end
end

# Identity transform
const IDENTITY_TRANSFORM = Transform2D(1.0f0, 0.0f0, 0.0f0, 1.0f0, 0.0f0, 0.0f0)

"""
    translate(tx::Number, ty::Number) -> Transform2D

Create a translation transform.
"""
translate(tx::Number, ty::Number) = Transform2D(1.0f0, 0.0f0, 0.0f0, 1.0f0, Float32(tx), Float32(ty))
translate(v::Vec2) = translate(v.x, v.y)

"""
    scale(sx::Number, sy::Number) -> Transform2D

Create a scale transform.
"""
scale(sx::Number, sy::Number) = Transform2D(Float32(sx), 0.0f0, 0.0f0, Float32(sy), 0.0f0, 0.0f0)
scale(s::Number) = scale(s, s)
scale(v::Vec2) = scale(v.x, v.y)

"""
    rotate(angle::Number) -> Transform2D

Create a rotation transform (angle in radians).
"""
function rotate(angle::Number)
    c = Float32(cos(angle))
    s = Float32(sin(angle))
    Transform2D(c, -s, s, c, 0.0f0, 0.0f0)
end

# Transform composition (matrix multiplication)
function Base.:*(a::Transform2D, b::Transform2D)
    Transform2D(
        a.a * b.a + a.b * b.c,
        a.a * b.b + a.b * b.d,
        a.c * b.a + a.d * b.c,
        a.c * b.b + a.d * b.d,
        a.a * b.tx + a.b * b.ty + a.tx,
        a.c * b.tx + a.d * b.ty + a.ty
    )
end

# Apply transform to a point
function Base.:*(t::Transform2D, v::Vec2)
    Vec2(
        t.a * v.x + t.b * v.y + t.tx,
        t.c * v.x + t.d * v.y + t.ty
    )
end

# =============================================================================
# Mathematical Utility Functions
# =============================================================================

"""
    lerp(a, b, t) -> Number

Linear interpolation between a and b.
`t = 0` returns `a`, `t = 1` returns `b`.

# Example
```julia
lerp(0.0, 100.0, 0.5)  # 50.0
```
"""
lerp(a::Number, b::Number, t::Number) = a + (b - a) * t
lerp(a::Vec2, b::Vec2, t::Number) = Vec2(lerp(a.x, b.x, t), lerp(a.y, b.y, t))

"""
    clamp01(x) -> Number

Clamp value to [0, 1] range.
"""
clamp01(x::Number) = clamp(x, zero(x), one(x))

"""
    remap(value, from_low, from_high, to_low, to_high) -> Number

Remap a value from one range to another.

# Example
```julia
remap(50, 0, 100, 0, 1)  # 0.5
```
"""
function remap(value::Number, from_low::Number, from_high::Number, to_low::Number, to_high::Number)
    t = (value - from_low) / (from_high - from_low)
    lerp(to_low, to_high, t)
end

"""
    smoothstep(edge0, edge1, x) -> Number

Hermite interpolation between 0 and 1 when edge0 < x < edge1.
Useful for smooth transitions in animations.
"""
function smoothstep(edge0::Number, edge1::Number, x::Number)
    t = clamp01((x - edge0) / (edge1 - edge0))
    t * t * (3 - 2 * t)
end

# =============================================================================
# Mathematical Operators (Unicode) - Expressive Math Notation
# =============================================================================

"""
    box_merge(a::Box4, b::Box4) -> Box4
    ⊕(a::Box4, b::Box4) -> Box4

Box merge operator (⊕) - maximum of each side.
Useful for combining constraint boxes.

# Example
```julia
b₁ = Box4(10.0f0, 20.0f0, 30.0f0, 40.0f0)
b₂ = Box4(15.0f0)
merged = b₁ ⊕ b₂  # Box4(15.0, 20.0, 30.0, 40.0) - max of each side
```
"""
box_merge(a::Box4, b::Box4) = Box4(max.(a.data, b.data))
const ⊕ = box_merge

"""
    hadamard(a::Vec2, b::Vec2) -> Vec2
    ⊗(a::Vec2, b::Vec2) -> Vec2

Hadamard product (⊗) - component-wise multiplication.
Also known as element-wise or Schur product.

# Example
```julia
v₁ = Vec2(2.0f0, 3.0f0)
v₂ = Vec2(4.0f0, 5.0f0)
result = v₁ ⊗ v₂  # Vec2(8.0, 15.0)
```
"""
hadamard(a::Vec2, b::Vec2) = Vec2(a.data .* b.data)
const ⊗ = hadamard

"""
    dot_product(a::Vec2, b::Vec2) -> Number
    ⊙(a::Vec2, b::Vec2) -> Number

Dot product operator (⊙).
Returns the scalar product of two vectors.

# Example
```julia
using LinearAlgebra
v₁ = Vec2(3.0f0, 4.0f0)
v₂ = Vec2(1.0f0, 0.0f0)
result = v₁ ⊙ v₂  # 3.0 (same as dot(v₁, v₂))
```
"""
dot_product(a::Vec2, b::Vec2) = dot(a, b)
const ⊙ = dot_product

# =============================================================================
# Layout Computation Helpers
# =============================================================================

"""
    compute_content_box(bounds::Rect, inset::Box4) -> Rect

Compute the content box (where children are placed) from bounds and inset.

Layout equation:
```
content_box = bounds - inset
```
"""
compute_content_box(bounds::Rect, inset::Box4) = inset_rect(bounds, inset)

"""
    compute_total_size(content_size::Vec2, inset::Box4, offset::Box4) -> Vec2

Compute total size including inset and offset.

Layout equation:
```
total_size = content_size + inset_total + offset_total
```
"""
function compute_total_size(content_size::Vec2, inset::Box4, offset::Box4)
    content_size + total(inset) + total(offset)
end

"""
    compute_child_position(parent_content_origin::Vec2, 
                           preceding_size::Vec2,
                           child_offset::Box4,
                           direction::Symbol) -> Vec2

Compute a child's position within a stack layout.

Layout equation (for :down direction):
```
child.pos = parent.content_origin + (0, preceding_height) + child.offset
```
"""
function compute_child_position(parent_content_origin::Vec2,
                                preceding_size::Vec2,
                                child_offset::Box4,
                                direction::Symbol)
    δ = Vec2(child_offset.left, child_offset.top)  # offset delta (unicode for clarity)
    
    direction == :down  ? parent_content_origin + Vec2(0.0f0, preceding_size.y) + δ :
    direction == :up    ? parent_content_origin + Vec2(0.0f0, -preceding_size.y) + δ :
    direction == :right ? parent_content_origin + Vec2(preceding_size.x, 0.0f0) + δ :
                          parent_content_origin + Vec2(-preceding_size.x, 0.0f0) + δ  # :left
end

end # module MathOps
