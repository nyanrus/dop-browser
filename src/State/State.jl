"""
    State

Reactive state management for interactive UI applications.

This module provides an observable state system for building reactive UIs.
State changes automatically trigger UI updates.

## Core Concepts

- **Signal**: A reactive value that notifies observers when changed
- **Computed**: A derived value that automatically updates when dependencies change
- **Effect**: A side effect that runs when its dependencies change
- **Store**: A container for application state with actions

## Usage

```julia
using DOPBrowser.State

# Create reactive signals
count = signal(0)
name = signal("World")

# Create computed values
greeting = computed(() -> "Hello, \$(name())! Count: \$(count())")

# Create effects
effect(() -> println(greeting()))  # Prints on every change

# Update signals
count[] = count[] + 1  # Triggers effect
name[] = "Julia"       # Triggers effect

# Batch updates
batch(() -> begin
    count[] = 10
    name[] = "Everyone"
end)  # Effect runs once at end
```

## Store Pattern

```julia
# Define a store with initial state and actions
store = create_store(
    Dict(:count => 0, :todos => []),
    Dict(
        :increment => (state, payload) -> Dict(:count => state[:count] + 1),
        :add_todo => (state, todo) -> Dict(:todos => [state[:todos]..., todo])
    )
)

# Subscribe to changes
subscribe(store) do state
    println("State changed: ", state)
end

# Dispatch actions
dispatch(store, :increment)
dispatch(store, :add_todo, "Learn Julia")
```
"""
module State

export Signal, signal, Computed, computed, Effect, effect, batch
export Store, create_store, dispatch, subscribe, unsubscribe, get_state
export on_change, watch

# ============================================================================
# Reactive Context
# ============================================================================

"""
Global reactive context for tracking dependencies.
"""
mutable struct ReactiveContext
    # Currently tracking effect/computed
    current_observer::Union{Any, Nothing}
    # Batch update in progress
    is_batching::Bool
    # Pending notifications
    pending_notifications::Set{Any}
    # Observer ID counter
    next_id::UInt64
    
    ReactiveContext() = new(nothing, false, Set{Any}(), UInt64(1))
end

# Global reactive context
const CONTEXT = Ref{ReactiveContext}(ReactiveContext())

function get_context()::ReactiveContext
    return CONTEXT[]
end

function reset_context!()
    CONTEXT[] = ReactiveContext()
end

# ============================================================================
# Signal - Reactive Value
# ============================================================================

"""
    Signal{T}

A reactive value that notifies observers when changed.
"""
mutable struct Signal{T}
    id::UInt64
    value::T
    observers::Set{Any}  # Observers to notify on change
    comparator::Function  # Custom equality check
    
    function Signal{T}(value::T; comparator::Function = (===)) where T
        ctx = get_context()
        id = ctx.next_id
        ctx.next_id += 1
        new{T}(id, value, Set{Any}(), comparator)
    end
end

"""
    signal(initial_value::T; comparator = (===)) -> Signal{T}

Create a new reactive signal with an initial value.
"""
function signal(initial_value::T; comparator::Function = (===)) where T
    return Signal{T}(initial_value; comparator=comparator)
end

"""
Get the current value of a signal and register as dependency.
"""
function Base.getindex(s::Signal{T})::T where T
    ctx = get_context()
    
    # Track dependency if there's an active observer
    if ctx.current_observer !== nothing
        push!(s.observers, ctx.current_observer)
    end
    
    return s.value
end

"""
Set the value of a signal and notify observers.
"""
function Base.setindex!(s::Signal{T}, value::T) where T
    # Skip if value hasn't changed, then update and notify
    s.comparator(s.value, value) && return value
    s.value = value
    notify!(s)
    value
end

"""
Notify all observers of a signal change.
"""
function notify!(s::Signal)
    ctx = get_context()
    
    # Queue notifications for batch or notify immediately
    for observer in (ctx.is_batching ? s.observers : copy(s.observers))
        ctx.is_batching ? push!(ctx.pending_notifications, observer) :
                         try run!(observer) catch e; @warn "Error in observer" exception=e end
    end
end

"""
Remove an observer from a signal.
"""
function unobserve!(s::Signal, observer)
    delete!(s.observers, observer)
end

# Convenience: call syntax to get value
(s::Signal)() = s[]

# ============================================================================
# Computed - Derived Value
# ============================================================================

