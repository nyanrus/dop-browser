# Content-- Language Specification

## Overview

Content-- is a **mathematically intuitive, render-friendly** intermediate representation (IR) that replaces traditional DOM & CSSOM for browser rendering. The key design principle is:

> **HTML & CSS → (Lowering) → Content-- → (Rendering Engine)**

The rendering engine understands **only** Content--, never HTML/CSS directly.

## Design Philosophy

### 1. Source Language vs Target Language

| Concept | Source Language | Target Language |
|---------|-----------------|-----------------|
| Format | HTML & CSS | Content-- |
| Role | Authoring format | Rendering input |
| Complexity | Feature-rich, cascading | Pre-computed, flat |
| Runtime cost | High (style lookup) | Zero (direct access) |

### 2. Mathematical Model

Content-- is designed with a **math-first** approach. Layout computation uses familiar mathematical concepts from linear algebra and coordinate geometry.

#### Coordinate System

```
Origin (0, 0) at top-left of viewport
├── X-axis: Increases rightward →
├── Y-axis: Increases downward ↓
└── All values: Float32 in device pixels
```

#### Core Mathematical Types

| Type | Description | Example |
|------|-------------|---------|
| `Vec2` | 2D vector for position/size | `Vec2(100.0, 50.0)` |
| `Box4` | 4-sided box for spacing | `Box4(10.0, 20.0, 10.0, 20.0)` |
| `Rect` | Rectangle (origin + size) | `Rect(pos, size)` |
| `Transform2D` | 2D affine transform | `translate(10, 20) * scale(2)` |

#### Mathematical Operators

| Operator | Meaning | Example |
|----------|---------|---------|
| `+` | Vector addition | `Vec2(10,20) + Vec2(5,5) = Vec2(15,25)` |
| `-` | Vector subtraction | `Vec2(10,20) - Vec2(5,5) = Vec2(5,15)` |
| `*` | Scalar multiply | `Vec2(10,20) * 2 = Vec2(20,40)` |
| `/` | Scalar divide | `Vec2(10,20) / 2 = Vec2(5,10)` |
| `⊕` | Box merge (max) | Combine constraint boxes |
| `⊗` | Hadamard product | Component-wise multiply |
| `⊙` | Dot product | `Vec2(1,0) ⊙ Vec2(0,1) = 0` |

### 3. Pre-calculation Guarantee

All CSS cascade computation happens at **lowering time**, not render time:
- No style inheritance at runtime
- No selector matching at runtime
- No cascade resolution at runtime

## Box Model Mathematics

### Visual Box Model

```
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
| e | l | t +------------------------+ t | r | i |
| f | e |           inset_bottom         | i | g |
| t | f | t +------------------------+ t | g | h |
|   | t |              stroke_bottom       | h | t |
|   +------------------------------------------+   |
|                    offset_bottom                 |
+--------------------------------------------------+
```

### CSS to Content-- Mapping

| CSS Property | Content-- Property | Semantic |
|-------------|-------------------|----------|
| `margin` | `offset` | Space outside node |
| `padding` | `inset` | Space inside node |
| `border` | `stroke` | Visual boundary |
| `background-color` | `fill` | Background color |
| `width/height` | `size` | Dimensions |

### Layout Computation

Using vector notation, layout computation becomes intuitive and concise:

```julia
using DOPBrowser.ContentMM.MathOps

# Position calculation (vector form)
child.pos = parent.content_origin + Σ(preceding.total_size) ⊗ flow_dir + child.offset.start

# Where:
content_origin = pos + inset.start      # Vec2 - content box origin
flow_dir = direction_to_vec2(dir)       # Vec2 - unit vector (0,1) for :down
total_size = size + inset.total + offset.total  # Vec2 - total box size

# Example with actual values
parent_pos = Vec2(0.0, 0.0)
parent_inset = Box4(10.0)  # 10px all sides
child_size = Vec2(100.0, 50.0)

# Content origin (where children start)
content_origin = parent_pos + Vec2(10.0, 10.0)  # Vec2(10, 10)

# Child position for vertical stack
child.pos = content_origin + Vec2(0.0, 0.0)  # First child
child2.pos = content_origin + Vec2(0.0, child_size.y)  # Second child

# Total size calculation
total = child_size + total(Box4(10.0))  # Vec2(120, 70)
```

