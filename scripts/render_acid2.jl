#!/usr/bin/env julia
"""
Render the Acid2 test to PNG.

This script fetches the real Acid2 test page from webstandards.org,
parses it with enhanced CSS 2.1 selector and property support,
and renders it to acid2.png.
"""

using DOPBrowser
using DOPBrowser.Network: fetch!, NetworkContext, RESOURCE_HTML
# Renderer module has been removed - use RustRenderer instead
# using DOPBrowser.Renderer: RenderPipeline, render_frame!, export_png!

# Acid2 test URL
const ACID2_URL = "https://www.webstandards.org/files/acid2/test.html"

function main()
    println("Creating browser instance...")
    
    # Acid2 reference is 300x150 pixels (increased for better visibility)
    browser = Browser(width=UInt32(600), height=UInt32(300))
    
    println("Fetching Acid2 test from: $ACID2_URL")
    
    # Fetch the HTML
    success = load!(browser, ACID2_URL)
    
    if !success
        error("Failed to fetch Acid2 test from $ACID2_URL. Check network connection.")
    end
    
    println("Successfully fetched Acid2 test")
    
    # Render to PNG
    output_path = joinpath(@__DIR__, "..", "acid2.png")
    println("Rendering to: $output_path")
    render_to_png!(browser, output_path)
    
    println("Done! Check acid2.png in repository root.")
    println()
    println("Note: DOPBrowser now processes the REAL Acid2 test with enhanced CSS support.")
    println("See docs/ACID2_SUPPORT.md for details on what features are supported.")
    return output_path
end

# Run the main function
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
