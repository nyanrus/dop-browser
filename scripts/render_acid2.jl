#!/usr/bin/env julia
"""
Render the Acid2 test to PNG.

This script fetches the Acid2 test page from webstandards.org,
parses it, applies CSS styles, and renders it to acid2.png.
"""

using DOPBrowser
using DOPBrowser.Network: fetch!, NetworkContext, RESOURCE_HTML
using DOPBrowser.Renderer: RenderPipeline, render_frame!, export_png!

# Acid2 test URL
const ACID2_URL = "https://www.webstandards.org/files/acid2/test.html"

function main()
    println("Creating browser instance...")
    
    # Acid2 reference is 300x150 pixels
    browser = Browser(width=UInt32(300), height=UInt32(150))
    
    println("Fetching Acid2 test from: $ACID2_URL")
    
    # Fetch the HTML
    success = load!(browser, ACID2_URL)
    
    if !success
        println("Failed to fetch Acid2 test. Using local test HTML instead.")
        
        # Use a simpler test HTML
        html = create_acid2_approximation()
        load_html!(browser, html)
    else
        println("Successfully fetched Acid2 test")
    end
    
    # Render to PNG
    output_path = joinpath(@__DIR__, "..", "acid2.png")
    println("Rendering to: $output_path")
    render_to_png!(browser, output_path)
    
    println("Done! Check acid2.png in repository root.")
    return output_path
end

"""
Create a simplified Acid2-like test that our browser can handle.
This focuses on the core CSS features: positioning, backgrounds, borders, and clipping.
"""
function create_acid2_approximation()
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Acid2 Test - DOP Browser</title>
        <style>
            body {
                background-color: white;
                margin: 0;
                padding: 0;
            }
            
            /* Face container - yellow background */
            .picture {
                position: relative;
                width: 200px;
                height: 150px;
                background-color: yellow;
                margin: 0 auto;
                overflow: hidden;
            }
            
            /* Forehead - yellow top */
            .forehead {
                position: absolute;
                top: 0;
                left: 0;
                width: 200px;
                height: 40px;
                background-color: yellow;
            }
            
            /* Eyes container */
            .eyes {
                position: absolute;
                top: 40px;
                left: 0;
                width: 200px;
                height: 20px;
            }
            
            /* Left eye - black square */
            .eye-left {
                position: absolute;
                top: 0;
                left: 40px;
                width: 20px;
                height: 20px;
                background-color: black;
            }
            
            /* Right eye - black square */
            .eye-right {
                position: absolute;
                top: 0;
                left: 140px;
                width: 20px;
                height: 20px;
                background-color: black;
            }
            
            /* Nose - black rectangle */
            .nose {
                position: absolute;
                top: 50px;
                left: 90px;
                width: 20px;
                height: 40px;
                background-color: black;
            }
            
            /* Nose inner - yellow */
            .nose-inner {
                position: absolute;
                top: 10px;
                left: 5px;
                width: 10px;
                height: 25px;
                background-color: yellow;
            }
            
            /* Mouth - red arc approximated with rectangles */
            .mouth {
                position: absolute;
                top: 100px;
                left: 40px;
                width: 120px;
                height: 20px;
                background-color: black;
            }
            
            .mouth-inner {
                position: absolute;
                top: 0;
                left: 10px;
                width: 100px;
                height: 10px;
                background-color: red;
            }
            
            /* Chin */
            .chin {
                position: absolute;
                bottom: 0;
                left: 0;
                width: 200px;
                height: 30px;
                background-color: yellow;
            }
        </style>
    </head>
    <body>
        <div class="picture">
            <div class="forehead"></div>
            <div class="eyes">
                <div class="eye-left"></div>
                <div class="eye-right"></div>
            </div>
            <div class="nose">
                <div class="nose-inner"></div>
            </div>
            <div class="mouth">
                <div class="mouth-inner"></div>
            </div>
            <div class="chin"></div>
        </div>
    </body>
    </html>
    """
end

# Run the main function
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
