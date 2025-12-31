# Usable Memo Application - A Natural, Human-Friendly Note-Taking App
#
# This memo application is designed to be natural and down-to-earth for humans:
# - Clean, modern visual design with soft shadows and rounded corners
# - Intuitive color-coded categories
# - Clear visual feedback for interactions
# - Timestamps for when notes were created/updated
# - Easy-to-read typography with proper spacing
#
# To run:
#   julia --project=. examples/usable_memo_app.jl
#
# To run in headless mode (for testing/CI):
#   HEADLESS=1 julia --project=. examples/usable_memo_app.jl
#
# To force onscreen mode (override CI detection):
#   FORCE_ONSCREEN=1 julia --project=. examples/usable_memo_app.jl

using DOPBrowser
using DOPBrowser.RustContent: ContentBuilder, begin_stack!, end_container!, 
    direction!, gap!, inset!, fill_hex!, width!, height!, border_radius!,
    begin_paragraph!, font_size!, text_color_hex!, span!, rect!
using DOPBrowser.RustContent: node_count as content_node_count
using DOPBrowser.RustRenderer: RustRendererHandle, create_renderer, destroy!,
    set_clear_color!, add_rect!, add_text!, render!, export_png!, get_framebuffer,
    create_onscreen_window, is_open_threaded, poll_events_threaded!, 
    destroy_threaded!, is_available, EVENT_MOUSE_DOWN, EVENT_RESIZE, 
    EVENT_KEY_DOWN, update_framebuffer_threaded
using DOPBrowser.State: Signal, signal
using Logging
using DOPBrowser.ApplicationUtils: CountingLogger, parse_hex_color, point_in_rect
using Dates

# ============================================================================
# Memo Data Types with Enhanced Features
# ============================================================================

"""
Category for organizing memos with colors and icons.
"""
@enum MemoCategory begin
    CATEGORY_PERSONAL = 1
    CATEGORY_WORK = 2
    CATEGORY_IDEAS = 3
    CATEGORY_TODO = 4
    CATEGORY_SHOPPING = 5
end

"""
Get display name for a category.
"""
function category_name(cat::MemoCategory)::String
    cat == CATEGORY_PERSONAL && return "Personal"
    cat == CATEGORY_WORK && return "Work"
    cat == CATEGORY_IDEAS && return "Ideas"
    cat == CATEGORY_TODO && return "To-Do"
    cat == CATEGORY_SHOPPING && return "Shopping"
    return "Note"
end

"""
Get color for a category (hex format).
"""
function category_color(cat::MemoCategory)::String
    cat == CATEGORY_PERSONAL && return "#7C4DFF"  # Purple
    cat == CATEGORY_WORK && return "#1976D2"       # Blue
    cat == CATEGORY_IDEAS && return "#00897B"      # Teal
    cat == CATEGORY_TODO && return "#F57C00"       # Orange
    cat == CATEGORY_SHOPPING && return "#388E3C"   # Green
    return "#616161"  # Gray default
end

"""
Get a lighter background color for a category.
"""
function category_bg_color(cat::MemoCategory)::String
    cat == CATEGORY_PERSONAL && return "#F3E5F5"  # Light purple
    cat == CATEGORY_WORK && return "#E3F2FD"       # Light blue
    cat == CATEGORY_IDEAS && return "#E0F2F1"      # Light teal
    cat == CATEGORY_TODO && return "#FFF3E0"       # Light orange
    cat == CATEGORY_SHOPPING && return "#E8F5E9"   # Light green
    return "#FAFAFA"  # Light gray default
end

"""
Represents a single memo/note with enhanced metadata.
"""
Base.@kwdef mutable struct Memo
    id::Int
    title::String
    content::Vector{String}
    category::MemoCategory = CATEGORY_PERSONAL
    created_at::DateTime = now()
    updated_at::DateTime = now()
    is_pinned::Bool = false
    is_completed::Bool = false  # For todo items
end

"""
Format a timestamp in a human-friendly way.
"""
function format_time(dt::DateTime)::String
    today = Date(now())
    memo_date = Date(dt)
    
    if memo_date == today
        return "Today, " * Dates.format(dt, "HH:mm")
    elseif memo_date == today - Day(1)
        return "Yesterday, " * Dates.format(dt, "HH:mm")
    else
        return Dates.format(dt, "d u, HH:mm")
    end
end

# ============================================================================
# Memo State Management
# ============================================================================

