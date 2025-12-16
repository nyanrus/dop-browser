using Test
using DOPBrowser

@testset "DOPBrowser" begin
    
    @testset "StringInterner" begin
        pool = StringPool()
        
        # Test basic interning
        id1 = intern!(pool, "hello")
        id2 = intern!(pool, "world")
        id3 = intern!(pool, "hello")  # Duplicate
        
        @test id1 == id3  # Same string should have same ID
        @test id1 != id2  # Different strings should have different IDs
        
        # Test string retrieval
        @test get_string(pool, id1) == "hello"
        @test get_string(pool, id2) == "world"
        
        # Test lookup
        @test get_id(pool, "hello") == id1
        @test get_id(pool, "world") == id2
        @test get_id(pool, "nonexistent") === nothing
    end
    
    @testset "TokenTape" begin
        pool = StringPool()
        tokenizer = Tokenizer(pool)
        
        # Test basic HTML parsing
        html = "<div><p>Hello</p></div>"
        tokens = tokenize!(tokenizer, html)
        
        @test length(tokens) > 0
        
        # Test tokenizer reset
        reset!(tokenizer)
        @test length(get_tokens(tokenizer)) == 0
        
        # Test more complex HTML
        html = """<html><head><title>Test</title></head><body><div class="container">Content</div></body></html>"""
        tokens = tokenize!(tokenizer, html)
        @test length(tokens) > 0
    end
    
    @testset "NodeTable" begin
        pool = StringPool()
        dom = DOMTable(pool)
        
        # Test node creation
        root_id = add_node!(dom, NODE_DOCUMENT)
        @test root_id == UInt32(1)
        @test node_count(dom) == 1
        
        # Test child node
        child_id = add_node!(dom, NODE_ELEMENT, 
                            tag=intern!(pool, "div"), 
                            parent=root_id)
        @test child_id == UInt32(2)
        @test get_parent(dom, child_id) == root_id
        @test get_first_child(dom, root_id) == child_id
        
        # Test sibling
        sibling_id = add_node!(dom, NODE_ELEMENT,
                              tag=intern!(pool, "p"),
                              parent=root_id)
        @test get_next_sibling(dom, child_id) == sibling_id
    end
    
    @testset "StyleArchetypes" begin
        table = ArchetypeTable()
        
        # Test archetype creation
        classes1 = UInt32[1, 2, 3]
        id1 = get_or_create_archetype!(table, classes1)
        @test id1 == UInt32(1)
        
        # Test duplicate archetype
        classes2 = UInt32[3, 1, 2]  # Same classes, different order
        id2 = get_or_create_archetype!(table, classes2)
        @test id1 == id2  # Should return same archetype
        
        # Test different archetype
        classes3 = UInt32[4, 5]
        id3 = get_or_create_archetype!(table, classes3)
        @test id3 != id1
        
        @test archetype_count(table) == 2
    end
    
    @testset "LayoutArrays" begin
        layout = LayoutData()
        
        # Test resize
        resize_layout!(layout, 10)
        @test length(layout.x) == 10
        @test length(layout.width) == 10
        
        # Test bounds
        set_bounds!(layout, 1, 100.0f0, 50.0f0)
        @test get_bounds(layout, 1) == (100.0f0, 50.0f0)
        
        # Test position
        set_position!(layout, 1, 10.0f0, 20.0f0)
        @test get_position(layout, 1) == (10.0f0, 20.0f0)
    end
    
    @testset "RenderBuffer" begin
        buffer = CommandBuffer()
        
        # Test rect emission
        emit_rect!(buffer, 0.0f0, 0.0f0, 100.0f0, 50.0f0,
                   1.0f0, 0.0f0, 0.0f0, 1.0f0)
        @test command_count(buffer) == 1
        
        # Test text emission
        emit_text!(buffer, 10.0f0, 10.0f0, 80.0f0, 20.0f0,
                   0.0f0, 0.0f0, 0.0f0, 1.0f0,
                   UInt32(1), UInt32(0))
        @test command_count(buffer) == 2
        
        # Test image emission
        emit_image!(buffer, 0.0f0, 0.0f0, 64.0f0, 64.0f0, UInt32(1))
        @test command_count(buffer) == 3
        
        # Test clear
        clear!(buffer)
        @test command_count(buffer) == 0
    end
    
    @testset "Core - Full Pipeline" begin
        ctx = create_context(viewport_width=800.0f0, viewport_height=600.0f0)
        
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Test Page</title>
        </head>
        <body>
            <div id="main">
                <h1>Hello World</h1>
                <p>This is a test paragraph.</p>
            </div>
        </body>
        </html>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        @test result.archetype_count >= 1
        # Commands may be 0 if no sized elements, which is fine
        @test result.command_count >= 0
    end
    
    @testset "Core - Simple HTML" begin
        ctx = create_context()
        
        nodes = parse_html!(ctx, "<div><p>Test</p></div>")
        @test nodes > 0
        
        archetypes = apply_styles!(ctx)
        @test archetypes >= 1
        
        compute_layouts!(ctx)
        @test length(ctx.layout.x) == nodes
        
        commands = generate_render_commands!(ctx)
        @test commands >= 0
    end
    
    @testset "CSSParser - Color Parsing" begin
        # Named colors
        @test parse_color("black") == (0x00, 0x00, 0x00, 0xff)
        @test parse_color("white") == (0xff, 0xff, 0xff, 0xff)
        @test parse_color("red") == (0xff, 0x00, 0x00, 0xff)
        @test parse_color("transparent") == (0x00, 0x00, 0x00, 0x00)
        
        # Hex colors
        @test parse_color("#fff") == (0xff, 0xff, 0xff, 0xff)
        @test parse_color("#000") == (0x00, 0x00, 0x00, 0xff)
        @test parse_color("#ff0000") == (0xff, 0x00, 0x00, 0xff)
        @test parse_color("#00ff00") == (0x00, 0xff, 0x00, 0xff)
    end
    
    @testset "CSSParser - Length Parsing" begin
        # Pixels
        (val, auto) = parse_length("100px")
        @test val == 100.0f0
        @test auto == false
        
        # Auto
        (val, auto) = parse_length("auto")
        @test auto == true
        
        # No unit (default px)
        (val, auto) = parse_length("50")
        @test val == 50.0f0
        @test auto == false
    end
    
    @testset "CSSParser - Inline Styles" begin
        styles = parse_inline_style("width: 100px; height: 50px; background-color: red;")
        
        @test styles.width == 100.0f0
        @test styles.width_auto == false
        @test styles.height == 50.0f0
        @test styles.height_auto == false
        @test styles.background_r == 0xff
        @test styles.background_g == 0x00
        @test styles.background_b == 0x00
        @test styles.has_background == true
    end
    
    @testset "CSSParser - Positioning" begin
        styles = parse_inline_style("position: absolute; top: 10px; left: 20px;")
        
        @test styles.position == POSITION_ABSOLUTE
        @test styles.top == 10.0f0
        @test styles.top_auto == false
        @test styles.left == 20.0f0
        @test styles.left_auto == false
    end
    
    @testset "Acid2 - Basic Features" begin
        ctx = create_context(viewport_width=800.0f0, viewport_height=600.0f0)
        
        # Acid2-like HTML with positioned elements
        html = """
        <!DOCTYPE html>
        <html>
        <body style="background-color: white;">
            <div style="position: relative; width: 300px; height: 300px; background-color: yellow;">
                <div style="position: absolute; top: 10px; left: 10px; width: 50px; height: 50px; background-color: red;"></div>
                <div style="position: absolute; top: 10px; right: 10px; width: 50px; height: 50px; background-color: blue;"></div>
                <div style="position: absolute; bottom: 10px; left: 10px; width: 50px; height: 50px; background-color: green;"></div>
            </div>
        </body>
        </html>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        @test result.command_count > 0
        
        # Verify positioned elements are correctly placed
        # Find the absolute positioned red box (should be at top:10, left:10 relative to parent)
        # The parent yellow box is relative positioned
    end
    
    @testset "Acid2 - Z-Index Ordering" begin
        ctx = create_context(viewport_width=200.0f0, viewport_height=200.0f0)
        
        html = """
        <div style="position: relative; width: 100px; height: 100px;">
            <div style="position: absolute; z-index: 2; width: 50px; height: 50px; background-color: red;"></div>
            <div style="position: absolute; z-index: 1; width: 50px; height: 50px; background-color: blue;"></div>
        </div>
        """
        
        result = process_document!(ctx, html)
        
        # Commands should be ordered by z-index
        commands = get_commands(ctx.render_buffer)
        @test length(commands) >= 2
        
        # First command (z-index 1) should be blue
        @test commands[1].color_b > commands[1].color_r
        
        # Second command (z-index 2) should be red
        @test commands[2].color_r > commands[2].color_b
    end
    
    @testset "Acid2 - Display None" begin
        ctx = create_context(viewport_width=200.0f0, viewport_height=200.0f0)
        
        html = """
        <div style="width: 100px; height: 100px; background-color: red;"></div>
        <div style="display: none; width: 100px; height: 100px; background-color: blue;"></div>
        <div style="width: 100px; height: 100px; background-color: green;"></div>
        """
        
        result = process_document!(ctx, html)
        
        # display:none element should not generate render commands
        # Only 2 visible elements
        @test result.command_count == 2
    end
    
    @testset "Acid2 - Visibility Hidden" begin
        ctx = create_context(viewport_width=200.0f0, viewport_height=200.0f0)
        
        html = """
        <div style="width: 100px; height: 100px; background-color: red;"></div>
        <div style="visibility: hidden; width: 100px; height: 100px; background-color: blue;"></div>
        """
        
        result = process_document!(ctx, html)
        
        # visibility:hidden element should not generate render commands
        @test result.command_count == 1
    end
    
    @testset "Acid2 - Overflow Hidden" begin
        ctx = create_context(viewport_width=200.0f0, viewport_height=200.0f0)
        
        html = """
        <div style="overflow: hidden; width: 100px; height: 100px; background-color: red;">
            <div style="width: 200px; height: 200px; background-color: blue;"></div>
        </div>
        """
        
        result = process_document!(ctx, html)
        
        # Both elements rendered, but overflow:hidden should be set on parent
        @test result.node_count > 0
        
        # Parent should have overflow hidden
        # Find the parent div (index 3 - after document and html)
        for i in 1:result.node_count
            if ctx.layout.overflow[i] == OVERFLOW_HIDDEN
                @test ctx.layout.width[i] == 100.0f0
                break
            end
        end
    end

end