"""
    Computed{T}

A derived value that automatically updates when dependencies change.
"""
mutable struct Computed{T}
    id::UInt64
    compute::Function
    cached_value::T
    dependencies::Set{Signal}
    observers::Set{Any}
    is_dirty::Bool
    
    function Computed{T}(compute::Function, initial_value::T) where T
        ctx = get_context()
        id = ctx.next_id
        ctx.next_id += 1
        
        computed_obj = new{T}(id, compute, initial_value, Set{Signal}(), Set{Any}(), true)
        
        # Initial computation to set up dependencies
        recompute!(computed_obj)
        
        return computed_obj
    end
end

"""
    computed(f::Function) -> Computed

Create a computed value from a function.
"""
function computed(f::Function)
    # Infer type and initial value from first computation
    initial_value = f()
    T = typeof(initial_value)
    return Computed{T}(f, initial_value)
end

"""
Recompute the cached value and track dependencies.
"""
function recompute!(c::Computed)
    ctx = get_context()
    
    # Clear old dependencies
    for dep in c.dependencies
        unobserve!(dep, c)
    end
    empty!(c.dependencies)
    
    # Track new dependencies
    old_observer = ctx.current_observer
    ctx.current_observer = c
    
    try
        c.cached_value = c.compute()
        c.is_dirty = false
    finally
        ctx.current_observer = old_observer
    end
end

"""
Mark computed as dirty (needs recomputation).
"""
function run!(c::Computed)
    c.is_dirty = true
    
    # Notify our observers that we may have changed
    for observer in copy(c.observers)
        try
            run!(observer)
        catch e
            @warn "Error notifying computed observer" exception=e
        end
    end
end

"""
Get the current value of a computed.
"""
function Base.getindex(c::Computed{T})::T where T
    ctx = get_context()
    
    # Track dependency if there's an active observer
    if ctx.current_observer !== nothing
        push!(c.observers, ctx.current_observer)
    end
    
    # Recompute if dirty
    if c.is_dirty
        recompute!(c)
    end
    
    return c.cached_value
end

# Call syntax
(c::Computed)() = c[]

# ============================================================================
# Effect - Side Effects
# ============================================================================

"""
    Effect

A side effect that runs when its dependencies change.
"""
mutable struct Effect
    id::UInt64
    fn::Function
    dependencies::Set{Signal}
    is_active::Bool
    
    function Effect(fn::Function)
        ctx = get_context()
        id = ctx.next_id
        ctx.next_id += 1
        
        eff = new(id, fn, Set{Signal}(), true)
        
        # Run initially to set up dependencies
        run!(eff)
        
        return eff
    end
end

"""
    effect(f::Function) -> Effect

Create an effect that runs when its dependencies change.
"""
effect(f::Function) = Effect(f)

"""
Run the effect and track dependencies.
"""
function run!(e::Effect)
    if !e.is_active
        return
    end
    
    ctx = get_context()
    
    # Clear old dependencies
    for dep in e.dependencies
        unobserve!(dep, e)
    end
    empty!(e.dependencies)
    
    # Track new dependencies
    old_observer = ctx.current_observer
    ctx.current_observer = e
    
    try
        e.fn()
    finally
        ctx.current_observer = old_observer
    end
end

"""
    dispose!(e::Effect)

Dispose of an effect, removing all dependencies.
"""
function dispose!(e::Effect)
    e.is_active = false
    for dep in e.dependencies
        unobserve!(dep, e)
    end
    empty!(e.dependencies)
end

export dispose!

# ============================================================================
# Batching
# ============================================================================

"""
    batch(f::Function)

Batch multiple signal updates into a single notification.
"""
function batch(f::Function)
    ctx = get_context()
    
    if ctx.is_batching
        # Already batching, just run the function
        f()
        return
    end
    
    ctx.is_batching = true
    empty!(ctx.pending_notifications)
    
    try
        f()
    finally
        ctx.is_batching = false
        
        # Notify all pending observers
        for observer in ctx.pending_notifications
            try
                run!(observer)
            catch e
                @warn "Error in batched notification" exception=e
            end
        end
        empty!(ctx.pending_notifications)
    end
end

# ============================================================================
# Simple Change Listeners
# ============================================================================

"""
    on_change(signal::Signal, callback::Function) -> Function

Register a callback to run when a signal changes.
Returns an unsubscribe function.
"""
function on_change(s::Signal, callback::Function)
    # Create a wrapper effect
    eff = effect(() -> begin
        val = s[]
        callback(val)
    end)
    
    # Return unsubscribe function
    return () -> dispose!(eff)
