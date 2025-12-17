"""
    Widgets

High-level widget components for building interactive UIs.

This module provides production-ready UI widgets that integrate with 
the Content-- rendering system and reactive state management.

## Available Widgets

- **Button**: Clickable button with hover/pressed states
- **TextInput**: Single-line text input field
- **Checkbox**: Toggle checkbox
- **Radio**: Radio button group
- **Slider**: Range slider
- **ProgressBar**: Progress indicator
- **Label**: Text label
- **Container**: Layout container

## Usage

```julia
using DOPBrowser.Widgets
using DOPBrowser.State

# Create a reactive counter
count = signal(0)

# Build UI with widgets
ui = build_ui() do
    container(direction=:column, gap=10) do
        label(text=computed(() -> "Count: \$(count[])"))
        
        container(direction=:row, gap=5) do
            button(text="-", on_click=() -> count[] -= 1)
            button(text="+", on_click=() -> count[] += 1)
        end
        
        slider(min=0, max=100, value=count)
    end
end

# Render UI
render!(ui, window)
```
"""
module Widgets

using ..State: Signal, signal, computed, effect, batch
using ..ContentMM.Properties: Color, parse_color, Direction, 
                              DIRECTION_DOWN, DIRECTION_RIGHT,
                              Pack, PACK_START, PACK_CENTER, PACK_END,
                              Align, ALIGN_START, ALIGN_END, ALIGN_CENTER, ALIGN_STRETCH
using ..ContentMM.Primitives: NodeTable, NodeType, create_node!, node_count,
                               NODE_ROOT, NODE_STACK, NODE_RECT, NODE_PARAGRAPH, NODE_SPAN
using ..ContentMM.Properties: PropertyTable, resize_properties!, set_property!
using ..ContentMM.NativeUI: UIContext, create_ui, render!, render_cairo!

export Widget, WidgetTree, WidgetProps
export ContainerWidget, ButtonWidget, LabelWidget, TextInputWidget
export CheckboxWidget, SliderWidget, ProgressBarWidget, SpacerWidget
export button, label, text_input, checkbox, slider, progress_bar
export container, row, column, spacer
export build_ui, render_widgets!

# ============================================================================
# Widget Base Types
# ============================================================================

"""
Widget properties common to all widgets.
"""
Base.@kwdef mutable struct WidgetProps
    # Layout
    width::Union{Float32, Nothing} = nothing
    height::Union{Float32, Nothing} = nothing
    min_width::Float32 = 0.0f0
    min_height::Float32 = 0.0f0
    max_width::Float32 = Float32(Inf)
    max_height::Float32 = Float32(Inf)
    padding::Float32 = 0.0f0
    padding_x::Float32 = 0.0f0
    padding_y::Float32 = 0.0f0
    margin::Float32 = 0.0f0
    margin_x::Float32 = 0.0f0
    margin_y::Float32 = 0.0f0
    
    # Appearance
    background::Union{String, Nothing} = nothing
    border_color::Union{String, Nothing} = nothing
    border_width::Float32 = 0.0f0
    border_radius::Float32 = 0.0f0
    opacity::Float32 = 1.0f0
    
    # State
    visible::Bool = true
    enabled::Bool = true
    focusable::Bool = false
    
    # Accessibility
    role::Symbol = :none
    aria_label::String = ""
end

"""
Abstract base type for all widgets.
"""
abstract type Widget end

"""
    WidgetTree

A tree of widgets representing a UI.
"""
mutable struct WidgetTree
    root::Widget
    ui_context::Union{UIContext, Nothing}
    focused_widget::Union{Widget, Nothing}
    hover_widget::Union{Widget, Nothing}
    dirty::Bool
    
    function WidgetTree(root::Widget)
        new(root, nothing, nothing, nothing, true)
    end
end

# ============================================================================
# Container Widget
# ============================================================================

