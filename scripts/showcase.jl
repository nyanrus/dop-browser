#!/usr/bin/env julia
"""
    DOPBrowser Rendering Showcase

This script demonstrates the HTML+CSS rendering capability of DOPBrowser:

**Browser Rendering (HTML+CSS)**: Traditional web content rendering using the legacy pipeline

For modern UI construction examples, see:
- examples/memo_app.jl - RustContent builder API
- examples/interactive_ui_examples.jl - Application/Widgets framework

## Usage
```julia
julia --project=. scripts/showcase.jl
```

This will generate several PNG files demonstrating HTML/CSS rendering capabilities.
"""

using DOPBrowser

# Ensure output directory exists
const OUTPUT_DIR = joinpath(@__DIR__, "..", "showcase_output")
mkpath(OUTPUT_DIR)

println("=" ^ 60)
println("DOPBrowser Rendering Showcase")
println("=" ^ 60)
println()

# ============================================================================
# Browser HTML+CSS Rendering
# ============================================================================

println("Browser HTML+CSS Rendering")
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
println("For more rendering examples, see:")
println("  • examples/memo_app.jl - RustContent builder API")
println("  • examples/interactive_ui_examples.jl - Application/Widgets framework")
println()
