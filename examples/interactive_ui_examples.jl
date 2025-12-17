# Interactive UI Examples for DOP Browser
#
# This file contains examples of using the DOP Browser interactive UI library
# to build applications.
#
# To run these examples:
#   julia --project=. examples/interactive_ui_examples.jl

using DOPBrowser
using DOPBrowser.State
using DOPBrowser.Widgets
using DOPBrowser.Window
using DOPBrowser.Application

# ============================================================================
# Example 1: Basic Counter (Headless Mode)
# ============================================================================

function example_counter_headless()
    println("\n=== Example 1: Counter (Headless) ===")
    
    # Create reactive state
    count = signal(0)
    
    # Create headless app
    app = create_app(headless=true, width=400, height=200)
    
    # Define UI
    set_ui!(app) do
        column(gap=10.0f0) do
            label(text=computed(() -> "Count: $(count[])"), font_size=24.0f0)
            row(gap=10.0f0) do
                button(text="Decrement", on_click=() -> count[] -= 1)
                button(text="Increment", on_click=() -> count[] += 1)
            end
        end
    end
    
    # Render and save screenshot
    Application.initialize!(app)
    Application.build_app_ui!(app)
    render_frame!(app)
    
    println("Counter created with initial value: $(count[])")
    
    # Simulate button clicks
    count[] = 5
    println("After 5 increments: $(count[])")
    
    println("Example 1 complete!")
end

# ============================================================================
# Example 2: Reactive State Management
# ============================================================================

function example_reactive_state()
    println("\n=== Example 2: Reactive State ===")
    
    # Create signals
    first_name = signal("Julia")
    last_name = signal("Lang")
    
    # Create computed value
    full_name = computed(() -> "$(first_name[]) $(last_name[])")
    
    # Create effect
    effect_calls = Ref(0)
    eff = effect(() -> begin
        effect_calls[] += 1
        println("  Full name changed to: $(full_name[])")
    end)
    
    println("Initial effect call")
    
    # Update signals
    first_name[] = "John"
    println("Changed first name")
    
    last_name[] = "Doe"
    println("Changed last name")
    
    # Batch updates
    println("Batch update:")
    batch(() -> begin
        first_name[] = "Jane"
        last_name[] = "Smith"
    end)
    
    println("Total effect calls: $(effect_calls[])")
    
    # Cleanup
    dispose!(eff)
    
    println("Example 2 complete!")
end

# ============================================================================
# Example 3: Widget Showcase
# ============================================================================

function example_widget_showcase()
    println("\n=== Example 3: Widget Showcase ===")
    
    # Create reactive state for widgets
    input_value = signal("Hello")
    checkbox_checked = signal(false)
    slider_value = signal(50.0f0)
    
    # Build UI tree
    tree = build_ui() do
        column(gap=20.0f0) do
            # Header
            label(text="Widget Showcase", font_size=24.0f0, font_weight=:bold)
            
            # Button row
            row(gap=10.0f0) do
                button(text="Primary", variant=:primary)
                button(text="Secondary", variant=:secondary)
                button(text="Outline", variant=:outline)
            end
            
            # Text input
            text_input(value=input_value, placeholder="Enter text...")
            
            # Checkbox
            checkbox(checked=checkbox_checked, label="Enable feature")
            
            # Slider
            slider(value=slider_value, min=0.0f0, max=100.0f0)
            
            # Progress bar
            progress_bar(value=75.0f0, max=100.0f0, color="#4CAF50")
        end
    end
    
    println("Widget tree created with:")
    println("  - Input value: $(input_value[])")
    println("  - Checkbox checked: $(checkbox_checked[])")
    println("  - Slider value: $(slider_value[])")
    
    # Demonstrate reactive updates
    input_value[] = "World"
    checkbox_checked[] = true
    slider_value[] = 75.0f0
    
    println("After updates:")
    println("  - Input value: $(input_value[])")
    println("  - Checkbox checked: $(checkbox_checked[])")
    println("  - Slider value: $(slider_value[])")
    
    println("Example 3 complete!")
end

# ============================================================================
# Example 4: Store Pattern
# ============================================================================

function example_store_pattern()
    println("\n=== Example 4: Store Pattern ===")
    
    # Create a todo list store
    store = create_store(
        Dict{Symbol, Any}(
            :todos => String[],
            :filter => :all
        ),
        Dict{Symbol, Function}(
            :add_todo => (state, text) -> begin
                new_todos = [state[:todos]..., text]
                Dict{Symbol, Any}(:todos => new_todos)
            end,
            :remove_todo => (state, index) -> begin
                new_todos = [t for (i, t) in enumerate(state[:todos]) if i != index]
                Dict{Symbol, Any}(:todos => new_todos)
            end,
            :set_filter => (state, filter) -> Dict{Symbol, Any}(:filter => filter)
        )
    )
    
    # Subscribe to changes
    subscribe(store) do state
        println("  State updated: $(length(state[:todos])) todos, filter: $(state[:filter])")
    end
    
    # Dispatch actions
    println("Adding todos:")
    dispatch(store, :add_todo, "Learn Julia")
    dispatch(store, :add_todo, "Build UI library")
    dispatch(store, :add_todo, "Write documentation")
    
    println("Changing filter:")
    dispatch(store, :set_filter, :active)
    
    println("Removing todo:")
    dispatch(store, :remove_todo, 1)
    
    println("Final state: $(get_state(store))")
    
    println("Example 4 complete!")
end

# ============================================================================
# Example 5: Window and Events
# ============================================================================

function example_window_events()
    println("\n=== Example 5: Window and Events ===")
    
    # Create a window (software backend for testing)
    config = WindowConfig(
        title = "Event Demo",
        width = 640,
        height = 480,
        backend = :software
    )
    
    window = create_window(config)
    
    println("Window created: $(get_size(window))")
    
    # Inject some events
    println("Injecting events...")
    
    # Mouse move
    inject_event!(window, WindowEvent(EVENT_MOUSE_MOVE, x=100.0, y=200.0))
    
    # Key press
    inject_event!(window, WindowEvent(EVENT_KEY_DOWN, key=Int32(65)))  # 'A'
    
    # Mouse click
    inject_event!(window, WindowEvent(EVENT_MOUSE_DOWN, x=150.0, y=250.0))
    
    # Poll events
    events = poll_events!(window)
    println("Received $(length(events)) events:")
    for event in events
        println("  - $(event.type)")
    end
    
    # Check mouse position
    mx, my = get_mouse_position(window)
    println("Mouse position: ($mx, $my)")
    
    # Clean up
    destroy!(window)
    
    println("Example 5 complete!")
end

# ============================================================================
# Run all examples
# ============================================================================

function run_all_examples()
    println("DOP Browser Interactive UI Library Examples")
    println("=" ^ 50)
    
    example_counter_headless()
    example_reactive_state()
    example_widget_showcase()
    example_store_pattern()
    example_window_events()
    
    println("\n" * "=" ^ 50)
    println("All examples completed successfully!")
end

# Run examples when script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    run_all_examples()
end