"""
Container widget for laying out children.
"""
mutable struct ContainerWidget <: Widget
    props::WidgetProps
    children::Vector{Widget}
    direction::Direction
    gap::Float32
    pack::Pack
    align::Align
    
    function ContainerWidget(;
                             direction::Symbol = :column,
                             gap::Float32 = 0.0f0,
                             pack::Symbol = :start,
                             align::Symbol = :stretch,
                             props::WidgetProps = WidgetProps())
        dir = direction == :row ? DIRECTION_RIGHT : DIRECTION_DOWN
        pk = pack == :center ? PACK_CENTER : pack == :end ? PACK_END : PACK_START
        al = align == :center ? ALIGN_CENTER : align == :end ? ALIGN_END : ALIGN_STRETCH
        new(props, Widget[], dir, gap, pk, al)
    end
end

"""
    container(f::Function; kwargs...) -> ContainerWidget

Create a container widget with children defined in a block.
"""
function container(f::Function; kwargs...)
    c = ContainerWidget(; kwargs...)
    # Add to parent if there is one
    _add_to_parent(c)
    # Execute block to collect children
    old_parent = _get_current_parent()
    _set_current_parent(c)
    f()
    _set_current_parent(old_parent)
    return c
end

"""
    container(; kwargs...) -> ContainerWidget

Create an empty container widget.
"""
container(; kwargs...) = ContainerWidget(; kwargs...)

"""
    row(f::Function; kwargs...) -> ContainerWidget

Shorthand for container with direction=:row.
"""
row(f::Function; kwargs...) = container(f; direction=:row, kwargs...)

"""
    column(f::Function; kwargs...) -> ContainerWidget

Shorthand for container with direction=:column.
"""
column(f::Function; kwargs...) = container(f; direction=:column, kwargs...)

# ============================================================================
# Button Widget
# ============================================================================

"""
Button widget with click handling.
"""
mutable struct ButtonWidget <: Widget
    props::WidgetProps
    text::Union{String, Signal{String}}
    on_click::Union{Function, Nothing}
    on_hover::Union{Function, Nothing}
    is_hovered::Bool
    is_pressed::Bool
    variant::Symbol  # :primary, :secondary, :outline, :text
    
    function ButtonWidget(;
                          text::Union{String, Signal{String}} = "Button",
                          on_click::Union{Function, Nothing} = nothing,
                          on_hover::Union{Function, Nothing} = nothing,
                          variant::Symbol = :primary,
                          props::WidgetProps = WidgetProps())
        # Set default button styling
        if props.padding == 0.0f0 && props.padding_x == 0.0f0
            props.padding_x = 16.0f0
            props.padding_y = 8.0f0
        end
        if props.border_radius == 0.0f0
            props.border_radius = 4.0f0
        end
        props.focusable = true
        props.role = :button
        
        new(props, text, on_click, on_hover, false, false, variant)
    end
end

"""
    button(; text="Button", on_click=nothing, kwargs...) -> ButtonWidget

Create a button widget.
"""
function button(; text::Union{String, Signal{String}} = "Button",
                 on_click::Union{Function, Nothing} = nothing,
                 on_hover::Union{Function, Nothing} = nothing,
                 variant::Symbol = :primary,
                 kwargs...)
    props = WidgetProps(; kwargs...)
    btn = ButtonWidget(; text=text, on_click=on_click, on_hover=on_hover, 
                        variant=variant, props=props)
    _add_to_parent(btn)
    return btn
end

"""
Get the button's current text.
"""
function get_text(btn::ButtonWidget)::String
    if btn.text isa Signal
        return btn.text[]
    else
        return btn.text
    end
end

"""
Get button background color based on state.
"""
function get_button_background(btn::ButtonWidget)::String
    if !btn.props.enabled
        return "#9E9E9E"  # Disabled gray
    elseif btn.is_pressed
        if btn.variant == :primary
            return "#1565C0"  # Darker blue
        else
            return "#E0E0E0"
        end
    elseif btn.is_hovered
        if btn.variant == :primary
            return "#1976D2"  # Slightly darker blue
        else
            return "#EEEEEE"
        end
    else
        if btn.variant == :primary
            return "#2196F3"  # Primary blue
        elseif btn.variant == :secondary
            return "#757575"  # Secondary gray
        elseif btn.variant == :outline
            return "transparent"
        else
            return "transparent"
        end
    end