end

"""
    watch(signals::Vector, callback::Function) -> Function

Watch multiple signals and call callback with their values when any change.
Returns an unsubscribe function.
"""
function watch(signals::Vector, callback::Function)
    eff = effect(() -> begin
        values = [s[] for s in signals]
        callback(values...)
    end)
    
    return () -> dispose!(eff)
end

# ============================================================================
# Store - Application State Container
# ============================================================================

"""
    Store

A container for application state with actions.
"""
mutable struct Store
    state::Signal{Dict{Symbol, Any}}
    actions::Dict{Symbol, Function}
    subscribers::Vector{Function}
    middleware::Vector{Function}
    
    function Store(initial_state::Dict{Symbol, Any},
                   actions::Dict{Symbol, Function} = Dict{Symbol, Function}())
        new(
            signal(initial_state),
            actions,
            Function[],
            Function[]
        )
    end
end

"""
    create_store(initial_state::Dict, actions::Dict) -> Store

Create a new store with initial state and actions.
"""
function create_store(initial_state::Dict{Symbol, Any},
                      actions::Dict{Symbol, Function} = Dict{Symbol, Function}())
    return Store(initial_state, actions)
end

"""
    get_state(store::Store) -> Dict{Symbol, Any}

Get the current state of the store.
"""
get_state(store::Store) = store.state[]

"""
    dispatch(store::Store, action::Symbol, payload = nothing)

Dispatch an action to update the store state.
"""
function dispatch(store::Store, action::Symbol, payload = nothing)
    if !haskey(store.actions, action)
        @warn "Unknown action" action=action
        return
    end
    
    # Get current state
    current_state = store.state[]
    
    # Apply middleware (if any)
    for middleware_fn in store.middleware
        payload = middleware_fn(action, payload)
    end
    
    # Call action handler
    handler = store.actions[action]
    updates = handler(current_state, payload)
    
    # Merge updates into state
    if updates !== nothing && isa(updates, Dict)
        new_state = merge(current_state, updates)
        store.state[] = new_state
        
        # Notify subscribers
        for subscriber in store.subscribers
            try
                subscriber(new_state)
            catch e
                @warn "Error in store subscriber" exception=e
            end
        end
    end
end

"""
    subscribe(store::Store, callback::Function) -> Function

Subscribe to store changes. Returns an unsubscribe function.
"""
function subscribe(store::Store, callback::Function)
    push!(store.subscribers, callback)
    
    # Return unsubscribe function
    return () -> begin
        filter!(f -> f !== callback, store.subscribers)
    end
end

"""
    subscribe(callback::Function, store::Store) -> Function

Subscribe to store changes (do-block syntax). Returns an unsubscribe function.
"""
function subscribe(callback::Function, store::Store)
    subscribe(store, callback)
end

"""
    unsubscribe(store::Store, callback::Function)

Unsubscribe a callback from store changes.
"""
function unsubscribe(store::Store, callback::Function)
    filter!(f -> f !== callback, store.subscribers)
end

"""
    add_middleware!(store::Store, middleware::Function)

Add middleware to the store for intercepting actions.
"""
function add_middleware!(store::Store, middleware::Function)
    push!(store.middleware, middleware)
end

export add_middleware!

# ============================================================================
# Selector - Efficient State Selection
# ============================================================================

"""
    selector(store::Store, select_fn::Function) -> Signal

Create a derived signal that selects a portion of store state.
"""
function selector(store::Store, select_fn::Function)
    result = signal(select_fn(get_state(store)))
    
    # Subscribe to store changes
    subscribe(store) do state
        new_value = select_fn(state)
        if result[] !== new_value
            result[] = new_value
        end
    end
    
    return result
end

export selector

# ============================================================================
# Utility Functions
# ============================================================================

"""
    peek(s::Signal) -> T

Get the value of a signal without tracking as a dependency.
"""
function peek(s::Signal{T})::T where T
    return s.value
end

export peek

"""
    untrack(f::Function)

Run a function without tracking any dependencies.
"""
function untrack(f::Function)
    ctx = get_context()
    old_observer = ctx.current_observer
    ctx.current_observer = nothing
    try
        return f()
    finally
        ctx.current_observer = old_observer
    end
end

export untrack

end # module State
