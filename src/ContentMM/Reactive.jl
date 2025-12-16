"""
    Reactive

Content-- reactive system for dynamic values.

## Types of Reactive Values
1. Environment Switch: `Direction: (Down | desktop: Right)` - AOT resolved
2. Variable Injection: `Fill: var(PrimaryColor)` - Runtime resolution
3. Event Binding: `on: (pointer_enter: "hover_on")` - WASM runtime

## Implementation
- Environment switches are resolved to single values per `.bin` file
- Variable injection points to a VarMap in the host
- Event bindings map interactions to script logic
"""
module Reactive

using ..Environment: ExternalVarTable, get_external, set_external!
using ..Properties: Color, PropertyValue

export EventType, EVENT_POINTER_ENTER, EVENT_POINTER_LEAVE, EVENT_POINTER_DOWN,
       EVENT_POINTER_UP, EVENT_FOCUS, EVENT_BLUR, EVENT_KEY_DOWN, EVENT_KEY_UP
export EventBinding, EventBindingTable, VarReference, VarMap
export bind_event!, unbind_event!, get_bindings
export resolve_var, set_var!, create_var_reference

"""
    EventType

Types of events that can be bound.
"""
@enum EventType::UInt8 begin
    EVENT_POINTER_ENTER = 1
    EVENT_POINTER_LEAVE = 2
    EVENT_POINTER_DOWN = 3
    EVENT_POINTER_UP = 4
    EVENT_POINTER_MOVE = 5
    EVENT_CLICK = 6
    EVENT_DOUBLE_CLICK = 7
    EVENT_FOCUS = 8
    EVENT_BLUR = 9
    EVENT_KEY_DOWN = 10
    EVENT_KEY_UP = 11
    EVENT_SCROLL = 12
    EVENT_WHEEL = 13
end

"""
    EventBinding

Binding between an event and a handler.
"""
struct EventBinding
    node_id::UInt32
    event_type::EventType
    handler_id::UInt32  # Reference to script handler
    capture::Bool       # Capture phase or bubble phase
end

"""
    EventBindingTable

Table of event bindings for reactive interactions.
"""
mutable struct EventBindingTable
    bindings::Vector{EventBinding}
    # Index by node for fast lookup
    node_bindings::Dict{UInt32, Vector{UInt32}}  # node_id -> binding indices
    # Index by event type for delegation
    type_bindings::Dict{EventType, Vector{UInt32}}  # event_type -> binding indices
    
    function EventBindingTable()
        new(
            EventBinding[],
            Dict{UInt32, Vector{UInt32}}(),
            Dict{EventType, Vector{UInt32}}()
        )
    end
end

"""
    bind_event!(table::EventBindingTable, node_id::UInt32, 
                event_type::EventType, handler_id::UInt32;
                capture::Bool = false) -> UInt32

Create an event binding.
"""
function bind_event!(table::EventBindingTable, node_id::UInt32,
                     event_type::EventType, handler_id::UInt32;
                     capture::Bool = false)::UInt32
    binding = EventBinding(node_id, event_type, handler_id, capture)
    push!(table.bindings, binding)
    binding_id = UInt32(length(table.bindings))
    
    # Index by node
    if !haskey(table.node_bindings, node_id)
        table.node_bindings[node_id] = UInt32[]
    end
    push!(table.node_bindings[node_id], binding_id)
    
    # Index by type
    if !haskey(table.type_bindings, event_type)
        table.type_bindings[event_type] = UInt32[]
    end
    push!(table.type_bindings[event_type], binding_id)
    
    return binding_id
end

"""
    unbind_event!(table::EventBindingTable, binding_id::UInt32)

Remove an event binding.
"""
function unbind_event!(table::EventBindingTable, binding_id::UInt32)
    if binding_id == 0 || binding_id > length(table.bindings)
        return
    end
    
    binding = table.bindings[binding_id]
    
    # Remove from indices
    if haskey(table.node_bindings, binding.node_id)
        filter!(id -> id != binding_id, table.node_bindings[binding.node_id])
    end
    if haskey(table.type_bindings, binding.event_type)
        filter!(id -> id != binding_id, table.type_bindings[binding.event_type])
    end
    
    # Note: We don't remove from bindings vector to preserve IDs
