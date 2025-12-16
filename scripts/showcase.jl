#!/usr/bin/env julia
"""
    DOPBrowser Rendering Showcase

This script demonstrates both rendering approaches available in DOPBrowser:

1. **Browser Rendering (HTML+CSS)**: Traditional web content rendering
2. **NativeUI with Content-- Text Format**: High-performance native UI rendering

Both approaches can use either:
- GPU Renderer: Software-based WebGPU-style rendering
- Cairo Renderer: Vector graphics with high-quality text rendering via FreeTypeAbstraction

## Usage
```julia
julia --project=. scripts/showcase.jl
```

This will generate several PNG files demonstrating different rendering capabilities.
"""

using DOPBrowser
using DOPBrowser.ContentMM.NativeUI

# Ensure output directory exists
const OUTPUT_DIR = joinpath(@__DIR__, "..", "showcase_output")
mkpath(OUTPUT_DIR)

println("=" ^ 60)
println("DOPBrowser Rendering Showcase")
println("=" ^ 60)
println()

# ============================================================================
# Part 1: Browser HTML+CSS Rendering
# ============================================================================

println("Part 1: Browser HTML+CSS Rendering")
println("-" ^ 40)

# Example 1: Simple colored boxes
println("  → Rendering: Simple colored boxes (HTML+CSS)")
browser = Browser(width=UInt32(400), height=UInt32(300))

html_boxes = """
<!DOCTYPE html>
<html>
<head>
    <title>Colored Boxes</title>
    <style>
        body { 
            background-color: white; 
            margin: 20px; 
        }
        .container {
            position: relative;
            width: 360px;
            height: 260px;
        }
        .box {
            position: absolute;
            width: 80px;
            height: 80px;
        }
        .red { background-color: #FF0000; top: 0; left: 0; }
        .green { background-color: #00FF00; top: 0; left: 90px; }
        .blue { background-color: #0000FF; top: 0; left: 180px; }
        .yellow { background-color: #FFFF00; top: 90px; left: 45px; }
        .cyan { background-color: #00FFFF; top: 90px; left: 135px; }
        .magenta { background-color: #FF00FF; top: 180px; left: 90px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="box red"></div>
        <div class="box green"></div>
        <div class="box blue"></div>
        <div class="box yellow"></div>
        <div class="box cyan"></div>
        <div class="box magenta"></div>
    </div>
</body>
</html>
"""

load_html!(browser, html_boxes)
render_to_png!(browser, joinpath(OUTPUT_DIR, "html_colored_boxes.png"))
println("    ✓ Saved: html_colored_boxes.png")

# Example 2: Nested layouts
println("  → Rendering: Nested layouts with borders (HTML+CSS)")
browser2 = Browser(width=UInt32(500), height=UInt32(400))

html_nested = """
<!DOCTYPE html>
<html>
<head>
    <style>
        .outer {
            width: 460px;
            height: 360px;
            background-color: #f0f0f0;
            padding: 10px;
        }
        .row {
            display: block;
            margin-bottom: 10px;
        }
        .card {
            width: 140px;
            height: 100px;
            background-color: white;
            border: 2px solid #333;
            margin-right: 10px;
            display: inline-block;
        }
        .header {
            background-color: #4a90d9;
            height: 30px;
        }
    </style>
</head>
<body style="margin: 10px;">
    <div class="outer">
        <div class="row">
            <div class="card"><div class="header"></div></div>
            <div class="card"><div class="header"></div></div>
            <div class="card"><div class="header"></div></div>
        </div>
        <div class="row">
            <div class="card"><div class="header"></div></div>
            <div class="card"><div class="header"></div></div>
            <div class="card"><div class="header"></div></div>
        </div>
    </div>
</body>
</html>
"""

load_html!(browser2, html_nested)
render_to_png!(browser2, joinpath(OUTPUT_DIR, "html_nested_layouts.png"))
println("    ✓ Saved: html_nested_layouts.png")

# Example 3: Acid2-style face
println("  → Rendering: Smiley face (HTML+CSS)")
browser3 = Browser(width=UInt32(300), height=UInt32(350))

html_face = """
<!DOCTYPE html>
<html>
<body style="background-color: white; margin: 20px;">
    <div style="position: relative; width: 250px; height: 250px; 
                background-color: #FFCC00; border-radius: 125px;">
        <!-- Left eye -->
        <div style="position: absolute; top: 60px; left: 60px; 
                    width: 30px; height: 30px; background-color: black;
                    border-radius: 15px;"></div>
        <!-- Right eye -->
        <div style="position: absolute; top: 60px; right: 60px;
                    width: 30px; height: 30px; background-color: black;
                    border-radius: 15px;"></div>
        <!-- Mouth -->
        <div style="position: absolute; top: 140px; left: 50px;
                    width: 150px; height: 40px; background-color: #CC0000;
                    border-radius: 0 0 75px 75px;"></div>
    </div>
</body>
</html>
"""

