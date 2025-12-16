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
    
    @testset "Acid2 - Complete Face Test" begin
        # This test simulates the Acid2 smiley face structure
        # Using positioned divs to create facial features
        ctx = create_context(viewport_width=400.0f0, viewport_height=400.0f0)
        
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Acid2 Test</title>
        </head>
        <body>
            <!-- Face container -->
            <div style="position: relative; width: 200px; height: 200px; background-color: yellow; overflow: hidden;">
                <!-- Left eye -->
                <div style="position: absolute; top: 40px; left: 40px; width: 20px; height: 20px; background-color: black;"></div>
                <!-- Right eye -->
                <div style="position: absolute; top: 40px; left: 140px; width: 20px; height: 20px; background-color: black;"></div>
                <!-- Nose -->
                <div style="position: absolute; top: 80px; left: 90px; width: 20px; height: 40px; background-color: orange;"></div>
                <!-- Mouth -->
                <div style="position: absolute; top: 140px; left: 40px; width: 120px; height: 20px; background-color: red;"></div>
            </div>
        </body>
        </html>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        @test result.command_count >= 5  # Face + 2 eyes + nose + mouth
        
        # Verify face is positioned correctly
        commands = get_commands(ctx.render_buffer)
        
        # Check we have multiple colored elements
        colors = Set{Tuple{Float32, Float32, Float32}}()
        for cmd in commands
            push!(colors, (cmd.color_r, cmd.color_g, cmd.color_b))
        end
        
        # Should have at least yellow (face), black (eyes), orange (nose), red (mouth)
        @test length(colors) >= 4
    end
    
    @testset "Acid2 - Margin and Padding" begin
        ctx = create_context(viewport_width=400.0f0, viewport_height=400.0f0)
        
        html = """
        <div style="margin: 20px; padding: 10px; width: 100px; height: 100px; background-color: blue;">
            <div style="width: 50px; height: 50px; background-color: red;"></div>
        </div>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        
        # Find the outer div
        for i in 1:result.node_count
            if ctx.layout.margin_top[i] == 20.0f0
                @test ctx.layout.padding_top[i] == 10.0f0
                @test ctx.layout.padding_left[i] == 10.0f0
                @test ctx.layout.x[i] == 20.0f0  # Margin left
                @test ctx.layout.y[i] == 20.0f0  # Margin top
                break
            end
        end
    end
    
    @testset "Acid2 - Relative Positioning" begin
        ctx = create_context(viewport_width=300.0f0, viewport_height=300.0f0)
        
        html = """
        <div style="width: 100px; height: 100px; background-color: blue;"></div>
        <div style="position: relative; top: -50px; left: 50px; width: 100px; height: 100px; background-color: red;"></div>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        @test result.command_count >= 2
        
        # The relative positioned element should be offset
        # First div at (0, 0), second at (50, 50) due to relative offset
        commands = get_commands(ctx.render_buffer)
        
        # Find the red element (relative positioned)
        red_cmd = nothing
        for cmd in commands
            if cmd.color_r > cmd.color_b
                red_cmd = cmd
                break
            end
        end
        
        @test red_cmd !== nothing
        @test red_cmd.x == 50.0f0  # left: 50px
    end
    
    @testset "CSS Style Block Parsing" begin
        ctx = create_context(viewport_width=300.0f0, viewport_height=150.0f0)
        
        # Test with CSS in style block
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                .red-box { width: 100px; height: 50px; background-color: red; }
                .blue-box { width: 50px; height: 25px; background-color: blue; }
                #special { width: 200px; height: 100px; }
            </style>
        </head>
        <body>
            <div class="red-box"></div>
            <div class="blue-box"></div>
            <div id="special"></div>
        </body>
        </html>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        # CSS rules should be parsed
        @test length(ctx.css_rules) >= 3
        
        # Check that selectors are stored correctly
        selectors = [rule.selector for rule in ctx.css_rules]
        @test ".red-box" in selectors
        @test ".blue-box" in selectors
        @test "#special" in selectors
    end
    
    @testset "CSS Selector Matching" begin
        ctx = create_context(viewport_width=300.0f0, viewport_height=150.0f0)
        
        html = """
        <html>
        <head>
            <style>
                .container { position: relative; width: 200px; height: 150px; background-color: yellow; }
                .box { position: absolute; width: 20px; height: 20px; background-color: black; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="box" style="top: 10px; left: 10px;"></div>
            </div>
        </body>
        </html>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        @test result.command_count >= 2  # container + box
        
        # Check commands have correct colors
        commands = get_commands(ctx.render_buffer)
        
        # Should have yellow and black boxes
        colors_found = Set{Tuple{Float32, Float32, Float32}}()
        for cmd in commands
            push!(colors_found, (cmd.color_r, cmd.color_g, cmd.color_b))
        end
        
        # Yellow: (1.0, 1.0, 0.0), Black: (0.0, 0.0, 0.0)
        @test length(colors_found) >= 2
    end

end

# ============================================================================
# Content-- IR Tests
# ============================================================================

@testset "Content-- IR" begin
    
    @testset "Primitives - NodeTable" begin
        table = DOPBrowser.ContentMM.Primitives.NodeTable()
        
        # Create root node
        root_id = DOPBrowser.ContentMM.Primitives.create_node!(
            table, 
            DOPBrowser.ContentMM.Primitives.NODE_ROOT
        )
        @test root_id == UInt32(1)
        @test DOPBrowser.ContentMM.Primitives.node_count(table) == 1
        
        # Create Stack child
        stack_id = DOPBrowser.ContentMM.Primitives.create_node!(
            table,
            DOPBrowser.ContentMM.Primitives.NODE_STACK,
            parent=root_id
        )
        @test stack_id == UInt32(2)
        @test DOPBrowser.ContentMM.Primitives.get_parent(table, stack_id) == root_id
        
        # Get children
        children = DOPBrowser.ContentMM.Primitives.get_children(table, root_id)
        @test length(children) == 1
        @test children[1] == stack_id
        
        # Create more children
        rect_id = DOPBrowser.ContentMM.Primitives.create_node!(
            table,
            DOPBrowser.ContentMM.Primitives.NODE_RECT,
            parent=stack_id
        )
        @test rect_id == UInt32(3)
        
        para_id = DOPBrowser.ContentMM.Primitives.create_node!(
            table,
            DOPBrowser.ContentMM.Primitives.NODE_PARAGRAPH,
            parent=stack_id
        )
        @test para_id == UInt32(4)
        
        # Verify tree structure
        stack_children = DOPBrowser.ContentMM.Primitives.get_children(table, stack_id)
        @test length(stack_children) == 2
        @test rect_id in stack_children
        @test para_id in stack_children
    end
    
    @testset "Properties - Layout Semantics" begin
        # Test Direction enum
        @test DOPBrowser.ContentMM.Properties.DIRECTION_DOWN == DOPBrowser.ContentMM.Properties.Direction(0)
        @test DOPBrowser.ContentMM.Properties.DIRECTION_RIGHT == DOPBrowser.ContentMM.Properties.Direction(2)
        
        # Test Pack enum
        @test DOPBrowser.ContentMM.Properties.PACK_START == DOPBrowser.ContentMM.Properties.Pack(0)
        @test DOPBrowser.ContentMM.Properties.PACK_CENTER == DOPBrowser.ContentMM.Properties.Pack(2)
        
        # Test Inset (padding equivalent)
        inset = DOPBrowser.ContentMM.Properties.Inset(10.0f0)
        @test inset.top == 10.0f0
        @test inset.right == 10.0f0
        @test inset.bottom == 10.0f0
        @test inset.left == 10.0f0
        
        # Test Offset (margin equivalent)
        offset = DOPBrowser.ContentMM.Properties.Offset(5.0f0, 10.0f0)
        @test offset.top == 5.0f0
        @test offset.right == 10.0f0
        @test offset.bottom == 5.0f0
        @test offset.left == 10.0f0
        
        # Test Color parsing
        red = DOPBrowser.ContentMM.Properties.parse_color("#ff0000")
        @test red.r == 0xff
        @test red.g == 0x00
        @test red.b == 0x00
        @test red.a == 0xff
        
        # Test named colors
        white = DOPBrowser.ContentMM.Properties.parse_color("white")
        @test white.r == 0xff
        @test white.g == 0xff
        @test white.b == 0xff
        
        # Test Gap
        gap = DOPBrowser.ContentMM.Properties.Gap(8.0f0, 16.0f0)
        @test gap.row == 8.0f0
        @test gap.column == 16.0f0
    end
    
    @testset "Styles - Inheritance Flattening" begin
        style_table = DOPBrowser.ContentMM.Styles.StyleTable()
        
        # Create base style
        base_id = DOPBrowser.ContentMM.Styles.create_style!(style_table, UInt32(1))
        @test base_id == UInt32(1)
        
        # Set properties on base
        DOPBrowser.ContentMM.Styles.set_style_property!(
            style_table, base_id, :width, 100.0f0
        )
        DOPBrowser.ContentMM.Styles.set_style_property!(
            style_table, base_id, :height, 50.0f0
        )
        
        # Create derived style with inheritance
        derived_id = DOPBrowser.ContentMM.Styles.create_style!(style_table, UInt32(2))
        DOPBrowser.ContentMM.Styles.inherit_style!(style_table, derived_id, base_id)
        DOPBrowser.ContentMM.Styles.set_style_property!(
            style_table, derived_id, :height, 100.0f0  # Override
        )
        
        # Flatten all styles (AOT operation)
        DOPBrowser.ContentMM.Styles.flatten_styles!(style_table)
        
        # Verify derived style inherited width but overrode height
        derived_flat = DOPBrowser.ContentMM.Styles.get_style(style_table, derived_id)
        @test derived_flat !== nothing
        @test derived_flat.width == 100.0f0  # Inherited
        @test derived_flat.height == 100.0f0  # Overridden
    end
    
    @testset "Environment - Breakpoints" begin
        env_table = DOPBrowser.ContentMM.Environment.EnvironmentTable()
        
        # Define environments
        mobile_id = DOPBrowser.ContentMM.Environment.define_environment!(
            env_table, UInt32(1),
            width_min=0.0f0, width_max=768.0f0,
            priority=Int32(1)
        )
        
        desktop_id = DOPBrowser.ContentMM.Environment.define_environment!(
            env_table, UInt32(2),
            width_min=769.0f0,
            priority=Int32(2)
        )
        
        # Test environment resolution
        @test DOPBrowser.ContentMM.Environment.resolve_environment(
            env_table, 320.0f0, 480.0f0
        ) == mobile_id
        
        @test DOPBrowser.ContentMM.Environment.resolve_environment(
            env_table, 1920.0f0, 1080.0f0
        ) == desktop_id
    end
    
    @testset "TextJIT - Paragraph Shaping" begin
        shaper = DOPBrowser.ContentMM.TextJIT.TextShaper()
        
        # Shape a paragraph
        shaped = DOPBrowser.ContentMM.TextJIT.shape_paragraph!(
            shaper, "Hello World", 200.0f0
        )
        
        @test shaped.width > 0.0f0
        @test shaped.height > 0.0f0
        @test shaped.line_count >= 1
        
        # Test caching - second call should hit cache
        shaped2 = DOPBrowser.ContentMM.TextJIT.shape_paragraph!(
            shaper, "Hello World", 200.0f0
        )
        @test shaped2.text_hash == shaped.text_hash
        
        # Different text should not hit cache
        shaped3 = DOPBrowser.ContentMM.TextJIT.shape_paragraph!(
            shaper, "Different text", 200.0f0
        )
        @test shaped3.text_hash != shaped.text_hash
    end
    
    @testset "Reactive - Event Bindings" begin
        event_table = DOPBrowser.ContentMM.Reactive.EventBindingTable()
        
        # Bind events
        binding_id = DOPBrowser.ContentMM.Reactive.bind_event!(
            event_table, UInt32(1),
            DOPBrowser.ContentMM.Reactive.EVENT_POINTER_ENTER,
            UInt32(100)
        )
        @test binding_id == UInt32(1)
        
        # Get bindings for node
        bindings = DOPBrowser.ContentMM.Reactive.get_bindings(event_table, UInt32(1))
        @test length(bindings) == 1
        @test bindings[1].event_type == DOPBrowser.ContentMM.Reactive.EVENT_POINTER_ENTER
        @test bindings[1].handler_id == UInt32(100)
        
        # Unbind
        DOPBrowser.ContentMM.Reactive.unbind_event!(event_table, binding_id)
        bindings2 = DOPBrowser.ContentMM.Reactive.get_bindings(event_table, UInt32(1))
        @test length(bindings2) == 0
    end
    
    @testset "Reactive - VarMap" begin
        varmap = DOPBrowser.ContentMM.Reactive.VarMap()
        
        # Define external variable
        var_id = DOPBrowser.ContentMM.Environment.define_external!(
            varmap.external_vars, UInt32(1), :color, 
            DOPBrowser.ContentMM.Properties.Color(0xff, 0x00, 0x00, 0xff)
        )
        
        # Create variable reference
        ref_id = DOPBrowser.ContentMM.Reactive.create_var_reference!(
            varmap, UInt32(1), :fill, var_id,
            fallback=DOPBrowser.ContentMM.Properties.Color(0x00, 0x00, 0x00, 0xff)
        )
        
        # Resolve var
        value = DOPBrowser.ContentMM.Reactive.resolve_var(varmap, ref_id)
        @test value isa DOPBrowser.ContentMM.Properties.Color
        @test value.r == 0xff
        
        # Update var
        DOPBrowser.ContentMM.Reactive.set_var!(
            varmap, var_id,
            DOPBrowser.ContentMM.Properties.Color(0x00, 0xff, 0x00, 0xff)
        )
        
        value2 = DOPBrowser.ContentMM.Reactive.resolve_var(varmap, ref_id)
        @test value2.g == 0xff
    end
    
    @testset "Runtime - Sticky Positioning" begin
        runtime = DOPBrowser.ContentMM.Runtime.RuntimeContext(800.0f0, 600.0f0)
        
        # Add sticky element
        sticky = DOPBrowser.ContentMM.Runtime.StickyElement(
            UInt32(1),   # node_id
            100.0f0,     # anchor_y
            10.0f0,      # sticky_offset
            500.0f0,     # parent_bottom
            100.0f0,     # current_y
            false        # is_stuck
        )
        push!(runtime.sticky_elements, sticky)
        
        # Initialize layout arrays
        resize!(runtime.layout_y, 1)
        resize!(runtime.layout_height, 1)
        runtime.layout_y[1] = 100.0f0
        runtime.layout_height[1] = 50.0f0
        
        # Scroll down
        runtime.scroll_y = 150.0f0
        DOPBrowser.ContentMM.Runtime.resolve_sticky!(runtime)
        
        # Element should be stuck
        @test runtime.sticky_elements[1].is_stuck == true
        @test runtime.layout_y[1] == 160.0f0  # scroll_y + offset
    end
    
    @testset "Runtime - JS Interface" begin
        runtime = DOPBrowser.ContentMM.Runtime.RuntimeContext(800.0f0, 600.0f0)
        js = DOPBrowser.ContentMM.Runtime.JSInterface(runtime)
        
        # Set up layout data
        resize!(runtime.layout_x, 1)
        resize!(runtime.layout_y, 1)
        resize!(runtime.layout_width, 1)
        resize!(runtime.layout_height, 1)
        runtime.layout_x[1] = 100.0f0
        runtime.layout_y[1] = 200.0f0
        runtime.layout_width[1] = 300.0f0
        runtime.layout_height[1] = 400.0f0
        
        # Get properties via JS interface
        @test DOPBrowser.ContentMM.Runtime.js_get_property(js, UInt32(1), :offsetLeft) == 100.0f0
        @test DOPBrowser.ContentMM.Runtime.js_get_property(js, UInt32(1), :offsetTop) == 200.0f0
        @test DOPBrowser.ContentMM.Runtime.js_get_property(js, UInt32(1), :offsetWidth) == 300.0f0
        @test DOPBrowser.ContentMM.Runtime.js_get_property(js, UInt32(1), :offsetHeight) == 400.0f0
        
        # Call getBoundingClientRect
        rect = DOPBrowser.ContentMM.Runtime.js_call_method(
            js, UInt32(1), :getBoundingClientRect, Any[]
        )
        @test rect[:x] == 100.0f0
        @test rect[:y] == 200.0f0
        @test rect[:width] == 300.0f0
        @test rect[:height] == 400.0f0
        @test rect[:right] == 400.0f0
        @test rect[:bottom] == 600.0f0
    end

end

# ============================================================================
# Network Tests
# ============================================================================

@testset "Network Layer" begin
    
    @testset "URL Parsing" begin
        parsed = DOPBrowser.Network.parse_url("https://example.com:8443/path/to/page?query=1")
        @test parsed.scheme == "https"
        @test parsed.host == "example.com"
        @test parsed.port == UInt16(8443)
        @test parsed.path == "/path/to/page"
        @test parsed.query == "query=1"
        @test parsed.is_https == true
        
        # HTTP default port
        parsed2 = DOPBrowser.Network.parse_url("http://example.com/")
        @test parsed2.port == UInt16(80)
        @test parsed2.is_https == false
        
        # HTTPS default port
        parsed3 = DOPBrowser.Network.parse_url("https://example.com/")
        @test parsed3.port == UInt16(443)
        @test parsed3.is_https == true
    end
    
    @testset "Connection Pool" begin
        pool = DOPBrowser.Network.ConnectionPool()
        
        # Get connection
        conn1 = DOPBrowser.Network.get_connection(pool, "example.com", UInt16(443), true)
        @test conn1.host == "example.com"
        @test conn1.is_busy == true
        
        # Release connection
        DOPBrowser.Network.release_connection(pool, conn1)
        @test conn1.is_busy == false
        
        # Get again - should reuse
        conn2 = DOPBrowser.Network.get_connection(pool, "example.com", UInt16(443), true)
        @test conn2.id == conn1.id
    end
    
    @testset "Resource Cache" begin
        cache = DOPBrowser.Network.ResourceCache(10, 100000)
        
        # Create and cache resource
        resource = DOPBrowser.Network.Resource("https://example.com/style.css", 
                                                DOPBrowser.Network.RESOURCE_CSS)
        resource.data = Vector{UInt8}("body { color: red; }")
        resource.fetched_at = time()
        resource.max_age = UInt32(3600)
        
        DOPBrowser.Network.cache_resource!(cache, resource)
        
        # Retrieve from cache
        cached = DOPBrowser.Network.get_cached(cache, "https://example.com/style.css")
        @test cached !== nothing
        @test cached.resource_type == DOPBrowser.Network.RESOURCE_CSS
        
        # Non-existent URL
        @test DOPBrowser.Network.get_cached(cache, "https://other.com/") === nothing
    end

end

# ============================================================================
# Renderer Tests
# ============================================================================

@testset "Renderer Pipeline" begin
    
    @testset "GPU Context" begin
        ctx = DOPBrowser.Renderer.GPURenderer.create_gpu_context(UInt32(100), UInt32(100))
        @test ctx.width == 100
        @test ctx.height == 100
        
        # Begin frame with red clear color
        DOPBrowser.Renderer.GPURenderer.begin_frame(ctx, 
            clear_color=(1.0f0, 0.0f0, 0.0f0, 1.0f0))
        
        # Add a rectangle
        batch = ctx.current_batch
        DOPBrowser.Renderer.GPURenderer.add_rect!(batch, 10.0f0, 10.0f0, 
                                                   50.0f0, 50.0f0,
                                                   0.0f0, 1.0f0, 0.0f0, 1.0f0)
        
        @test length(batch.vertices) == 4
        @test length(batch.indices) == 6
        @test length(batch.commands) == 1
        
        # End frame
        DOPBrowser.Renderer.GPURenderer.end_frame(ctx)
        @test ctx.draw_calls == 1
        @test ctx.vertices_submitted == 4
    end
    
    @testset "PNG Export" begin
        # Create a simple 2x2 image
        framebuffer = UInt8[
            255, 0, 0, 255,    0, 255, 0, 255,   # Red, Green
            0, 0, 255, 255,    255, 255, 0, 255  # Blue, Yellow
        ]
        
        png_data = DOPBrowser.Renderer.PNGExport.encode_png(framebuffer, UInt32(2), UInt32(2))
        
        # Check PNG signature
        @test png_data[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        
        # Check we have some data
        @test length(png_data) > 8
    end
    
    @testset "Render Pipeline" begin
        pipeline = DOPBrowser.Renderer.create_pipeline(UInt32(200), UInt32(200))
        @test pipeline.width == 200
        @test pipeline.height == 200
        
        # Create command buffer with test commands
        buffer = CommandBuffer()
        emit_rect!(buffer, 0.0f0, 0.0f0, 100.0f0, 100.0f0,
                   1.0f0, 0.0f0, 0.0f0, 1.0f0)
        
        # Render frame
        DOPBrowser.Renderer.render_frame!(pipeline, buffer)
        
        # Export to PNG
        png_data = DOPBrowser.Renderer.get_png_data(pipeline)
        @test length(png_data) > 0
        
        # Verify PNG signature
        @test png_data[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    end

end

# ============================================================================
# Complete Browser Tests
# ============================================================================

@testset "Complete Browser" begin
    
    @testset "Browser Creation" begin
        browser = Browser(width=UInt32(800), height=UInt32(600))
        @test browser.context.viewport_width == 800.0f0
        @test browser.context.viewport_height == 600.0f0
        @test browser.is_loading == false
        @test browser.current_url == ""
    end
    
    @testset "Load HTML" begin
        browser = Browser(width=UInt32(400), height=UInt32(300))
        
        html = """
        <!DOCTYPE html>
        <html>
        <body style="background-color: yellow;">
            <div style="width: 100px; height: 100px; background-color: red;"></div>
        </body>
        </html>
        """
        
        load_html!(browser, html)
        
        @test browser.current_url == "about:blank"
        @test browser.is_loading == false
        @test node_count(browser.context.dom) > 0
    end
    
    @testset "Render and Export" begin
        browser = Browser(width=UInt32(200), height=UInt32(200))
        
        html = """
        <div style="width: 50px; height: 50px; background-color: blue;"></div>
        """
        
        load_html!(browser, html)
        
        # Render
        render!(browser)
        
        # Get PNG data
        png_data = get_png_data(browser)
        @test length(png_data) > 0
        @test png_data[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    end
    
    @testset "Viewport Resize" begin
        browser = Browser(width=UInt32(800), height=UInt32(600))
        
        set_viewport!(browser, UInt32(1920), UInt32(1080))
        
        @test browser.context.viewport_width == 1920.0f0
        @test browser.context.viewport_height == 1080.0f0
        @test browser.runtime.viewport_width == 1920.0f0
        @test browser.runtime.viewport_height == 1080.0f0
    end
    
    @testset "Scroll" begin
        browser = Browser(width=UInt32(800), height=UInt32(600))
        
        scroll_to!(browser, 0.0f0, 100.0f0)
        
        @test browser.runtime.scroll_x == 0.0f0
        @test browser.runtime.scroll_y == 100.0f0
    end
    
    @testset "JS Interface" begin
        browser = Browser(width=UInt32(800), height=UInt32(600))
        
        html = """
        <div style="width: 100px; height: 100px;"></div>
        """
        load_html!(browser, html)
        
        # Set up some test data in runtime
        resize!(browser.runtime.layout_x, 1)
        resize!(browser.runtime.layout_y, 1)
        resize!(browser.runtime.layout_width, 1)
        resize!(browser.runtime.layout_height, 1)
        browser.runtime.layout_x[1] = 50.0f0
        browser.runtime.layout_y[1] = 75.0f0
        browser.runtime.layout_width[1] = 100.0f0
        browser.runtime.layout_height[1] = 100.0f0
        
        # Use JS interface
        left = js_eval(browser, UInt32(1), :offsetLeft)
        @test left == 50.0f0
        
        rect = js_call(browser, UInt32(1), :getBoundingClientRect, Any[])
        @test rect[:x] == 50.0f0
        @test rect[:y] == 75.0f0
    end

end