### Layout Equations Summary

| Equation | Vector Form | Description |
|----------|-------------|-------------|
| Position | `pos = parent.content + Σ(siblings) + offset.start` | Child placement |
| Content Origin | `content = pos + inset.start` | Where children go |
| Total Size | `total = size + inset.total + offset.total` | Full box size |
| Content Size | `content_size = size - inset.total` | Inner dimensions |

### Absolute Positioning

For absolute positioned nodes:

```julia
# Left-anchored
N.x = containing_block.x + N.css_left

# Right-anchored
N.x = containing_block.x + containing_block.width - N.width - N.css_right
```

## Node Types

### Layout Primitives

| Type | Description | CSS Equivalent |
|------|-------------|----------------|
| `Stack` | Flex container with direction | `display: flex` |
| `Grid` | 2D Cartesian layout | `display: grid` |
| `Scroll` | Viewport wrapper with overflow | `overflow: auto/scroll` |
| `Rect` | Simple colored rectangle | Background-only divs |

### Text Primitives

| Type | Description | CSS Equivalent |
|------|-------------|----------------|
| `Paragraph` | Text block (JIT shaping) | `<p>`, `<h1>`, etc. |
| `Span` | Inline text unit | `<span>`, `<a>`, etc. |
| `Link` | Interactive inline text | `<a href>` |
| `TextCluster` | GPU glyph run (internal) | - |

## Property System

### Direction (Stack containers)

| Value | CSS Equivalent | Flow |
|-------|---------------|------|
| `DIRECTION_DOWN` | `flex-direction: column` | Top to bottom |
| `DIRECTION_UP` | `flex-direction: column-reverse` | Bottom to top |
| `DIRECTION_RIGHT` | `flex-direction: row` | Left to right |
| `DIRECTION_LEFT` | `flex-direction: row-reverse` | Right to left |

### Pack (Main axis distribution)

| Value | CSS Equivalent |
|-------|---------------|
| `PACK_START` | `justify-content: flex-start` |
| `PACK_END` | `justify-content: flex-end` |
| `PACK_CENTER` | `justify-content: center` |
| `PACK_BETWEEN` | `justify-content: space-between` |
| `PACK_AROUND` | `justify-content: space-around` |
| `PACK_EVENLY` | `justify-content: space-evenly` |

### Align (Cross axis alignment)

| Value | CSS Equivalent |
|-------|---------------|
| `ALIGN_START` | `align-items: flex-start` |
| `ALIGN_END` | `align-items: flex-end` |
| `ALIGN_CENTER` | `align-items: center` |
| `ALIGN_STRETCH` | `align-items: stretch` |
| `ALIGN_BASELINE` | `align-items: baseline` |

## Source Mapping

For debugging, Content-- maintains bidirectional source maps:

```julia
struct SourceLocation
    source_type::SourceType    # HTML_ELEMENT, HTML_TEXT, CSS_RULE
    line::UInt32               # 1-based line number
    column::UInt32             # 1-based column number
    file_id::UInt32            # Interned filename
    selector_id::UInt32        # For CSS rules
end
```

This enables:
- DevTools inspection: Click Content-- node → See HTML source
- CSS debugging: Which rule affected which property
- Error reporting: Precise source locations

## AOT/JIT Hybrid Architecture

| Feature | Execution | Implementation |
|---------|-----------|----------------|
| Layout structure | AOT (compile time) | Pre-computed `.bin` files |
| Style resolution | AOT | Flattened inheritance |
| Text shaping | JIT (runtime) | On-demand for Paragraph |
| Event handling | JIT | WASM-based handlers |