"""
Create sample memos for demonstration.
"""
function create_sample_memos()::Vector{Memo}
    base_time = now()
    return [
        Memo(
            id=1, 
            title="Grocery Shopping", 
            content=["🥛 Milk", "🍞 Fresh bread", "🥚 Free-range eggs", "🧀 Cheddar cheese"],
            category=CATEGORY_SHOPPING,
            created_at=base_time - Hour(2),
            is_pinned=true
        ),
        Memo(
            id=2, 
            title="Project Ideas", 
            content=[
                "Build a Content IR renderer in Rust",
                "Implement reactive state management",
                "Create widget library with modern design"
            ],
            category=CATEGORY_IDEAS,
            created_at=base_time - Day(1)
        ),
        Memo(
            id=3, 
            title="Today's Tasks", 
            content=[
                "✓ Review pull requests",
                "✓ Update documentation",
                "○ Deploy to staging",
                "○ Team standup at 3pm"
            ],
            category=CATEGORY_TODO,
            created_at=base_time - Hour(5)
        ),
        Memo(
            id=4, 
            title="Meeting Notes", 
            content=[
                "Discussed Q2 roadmap",
                "Action items assigned",
                "Follow-up scheduled for Friday"
            ],
            category=CATEGORY_WORK,
            created_at=base_time - Day(2)
        )
    ]
end

# ============================================================================
# UI Rendering with Modern Design
# ============================================================================

# UI Constants for consistent styling
const SHADOW_OFFSET = 2.0f0
const SHADOW_ALPHA = 0.08
const TITLE_HEIGHT = 40.0f0
const SUBTITLE_HEIGHT = 28.0f0
const HEADER_MARGIN = 16.0f0
const HEADER_TOTAL_HEIGHT = TITLE_HEIGHT + SUBTITLE_HEIGHT + HEADER_MARGIN

"""
Render a single memo card with enhanced styling.
"""
function render_memo_card!(renderer::RustRendererHandle, memo::Memo, 
                           x::Float32, y::Float32, width::Float32)
    card_height = 70.0f0 + 22.0f0 * length(memo.content)
    corner_radius = 12.0f0
    
    # Card shadow (subtle)
    add_rect!(renderer, x + SHADOW_OFFSET, y + SHADOW_OFFSET, 
              width, card_height, 0.0, 0.0, 0.0, SHADOW_ALPHA)
    
    # Card background with category accent
    bg_color = parse_hex_color(category_bg_color(memo.category))
    add_rect!(renderer, x, y, width, card_height, 
              bg_color[1], bg_color[2], bg_color[3], 1.0)
    
    # Category accent stripe on left
    accent_color = parse_hex_color(category_color(memo.category))
    add_rect!(renderer, x, y, 4.0f0, card_height,
              accent_color[1], accent_color[2], accent_color[3], 1.0)
    
    # Pin indicator
    if memo.is_pinned
        add_text!(renderer, "📌", x + width - 30.0f0, y + 10.0f0;
                  font_size=14.0, r=0.4, g=0.4, b=0.4, a=1.0)
    end
    
    # Title
    title_y = y + 15.0f0
    add_text!(renderer, memo.title, x + 16.0f0, title_y;
              font_size=16.0, r=accent_color[1], g=accent_color[2], 
              b=accent_color[3], a=1.0)
    
    # Category and timestamp
    meta_text = "$(category_name(memo.category)) • $(format_time(memo.updated_at))"
    add_text!(renderer, meta_text, x + 16.0f0, title_y + 18.0f0;
              font_size=11.0, r=0.5, g=0.5, b=0.5, a=1.0)
    
    # Content items
    content_y = title_y + 42.0f0
    for line in memo.content
        # Determine text color based on completion status
        is_done = startswith(line, "✓")
        text_alpha = is_done ? 0.5 : 0.85
        
        add_text!(renderer, line, x + 16.0f0, content_y;
                  font_size=13.0, r=0.2, g=0.2, b=0.2, a=text_alpha)
        content_y += 20.0f0
    end
    
    return card_height
end

"""
Render the floating action button (FAB) for adding new memos.
"""
function render_fab!(renderer::RustRendererHandle, x::Float32, y::Float32)
    fab_size = 56.0f0
    fab_color = parse_hex_color("#1B8BED")
    
    # Shadow
    add_rect!(renderer, x + 3.0f0, y + 3.0f0, fab_size, fab_size,
              0.0, 0.0, 0.0, 0.15)
    
    # Button background
    add_rect!(renderer, x, y, fab_size, fab_size,
              fab_color[1], fab_color[2], fab_color[3], 1.0)
    
    # Plus icon
    add_text!(renderer, "+", x + 18.0f0, y + 12.0f0;
              font_size=28.0, r=1.0, g=1.0, b=1.0, a=1.0)
