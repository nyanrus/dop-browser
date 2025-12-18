# Complete Memo Application with Interactive UI
#
# This example demonstrates a full memo/note-taking application with:
# - Text rendering using RustRenderer
# - Reactive state management for memos
# - User interaction (add/delete memos)
# - Re-rendering on state changes
# - Both headless (PNG export) and onscreen modes
#
# To run:
#   julia --project=. examples/memo_app.jl
#
# To run in headless mode (for testing/CI):
#   HEADLESS=1 julia --project=. examples/memo_app.jl

using DOPBrowser
using DOPBrowser.RustContent: ContentBuilder, begin_stack!, end_container!, 
    direction!, gap!, inset!, fill_hex!, width!, height!, border_radius!,
    begin_paragraph!, font_size!, text_color_hex!, span!, rect!
using DOPBrowser.RustContent: node_count as content_node_count
using DOPBrowser.RustRenderer: RustRendererHandle, create_renderer, destroy!,
    set_clear_color!, add_rect!, add_text!, render!, export_png!, get_framebuffer,
    create_onscreen_window, is_open_threaded, poll_events_threaded!, 
    destroy_threaded!, is_available, EVENT_MOUSE_DOWN, EVENT_RESIZE, update_framebuffer_threaded
using DOPBrowser.State: Signal, signal
using Logging
using DOPBrowser.ApplicationUtils: CountingLogger, parse_hex_color, point_in_rect, get_button_rect

# (General utilities such as a counting logger, color parsing and simple
# hit-testing live in `DOPBrowser.ApplicationUtils` and are imported above.)

# ============================================================================
# Memo Data Types
# ============================================================================

"""
Represents a single memo/note.
"""
Base.@kwdef struct Memo
    id::Int
    title::String
    content::Vector{String}
    color::String = "#1976D2"  # Title color (hex), default blue
end

# ============================================================================
# Memo State Management
# ============================================================================

"""
Create initial memos for the application.
"""
function create_initial_memos()::Vector{Memo}
    return [
        Memo(id=1, title="Shopping List", content=["- Milk", "- Bread", "- Eggs"], color="#1976D2"),
        Memo(id=2, title="Ideas", content=["Build a Content IR renderer in Rust", "Implement reactive state management"], color="#388E3C"),
        Memo(id=3, title="TODO", content=["✓ Create Rust Content IR library", "✓ Add Julia FFI wrapper", "✓ Build memo application"], color="#F57C00")
    ]
end

# ============================================================================
# UI Building with RustContent
# ============================================================================

"""
Build a single note card UI.
"""
function build_note_card!(builder::ContentBuilder, memo::Memo)
    # Note card container
    begin_stack!(builder)
    direction!(builder, :down)
    fill_hex!(builder, "#FFFFFF")
    border_radius!(builder, 8)
    inset!(builder, 15)
    gap!(builder, 5)
    width!(builder, 360)
    
    # Note title
    begin_paragraph!(builder)
    font_size!(builder, 18)
    text_color_hex!(builder, memo.color)
    span!(builder, memo.title)
    end_container!(builder)
    
    # Note content lines
    for line in memo.content
        begin_paragraph!(builder)
        font_size!(builder, 14)
        text_color_hex!(builder, "#424242")
        span!(builder, line)
        end_container!(builder)
    end
    
    end_container!(builder)  # End note card
end

"""
Build the complete memo app UI from current state.
"""
function build_memo_ui(memos::Vector{Memo}, title::String="My Notes")::ContentBuilder
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
    span!(builder, title)
    end_container!(builder)
    
    # Build each note card
    for memo in memos
        build_note_card!(builder, memo)
    end
    
    # Add New Note button
    begin_stack!(builder)
    direction!(builder, :right)
    fill_hex!(builder, "#2196F3")
    border_radius!(builder, 4)
    width!(builder, 360)
    height!(builder, 40)
    inset!(builder, 10)
    
    begin_paragraph!(builder)
    font_size!(builder, 16)
    text_color_hex!(builder, "#FFFFFF")
    span!(builder, "+ Add New Note")
    end_container!(builder)
    
    end_container!(builder)  # End button
    
    end_container!(builder)  # End main container
    
    return builder
