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

Content-- uses a simple coordinate system:

```
Origin (0, 0) at top-left of viewport
├── X-axis: Increases rightward →
├── Y-axis: Increases downward ↓
└── All values: Float32 in device pixels
```

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

For a node N with parent P in normal flow:

```julia
# Position calculation
N.x = P.content_x + N.offset_left + Σ(preceding_sibling.total_width)
N.y = P.content_y + N.offset_top + Σ(preceding_sibling.total_height)

# Content box (where children are placed)
P.content_x = P.x + P.inset_left + P.stroke_left
P.content_y = P.y + P.inset_top + P.stroke_top

# Total size (for sibling calculation)
N.total_width = N.width + N.offset_left + N.offset_right
N.total_height = N.height + N.offset_top + N.offset_bottom
```

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

## Future Directions

1. **Binary format**: Serialize Content-- to `.cmm` files for faster loading
2. **Incremental updates**: Diff-based patching for dynamic content
3. **WebGPU compute**: GPU-based layout for large documents
4. **WASM integration**: Portable runtime for any platform

---

*Content-- is designed to make browsers faster by eliminating runtime CSS complexity while maintaining perfect compatibility with HTML/CSS authoring.*