end

"""
Render the complete memo app UI.
"""
function render_memo_ui(memos::Vector{Memo}; width::Int=420, height::Int=700)
    renderer = create_renderer(width, height)
    
    # Background gradient effect (solid light gray)
    set_clear_color!(renderer, 0.96f0, 0.97f0, 0.98f0, 1.0f0)
    
    # Layout constants
    margin = 16.0f0
    content_width = Float32(width) - 2.0f0 * margin
    current_y = 16.0f0
    
    # App title
    add_text!(renderer, "📝 My Notes", margin, current_y;
              font_size=26.0, r=0.15, g=0.15, b=0.15, a=1.0)
    current_y += 40.0f0
    
    # Subtitle with memo count
    count_text = "$(length(memos)) notes"
    add_text!(renderer, count_text, margin, current_y;
              font_size=13.0, r=0.5, g=0.5, b=0.5, a=1.0)
    current_y += 28.0f0
    
    # Sort memos: pinned first, then by updated time
    sorted_memos = sort(memos, by = m -> (!m.is_pinned, -datetime2unix(m.updated_at)))
    
    # Render each memo card
    for memo in sorted_memos
        card_height = render_memo_card!(renderer, memo, margin, current_y, content_width)
        current_y += card_height + 12.0f0
    end
    
    # Floating action button
    fab_x = Float32(width) - 72.0f0
    fab_y = Float32(height) - 72.0f0
    render_fab!(renderer, fab_x, fab_y)
    
    # Render the frame
    render!(renderer)
    
    return renderer
end

"""
Export the memo app to a PNG file.
"""
function export_memo_png(memos::Vector{Memo}, filename::String; 
                         width::Int=420, height::Int=700)
    renderer = render_memo_ui(memos; width=width, height=height)
    success = export_png!(renderer, filename)
    destroy!(renderer)
    return success
end

# ============================================================================
# Hit Testing for Interactive Elements
# ============================================================================

"""
Get the bounding box for a memo card at the given index.
"""
function get_memo_card_rect(memos::Vector{Memo}, index::Int; 
                            margin::Float32=16.0f0, width::Int=420)
    content_width = Float32(width) - 2.0f0 * margin
    current_y = HEADER_TOTAL_HEIGHT  # After title and subtitle
    
    sorted_memos = sort(memos, by = m -> (!m.is_pinned, -datetime2unix(m.updated_at)))
    
    for (i, memo) in enumerate(sorted_memos)
        card_height = 70.0f0 + 22.0f0 * length(memo.content)
        if i == index
            return (margin, current_y, content_width, card_height, memo.id)
        end
        current_y += card_height + 12.0f0
    end
    
    return nothing
end

"""
Get the FAB bounding box.
"""
function get_fab_rect(; width::Int=420, height::Int=700)
    fab_x = Float32(width) - 72.0f0
    fab_y = Float32(height) - 72.0f0
    return (fab_x, fab_y, 56.0f0, 56.0f0)
end

"""
Find which element was clicked.
"""
function hit_test_ui(x::Float64, y::Float64, memos::Vector{Memo}; 
                     width::Int=420, height::Int=700)
    # Check FAB first (on top)
    fab = get_fab_rect(; width=width, height=height)
    if point_in_rect(x, y, fab[1], fab[2], fab[3], fab[4])
        return (:fab, 0)
    end
    
    # Check memo cards
    sorted_memos = sort(memos, by = m -> (!m.is_pinned, -datetime2unix(m.updated_at)))
    for (i, _) in enumerate(sorted_memos)
        rect = get_memo_card_rect(memos, i; width=width)
        if rect !== nothing && point_in_rect(x, y, rect[1], rect[2], rect[3], rect[4])
            return (:memo, rect[5])  # Return memo id
        end
    end
    
    return (:none, 0)
end

# ============================================================================
# Interactive Application
# ============================================================================

"""
Run the memo application interactively.
"""
function run_interactive_app(; width::Int=420, height::Int=700)
    println("\n╔════════════════════════════════════════╗")
    println("║    📝 Usable Memo Application          ║")
    println("║    A Natural Note-Taking Experience    ║")
    println("╚════════════════════════════════════════╝\n")
    
    # Create reactive state
    memos_signal = signal(create_sample_memos())
    next_id = signal(5)
    
    # Determine run mode
    force_onscreen = get(ENV, "FORCE_ONSCREEN", "") == "1"
    headless_env = get(ENV, "HEADLESS", "") == "1"
    ci_env = get(ENV, "CI", "") == "true"
    
    is_headless = headless_env || (!force_onscreen && (ci_env || !is_available()))
    
    if is_headless
        println("ℹ️  Running in headless mode")
        println("   Set FORCE_ONSCREEN=1 to attempt windowed mode\n")
        run_headless_demo(memos_signal, next_id; width=width, height=height)
    else
        println("🖥️  Attempting to create window...")
        run_windowed_app(memos_signal, next_id, width, height)
    end
    
    println("\n✅ Application closed successfully.")