end

# ============================================================================
# Rendering
# ============================================================================

"""
Render the memo UI to a framebuffer using RustRenderer.

This function demonstrates:
- Creating a renderer
- Adding rectangles for UI backgrounds
- Adding text for labels and content
- Rendering to framebuffer
"""
function render_memo_ui(memos::Vector{Memo}; width::Int=400, height::Int=600)
    # Create headless renderer
    renderer = create_renderer(width, height)
    
    # Set clear color (light gray background)
    set_clear_color!(renderer, 0.96f0, 0.96f0, 0.96f0, 1.0f0)
    
    # Current rendering position
    y_pos = 20.0f0
    x_margin = 20.0f0
    content_width = Float32(width - 2 * x_margin)
    
    # Render title
    add_text!(renderer, "My Notes", x_margin, y_pos; 
              font_size=24.0, r=0.13, g=0.13, b=0.13, a=1.0)
    y_pos += 35.0f0
    
    # Render each memo card
    for memo in memos
        card_height = 60.0f0 + 20.0f0 * length(memo.content)
        
        # Card background (white)
        add_rect!(renderer, x_margin, y_pos, content_width, card_height,
                 1.0, 1.0, 1.0, 1.0)
        
        # Parse memo title color
        title_color = parse_hex_color(memo.color)
        
        # Card title
        add_text!(renderer, memo.title, x_margin + 15.0f0, y_pos + 15.0f0;
                 font_size=18.0, r=title_color[1], g=title_color[2], 
                 b=title_color[3], a=1.0)
        
        # Card content
        content_y = y_pos + 40.0f0
        for line in memo.content
            add_text!(renderer, line, x_margin + 15.0f0, content_y;
                     font_size=14.0, r=0.26, g=0.26, b=0.26, a=1.0)
            content_y += 18.0f0
        end
        
        y_pos += card_height + 10.0f0
    end
    
    # Render "Add New Note" button
    button_height = 40.0f0
    add_rect!(renderer, x_margin, y_pos, content_width, button_height,
             0.13, 0.59, 0.95, 1.0)  # Blue button
    add_text!(renderer, "+ Add New Note", x_margin + 120.0f0, y_pos + 12.0f0;
             font_size=16.0, r=1.0, g=1.0, b=1.0, a=1.0)
    
    # Render the frame
    render!(renderer)
    
    return renderer
end


"""
Export the memo app to a PNG file.
"""
function export_memo_png(memos::Vector{Memo}, filename::String; 
                         width::Int=400, height::Int=600)
    renderer = render_memo_ui(memos; width=width, height=height)
    success = export_png!(renderer, filename)
    destroy!(renderer)
    return success
end

# ============================================================================
# Interactive Application
# ============================================================================

# parse_hex_color, point_in_rect and get_button_rect are provided by
# DOPBrowser.ApplicationUtils and imported above.

"""
Run the memo application in interactive mode.

This demonstrates:
- Event handling
- State updates triggering re-renders
- Mouse click detection on buttons
"""
function run_interactive_memo_app(; width::Int=400, height::Int=600)
    println("\n=== Interactive Memo Application ===\n")
    
    # Create reactive state for memos
    memos_signal = signal(create_initial_memos())
    next_id = signal(4)  # Next memo ID
    
    # Check if we should run in headless mode
    is_headless_mode = get(ENV, "HEADLESS", "") == "1" || 
                       get(ENV, "CI", "") == "true" ||
                       !is_available()
    
    if is_headless_mode
        println("Running in headless mode...")
        run_headless_demo(memos_signal, next_id)
    else
        println("Attempting to create onscreen window...")
        run_onscreen_demo(memos_signal, next_id, width, height)
    end
    
    println("\nApplication closed.")
end