end

# ============================================================================
# Label Widget
# ============================================================================

"""
Label widget for displaying text.
"""
mutable struct LabelWidget <: Widget
    props::WidgetProps
    text::Union{String, Signal{String}}
    font_size::Float32
    font_weight::Symbol  # :normal, :bold
    color::String
    
    function LabelWidget(;
                         text::Union{String, Signal{String}} = "",
                         font_size::Float32 = 14.0f0,
                         font_weight::Symbol = :normal,
                         color::String = "#000000",
                         props::WidgetProps = WidgetProps())
        new(props, text, font_size, font_weight, color)
    end
end

"""
    label(; text="", kwargs...) -> LabelWidget

Create a label widget.
"""
function label(; text::Union{String, Signal{String}} = "",
               font_size::Float32 = 14.0f0,
               font_weight::Symbol = :normal,
               color::String = "#000000",
               kwargs...)
    props = WidgetProps(; kwargs...)
    lbl = LabelWidget(; text=text, font_size=font_size, font_weight=font_weight,
                       color=color, props=props)
    _add_to_parent(lbl)
    return lbl
end

# ============================================================================
# TextInput Widget
# ============================================================================

"""
Text input widget for single-line text entry.
"""
mutable struct TextInputWidget <: Widget
    props::WidgetProps
    value::Signal{String}
    placeholder::String
    on_change::Union{Function, Nothing}
    on_submit::Union{Function, Nothing}
    is_focused::Bool
    cursor_position::Int
    selection_start::Int
    selection_end::Int
    input_type::Symbol  # :text, :password, :email, :number
    
    function TextInputWidget(;
                             value::Union{String, Signal{String}} = "",
                             placeholder::String = "",
                             on_change::Union{Function, Nothing} = nothing,
                             on_submit::Union{Function, Nothing} = nothing,
                             input_type::Symbol = :text,
                             props::WidgetProps = WidgetProps())
        # Convert string to signal if needed
        sig_value = value isa Signal ? value : signal(value)
        
        # Set default styling
        if props.padding == 0.0f0 && props.padding_x == 0.0f0
            props.padding_x = 12.0f0
            props.padding_y = 8.0f0
        end
        if props.border_width == 0.0f0
            props.border_width = 1.0f0
            props.border_color = "#BDBDBD"
        end
        if props.border_radius == 0.0f0
            props.border_radius = 4.0f0
        end
        if props.background === nothing
            props.background = "#FFFFFF"
        end
        props.focusable = true
        props.role = :textbox
        
        new(props, sig_value, placeholder, on_change, on_submit,
            false, 0, 0, 0, input_type)
    end
end

"""
    text_input(; value="", placeholder="", kwargs...) -> TextInputWidget

Create a text input widget.
"""
function text_input(; value::Union{String, Signal{String}} = "",
                    placeholder::String = "",
                    on_change::Union{Function, Nothing} = nothing,
                    on_submit::Union{Function, Nothing} = nothing,
                    input_type::Symbol = :text,
                    kwargs...)
    props = WidgetProps(; kwargs...)
    input = TextInputWidget(; value=value, placeholder=placeholder,
                            on_change=on_change, on_submit=on_submit,
                            input_type=input_type, props=props)
    _add_to_parent(input)
    return input
end

# ============================================================================
# Checkbox Widget
# ============================================================================

"""
Checkbox widget for boolean values.
"""
mutable struct CheckboxWidget <: Widget
    props::WidgetProps
    checked::Signal{Bool}
    label::Union{String, Nothing}
    on_change::Union{Function, Nothing}
    is_hovered::Bool
    
    function CheckboxWidget(;
                            checked::Union{Bool, Signal{Bool}} = false,
                            label::Union{String, Nothing} = nothing,
                            on_change::Union{Function, Nothing} = nothing,
                            props::WidgetProps = WidgetProps())
        sig_checked = checked isa Signal ? checked : signal(checked)
        props.focusable = true
        props.role = :checkbox
        new(props, sig_checked, label, on_change, false)
    end
