"""
Entry point for StaticCompiler-compiled memo application.
This file provides a C-compatible entry point that can be compiled without the Julia runtime.
"""

using StaticCompiler
using StaticTools

# Import the basic memo functionality
using DOPBrowser.RustRenderer: RustRendererHandle, create_renderer, destroy!,
    set_clear_color!, add_rect!, add_text!, render!, export_png!
using DOPBrowser.ApplicationUtils: parse_hex_color

# Simple memo structure compatible with static compilation
struct SimpleMemo
    id::Int32
    title_ptr::Ptr{UInt8}
    title_len::Int64
    color_r::Float32
    color_g::Float32
    color_b::Float32
end

"""
    static_render_memo() -> Int32

Simple static entry point for rendering a single memo to PNG.
Returns 0 on success, 1 on failure.
"""
function static_render_memo()::Int32
    try
        # Create a simple renderer (400x600)
        renderer = create_renderer(400, 600)
        
        # Set background color
        set_clear_color!(renderer, 0.96f0, 0.96f0, 0.96f0, 1.0f0)
        
        # Add a simple title text
        add_text!(renderer, "Static Memo App", 20.0f0, 20.0f0; 
                  font_size=24.0, r=0.13, g=0.13, b=0.13, a=1.0)
        
        # Add a simple card background
        add_rect!(renderer, 20.0f0, 60.0f0, 360.0f0, 100.0f0,
                 1.0, 1.0, 1.0, 1.0)
        
        # Add card title
        add_text!(renderer, "Sample Note", 35.0f0, 75.0f0;
                 font_size=18.0, r=0.1, g=0.46, b=0.82, a=1.0)
        
        # Add card content
        add_text!(renderer, "This memo was rendered", 35.0f0, 100.0f0;
                 font_size=14.0, r=0.26, g=0.26, b=0.26, a=1.0)
        add_text!(renderer, "by a statically compiled", 35.0f0, 118.0f0;
                 font_size=14.0, r=0.26, g=0.26, b=0.26, a=1.0)
        add_text!(renderer, "Julia application!", 35.0f0, 136.0f0;
                 font_size=14.0, r=0.26, g=0.26, b=0.26, a=1.0)
        
        # Render
        render!(renderer)
        
        # Export to PNG
        success = export_png!(renderer, "static_memo_output.png")
        
        # Cleanup
        destroy!(renderer)
        
        return success ? Int32(0) : Int32(1)
    catch e
        return Int32(1)
    end
end

"""
    c_main() -> Int32

C-compatible main entry point for static compilation.
"""
Base.@ccallable function c_main()::Int32
    return static_render_memo()
end