"""
Run headless demo with simulated interactions.
"""
function run_headless_demo(memos_signal::Signal, next_id::Signal)
    println("Initial memos:")
    for memo in memos_signal[]
        println("  - $(memo.title): $(length(memo.content)) items")
    end
    
    # Render initial state
    output_path = joinpath(pwd(), "memo_app_initial.png")
    if export_memo_png(memos_signal[], output_path)
        println("\nInitial state saved to: $output_path")
    end
    
    # Simulate adding a new memo
    println("\nSimulating: Add new memo...")
    new_memo = Memo(id=next_id[], title="New Note", content=["This is a new note", "Added by user"])
    next_id[] += 1
    memos_signal[] = [memos_signal[]..., new_memo]
    
    println("Updated memos:")
    for memo in memos_signal[]
        println("  - $(memo.title): $(length(memo.content)) items")
    end
    
    # Render updated state
    output_path = joinpath(pwd(), "memo_app_updated.png")
    if export_memo_png(memos_signal[], output_path)
        println("\nUpdated state saved to: $output_path")
    end
    
    # Simulate deleting a memo
    println("\nSimulating: Delete first memo...")
    memos_signal[] = memos_signal[][2:end]
    
    println("Final memos:")
    for memo in memos_signal[]
        println("  - $(memo.title): $(length(memo.content)) items")
    end
    
    # Render final state
    output_path = joinpath(pwd(), "memo_app_final.png")
    if export_memo_png(memos_signal[], output_path)
        println("\nFinal state saved to: $output_path")
    end
    
    println("\nHeadless demo completed successfully!")
end

"""
Run onscreen demo with real window.
"""
function run_onscreen_demo(memos_signal::Signal, next_id::Signal, 
                           width::Int, height::Int)
    try
        # Try to create onscreen window
        window = create_onscreen_window(width=width, height=height, 
                                         title="Memo App")
        
        println("Window created! Close the window to exit.")
        println("Click the '+ Add New Note' button to add a memo.")
        
        frame_count = 0
        last_render_time = time()
        # Throttle presenting to the onscreen window to avoid hammering the
        # GPU surface during interactive resizes. We'll allow rendering at 60Hz
        # but present at most at 30Hz.
        last_present_time = time()
        
        while is_open_threaded(window)
            # Poll events
            events = poll_events_threaded!(window)
            
            for event in events
                # Handle mouse click
                if event.event_type == EVENT_MOUSE_DOWN
                    x, y = event.x, event.y

                    # Check if "Add New Note" button was clicked
                    btn_x, btn_y, btn_w, btn_h = get_button_rect(length(memos_signal[]); width=width)

                    if point_in_rect(x, y, btn_x, btn_y, btn_w, btn_h)
                        println("Button clicked! Adding new memo...")
                        new_memo = Memo(id=next_id[], title="Note $(next_id[])", 
                                       content=["New content item"])
                        next_id[] += 1
                        memos_signal[] = [memos_signal[]..., new_memo]
                    end
                elseif event.event_type == EVENT_RESIZE
                    # Update local width/height so layout reflows to the new window size.
                    # The renderer will be recreated each frame using these values.
                    new_w = Int(event.width)
                    new_h = Int(event.height)
                    if new_w > 0 && new_h > 0
                        println("Window resized -> $(new_w)x$(new_h)")
                        width = new_w
                        height = new_h
                    end
                end
            end
            
            # Render at ~60 FPS
            current_time = time()
            if current_time - last_render_time >= 1.0/60.0
                renderer = render_memo_ui(memos_signal[]; width=width, height=height)

                # Present the headless renderer framebuffer into the onscreen window.
                # We render into a headless renderer, read back the RGBA buffer and
                # push it to the threaded window which will present it.
                buf = get_framebuffer(renderer)
                # Debug: log framebuffer size before presenting to threaded window
                try
                    # Present at most 30Hz to avoid repeated surface reconfigures
                    current_present_time = time()
                    present_interval = 1.0 / 30.0
                    if current_present_time - last_present_time >= present_interval
                        @debug "Presenting framebuffer" length=length(buf) width=width height=height
                        # Sanity check: buffer length should be width * height * 4 (RGBA)
                        expected_len = Int(width) * Int(height) * 4
                        if length(buf) != expected_len
                            @warn "Framebuffer length mismatch before presenting" length=length(buf) expected=expected_len width=width height=height
                        end
                        update_framebuffer_threaded(window, buf, width, height)
                        last_present_time = current_present_time
                    else
                        @debug "Skipping present (throttled)" since=current_present_time - last_present_time
                    end
                catch e
                    @warn "Failed to update threaded window framebuffer" exception=(e, catch_backtrace())
                end

                destroy!(renderer)
                
                frame_count += 1
                last_render_time = current_time
            end
            
            sleep(0.001)  # Small sleep to reduce CPU usage
        end
        
        destroy_threaded!(window)
        println("Rendered $frame_count frames")
        
    catch e
        @warn "Onscreen mode failed, falling back to headless" exception=e
        run_headless_demo(memos_signal, next_id)
    end