end

"""
    checkbox(; checked=false, label=nothing, kwargs...) -> CheckboxWidget

Create a checkbox widget.
"""
function checkbox(; checked::Union{Bool, Signal{Bool}} = false,
                  label::Union{String, Nothing} = nothing,
                  on_change::Union{Function, Nothing} = nothing,
                  kwargs...)
    props = WidgetProps(; kwargs...)
    cb = CheckboxWidget(; checked=checked, label=label, on_change=on_change, props=props)
    _add_to_parent(cb)
    return cb
end

# ============================================================================
# Slider Widget
# ============================================================================

"""
Slider widget for numeric range selection.
"""
mutable struct SliderWidget <: Widget
    props::WidgetProps
    value::Signal{Float32}
    min::Float32
    max::Float32
    step::Float32
    on_change::Union{Function, Nothing}
    is_dragging::Bool
    
    function SliderWidget(;
                          value::Union{Number, Signal{Float32}} = 0.0f0,
                          min::Float32 = 0.0f0,
                          max::Float32 = 100.0f0,
                          step::Float32 = 1.0f0,
                          on_change::Union{Function, Nothing} = nothing,
                          props::WidgetProps = WidgetProps())
        sig_value = if value isa Signal{Float32}
            value
        elseif value isa Signal
            # Convert other signal types
            signal(Float32(value[]))
        else
            signal(Float32(value))
        end
        
        if props.height === nothing
            props.height = 24.0f0
        end
        props.focusable = true
        props.role = :slider
        
        new(props, sig_value, min, max, step, on_change, false)
    end
end

"""
    slider(; min=0, max=100, value=0, kwargs...) -> SliderWidget

Create a slider widget.
"""
function slider(; value::Union{Number, Signal{Float32}} = 0.0f0,
                min::Float32 = 0.0f0,
                max::Float32 = 100.0f0,
                step::Float32 = 1.0f0,
                on_change::Union{Function, Nothing} = nothing,
                kwargs...)
    props = WidgetProps(; kwargs...)
    s = SliderWidget(; value=value, min=min, max=max, step=step,
                     on_change=on_change, props=props)
    _add_to_parent(s)
    return s
end

# ============================================================================
# Progress Bar Widget
# ============================================================================

"""
Progress bar widget for showing progress.
"""
mutable struct ProgressBarWidget <: Widget
    props::WidgetProps
    value::Union{Float32, Signal{Float32}}
    max::Float32
    indeterminate::Bool
    color::String
    
    function ProgressBarWidget(;
                               value::Union{Float32, Signal{Float32}} = 0.0f0,
                               max::Float32 = 100.0f0,
                               indeterminate::Bool = false,
                               color::String = "#2196F3",
                               props::WidgetProps = WidgetProps())
        if props.height === nothing
            props.height = 8.0f0
        end
        if props.background === nothing
            props.background = "#E0E0E0"
        end
        if props.border_radius == 0.0f0
            props.border_radius = 4.0f0
        end
        props.role = :progressbar
        
        new(props, value, max, indeterminate, color)
    end
end

"""
    progress_bar(; value=0, max=100, kwargs...) -> ProgressBarWidget

Create a progress bar widget.
"""
function progress_bar(; value::Union{Float32, Signal{Float32}} = 0.0f0,
                      max::Float32 = 100.0f0,
                      indeterminate::Bool = false,
                      color::String = "#2196F3",
                      kwargs...)
    props = WidgetProps(; kwargs...)
    pb = ProgressBarWidget(; value=value, max=max, indeterminate=indeterminate,
                           color=color, props=props)
    _add_to_parent(pb)
    return pb
end

# ============================================================================
# Spacer Widget
# ============================================================================

"""
Spacer widget for flexible spacing.
"""
mutable struct SpacerWidget <: Widget
    props::WidgetProps
    flex::Float32
    
    function SpacerWidget(; flex::Float32 = 1.0f0, props::WidgetProps = WidgetProps())
        new(props, flex)
    end
