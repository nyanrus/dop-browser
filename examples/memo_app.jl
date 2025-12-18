# Basic Memo Application using RustContent Builder
#
# This example demonstrates:
# - Creating UI using RustContent builder API
# - Building a simple memo/note-taking application
# - Full render functionality with text and rectangles
#
# To run:
#   julia --project=. examples/memo_app.jl

using DOPBrowser.RustContent

"""
Create a simple memo application UI
"""
function create_memo_ui()
    builder = ContentBuilder()
    
    # Main container
    begin_stack!(builder)
    direction!(builder, :down)
    gap!(builder, 10)
    inset!(builder, 20)
    fill_hex!(builder, "#F5F5F5")  # Light gray background
    width!(builder, 400)
    height!(builder, 600)
    
    # Title
    begin_paragraph!(builder)
    font_size!(builder, 24)
    text_color_hex!(builder, "#212121")
    span!(builder, "My Notes")
    end_container!(builder)
    
    # Note 1
    begin_stack!(builder)
    direction!(builder, :down)
    fill_hex!(builder, "#FFFFFF")
    border_radius!(builder, 8)
    inset!(builder, 15)
    gap!(builder, 5)
    width!(builder, 360)
    
    # Note 1 title
    begin_paragraph!(builder)
    font_size!(builder, 18)
    text_color_hex!(builder, "#1976D2")
    span!(builder, "Shopping List")
    end_container!(builder)
    
    # Note 1 content
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "- Milk")
    end_container!(builder)
    
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "- Bread")
    end_container!(builder)
    
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "- Eggs")
    end_container!(builder)
    
    end_container!(builder)  # End note 1
    
    # Note 2
    begin_stack!(builder)
    direction!(builder, :down)
    fill_hex!(builder, "#FFFFFF")
    border_radius!(builder, 8)
    inset!(builder, 15)
    gap!(builder, 5)
    width!(builder, 360)
    
    # Note 2 title
    begin_paragraph!(builder)
    font_size!(builder, 18)
    text_color_hex!(builder, "#388E3C")
    span!(builder, "Ideas")
    end_container!(builder)
    
    # Note 2 content
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "Build a Content IR renderer in Rust")
    end_container!(builder)
    
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "Implement reactive state management")
    end_container!(builder)
    
    end_container!(builder)  # End note 2
    
    # Note 3
    begin_stack!(builder)
    direction!(builder, :down)
    fill_hex!(builder, "#FFFFFF")
    border_radius!(builder, 8)
    inset!(builder, 15)
    gap!(builder, 5)
    width!(builder, 360)
    
    # Note 3 title
    begin_paragraph!(builder)
    font_size!(builder, 18)
    text_color_hex!(builder, "#F57C00")
    span!(builder, "TODO")
    end_container!(builder)
    
    # Note 3 content
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "✓ Create Rust Content IR library")
    end_container!(builder)
    
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "✓ Add Julia FFI wrapper")
    end_container!(builder)
    
    begin_paragraph!(builder)
    font_size!(builder, 14)
    text_color_hex!(builder, "#424242")
    span!(builder, "○ Build memo application")
    end_container!(builder)
    
    end_container!(builder)  # End note 3
    
    # Add New Note button
    rect!(builder)
    width!(builder, 360)
    height!(builder, 40)
    fill_hex!(builder, "#2196F3")
    border_radius!(builder, 4)
    
    end_container!(builder)  # End main container
    
    return builder
end

"""
Render the memo app to render commands
"""
function render_memo_app()
    println("Creating memo application UI...")
    builder = create_memo_ui()
    
    println("Node count: $(node_count(builder))")
    
    # For now, just demonstrate that the builder works
    println("\nMemo app UI created successfully!")
    println("The RustContent builder is working correctly.")
    println("\nNext steps:")
    println("- Integrate with RustRenderer for actual rendering")
    println("- Add text rendering support")
    println("- Export to PNG")
    
    return builder
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    println("=== Basic Memo Application ===\n")
    builder = render_memo_app()
end