load_html!(browser3, html_face)
render_to_png!(browser3, joinpath(OUTPUT_DIR, "html_smiley_face.png"))
println("    ✓ Saved: html_smiley_face.png")

println()

# ============================================================================
# Part 2: NativeUI with Content-- Text Format (GPU Renderer)
# ============================================================================

println("Part 2: NativeUI with Content-- Text Format (GPU Renderer)")
println("-" ^ 40)

# Example 1: Simple Stack layout
println("  → Rendering: Stack layout (Content--)")
ui_stack = create_ui("""
Stack(Direction: Down, Fill: #FFFFFF, Inset: 20) {
    Rect(Size: (300, 60), Fill: #FF6B6B);
    Rect(Size: (300, 60), Fill: #4ECDC4);
    Rect(Size: (300, 60), Fill: #45B7D1);
    Rect(Size: (300, 60), Fill: #96CEB4);
}
""")
render_to_png!(ui_stack, joinpath(OUTPUT_DIR, "contentmm_stack.png"), width=400, height=320)
println("    ✓ Saved: contentmm_stack.png")

# Example 2: Grid-like layout using nested stacks
println("  → Rendering: Grid layout (Content--)")
ui_grid = create_ui("""
Stack(Direction: Down, Fill: #1A1A2E, Inset: 15, Gap: 10) {
    Stack(Direction: Right, Gap: 10) {
        Rect(Size: (90, 90), Fill: #E94560);
        Rect(Size: (90, 90), Fill: #0F3460);
        Rect(Size: (90, 90), Fill: #16213E);
    }
    Stack(Direction: Right, Gap: 10) {
        Rect(Size: (90, 90), Fill: #16213E);
        Rect(Size: (90, 90), Fill: #E94560);
        Rect(Size: (90, 90), Fill: #0F3460);
    }
    Stack(Direction: Right, Gap: 10) {
        Rect(Size: (90, 90), Fill: #0F3460);
        Rect(Size: (90, 90), Fill: #16213E);
        Rect(Size: (90, 90), Fill: #E94560);
    }
}
""")
render_to_png!(ui_grid, joinpath(OUTPUT_DIR, "contentmm_grid.png"), width=350, height=350)
println("    ✓ Saved: contentmm_grid.png")

# Example 3: Color palette
println("  → Rendering: Color palette (Content--)")
ui_palette = create_ui("""
Stack(Direction: Down, Fill: #2C3E50, Inset: 20, Gap: 5) {
    Stack(Direction: Right, Gap: 5) {
        Rect(Size: (50, 50), Fill: #E74C3C);
        Rect(Size: (50, 50), Fill: #E67E22);
        Rect(Size: (50, 50), Fill: #F1C40F);
        Rect(Size: (50, 50), Fill: #2ECC71);
        Rect(Size: (50, 50), Fill: #3498DB);
        Rect(Size: (50, 50), Fill: #9B59B6);
    }
    Stack(Direction: Right, Gap: 5) {
        Rect(Size: (50, 50), Fill: #C0392B);
        Rect(Size: (50, 50), Fill: #D35400);
        Rect(Size: (50, 50), Fill: #F39C12);
        Rect(Size: (50, 50), Fill: #27AE60);
        Rect(Size: (50, 50), Fill: #2980B9);
        Rect(Size: (50, 50), Fill: #8E44AD);
    }
    Stack(Direction: Right, Gap: 5) {
        Rect(Size: (50, 50), Fill: #ECF0F1);
        Rect(Size: (50, 50), Fill: #BDC3C7);
        Rect(Size: (50, 50), Fill: #95A5A6);
        Rect(Size: (50, 50), Fill: #7F8C8D);
        Rect(Size: (50, 50), Fill: #34495E);
        Rect(Size: (50, 50), Fill: #1ABC9C);
    }
}
""")
render_to_png!(ui_palette, joinpath(OUTPUT_DIR, "contentmm_palette.png"), width=400, height=230)
println("    ✓ Saved: contentmm_palette.png")

println()

# ============================================================================
# Part 3: Cairo Rendering with Text (High-Quality)
# ============================================================================

println("Part 3: Cairo Rendering with Text (FreeTypeAbstraction)")
println("-" ^ 40)