end

# ============================================================================
# Simple Demo (No Window)
# ============================================================================

"""
Run a simple demo that creates and renders the memo UI.
"""
function run_simple_demo()
    println("=== Simple Memo App Demo ===\n")
    
    # Create memos
    memos = create_initial_memos()
    println("Created $(length(memos)) memos:")
    for memo in memos
        println("  - $(memo.title) ($(length(memo.content)) items)")
    end
    
    # Build UI using RustContent
    println("\nBuilding UI with RustContent...")
    builder = build_memo_ui(memos)
    println("Node count: $(content_node_count(builder))")
    
    # Render to PNG
    println("\nRendering to PNG...")
    output_path = joinpath(pwd(), "memo_app_output.png")
    if export_memo_png(memos, output_path)
        println("Successfully rendered to: $output_path")
    else
        println("Failed to render PNG (text rendering may not be available)")
    end
    
    println("\nDemo completed!")
    return builder
end

# ============================================================================
# Main Entry Point
# ============================================================================

function main()
    args = ARGS
    
    if "--simple" in args
        # Simple demo mode
        run_simple_demo()
    elseif "--interactive" in args || isempty(args)
        # Interactive mode (default)
        run_interactive_memo_app()
    else
        println("Memo App Example")
        println("================")
        println("Usage:")
        println("  julia --project=. examples/memo_app.jl             # Interactive mode")
        println("  julia --project=. examples/memo_app.jl --simple    # Simple demo")
        println("  julia --project=. examples/memo_app.jl --help      # Show this help")
        println("")
        println("Environment variables:")
        println("  HEADLESS=1    Force headless mode (no window)")
    end
end

# Run if executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    # Wrap execution with a counting logger. If any warning is emitted, the
    # example will print a message and then hang (sleep loop) so that CI or a
    # developer can inspect logs and attached debuggers. The logger forwards
    # all messages to stderr via a SimpleLogger configured at Debug level.
    warning_count = Ref(0)
    base_logger = Logging.SimpleLogger(stderr, Logging.Debug)
    counting_logger = CountingLogger(base_logger, warning_count)

    Logging.with_logger(counting_logger) do
        # Monitor warnings in a background task. If a warning is observed,
        # hang the process (sleep forever) after printing a message.
        monitor = @async begin
            while warning_count[] == 0
                sleep(0.1)
            end
            println("Warning detected; hanging to allow inspection (press Ctrl-C to exit)...")
            while true
                sleep(1.0)
            end
        end

        try
            main()
        finally
            # If main returns normally (no warnings), cancel the monitor task.
            # Use `isa(..., Task)` and `isdone` which are defined in Base.
            # Best-effort cancel: try canceling the monitor task, ignore errors.
            try
                Base.cancel(monitor)
            catch
                # ignore - monitor might have finished or cancellation unsupported
            end
        end
    end
end