end

"""
    spacer(; flex=1) -> SpacerWidget

Create a spacer widget.
"""
function spacer(; flex::Float32 = 1.0f0, kwargs...)
    props = WidgetProps(; kwargs...)
    s = SpacerWidget(; flex=flex, props=props)
    _add_to_parent(s)
    return s
end

# ============================================================================
# Building Context
# ============================================================================

# Thread-local building context
const _PARENT_STACK = Ref{Vector{Widget}}(Widget[])

function _get_current_parent()::Union{Widget, Nothing}
    if isempty(_PARENT_STACK[])
        return nothing
    end
    return last(_PARENT_STACK[])
end

function _set_current_parent(widget::Union{Widget, Nothing})
    if widget === nothing
        if !isempty(_PARENT_STACK[])
            pop!(_PARENT_STACK[])
        end
    else
        push!(_PARENT_STACK[], widget)
    end
end

function _add_to_parent(widget::Widget)
    parent = _get_current_parent()
    if parent !== nothing && parent isa ContainerWidget
        push!(parent.children, widget)
    end
end

# ============================================================================
# UI Building
# ============================================================================

"""
    build_ui(f::Function) -> WidgetTree

Build a UI from a widget definition block.
"""
function build_ui(f::Function)::WidgetTree
    # Reset parent stack
    empty!(_PARENT_STACK[])
    
    # Create root container
    root = ContainerWidget(direction=:column)
    push!(_PARENT_STACK[], root)
    
    # Execute building block
    f()
    
    # Clean up
    empty!(_PARENT_STACK[])
    
    return WidgetTree(root)
end

# ============================================================================
# Rendering
# ============================================================================

"""
    render_widgets!(tree::WidgetTree; width::Int=800, height::Int=600)

Render the widget tree to Content-- primitives.
"""
function render_widgets!(tree::WidgetTree; width::Int=800, height::Int=600)
    # Create or reuse UI context
    if tree.ui_context === nothing
        tree.ui_context = create_ui()
    end
    
    ctx = tree.ui_context
    
    # Build Content-- source from widget tree
    source = _widget_to_content(tree.root)
    
    # Parse and render
    new_ctx = create_ui(source)
    tree.ui_context = new_ctx
    
    # Render using Cairo for high quality
    render_cairo!(tree.ui_context, width=width, height=height)
    
    tree.dirty = false
end

"""
Convert a widget to Content-- text format.
"""
function _widget_to_content(widget::Widget)::String
    io = IOBuffer()
    _write_widget(io, widget)
    return String(take!(io))
end

function _write_widget(io::IO, widget::ContainerWidget)
    dir = widget.direction == DIRECTION_RIGHT ? "Right" : "Down"
    
    # Build properties
    props = String[]
    push!(props, "Direction: $dir")
    
    if widget.gap > 0
        push!(props, "Gap: $(widget.gap)")
    end
    
    if widget.props.background !== nothing
        push!(props, "Fill: $(widget.props.background)")
    end
    
    if widget.props.padding > 0 || widget.props.padding_x > 0 || widget.props.padding_y > 0
        pad = widget.props.padding > 0 ? widget.props.padding : 
              max(widget.props.padding_x, widget.props.padding_y)
        push!(props, "Inset: $pad")
    end
    
    if widget.props.width !== nothing
        push!(props, "Width: $(widget.props.width)")
    end
    if widget.props.height !== nothing
        push!(props, "Height: $(widget.props.height)")
    end
    
    print(io, "Stack(")
    print(io, join(props, ", "))
    print(io, ")")
    
    if !isempty(widget.children)
        println(io, " {")
        for child in widget.children
            print(io, "    ")
            _write_widget(io, child)
            println(io, ";")
        end
        print(io, "}")
    end
end

