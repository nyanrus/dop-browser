# Precompile execution file for memo app
# This file is executed during compilation to trace code paths that should be precompiled

# Simulate the memo app execution in headless mode
ENV["HEADLESS"] = "1"
ENV["CI"] = "true"

println("=== Precompile Execution: Loading DOPBrowser ===")
using DOPBrowser
using DOPBrowser.RustContent
using DOPBrowser.RustRenderer
using DOPBrowser.State
using DOPBrowser.ApplicationUtils

println("=== Precompile Execution: Loading example script ===")
include(joinpath(dirname(dirname(@__FILE__)), "examples", "memo_app.jl"))

println("=== Precompile Execution: Creating initial memos ===")
memos = create_initial_memos()

println("=== Precompile Execution: Building UI ===")
builder = build_memo_ui(memos)

println("=== Precompile Execution: Testing signal operations ===")
memos_signal = signal(memos)
next_id = signal(4)

# Add a new memo
new_memo = Memo(id=next_id[], title="Test Note", content=["Test content"])
next_id[] += 1
memos_signal[] = [memos_signal[]..., new_memo]

# Remove a memo
memos_signal[] = memos_signal[][2:end]

println("=== Precompile Execution: Complete ===")
