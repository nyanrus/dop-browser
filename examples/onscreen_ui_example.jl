# Onscreen UI Example for DOP Browser
#
# This file demonstrates how to use the DOP Browser interactive UI library
# to build a real desktop application with onscreen rendering.
#
# To run this example:
#   julia --project=. examples/onscreen_ui_example.jl

using DOPBrowser
using DOPBrowser.State
using DOPBrowser.Widgets
using DOPBrowser.Window
using DOPBrowser.Application

# ============================================================================
# Example: Interactive Counter with Onscreen Rendering
# ============================================================================

"""
Run an interactive counter application with onscreen rendering.

This example creates a real desktop window using the Gtk backend.
"""
function run_onscreen_counter()
    println("\n=== Onscreen Counter Example ===")
    
    # Check if Gtk is available
    if !Window.is_gtk_available()
        println("Gtk is not available. Running in headless mode instead.")
        return run_headless_demo()
    end
    
    # Create reactive state
    count = signal(0)
    
    # Create application with Gtk backend for onscreen rendering
    app = create_app(
        title = "Counter App",
        width = 400,
        height = 200,
        headless = false,
        backend = :gtk
    )
    
    # Define UI
    set_ui!(app) do
        column(gap=10.0f0) do
            label(text=computed(() -> "Count: $(count[])"), font_size=24.0f0)
            row(gap=10.0f0) do
                button(text="Decrement (-)", on_click=() -> begin
                    count[] -= 1
                    println("Count: $(count[])")
                end)
                button(text="Increment (+)", on_click=() -> begin
                    count[] += 1
                    println("Count: $(count[])")
                end)
            end
        end
    end
    
    println("Starting onscreen application...")
    println("Close the window to exit.")
    
    # Run the application
    run!(app)
    
    println("\nApplication closed. Final count: $(count[])")
end

"""
Run a headless demo as fallback when Gtk is not available.
"""
function run_headless_demo()
    println("\n=== Headless Demo (Gtk not available) ===")
    
    count = signal(0)
    
    app = create_app(
        title = "Counter Demo",
        width = 400,
        height = 200,
        headless = true,
        backend = :cairo
    )
    
    set_ui!(app) do
        column(gap=10.0f0) do
            label(text=computed(() -> "Count: $(count[])"), font_size=24.0f0)
            row(gap=10.0f0) do
                button(text="Decrement (-)")
                button(text="Increment (+)")
            end
        end
    end
    
    # Initialize and render
    Application.initialize!(app)
    Application.build_app_ui!(app)
    render_frame!(app)
    
    # Simulate some interactions
    println("Simulating count changes:")
    for i in 1:5
        count[] = i
        println("  Count: $(count[])")
    end
    
    # Save a screenshot
    screenshot_path = joinpath(tempdir(), "onscreen_demo.png")
    save_app_screenshot(app, screenshot_path)
    println("Screenshot saved to: $screenshot_path")
    
    println("\nHeadless demo complete!")
end

# ============================================================================
# Example: Todo List Application
# ============================================================================

"""
Run a simple todo list application with onscreen rendering.
"""
function run_todo_app()
    println("\n=== Todo List Application ===")
    
    if !Window.is_gtk_available()
        println("Gtk is not available. Skipping onscreen todo app.")
        return
    end
    
    # Create store for todos
    todos = signal(String[])
    input_text = signal("")
    
    app = create_app(
        title = "Todo List",
        width = 500,
        height = 400,
        headless = false,
        backend = :gtk
    )
    
    # Define UI
    set_ui!(app) do
        column(gap=15.0f0) do
            # Header
            label(text="Todo List", font_size=24.0f0, font_weight=:bold)
            
            # Input row
            row(gap=10.0f0) do
                text_input(value=input_text, placeholder="Enter a todo...")
                button(text="Add", on_click=() -> begin
                    text = input_text[]
                    if !isempty(text)
                        todos[] = [todos[]..., text]
                        input_text[] = ""
                        println("Added todo: $text")
                    end
                end)
            end
            
            # Todo list
            column(gap=5.0f0) do
                for (i, todo) in enumerate(todos[])
                    row(gap=10.0f0) do
                        checkbox(label=todo)
                        button(text="Remove", variant=:outline, on_click=() -> begin
                            todos[] = [t for (j, t) in enumerate(todos[]) if j != i]
                            println("Removed todo at index $i")
                        end)
                    end
                end
            end
            
            # Status
            label(text=computed(() -> "Total: $(length(todos[])) items"))
        end
    end
    
    println("Starting todo application...")
    println("Close the window to exit.")
    
    run!(app)
    
    println("\nTodo app closed.")
end

# ============================================================================
# Main
# ============================================================================

function main()
    println("DOP Browser Onscreen UI Examples")
    println("=" ^ 50)
    
    # Check environment
    println("\nEnvironment:")
    println("  Julia version: $(VERSION)")
    println("  Gtk available: $(Window.is_gtk_available())")
    
    # Run examples
    run_onscreen_counter()
    
    println("\n" * "=" ^ 50)
    println("Examples completed!")
end

# Run main when script is executed directly
if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