end

"""
    get_bindings(table::EventBindingTable, node_id::UInt32) -> Vector{EventBinding}

Get all event bindings for a node.
"""
function get_bindings(table::EventBindingTable, node_id::UInt32)::Vector{EventBinding}
    if !haskey(table.node_bindings, node_id)
        return EventBinding[]
    end
    
    result = EventBinding[]
    for binding_id in table.node_bindings[node_id]
        if binding_id <= length(table.bindings)
            push!(result, table.bindings[binding_id])
        end
    end
    return result
end

"""
    VarReference

Reference to a runtime variable (var() syntax).
"""
struct VarReference
    var_id::UInt32        # ID in ExternalVarTable
    property::Symbol      # Property this var applies to
    fallback::Any         # Fallback value if var undefined
end

"""
    VarMap

Runtime variable map for dynamic styling.
"""
mutable struct VarMap
    references::Vector{VarReference}
    external_vars::ExternalVarTable
    # Node -> property -> reference mapping
    node_refs::Dict{UInt32, Dict{Symbol, UInt32}}
    
    function VarMap()
        new(
            VarReference[],
            ExternalVarTable(),
            Dict{UInt32, Dict{Symbol, UInt32}}()
        )
    end
end

"""
    create_var_reference!(varmap::VarMap, node_id::UInt32, 
                          property::Symbol, var_id::UInt32;
                          fallback = nothing) -> UInt32

Create a variable reference for a node property.
"""
function create_var_reference!(varmap::VarMap, node_id::UInt32,
                               property::Symbol, var_id::UInt32;
                               fallback = nothing)::UInt32
    ref = VarReference(var_id, property, fallback)
    push!(varmap.references, ref)
    ref_id = UInt32(length(varmap.references))
    
    if !haskey(varmap.node_refs, node_id)
        varmap.node_refs[node_id] = Dict{Symbol, UInt32}()
    end
    varmap.node_refs[node_id][property] = ref_id
    
    return ref_id
end

"""
    resolve_var(varmap::VarMap, ref_id::UInt32) -> Any

Resolve a variable reference to its current value.
"""
function resolve_var(varmap::VarMap, ref_id::UInt32)::Any
    if ref_id == 0 || ref_id > length(varmap.references)
        return nothing
    end
    
    ref = varmap.references[ref_id]
    value = get_external(varmap.external_vars, ref.var_id)
    
    if value === nothing
        return ref.fallback
    end
    return value
end

"""
    set_var!(varmap::VarMap, var_id::UInt32, value)

Set a runtime variable value (triggers style updates).
"""
function set_var!(varmap::VarMap, var_id::UInt32, value)
    set_external!(varmap.external_vars, var_id, value)
end

"""
    get_node_var_value(varmap::VarMap, node_id::UInt32, property::Symbol) -> Any

Get the resolved variable value for a node property.
"""
function get_node_var_value(varmap::VarMap, node_id::UInt32, property::Symbol)::Any
    if !haskey(varmap.node_refs, node_id)
        return nothing
    end
    if !haskey(varmap.node_refs[node_id], property)
        return nothing
    end
    
    ref_id = varmap.node_refs[node_id][property]
    return resolve_var(varmap, ref_id)
end

"""
    EnvironmentSwitch

Compile-time environment switch value.
Syntax: `Direction: (Down | desktop: Right)`
"""
struct EnvironmentSwitch
    default_value::Any
    env_values::Dict{UInt32, Any}  # env_id -> value
end

"""
    resolve_switch(switch::EnvironmentSwitch, env_id::UInt32) -> Any

Resolve an environment switch for a specific environment.
This is an AOT operation - result is baked into the binary.
"""
function resolve_switch(switch::EnvironmentSwitch, env_id::UInt32)::Any
    if haskey(switch.env_values, env_id)
        return switch.env_values[env_id]
    end
    return switch.default_value
end

end # module Reactive