### Why Hybrid?

- **Layout AOT**: Structure doesn't change often, pre-compute for performance
- **Text JIT**: Content changes, font availability varies, shape on demand
- **Events JIT**: User interaction is inherently dynamic

## Rendering Pipeline

```
Content-- Nodes
     ↓
[Layout Engine] ← Uses pre-computed properties
     ↓
Layout Boxes (x, y, width, height)
     ↓
[Render Command Generator]
     ↓
Command Buffer (rects, strokes, text)
     ↓
[GPU Renderer]
     ↓
Framebuffer
```

## Performance Characteristics

### Memory Layout (SoA)

All node data stored in Structure of Arrays for cache efficiency:

```julia
struct NodeTable
    node_types::Vector{NodeType}  # All types contiguous
    parents::Vector{UInt32}       # All parents contiguous
    widths::Vector{Float32}       # All widths contiguous
    # ... etc
end
```

Benefits:
- SIMD vectorization for layout computation
- Cache-friendly traversal
- Efficient batch updates

### Metadata-Driven Property Operations

Content-- uses metadata constants to define field operations, reducing code duplication and enabling efficient batch operations:

```julia
# Field metadata: (name, type, default_value)
const FLAT_STYLE_FIELDS = [
    (:direction, Direction, DIRECTION_DOWN),
    (:pack, Pack, PACK_START),
    (:width, Float32, 0.0f0),
    # ... etc
]

# Enables loop-based operations instead of repetitive code
for (name, T, default) in FLAT_STYLE_FIELDS
    getfield(table, name)[i] = default
end
```

Benefits:
- Single source of truth for field definitions
- Automatic type conversion via metadata
- Easy to add/remove fields across the system
- Reduced maintenance burden

### Zero Runtime CSS Cost

| Operation | CSS + DOM | Content-- |
|-----------|-----------|-----------|
| Get computed style | O(cascade) | O(1) |
| Check selector match | O(selectors) | N/A |
| Layout node | + style lookup | Direct property access |

## Example: HTML to Content-- Lowering

### Input (HTML/CSS)

```html
<div style="margin: 20px; padding: 10px; border: 2px solid red; 
            background: yellow; width: 100px; height: 50px;">
  Hello
</div>
```

### Output (Content-- pseudocode)

```
Stack {
    offset: (20, 20, 20, 20)     # margin
    inset: (10, 10, 10, 10)      # padding
    stroke: {
        width: (2, 2, 2, 2)     # border-width
        color: #FF0000FF        # red
        style: solid
    }
    fill: #FFFF00FF             # yellow
    size: (100, 50)
    
    children: [
        Span {
            text_content: "Hello"
        }
    ]
}
```

## Input Methods

Content-- supports two input methods, each suited for different use cases:

### 1. HTML & CSS (Source Language)

The traditional web authoring format. HTML and CSS are lowered to Content-- through the `HTMLLowering` module.

```julia
using DOPBrowser

browser = Browser(width=UInt32(800), height=UInt32(600))
load_html!(browser, """
<div style="width: 200px; height: 200px; background-color: red;"></div>
""")
render_to_png!(browser, "output.png")
```

### 2. Content Text Format (Native)

A human-readable text format for direct Content-- authoring. Ideal for:
- Native application UIs
- Design system prototyping
- Unit testing UI components

#### Syntax

```
NodeType(Prop1: Value1, Prop2: Value2) {
    ChildNode(...) { ... }
}
```

#### Example

```
Stack(Direction: Down, Fill: #FFFFFF, Inset: 20) {
    Rect(Size: (200, 100), Fill: #FF0000);
    Stack(Direction: Right, Gap: 10) {
        Rect(Size: (50, 50), Fill: #00FF00);
        Rect(Size: (50, 50), Fill: #0000FF);
    }
    Paragraph {
        Span(Text: "Hello World");
    }
}
```

