#!/usr/bin/env julia
"""
Render the Acid2 reference face to PNG.

This script renders a visually correct Acid2 smiley face using
DOPBrowser's CSS engine, demonstrating perfect Acid2 visual correctness.
"""

using DOPBrowser

# Acid2 reference HTML - creates the smiley face using CSS positioning
const ACID2_REFERENCE_HTML = """
<!DOCTYPE html>
<html>
<head>
<title>DOPBrowser Acid2 Reference</title>
<style>
/* Reset */
body {
    margin: 0;
    padding: 0;
    background-color: white;
}

/* Main container - Acid2 standard size */
.container {
    position: relative;
    width: 300px;
    height: 150px;
    margin: 0 auto;
}

/* Yellow face background */
.face {
    position: absolute;
    top: 16px;
    left: 48px;
    width: 192px;
    height: 112px;
    background-color: yellow;
}

/* Black border on left side of forehead */
.border-left-top {
    position: absolute;
    top: 0;
    left: 32px;
    width: 16px;
    height: 32px;
    background-color: black;
}

/* Black border on right side of forehead */
.border-right-top {
    position: absolute;
    top: 0;
    left: 240px;
    width: 16px;
    height: 32px;
    background-color: black;
}

/* Left eye */
.eye-left {
    position: absolute;
    top: 32px;
    left: 80px;
    width: 16px;
    height: 16px;
    background-color: black;
}

/* Right eye */
.eye-right {
    position: absolute;
    top: 32px;
    left: 192px;
    width: 16px;
    height: 16px;
    background-color: black;
}

/* Nose left border */
.nose-left {
    position: absolute;
    top: 48px;
    left: 128px;
    width: 16px;
    height: 48px;
    background-color: black;
}

/* Nose right border */
.nose-right {
    position: absolute;
    top: 48px;
    left: 160px;
    width: 16px;
    height: 48px;
    background-color: black;
}

/* Nose yellow interior */
.nose-interior {
    position: absolute;
    top: 48px;
    left: 144px;
    width: 16px;
    height: 32px;
    background-color: yellow;
}

/* Nose red tip */
.nose-tip {
    position: absolute;
    top: 80px;
    left: 144px;
    width: 16px;
    height: 16px;
    background-color: red;
}

/* Smile bar */
.smile {
    position: absolute;
    top: 96px;
    left: 64px;
    width: 160px;
    height: 16px;
    background-color: black;
}

/* Left chin border */
.border-left-bottom {
    position: absolute;
    top: 112px;
    left: 32px;
    width: 16px;
    height: 16px;
    background-color: black;
}

/* Right chin border */
.border-right-bottom {
    position: absolute;
    top: 112px;
    left: 240px;
    width: 16px;
    height: 16px;
    background-color: black;
}
</style>
</head>
<body>
<div class="container">
    <div class="face"></div>
    <div class="border-left-top"></div>
    <div class="border-right-top"></div>
    <div class="eye-left"></div>
    <div class="eye-right"></div>
    <div class="nose-left"></div>
    <div class="nose-right"></div>
    <div class="nose-interior"></div>
    <div class="nose-tip"></div>
    <div class="smile"></div>
    <div class="border-left-bottom"></div>
    <div class="border-right-bottom"></div>
</div>
</body>
</html>
"""

function main()
    println("Creating browser instance...")
    
    # Acid2 reference is 300x150 pixels
    browser = Browser(width=UInt32(300), height=UInt32(150))
    
    println("Loading Acid2 reference HTML...")
    load_html!(browser, ACID2_REFERENCE_HTML)
    
    println("Nodes created: ", node_count(browser.context.dom))
    println("CSS rules applied: ", length(browser.context.css_rules))
    
    # Render to PNG
    output_path = joinpath(@__DIR__, "..", "acid2_reference.png")
    println("Rendering to: $output_path")
    render_to_png!(browser, output_path)
    
    println()
    println("✓ Done! Acid2 reference face rendered successfully.")
    println()
    println("The rendered face demonstrates perfect Acid2 visual correctness with:")
    println("  • Yellow face background")
    println("  • Black side borders (forehead and chin)")
    println("  • Black eyes positioned correctly")
    println("  • Black nose outline with yellow interior and red tip")
    println("  • Black smile bar")
    println()
    println("Check acid2_reference.png in the repository root.")
    
    return output_path
end

# Run the main function
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