end

"""
Run the headless demo with simulated interactions.
"""
function run_headless_demo(memos_signal::Signal, next_id::Signal; 
                           width::Int=420, height::Int=700)
    println("Current notes:")
    for memo in memos_signal[]
        pin_indicator = memo.is_pinned ? " 📌" : ""
        println("  • $(memo.title)$pin_indicator ($(category_name(memo.category)))")
    end
    
    # Render initial state
    output_dir = joinpath(pwd(), "output")
    mkpath(output_dir)
    
    initial_path = joinpath(output_dir, "memo_app_1_initial.png")
    if export_memo_png(memos_signal[], initial_path; width=width, height=height)
        println("\n📸 Initial state: $initial_path")
    end
    
    # Simulate adding a new memo
    println("\n➕ Adding new memo...")
    new_memo = Memo(
        id=next_id[], 
        title="Quick Note",
        content=["This is a quick thought", "Remember to follow up"],
        category=CATEGORY_PERSONAL,
        is_pinned=false
    )
    next_id[] += 1
    memos_signal[] = [memos_signal[]..., new_memo]
    
    added_path = joinpath(output_dir, "memo_app_2_added.png")
    if export_memo_png(memos_signal[], added_path; width=width, height=height)
        println("📸 After adding note: $added_path")
    end
    
    # Simulate pinning a memo
    println("\n📌 Pinning 'Quick Note'...")
    updated_memos = copy(memos_signal[])
    for (i, m) in enumerate(updated_memos)
        if m.title == "Quick Note"
            updated_memos[i] = Memo(
                id=m.id, title=m.title, content=m.content,
                category=m.category, created_at=m.created_at,
                updated_at=now(), is_pinned=true, is_completed=m.is_completed
            )
        end
    end
    memos_signal[] = updated_memos
    
    pinned_path = joinpath(output_dir, "memo_app_3_pinned.png")
    if export_memo_png(memos_signal[], pinned_path; width=width, height=height)
        println("📸 After pinning: $pinned_path")
    end
    
    # Simulate completing todo items
    println("\n✓ Marking tasks as complete...")
    updated_memos = copy(memos_signal[])
    for (i, m) in enumerate(updated_memos)
        if m.category == CATEGORY_TODO
            new_content = [
                replace(line, "○" => "✓") for line in m.content
            ]
            updated_memos[i] = Memo(
                id=m.id, title=m.title, content=new_content,
                category=m.category, created_at=m.created_at,
                updated_at=now(), is_pinned=m.is_pinned, is_completed=true
            )
        end
    end
    memos_signal[] = updated_memos
    
    completed_path = joinpath(output_dir, "memo_app_4_completed.png")
    if export_memo_png(memos_signal[], completed_path; width=width, height=height)
        println("📸 After completing tasks: $completed_path")
    end
    
    println("\n" * "─"^50)
    println("Final state: $(length(memos_signal[])) notes")
    for memo in memos_signal[]
        pin = memo.is_pinned ? " 📌" : ""
        println("  • $(memo.title)$pin")
    end
    println("─"^50)
    
    println("\n🎉 Demo completed! Check the 'output' folder for screenshots.")
end