# Example 1: Text in boxes
println("  → Rendering: Text in colored boxes (Cairo)")
ui_text_boxes = create_ui("""
Stack(Direction: Down, Fill: #FFFFFF, Inset: 20, Gap: 15) {
    Rect(Size: (350, 80), Fill: #3498DB) {
        Paragraph { Span(Text: "Hello, World!"); }
    }
    Rect(Size: (350, 80), Fill: #2ECC71) {
        Paragraph { Span(Text: "Content-- Text Format"); }
    }
    Rect(Size: (350, 80), Fill: #E74C3C) {
        Paragraph { Span(Text: "Cairo + FreeType Rendering"); }
    }
}
""")
render_to_png_cairo!(ui_text_boxes, joinpath(OUTPUT_DIR, "cairo_text_boxes.png"), width=420, height=340)
println("    ✓ Saved: cairo_text_boxes.png")

# Example 2: Multi-paragraph text
println("  → Rendering: Multi-paragraph text (Cairo)")
ui_paragraphs = create_ui("""
Stack(Direction: Down, Fill: #F8F9FA, Inset: 25, Gap: 20) {
    Rect(Size: (400, 50), Fill: #343A40) {
        Paragraph { Span(Text: "DOPBrowser Showcase"); }
    }
    Paragraph { 
        Span(Text: "This is the first paragraph with some text."); 
    }
    Paragraph { 
        Span(Text: "The second paragraph demonstrates text flow."); 
    }
    Paragraph { 
        Span(Text: "Cairo provides high-quality vector graphics."); 
    }
    Rect(Size: (400, 3), Fill: #DEE2E6);
    Paragraph { 
        Span(Text: "FreeTypeAbstraction handles font rendering."); 
    }
}
""")
render_to_png_cairo!(ui_paragraphs, joinpath(OUTPUT_DIR, "cairo_paragraphs.png"), width=500, height=350)
println("    ✓ Saved: cairo_paragraphs.png")

# Example 3: UI Card with text
println("  → Rendering: UI Card design (Cairo)")
ui_card = create_ui("""
Stack(Direction: Down, Fill: #ECEFF1, Inset: 30, Gap: 0) {
    Stack(Direction: Down, Fill: #FFFFFF, Inset: 20, Gap: 10, Round: 8) {
        Rect(Size: (340, 150), Fill: #1976D2);
        Paragraph { Span(Text: "Material Design Card"); }
        Paragraph { Span(Text: "This is a sample card component"); }
        Paragraph { Span(Text: "built using Content-- text format."); }
        Stack(Direction: Right, Gap: 10) {
            Rect(Size: (80, 35), Fill: #2196F3);
            Rect(Size: (80, 35), Fill: #E0E0E0);
        }
    }
}
""")
render_to_png_cairo!(ui_card, joinpath(OUTPUT_DIR, "cairo_card.png"), width=440, height=380)
println("    ✓ Saved: cairo_card.png")

println()

# ============================================================================
# Part 4: Programmatic UI Builder
# ============================================================================

println("Part 4: Programmatic UI Builder")
println("-" ^ 40)

println("  → Rendering: Programmatic layout (Builder API)")
builder = UIBuilder()

with_stack!(builder, direction=:down, fill="#FAFAFA", inset=20.0f0, gap=10.0f0) do
    rect!(builder, width=250.0f0, height=50.0f0, fill="#673AB7")
    with_stack!(builder, direction=:row, gap=10.0f0) do
        rect!(builder, width=120.0f0, height=120.0f0, fill="#9C27B0")
        rect!(builder, width=120.0f0, height=120.0f0, fill="#E91E63")
    end
    with_stack!(builder, direction=:row, gap=10.0f0) do
        rect!(builder, width=80.0f0, height=80.0f0, fill="#F44336")
        rect!(builder, width=80.0f0, height=80.0f0, fill="#FF5722")
        rect!(builder, width=80.0f0, height=80.0f0, fill="#FF9800")
    end
    rect!(builder, width=250.0f0, height=30.0f0, fill="#FFC107")
end

ctx = get_context(builder)
render_to_png!(ctx, joinpath(OUTPUT_DIR, "builder_programmatic.png"), width=320, height=380)
println("    ✓ Saved: builder_programmatic.png")

println()

# ============================================================================
# Summary
# ============================================================================

println("=" ^ 60)
println("Showcase Complete!")
println("=" ^ 60)
println()
println("Generated files in: $OUTPUT_DIR")
println()
println("Files generated:")
for f in readdir(OUTPUT_DIR)
    if endswith(f, ".png")
        size = filesize(joinpath(OUTPUT_DIR, f))
        println("  • $f ($(round(size/1024, digits=1)) KB)")
    end
end
println()
println("Rendering Methods Demonstrated:")
println("  1. Browser HTML+CSS → GPU Renderer → PNG")
println("  2. Content-- Text Format → GPU Renderer → PNG")
println("  3. Content-- Text Format → Cairo/FreeType → PNG")
println("  4. Programmatic Builder API → GPU Renderer → PNG")
println()
