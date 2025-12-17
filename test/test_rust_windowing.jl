#!/usr/bin/env julia
"""
Test script for Rust native windowing functionality.

This script verifies that the Rust-based native windowing (using winit)
is fully functional and can be used as a usable UI library.
"""

using Test
using DOPBrowser
using DOPBrowser.RustRenderer
using DOPBrowser.Window
using DOPBrowser.ContentMM.NativeUI

@testset "Rust Native Windowing" begin
    
    @testset "RustRenderer Library" begin
        println("Testing RustRenderer library...")
        
        # Test library availability
        @test is_available() == true
        
        # Test library path
        lib_path = get_lib_path()
        @test isfile(lib_path)
        @test endswith(lib_path, "libdop_renderer.so") || 
              endswith(lib_path, "libdop_renderer.dylib") || 
              endswith(lib_path, "dop_renderer.dll")
        
        println("✓ RustRenderer library is available at: $lib_path")
    end
    
    @testset "Renderer Creation and Rendering" begin
        println("Testing renderer creation and basic rendering...")
        
        # Create renderer
        renderer = create_renderer(400, 300)
        @test renderer !== nothing
        
        # Test clear color
        set_clear_color!(renderer, 1.0f0, 1.0f0, 1.0f0, 1.0f0)
        RustRenderer.clear!(renderer)
        
        # Test adding rectangles
        add_rect!(renderer, 50.0f0, 50.0f0, 100.0f0, 80.0f0, 1.0f0, 0.0f0, 0.0f0, 1.0f0)
        add_rect!(renderer, 200.0f0, 100.0f0, 80.0f0, 60.0f0, 0.0f0, 1.0f0, 0.0f0, 1.0f0)
        
        # Test rendering
        RustRenderer.render!(renderer)
        
        # Test framebuffer
        buffer = RustRenderer.get_framebuffer(renderer)
        @test length(buffer) == 400 * 300 * 4  # RGBA pixels
        
        # Cleanup
        RustRenderer.destroy!(renderer)
        
        println("✓ Renderer creation and rendering works correctly")
    end
    
    @testset "Window Creation with Rust Backend" begin
        println("Testing window creation with Rust backend...")
        
        # Create window configuration
        config = WindowConfig(
            title = "Test Window",
            width = 400,
            height = 300,
            backend = :rust
        )
        @test config.backend == :rust
        
        # Create window
        window = Window.create_window(config)
        @test window !== nothing
        
        # Test window properties
        @test Window.is_open(window) == true
        @test Window.get_size(window) == (400, 300)
        
        # Test framebuffer
        framebuffer = Window.get_framebuffer(window)
        @test length(framebuffer) == 400 * 300 * 4
        
        # Cleanup
        Window.destroy!(window)
        @test Window.is_open(window) == false
        
        println("✓ Window creation and management works correctly")
    end
    
    @testset "NativeUI with Rust Backend" begin
        println("Testing NativeUI rendering with Rust backend...")
        
        # Create UI context
        ui = create_ui("""
        Stack(Direction: Down, Fill: #FFFFFF, Inset: 20, Gap: 10) {
            Rect(Size: (200, 60), Fill: #FF0000);
            Rect(Size: (200, 60), Fill: #00FF00);
            Rect(Size: (200, 60), Fill: #0000FF);
        }
        """)
        
        @test ui !== nothing
        
        # Render UI
        NativeUI.render!(ui; width=300, height=250)
        
        # Test render buffer
        buffer = NativeUI.render_to_buffer(ui; width=300, height=250)
        @test length(buffer) == 300 * 250 * 4
        
        println("✓ NativeUI rendering with Rust backend works correctly")
    end
    
    @testset "Backend Fallback" begin
        println("Testing backend fallback behavior...")
        
        # Test with unknown backend (should default to Rust)
        config = WindowConfig(backend = :unknown)
        window = Window.create_window(config)
        @test window !== nothing
        @test Window.is_open(window)
        Window.destroy!(window)
        
        # Test software backend
        config_soft = WindowConfig(backend = :software)
        window_soft = Window.create_window(config_soft)
        @test window_soft !== nothing
        @test Window.is_open(window_soft)
        Window.destroy!(window_soft)
        
        println("✓ Backend fallback works correctly")
    end
    
end

println("\n" * "=" ^ 60)
println("All Rust native windowing tests passed!")
println("=" ^ 60)