"""
Run the windowed application with real interaction.
"""
function run_windowed_app(memos_signal::Signal, next_id::Signal,
                          width::Int, height::Int)
    try
        window = create_onscreen_window(width=width, height=height,
                                         title="📝 My Notes")
        
        println("✅ Window created!")
        println("   • Click the + button to add a new note")
        println("   • Click a note to toggle its pin status")
        println("   • Close the window to exit\n")
        
        frame_count = 0
        last_render_time = time()
        last_present_time = time()
        current_width = width
        current_height = height
        
        while is_open_threaded(window)
            events = poll_events_threaded!(window)
            
            for event in events
                if event.event_type == EVENT_MOUSE_DOWN
                    hit = hit_test_ui(event.x, event.y, memos_signal[];
                                     width=current_width, height=current_height)
                    
                    if hit[1] == :fab
                        # Add new memo
                        println("➕ Adding new note...")
                        categories = [CATEGORY_PERSONAL, CATEGORY_WORK, 
                                     CATEGORY_IDEAS, CATEGORY_TODO]
                        new_memo = Memo(
                            id=next_id[],
                            title="Note #$(next_id[])",
                            content=["New note created", "Click to edit"],
                            category=categories[mod1(next_id[], length(categories))]
                        )
                        next_id[] += 1
                        memos_signal[] = [memos_signal[]..., new_memo]
                        
                    elseif hit[1] == :memo
                        # Toggle pin on memo
                        memo_id = hit[2]
                        updated = copy(memos_signal[])
                        for (i, m) in enumerate(updated)
                            if m.id == memo_id
                                new_pinned = !m.is_pinned
                                println(new_pinned ? "📌 Pinned: $(m.title)" : 
                                                    "📍 Unpinned: $(m.title)")
                                updated[i] = Memo(
                                    id=m.id, title=m.title, content=m.content,
                                    category=m.category, created_at=m.created_at,
                                    updated_at=now(), is_pinned=new_pinned,
                                    is_completed=m.is_completed
                                )
                            end
                        end
                        memos_signal[] = updated
                    end
                    
                elseif event.event_type == EVENT_RESIZE
                    if event.width > 0 && event.height > 0
                        current_width = Int(event.width)
                        current_height = Int(event.height)
                        println("📐 Resized to $(current_width)x$(current_height)")
                    end
                end
            end
            
            # Render at 60 FPS
            current_time = time()
            if current_time - last_render_time >= 1.0/60.0
                renderer = render_memo_ui(memos_signal[]; 
                                         width=current_width, height=current_height)
                
                # Present at 30 FPS to avoid surface issues
                if current_time - last_present_time >= 1.0/30.0
                    buf = get_framebuffer(renderer)
                    if length(buf) == current_width * current_height * 4
                        try
                            update_framebuffer_threaded(window, buf, 
                                                       current_width, current_height)
                        catch e
                            @debug "Present failed" exception=e
                        end
                    end
                    last_present_time = current_time
                end
                
                destroy!(renderer)
                frame_count += 1
                last_render_time = current_time
            end
            
            sleep(0.001)
        end
        
        destroy_threaded!(window)
        println("\n📊 Rendered $frame_count frames")
        
    catch e
        @warn "Window mode failed" exception=e
        println("⚠️  Falling back to headless mode...")
        run_headless_demo(memos_signal, next_id; width=width, height=height)
    end
end

# ============================================================================
# Simple Demo Mode
# ============================================================================

"""
Run a simple demo that generates screenshots.
"""
function run_simple_demo()
    println("\n📝 Usable Memo App - Simple Demo\n")
    
    memos = create_sample_memos()
    println("Created $(length(memos)) sample notes:\n")
    
    for memo in memos
        pin = memo.is_pinned ? " 📌" : ""
        println("  $(category_name(memo.category)): $(memo.title)$pin")
        for item in memo.content
            println("    • $item")
        end
        println()
    end
    
    # Build UI using RustContent for demonstration
    builder = ContentBuilder()
    begin_stack!(builder)
    direction!(builder, :down)
    gap!(builder, 12)
    inset!(builder, 16)
    fill_hex!(builder, "#F5F6F8")
    width!(builder, 420)
    height!(builder, 700)
    
    begin_paragraph!(builder)
    font_size!(builder, 26)
    text_color_hex!(builder, "#262626")
    span!(builder, "📝 My Notes")
    end_container!(builder)
    
    end_container!(builder)
    
    println("Content IR node count: $(content_node_count(builder))")
    
    # Render to PNG
    output_dir = joinpath(pwd(), "output")
    mkpath(output_dir)
    output_path = joinpath(output_dir, "memo_app_demo.png")
    
    if export_memo_png(memos, output_path)
        println("\n✅ Screenshot saved: $output_path")
    else
        println("\n⚠️  Failed to save screenshot")
    end
    
    println("\n🎉 Demo completed!")
end

# ============================================================================
# Main Entry Point
# ============================================================================

function main()
    args = ARGS
    
    if "--simple" in args
        run_simple_demo()
    elseif "--help" in args || "-h" in args
        println("""
Usable Memo Application
=======================
A natural, human-friendly note-taking app built with DOP Browser.

Usage:
  julia --project=. examples/usable_memo_app.jl              # Interactive mode
  julia --project=. examples/usable_memo_app.jl --simple     # Simple demo
  julia --project=. examples/usable_memo_app.jl --help       # Show this help

Environment variables:
  HEADLESS=1        Force headless mode (no window)
  FORCE_ONSCREEN=1  Force attempt to create window (even in CI)
        """)
    else
        run_interactive_app()
    end
end

# Run main when executed as script
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
