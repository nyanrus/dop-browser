"""
    EventLoop

Browser main event loop module.

This module provides the event loop infrastructure for the browser:
- Task scheduling
- Event dispatching
- Microtask queue
- Timer management
- Animation frame scheduling

## Architecture

The event loop follows the HTML5 event loop specification:
1. Execute oldest task from task queue
2. Execute all microtasks
3. Update rendering if needed
4. Request animation frame callbacks

## Usage

```julia
using DOPBrowser.EventLoop

loop = BrowserEventLoop()
schedule_task!(loop, task)
run_until_idle!(loop)
```
"""
module EventLoop

export BrowserEventLoop, Task, TaskType
export schedule_task!, schedule_microtask!, request_animation_frame!
export run_tick!, run_until_idle!, stop!

# Export TaskType enum values
export TASK_SCRIPT, TASK_TIMER, TASK_DOM, TASK_USER_INPUT, TASK_NETWORK, TASK_RENDER, TASK_IDLE

"""
    TaskType

Types of tasks in the event loop.
"""
@enum TaskType::UInt8 begin
    TASK_SCRIPT = 1        # Script execution
    TASK_TIMER = 2         # setTimeout/setInterval
    TASK_DOM = 3           # DOM manipulation
    TASK_USER_INPUT = 4    # User events (click, key, etc.)
    TASK_NETWORK = 5       # Network callbacks
    TASK_RENDER = 6        # Render frame
    TASK_IDLE = 7          # Idle callbacks
end

"""
    Task

A task in the event loop queue.
"""
mutable struct Task
    id::UInt64
    task_type::TaskType
    callback::Function
    scheduled_at::Float64
    deadline::Float64
    cancelled::Bool
    
    function Task(task_type::TaskType, callback::Function; 
                  deadline::Float64 = Inf)
        new(rand(UInt64), task_type, callback, time(), deadline, false)
    end
end

"""
    Microtask

A microtask (promise callbacks, mutation observers, etc.)
"""
struct Microtask
    callback::Function
end

"""
    AnimationFrameRequest

Request for animation frame callback.
"""
mutable struct AnimationFrameRequest
    id::UInt64
    callback::Function
    cancelled::Bool
    
    function AnimationFrameRequest(callback::Function)
        new(rand(UInt64), callback, false)
    end
end

"""
    BrowserEventLoop

The main browser event loop.

Manages task queues, microtasks, and rendering timing.
"""
mutable struct BrowserEventLoop
    # Task queues
    task_queue::Vector{Task}
    microtask_queue::Vector{Microtask}
    animation_frame_requests::Vector{AnimationFrameRequest}
    
    # Timing
    last_render_time::Float64
    target_frame_time::Float64  # e.g., 1/60 for 60fps
    
    # State
    is_running::Bool
    current_time::Float64
    
    # Callbacks
    on_render::Union{Function, Nothing}
    on_idle::Union{Function, Nothing}
    
    function BrowserEventLoop(; target_fps::Float64 = 60.0)
        new(
            Task[],
            Microtask[],
            AnimationFrameRequest[],
            0.0,
            1.0 / target_fps,
            false,
            time(),
            nothing,
            nothing
        )
    end
end

"""
    schedule_task!(loop::BrowserEventLoop, task::Task)

Add a task to the task queue.
"""
function schedule_task!(loop::BrowserEventLoop, task::Task)
    push!(loop.task_queue, task)
    return task.id
end

"""
    schedule_task!(loop::BrowserEventLoop, task_type::TaskType, callback::Function)

Create and schedule a task.
"""
function schedule_task!(loop::BrowserEventLoop, task_type::TaskType, callback::Function)
    task = Task(task_type, callback)
    return schedule_task!(loop, task)
end

"""
    schedule_microtask!(loop::BrowserEventLoop, callback::Function)

Schedule a microtask to run after the current task.
"""
function schedule_microtask!(loop::BrowserEventLoop, callback::Function)
    push!(loop.microtask_queue, Microtask(callback))
end

"""
    request_animation_frame!(loop::BrowserEventLoop, callback::Function) -> UInt64

Request a callback before the next repaint. Returns request ID.
"""
function request_animation_frame!(loop::BrowserEventLoop, callback::Function)::UInt64
    request = AnimationFrameRequest(callback)
    push!(loop.animation_frame_requests, request)
    return request.id
end

"""
    cancel_animation_frame!(loop::BrowserEventLoop, id::UInt64)

Cancel an animation frame request.
"""
function cancel_animation_frame!(loop::BrowserEventLoop, id::UInt64)
    for req in loop.animation_frame_requests
        if req.id == id
            req.cancelled = true
            break
        end
    end