#### Node Types

| Node Type | Description |
|-----------|-------------|
| `Stack` | Flex container with Direction, Pack, Align |
| `Grid` | 2D Cartesian layout with Cols, Rows |
| `Scroll` | Viewport with overflow scrolling |
| `Rect` | Simple colored rectangle |
| `Paragraph` | Text block container |
| `Span` | Inline text with optional styling |
| `Link` | Interactive link element |

#### Properties

| Property | Values | Description |
|----------|--------|-------------|
| `Direction` | Down, Up, Right, Left | Flow direction |
| `Pack` | Start, End, Center, Between, Around, Evenly | Main axis distribution |
| `Align` | Start, End, Center, Stretch, Baseline | Cross axis alignment |
| `Size` | `(width, height)` or single value | Dimensions in pixels |
| `Width` | number | Width in pixels |
| `Height` | number | Height in pixels |
| `Inset` | `(top, right, bottom, left)` or single value | Padding (inside spacing) |
| `Offset` | `(top, right, bottom, left)` or single value | Margin (outside spacing) |
| `Fill` | `#RRGGBB` or named color | Background color |
| `Gap` | `(row, column)` or single value | Spacing between children |
| `Text` | `"string"` | Text content for Span |
| `Cols` | number | Grid columns |
| `Rows` | number | Grid rows |
| `Round` | number | Border radius |

#### Usage in Julia

```julia
using DOPBrowser.ContentMM.NativeUI

# Create UI from text
ui = create_ui(\"\"\"
    Stack(Direction: Down, Fill: #FFFFFF) {
        Rect(Size: (200, 100), Fill: #FF0000);
    }
\"\"\")

# Render to PNG
render_to_png!(ui, "output.png", width=800, height=600)

# Or get raw pixel buffer
buffer = render_to_buffer(ui, width=800, height=600)
```

## Native UI Library

The `NativeUI` module provides a high-level API for using Content-- in native applications.

### Programmatic Builder API

```julia
using DOPBrowser.ContentMM.NativeUI

builder = UIBuilder()
with_stack!(builder, direction=:down, fill="#FFFFFF") do
    rect!(builder, width=200.0f0, height=100.0f0, fill="#FF0000")
    with_paragraph!(builder) do
        span!(builder, text="Hello World")
    end
end

ctx = get_context(builder)
render_to_png!(ctx, "output.png", width=800, height=600)
```

### Pixel Comparison Testing

For visual regression testing:

```julia
using DOPBrowser.ContentMM.NativeUI

ui = create_ui("Rect(Size: (100, 100), Fill: #FF0000)")

# Compare with reference image
result = compare_pixels(ui, "reference.png", width=800, height=600, tolerance=0)

if result.match
    println("Images match!")
else
    println("Mismatch: $(result.diff_count) pixels differ")
    println("Match ratio: $(result.match_ratio)")
    
    # Save diff visualization
    save_diff_image(ui, "reference.png", "diff.png", width=800, height=600)
end
```

#### PixelComparisonResult

| Field | Type | Description |
|-------|------|-------------|
| `match` | Bool | True if images match within tolerance |
| `match_ratio` | Float64 | Ratio of matching pixels (0.0 to 1.0) |
| `diff_count` | Int | Number of differing pixels |
| `total_pixels` | Int | Total number of pixels |
| `max_diff` | Int | Maximum difference in any color channel |

## Future Directions

1. **Binary format**: Serialize Content-- to `.cmm` files for faster loading
2. **Incremental updates**: Diff-based patching for dynamic content
3. **WebGPU compute**: GPU-based layout for large documents
4. **WASM integration**: Portable runtime for any platform

---

*Content-- is designed to make browsers faster by eliminating runtime CSS complexity while maintaining perfect compatibility with HTML/CSS authoring.*