function _write_widget(io::IO, widget::ButtonWidget)
    bg = get_button_background(widget)
    text = get_text(widget)
    
    props = String[]
    push!(props, "Fill: $bg")
    
    if widget.props.width !== nothing
        push!(props, "Width: $(widget.props.width)")
    end
    if widget.props.height !== nothing
        push!(props, "Height: $(widget.props.height)")
    end
    
    pad_x = widget.props.padding_x > 0 ? widget.props.padding_x : widget.props.padding
    pad_y = widget.props.padding_y > 0 ? widget.props.padding_y : widget.props.padding
    if pad_x > 0 || pad_y > 0
        push!(props, "Inset: ($(pad_y), $(pad_x), $(pad_y), $(pad_x))")
    end
    
    if widget.props.border_radius > 0
        push!(props, "Round: $(widget.props.border_radius)")
    end
    
    print(io, "Stack(")
    print(io, join(props, ", "))
    print(io, ") { Paragraph { Span(Text: \"$text\"); } }")
end

function _write_widget(io::IO, widget::LabelWidget)
    text = widget.text isa Signal ? widget.text[] : widget.text
    print(io, "Paragraph { Span(Text: \"$text\"); }")
end

function _write_widget(io::IO, widget::TextInputWidget)
    text = widget.value[]
    display_text = isempty(text) ? widget.placeholder : text
    
    bg = widget.props.background !== nothing ? widget.props.background : "#FFFFFF"
    border = widget.props.border_color !== nothing ? widget.props.border_color : "#BDBDBD"
    
    props = String["Fill: $bg"]
    
    if widget.props.width !== nothing
        push!(props, "Width: $(widget.props.width)")
    end
    if widget.props.height !== nothing
        push!(props, "Height: $(widget.props.height)")
    end
    
    pad_x = widget.props.padding_x > 0 ? widget.props.padding_x : widget.props.padding
    pad_y = widget.props.padding_y > 0 ? widget.props.padding_y : widget.props.padding
    if pad_x > 0 || pad_y > 0
        push!(props, "Inset: ($(pad_y), $(pad_x), $(pad_y), $(pad_x))")
    end
    
    print(io, "Stack(")
    print(io, join(props, ", "))
    print(io, ") { Paragraph { Span(Text: \"$display_text\"); } }")
end

function _write_widget(io::IO, widget::CheckboxWidget)
    is_checked = widget.checked[]
    box_bg = is_checked ? "#2196F3" : "#FFFFFF"
    
    print(io, "Stack(Direction: Right, Gap: 8) { ")
    print(io, "Rect(Size: (20, 20), Fill: $box_bg)")
    if widget.label !== nothing
        print(io, "; Paragraph { Span(Text: \"$(widget.label)\"); }")
    end
    print(io, " }")
end

function _write_widget(io::IO, widget::SliderWidget)
    value = widget.value[]
    percent = (value - widget.min) / (widget.max - widget.min) * 100
    
    track_bg = "#E0E0E0"
    fill_bg = "#2196F3"
    
    height = widget.props.height !== nothing ? widget.props.height : 24.0f0
    
    print(io, "Stack(Direction: Right) { ")
    print(io, "Rect(Size: ($(percent), $(height/3)), Fill: $fill_bg); ")
    print(io, "Rect(Size: ($(100-percent), $(height/3)), Fill: $track_bg)")
    print(io, " }")
end

function _write_widget(io::IO, widget::ProgressBarWidget)
    value = widget.value isa Signal ? widget.value[] : widget.value
    percent = (value / widget.max) * 100
    
    bg = widget.props.background !== nothing ? widget.props.background : "#E0E0E0"
    height = widget.props.height !== nothing ? widget.props.height : 8.0f0
    
    print(io, "Stack(Direction: Right, Fill: $bg) { ")
    print(io, "Rect(Size: ($percent, $height), Fill: $(widget.color))")
    print(io, " }")
end

function _write_widget(io::IO, widget::SpacerWidget)
    # Spacers are handled by flex layout, emit empty rect
    print(io, "Rect(Size: (1, 1))")
end

# Fallback for unknown widgets
function _write_widget(io::IO, widget::Widget)
    print(io, "Rect(Size: (50, 50), Fill: #FF00FF)")  # Magenta for debug
end

export render_widgets!

end # module Widgets