end

export cancel_animation_frame!

"""
    run_microtasks!(loop::BrowserEventLoop)

Execute all queued microtasks.
"""
function run_microtasks!(loop::BrowserEventLoop)
    while !isempty(loop.microtask_queue)
        microtask = popfirst!(loop.microtask_queue)
        try
            microtask.callback()
        catch e
            # Log error but continue processing
            @error "Microtask error" exception=e
        end
    end
end

"""
    run_tick!(loop::BrowserEventLoop)

Run one iteration of the event loop:
1. Execute oldest task
2. Run all microtasks
3. Update rendering if needed
"""
function run_tick!(loop::BrowserEventLoop)
    loop.current_time = time()
    
    # 1. Execute one task from the queue
    if !isempty(loop.task_queue)
        task = popfirst!(loop.task_queue)
        if !task.cancelled
            try
                task.callback()
            catch e
                @error "Task error" exception=e
            end
        end
    end
    
    # 2. Run all microtasks
    run_microtasks!(loop)
    
    # 3. Check if we need to render
    if loop.current_time - loop.last_render_time >= loop.target_frame_time
        render_frame!(loop)
    end
end

"""
    render_frame!(loop::BrowserEventLoop)

Execute render frame operations:
1. Run animation frame callbacks
2. Call render callback
3. Update timing
"""
function render_frame!(loop::BrowserEventLoop)
    # Run animation frame callbacks
    requests = copy(loop.animation_frame_requests)
    empty!(loop.animation_frame_requests)
    
    for req in requests
        if !req.cancelled
            try
                req.callback(loop.current_time)
            catch e
                @error "Animation frame error" exception=e
            end
        end
    end
    
    # Run microtasks after animation frames
    run_microtasks!(loop)
    
    # Call render callback
    if loop.on_render !== nothing
        try
            loop.on_render()
        catch e
            @error "Render callback error" exception=e
        end
    end
    
    loop.last_render_time = loop.current_time
end

"""
    run_until_idle!(loop::BrowserEventLoop; max_iterations::Int = 1000)

Run the event loop until no more tasks are pending.
"""
function run_until_idle!(loop::BrowserEventLoop; max_iterations::Int = 1000)
    loop.is_running = true
    iterations = 0
    
    while loop.is_running && 
          (!isempty(loop.task_queue) || !isempty(loop.microtask_queue)) &&
          iterations < max_iterations
        run_tick!(loop)
        iterations += 1
    end
    
    # Call idle callback
    if loop.on_idle !== nothing && 
       isempty(loop.task_queue) && isempty(loop.microtask_queue)
        try
            loop.on_idle()
        catch e
            @error "Idle callback error" exception=e
        end
    end
    
    loop.is_running = false
    return iterations
end

"""
    stop!(loop::BrowserEventLoop)

Stop the event loop.
"""
function stop!(loop::BrowserEventLoop)
    loop.is_running = false
end

"""
    set_timeout!(loop::BrowserEventLoop, callback::Function, delay_ms::Int) -> UInt64

Schedule a callback to run after a delay. Returns task ID.
"""
function set_timeout!(loop::BrowserEventLoop, callback::Function, delay_ms::Int)::UInt64
    deadline = time() + delay_ms / 1000.0
    task = Task(TASK_TIMER, callback, deadline=deadline)
    return schedule_task!(loop, task)
end

export set_timeout!

"""
    set_interval!(loop::BrowserEventLoop, callback::Function, interval_ms::Int) -> UInt64

Schedule a callback to run repeatedly at an interval. Returns task ID.
"""
function set_interval!(loop::BrowserEventLoop, callback::Function, interval_ms::Int)::UInt64
    task_id = UInt64(0)
    
    function interval_callback()
        if !any(t -> t.id == task_id && t.cancelled, loop.task_queue)
            try
                callback()
            finally
                # Reschedule
                deadline = time() + interval_ms / 1000.0
                new_task = Task(TASK_TIMER, interval_callback, deadline=deadline)
                schedule_task!(loop, new_task)
            end
        end
    end
    
    deadline = time() + interval_ms / 1000.0
    task = Task(TASK_TIMER, interval_callback, deadline=deadline)
    task_id = schedule_task!(loop, task)
    return task_id
end

export set_interval!

"""
    clear_timeout!(loop::BrowserEventLoop, id::UInt64)

Cancel a scheduled timeout.
"""
function clear_timeout!(loop::BrowserEventLoop, id::UInt64)
    for task in loop.task_queue
        if task.id == id
            task.cancelled = true
            break
        end
    end
end

export clear_timeout!

end # module EventLoop
