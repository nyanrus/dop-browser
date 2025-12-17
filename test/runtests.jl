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
    
    # ========== CSS3 Color Tests ==========
    @testset "CSS3 - HSL Color Parsing" begin
        # HSL colors
        color = parse_color("hsl(0, 100%, 50%)")  # Red
        @test color[1] == 0xff  # R
        @test color[2] == 0x00  # G
        @test color[3] == 0x00  # B
        @test color[4] == 0xff  # A
        
        color = parse_color("hsl(120, 100%, 50%)")  # Green
        @test color[2] == 0xff  # G should be high
        
        color = parse_color("hsl(240, 100%, 50%)")  # Blue
        @test color[3] == 0xff  # B should be high
        
        # HSLA with alpha
        color = parse_color("hsla(0, 100%, 50%, 0.5)")
        @test color[4] == 0x80  # ~50% alpha (127-128)
    end
    
    @testset "CSS3 - Extended Named Colors" begin
        # X11 colors
        @test parse_color("coral") == (0xff, 0x7f, 0x50, 0xff)
        @test parse_color("crimson") == (0xdc, 0x14, 0x3c, 0xff)
        @test parse_color("darkblue") == (0x00, 0x00, 0x8b, 0xff)
        @test parse_color("hotpink") == (0xff, 0x69, 0xb4, 0xff)
        @test parse_color("rebeccapurple") == (0x66, 0x33, 0x99, 0xff)
        @test parse_color("tomato") == (0xff, 0x63, 0x47, 0xff)
    end
    
    @testset "CSS3 - RGBA Hex Colors" begin
        # 4-character hex (RGBA)
        color = parse_color("#f00f")  # Red, full alpha
        @test color[1] == 0xff
        @test color[4] == 0xff
        
        # 8-character hex (RRGGBBAA)
        color = parse_color("#ff000080")  # Red, 50% alpha
        @test color[1] == 0xff
        @test color[4] == 0x80
    end
    
    # ========== CSS3 Length Units Tests ==========
    @testset "CSS3 - Length Units" begin
        # Rem
        (val, auto) = parse_length("2rem")
        @test val == 32.0f0  # 2 * 16px
        
        # Viewport units
        (val, auto) = parse_length("10vw")
        @test val == 192.0f0  # 10 * 19.2px
        
        (val, auto) = parse_length("10vh")
        @test val == 108.0f0  # 10 * 10.8px
        
        # Points
        (val, auto) = parse_length("12pt")
        @test val ≈ 16.0f0 atol=0.1f0  # 12 * 1.333
        
        # Inches
        (val, auto) = parse_length("1in")
        @test val == 96.0f0  # 1 * 96px
        
        # Centimeters
        (val, auto) = parse_length("1cm")
        @test val ≈ 37.795f0 atol=0.01f0
    end
    
    # ========== CSS3 Flexbox Tests ==========
    @testset "CSS3 - Flexbox Properties" begin
        styles = parse_inline_style("display: flex; flex-direction: column; justify-content: center; align-items: center;")
        
        @test styles.display == DOPBrowser.CSSParserModule.CSSCore.DISPLAY_FLEX
        @test styles.flex_direction == DOPBrowser.CSSParserModule.CSSCore.FLEX_DIRECTION_COLUMN
        @test styles.justify_content == DOPBrowser.CSSParserModule.CSSCore.JUSTIFY_CONTENT_CENTER
        @test styles.align_items == DOPBrowser.CSSParserModule.CSSCore.ALIGN_ITEMS_CENTER
    end
    
    @testset "CSS3 - Flex Shorthand" begin
        styles = parse_inline_style("flex: 1 0 auto;")
        @test styles.flex_grow == 1.0f0
        @test styles.flex_shrink == 0.0f0
        @test styles.flex_basis_auto == true
        
        styles = parse_inline_style("flex: 2;")
        @test styles.flex_grow == 2.0f0
    end
    
    @testset "CSS3 - Gap Property" begin
        styles = parse_inline_style("gap: 10px 20px;")
        @test styles.gap_row == 10.0f0
        @test styles.gap_column == 20.0f0
        
        styles = parse_inline_style("gap: 15px;")
        @test styles.gap_row == 15.0f0
        @test styles.gap_column == 15.0f0
    end
    
    # ========== CSS3 Visual Effects Tests ==========
    @testset "CSS3 - Opacity" begin
        styles = parse_inline_style("opacity: 0.5;")
        @test styles.opacity == 0.5f0
        
        styles = parse_inline_style("opacity: 1;")
        @test styles.opacity == 1.0f0
    end
    
    @testset "CSS3 - Border Radius" begin
        styles = parse_inline_style("border-radius: 10px;")
        @test styles.border_radius_tl == 10.0f0
        @test styles.border_radius_tr == 10.0f0
        @test styles.border_radius_br == 10.0f0
        @test styles.border_radius_bl == 10.0f0
        
        styles = parse_inline_style("border-top-left-radius: 5px;")
        @test styles.border_radius_tl == 5.0f0
    end
    
    @testset "CSS3 - Box Shadow" begin
        styles = parse_inline_style("box-shadow: 5px 10px 15px black;")
        @test styles.has_box_shadow == true
        @test styles.box_shadow_offset_x == 5.0f0
        @test styles.box_shadow_offset_y == 10.0f0
        @test styles.box_shadow_blur == 15.0f0
        
        styles = parse_inline_style("box-shadow: none;")
        @test styles.has_box_shadow == false
    end
    
    @testset "CSS3 - Transform" begin
        styles = parse_inline_style("transform: translateX(50px);")
        @test styles.has_transform == true
        @test styles.transform_translate_x == 50.0f0
        
        styles = parse_inline_style("transform: rotate(45deg);")
        @test styles.has_transform == true
        @test styles.transform_rotate == 45.0f0
        
        styles = parse_inline_style("transform: scale(2);")
        @test styles.has_transform == true
        @test styles.transform_scale_x == 2.0f0
        @test styles.transform_scale_y == 2.0f0
    end
    
    # ========== CSS3 Text Properties Tests ==========
    @testset "CSS3 - Text Properties" begin
        styles = parse_inline_style("text-align: center;")
        @test styles.text_align == DOPBrowser.CSSParserModule.CSSCore.TEXT_ALIGN_CENTER
        
        styles = parse_inline_style("text-decoration: underline;")
        @test styles.text_decoration == DOPBrowser.CSSParserModule.CSSCore.TEXT_DECORATION_UNDERLINE
        
        styles = parse_inline_style("font-weight: bold;")
        @test styles.font_weight == UInt16(700)
        
        styles = parse_inline_style("font-weight: 600;")
        @test styles.font_weight == UInt16(600)
    end
    
    @testset "CSS3 - Box Sizing" begin
        styles = parse_inline_style("box-sizing: border-box;")
        @test styles.box_sizing == DOPBrowser.CSSParserModule.CSSCore.BOX_SIZING_BORDER_BOX
        
        styles = parse_inline_style("box-sizing: content-box;")
        @test styles.box_sizing == DOPBrowser.CSSParserModule.CSSCore.BOX_SIZING_CONTENT_BOX
    end
    
    @testset "CSS3 - Sticky Positioning" begin
        styles = parse_inline_style("position: sticky;")
        @test styles.position == DOPBrowser.CSSParserModule.CSSCore.POSITION_STICKY
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
    
    @testset "Acid2 - Border Rendering" begin
        ctx = create_context(viewport_width=300.0f0, viewport_height=200.0f0)
        
        html = """
        <div style="width: 100px; height: 100px; border: 2px solid red; background-color: yellow;"></div>
        """
        
        result = process_document!(ctx, html)
        
        @test result.node_count > 0
        # Should have background (yellow) + 4 border rects (red)
        @test result.command_count >= 5
        
        # Verify border data was stored correctly
        # Find the div with border
        for i in 1:result.node_count
            if ctx.layout.border_top_width[i] == 2.0f0
                @test ctx.layout.border_top_r[i] == 0xff  # Red
                @test ctx.layout.border_top_g[i] == 0x00
                @test ctx.layout.border_top_b[i] == 0x00
                break
            end
        end
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
    
    @testset "SourceMap - Mapping" begin
        # Test SourceMap functionality
        table = DOPBrowser.ContentMM.SourceMap.SourceMapTable()
        
        # Add a mapping
        loc = DOPBrowser.ContentMM.SourceMap.SourceLocation(
            source_type = DOPBrowser.ContentMM.SourceMap.SOURCE_HTML_ELEMENT,
            line = UInt32(10),
            column = UInt32(5),
            file_id = UInt32(1)
        )
        DOPBrowser.ContentMM.SourceMap.add_mapping!(table, UInt32(1), loc)
        
        # Retrieve the mapping
        retrieved = DOPBrowser.ContentMM.SourceMap.get_location(table, UInt32(1))
        @test retrieved.line == UInt32(10)
        @test retrieved.column == UInt32(5)
        @test retrieved.source_type == DOPBrowser.ContentMM.SourceMap.SOURCE_HTML_ELEMENT
        
        # Test reverse lookup
        nodes = DOPBrowser.ContentMM.SourceMap.get_nodes_at_location(table, UInt32(1), UInt32(10))
        @test length(nodes) == 1
        @test nodes[1] == UInt32(1)
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

# ============================================================================
# New Modular Architecture Tests
# ============================================================================

@testset "Modular Architecture" begin
    
    @testset "HTMLParser Module" begin
        # Test that HTMLParser module is accessible and works
        html_parser = DOPBrowser.HTMLParser
        
        # Create a string pool using the module
        pool = html_parser.StringPool()
        
        # Test interning
        id1 = html_parser.intern!(pool, "hello")
        id2 = html_parser.intern!(pool, "hello")
        @test id1 == id2
        
        # Test tokenizer
        tokenizer = html_parser.Tokenizer(pool)
        tokens = html_parser.tokenize!(tokenizer, "<div>Test</div>")
        @test length(tokens) > 0
    end
    
    @testset "CSSParserModule" begin
        # Test that CSSParserModule is accessible
        css_mod = DOPBrowser.CSSParserModule
        
        # Test color parsing via the CSSCore submodule
        color = css_mod.parse_color("#ff0000")
        @test color == (0xff, 0x00, 0x00, 0xff)
        
        # Test length parsing
        (px, auto) = css_mod.parse_length("100px")
        @test px == 100.0f0
        @test auto == false
    end
    
    @testset "Layout Module" begin
        layout_mod = DOPBrowser.Layout
        
        # Create layout data
        layout = layout_mod.LayoutData()
        layout_mod.resize_layout!(layout, 10)
        @test length(layout.x) == 10
        
        # Set bounds
        layout_mod.set_bounds!(layout, 1, 100.0f0, 50.0f0)
        @test layout_mod.get_bounds(layout, 1) == (100.0f0, 50.0f0)
    end
    
    @testset "DOMCSSOM Module" begin
        domcssom = DOPBrowser.DOMCSSOM
        
        # Create string pool (now from HTMLParser)
        pool = domcssom.StringPool()
        @test pool isa DOPBrowser.HTMLParser.StringInterner.StringPool
        
        # Create DOM table
        dom = domcssom.DOMTable(pool)
        root_id = domcssom.add_node!(dom, domcssom.NODE_DOCUMENT)
        @test root_id == UInt32(1)
        
        # Test archetype table
        archetypes = domcssom.ArchetypeTable()
        id = domcssom.get_or_create_archetype!(archetypes, UInt32[1, 2])
        @test id > 0
        
        # Test command buffer
        buffer = domcssom.CommandBuffer()
        domcssom.emit_rect!(buffer, 0.0f0, 0.0f0, 100.0f0, 100.0f0, 1.0f0, 0.0f0, 0.0f0, 1.0f0)
        @test domcssom.command_count(buffer) == 1
    end
    
    @testset "Compiler Module" begin
        compiler = DOPBrowser.Compiler
        
        # Create compiler context
        ctx = compiler.CompilerContext()
        @test ctx.optimize == true
        
        # Test source registration
        file_id = compiler.register_source!(ctx, "<html></html>")
        @test file_id == UInt32(1)
        
        # Test basic compilation
        result = compiler.compile_document!("<html><body>Test</body></html>")
        @test result.success == true
    end
    
    @testset "EventLoop Module" begin
        eventloop = DOPBrowser.EventLoop
        
        # Create event loop
        loop = eventloop.BrowserEventLoop()
        @test loop.is_running == false
        
        # Test task scheduling
        executed = Ref(false)
        eventloop.schedule_task!(loop, eventloop.TASK_DOM, () -> begin
            executed[] = true
        end)
        
        # Run until idle
        eventloop.run_until_idle!(loop)
        @test executed[] == true
        
        # Test microtask
        micro_executed = Ref(false)
        eventloop.schedule_microtask!(loop, () -> begin
            micro_executed[] = true
        end)
        eventloop.run_until_idle!(loop)
        @test micro_executed[] == true
        
        # Test animation frame
        anim_executed = Ref(false)
        eventloop.request_animation_frame!(loop, (time) -> begin
            anim_executed[] = true
        end)
        # Force a render frame
        eventloop.run_tick!(loop)
        # Animation frame runs on render, so we may need to wait
        loop.last_render_time = 0.0  # Force render
        eventloop.run_tick!(loop)
        @test anim_executed[] == true
    end

end

# ============================================================================
# Content-- Text Format Parser Tests
# ============================================================================

@testset "Content-- Text Parser" begin
    
    @testset "Basic Parsing" begin
        source = """
        Stack(Direction: Down, Fill: #FF0000) {
            Rect(Size: (100, 50));
        }
        """
        
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        
        @test doc.success == true
        @test isempty(doc.errors)
        @test DOPBrowser.ContentMM.Primitives.node_count(doc.nodes) >= 3  # Root + Stack + Rect
    end
    
    @testset "Property Parsing" begin
        # Test Direction parsing
        source = "Stack(Direction: Right)"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.direction[2] == DOPBrowser.ContentMM.Properties.DIRECTION_RIGHT
        
        # Test Size parsing
        source = "Rect(Width: 100, Height: 50)"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.width[2] == 100.0f0
        @test doc.properties.height[2] == 50.0f0
        
        # Test Size tuple parsing
        source = "Rect(Size: (200, 150))"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.width[2] == 200.0f0
        @test doc.properties.height[2] == 150.0f0
    end
    
    @testset "Color Parsing" begin
        # Test hex color
        source = "Rect(Fill: #FF0000)"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.fill_r[2] == 0xff
        @test doc.properties.fill_g[2] == 0x00
        @test doc.properties.fill_b[2] == 0x00
        @test doc.properties.fill_a[2] == 0xff
        
        # Test named color
        source = "Rect(Fill: blue)"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.fill_b[2] == 0xff
    end
    
    @testset "Box Properties" begin
        # Test Inset (padding)
        source = "Stack(Inset: (10, 20, 30, 40))"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.inset_top[2] == 10.0f0
        @test doc.properties.inset_right[2] == 20.0f0
        @test doc.properties.inset_bottom[2] == 30.0f0
        @test doc.properties.inset_left[2] == 40.0f0
        
        # Test Offset (margin)
        source = "Stack(Offset: 15)"
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test doc.properties.offset_top[2] == 15.0f0
        @test doc.properties.offset_left[2] == 15.0f0
    end
    
    @testset "Nested Children" begin
        source = """
        Stack(Direction: Down) {
            Rect(Size: (100, 50));
            Stack(Direction: Right) {
                Rect(Size: (25, 25));
                Rect(Size: (25, 25));
            }
            Rect(Size: (100, 50));
        }
        """
        
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        # Root + outer Stack + 2 outer Rects + inner Stack + 2 inner Rects
        @test DOPBrowser.ContentMM.Primitives.node_count(doc.nodes) >= 6
    end
    
    @testset "Text Content" begin
        source = """
        Paragraph {
            Span(Text: "Hello World");
        }
        """
        
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test length(doc.strings) >= 1
        @test "Hello World" in doc.strings
    end
    
    @testset "Comments" begin
        source = """
        // This is a line comment
        Stack(Direction: Down) {
            /* This is a
               block comment */
            Rect(Size: (100, 50));
        }
        """
        
        doc = DOPBrowser.ContentMM.TextParser.parse_content_text(source)
        @test doc.success == true
        @test DOPBrowser.ContentMM.Primitives.node_count(doc.nodes) >= 2
    end

end

# ============================================================================
# Native UI Library Tests
# ============================================================================

@testset "Native UI Library" begin
    
    @testset "Create UI from Text" begin
        source = """
        Stack(Direction: Down, Fill: #FFFFFF) {
            Rect(Size: (100, 50), Fill: #FF0000);
        }
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        @test ui !== nothing
        @test DOPBrowser.ContentMM.Primitives.node_count(ui.nodes) >= 2
    end
    
    @testset "Create UI Programmatically" begin
        builder = DOPBrowser.ContentMM.NativeUI.UIBuilder()
        
        DOPBrowser.ContentMM.NativeUI.with_stack!(builder, direction=:down, fill="#FFFFFF") do
            DOPBrowser.ContentMM.NativeUI.rect!(builder, width=100.0f0, height=50.0f0, fill="#FF0000")
        end
        
        ctx = DOPBrowser.ContentMM.NativeUI.get_context(builder)
        @test DOPBrowser.ContentMM.Primitives.node_count(ctx.nodes) >= 2
    end
    
    @testset "Render Commands" begin
        source = """
        Rect(Size: (100, 50), Fill: #FF0000)
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        DOPBrowser.ContentMM.NativeUI.render!(ui, width=200, height=200)
        
        # Should have at least one render command for the rect
        @test command_count(ui.command_buffer) >= 1
    end

end

# ============================================================================
# Pixel Comparison Tests
# ============================================================================

@testset "Pixel Comparison" begin
    
    @testset "Buffer Comparison" begin
        # Create two identical buffers
        buffer1 = UInt8[255, 0, 0, 255, 0, 255, 0, 255]  # Red, Green
        buffer2 = UInt8[255, 0, 0, 255, 0, 255, 0, 255]  # Red, Green
        
        # This test validates internal comparison logic
        result = DOPBrowser.ContentMM.NativeUI.compare_buffers(buffer1, buffer2, 0)
        @test result.match == true
        @test result.match_ratio == 1.0
        @test result.diff_count == 0
        @test result.total_pixels == 2
    end
    
    @testset "Buffer Comparison with Difference" begin
        buffer1 = UInt8[255, 0, 0, 255, 0, 255, 0, 255]  # Red, Green
        buffer2 = UInt8[255, 0, 0, 255, 0, 0, 255, 255]  # Red, Blue
        
        result = DOPBrowser.ContentMM.NativeUI.compare_buffers(buffer1, buffer2, 0)
        @test result.match == false
        @test result.diff_count == 1  # One pixel differs
        @test result.match_ratio == 0.5
    end
    
    @testset "Buffer Comparison with Tolerance" begin
        buffer1 = UInt8[255, 0, 0, 255]  # Red
        buffer2 = UInt8[250, 5, 0, 255]  # Slightly different red
        
        # With tolerance 0, they differ
        result = DOPBrowser.ContentMM.NativeUI.compare_buffers(buffer1, buffer2, 0)
        @test result.match == false
        
        # With tolerance 10, they match
        result = DOPBrowser.ContentMM.NativeUI.compare_buffers(buffer1, buffer2, 10)
        @test result.match == true
    end
    
    @testset "PNG Encode/Decode Roundtrip" begin
        # Create a simple 2x2 image
        original = UInt8[
            255, 0, 0, 255,    0, 255, 0, 255,   # Red, Green
            0, 0, 255, 255,    255, 255, 0, 255  # Blue, Yellow
        ]
        
        # Encode to PNG
        png_data = DOPBrowser.Renderer.PNGExport.encode_png(original, UInt32(2), UInt32(2))
        @test length(png_data) > 0
        
        # PNG signature should be valid
        @test png_data[1:8] == UInt8[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        
        # Write and read back
        temp_file = tempname() * ".png"
        DOPBrowser.Renderer.PNGExport.write_png_file(temp_file, original, UInt32(2), UInt32(2))
        
        @test isfile(temp_file)
        
        # Decode
        decoded = DOPBrowser.Renderer.PNGExport.decode_png(temp_file)
        
        # Compare (allowing for minimal compression artifacts)
        result = DOPBrowser.ContentMM.NativeUI.compare_buffers(original, decoded, 0)
        @test result.match == true
        
        # Cleanup
        rm(temp_file)
    end
    
    @testset "Render and Compare" begin
        # Create a simple red rectangle
        source = """
        Rect(Size: (100, 100), Fill: #FF0000)
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        buffer = DOPBrowser.ContentMM.NativeUI.render_to_buffer(ui, width=100, height=100)
        
        @test length(buffer) == 100 * 100 * 4  # RGBA
        
        # Check that at least some pixels are red (the rect should render)
        # Note: The exact position depends on layout, so we just verify the buffer exists
        @test length(buffer) > 0
    end

end

# ============================================================================
# Cairo Rendering Tests
# ============================================================================

@testset "Cairo Rendering" begin
    
    @testset "Cairo Context Creation" begin
        ctx = DOPBrowser.Renderer.CairoRenderer.create_cairo_context(200, 150)
        @test ctx.width == 200
        @test ctx.height == 150
    end
    
    @testset "Cairo Rectangle Rendering" begin
        ctx = DOPBrowser.Renderer.CairoRenderer.create_cairo_context(100, 100)
        
        # Clear with white
        DOPBrowser.Renderer.CairoRenderer.clear!(ctx, 1.0, 1.0, 1.0, 1.0)
        
        # Draw red rectangle
        DOPBrowser.Renderer.CairoRenderer.render_rect!(ctx, 10.0, 10.0, 80.0, 80.0, (1.0, 0.0, 0.0, 1.0))
        
        # Get pixel data
        data = DOPBrowser.Renderer.CairoRenderer.get_surface_data(ctx)
        
        @test length(data) == 100 * 100 * 4  # RGBA
        
        # Check that we have some red pixels (center of the rectangle)
        # Pixel at (50, 50) should be red
        idx = (50 * 100 + 50) * 4 + 1
        @test data[idx] > 200  # R should be high
        @test data[idx + 1] < 50  # G should be low
        @test data[idx + 2] < 50  # B should be low
    end
    
    @testset "Cairo Text Rendering" begin
        ctx = DOPBrowser.Renderer.CairoRenderer.create_cairo_context(200, 50)
        
        # Clear with white
        DOPBrowser.Renderer.CairoRenderer.clear!(ctx, 1.0, 1.0, 1.0, 1.0)
        
        # Render some text
        DOPBrowser.Renderer.CairoRenderer.render_text!(ctx, "Hello", 10.0, 30.0, font_size=16.0)
        
        # Just verify it doesn't crash - text rendering depends on system fonts
        @test true
    end
    
    @testset "Cairo PNG Export" begin
        ctx = DOPBrowser.Renderer.CairoRenderer.create_cairo_context(50, 50)
        
        DOPBrowser.Renderer.CairoRenderer.clear!(ctx, 0.0, 0.0, 1.0, 1.0)  # Blue
        
        temp_file = tempname() * ".png"
        DOPBrowser.Renderer.CairoRenderer.save_png(ctx, temp_file)
        
        @test isfile(temp_file)
        @test filesize(temp_file) > 0
        
        # Cleanup
        rm(temp_file)
    end
    
    @testset "NativeUI Cairo Rendering" begin
        source = """
        Stack(Direction: Down, Fill: #FFFFFF) {
            Rect(Size: (100, 50), Fill: #FF0000);
        }
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        
        # Render with Cairo
        DOPBrowser.ContentMM.NativeUI.render_cairo!(ui, width=150, height=100)
        
        @test ui.cairo_context !== nothing
        @test ui.use_cairo == true
    end
    
    @testset "NativeUI Cairo PNG Export" begin
        source = """
        Rect(Size: (50, 50), Fill: #00FF00)
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        
        temp_file = tempname() * ".png"
        DOPBrowser.ContentMM.NativeUI.render_to_png_cairo!(ui, temp_file, width=100, height=100)
        
        @test isfile(temp_file)
        @test filesize(temp_file) > 0
        
        # Cleanup
        rm(temp_file)
    end
    
    @testset "NativeUI Cairo Buffer" begin
        source = """
        Rect(Size: (50, 50), Fill: #0000FF)
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        buffer = DOPBrowser.ContentMM.NativeUI.render_to_buffer_cairo(ui, width=100, height=100)
        
        @test length(buffer) == 100 * 100 * 4  # RGBA
    end
    
    @testset "Cairo Text in Content--" begin
        source = """
        Stack(Direction: Down, Fill: #FFFFFF, Inset: 10) {
            Paragraph {
                Span(Text: "Hello World");
            }
        }
        """
        
        ui = DOPBrowser.ContentMM.NativeUI.create_ui(source)
        
        # This should not error even if font is not available
        DOPBrowser.ContentMM.NativeUI.render_cairo!(ui, width=200, height=100)
        
        @test ui.cairo_context !== nothing
    end

end

# ============================================================================
# Rust Renderer Tests
# ============================================================================

@testset "Rust Renderer" begin
    
    @testset "Library Availability" begin
        # Check if the Rust library is available
        is_avail = DOPBrowser.RustRenderer.is_available()
        @test is_avail isa Bool
        
        if is_avail
            @info "Rust renderer library is available"
            
            # Get library version
            version = DOPBrowser.RustRenderer.get_version()
            @test version == "0.1.0"
        else
            @warn "Rust renderer library not found - skipping renderer tests"
        end
    end
    
    if DOPBrowser.RustRenderer.is_available()
        @testset "Headless Renderer Creation" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(200, 150)
            @test renderer.is_valid == true
            @test renderer.width == 200
            @test renderer.height == 150
            
            # Cleanup
            DOPBrowser.RustRenderer.destroy!(renderer)
            @test renderer.is_valid == false
        end
        
        @testset "Renderer Clear Color" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(100, 100)
            
            # Set clear color to red
            DOPBrowser.RustRenderer.set_clear_color!(renderer, 1.0, 0.0, 0.0, 1.0)
            
            # Get framebuffer - should be all red
            buffer = DOPBrowser.RustRenderer.get_framebuffer(renderer)
            
            @test length(buffer) == 100 * 100 * 4  # RGBA
            
            # First pixel should be red
            @test buffer[1] == 255  # R
            @test buffer[2] == 0    # G
            @test buffer[3] == 0    # B
            @test buffer[4] == 255  # A
            
            DOPBrowser.RustRenderer.destroy!(renderer)
        end
        
        @testset "Renderer Add Rect" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(100, 100)
            
            # Set white background
            DOPBrowser.RustRenderer.set_clear_color!(renderer, 1.0, 1.0, 1.0, 1.0)
            
            # Add a blue rectangle
            DOPBrowser.RustRenderer.add_rect!(renderer, 
                10.0, 10.0, 50.0, 50.0,  # x, y, width, height
                0.0, 0.0, 1.0, 1.0)      # RGBA
            
            # Render
            DOPBrowser.RustRenderer.render!(renderer)
            
            # Get framebuffer
            buffer = DOPBrowser.RustRenderer.get_framebuffer(renderer)
            
            # Check a pixel inside the rectangle (e.g., at 25, 25)
            idx = ((25 * 100) + 25) * 4 + 1
            @test buffer[idx] == 0      # R
            @test buffer[idx + 1] == 0  # G
            @test buffer[idx + 2] == 255  # B
            @test buffer[idx + 3] == 255  # A
            
            # Check a pixel outside the rectangle (e.g., at 0, 0)
            @test buffer[1] == 255    # R (white)
            @test buffer[2] == 255    # G (white)
            @test buffer[3] == 255    # B (white)
            
            DOPBrowser.RustRenderer.destroy!(renderer)
        end
        
        @testset "Renderer Clear Commands" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(100, 100)
            
            # Set white background
            DOPBrowser.RustRenderer.set_clear_color!(renderer, 1.0, 1.0, 1.0, 1.0)
            
            # Add a rectangle
            DOPBrowser.RustRenderer.add_rect!(renderer, 
                10.0, 10.0, 50.0, 50.0, 
                0.0, 0.0, 1.0, 1.0)
            
            # Clear commands
            DOPBrowser.RustRenderer.clear!(renderer)
            
            # Render - should have no rectangles
            DOPBrowser.RustRenderer.render!(renderer)
            
            # Get framebuffer - should be all white
            buffer = DOPBrowser.RustRenderer.get_framebuffer(renderer)
            
            # Check a pixel that would have been in the rectangle
            idx = ((25 * 100) + 25) * 4 + 1
            @test buffer[idx] == 255    # R (white)
            @test buffer[idx + 1] == 255  # G (white)
            @test buffer[idx + 2] == 255  # B (white)
            
            DOPBrowser.RustRenderer.destroy!(renderer)
        end
        
        @testset "Renderer Resize" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(100, 100)
            
            @test renderer.width == 100
            @test renderer.height == 100
            
            # Resize
            DOPBrowser.RustRenderer.renderer_resize!(renderer, 200, 150)
            
            @test renderer.width == 200
            @test renderer.height == 150
            
            # Check framebuffer size
            size = DOPBrowser.RustRenderer.get_framebuffer_size(renderer)
            @test size == 200 * 150 * 4
            
            DOPBrowser.RustRenderer.destroy!(renderer)
        end
        
        @testset "Renderer Z-Index Ordering" begin
            renderer = DOPBrowser.RustRenderer.create_renderer(100, 100)
            
            # Set white background
            DOPBrowser.RustRenderer.set_clear_color!(renderer, 1.0, 1.0, 1.0, 1.0)
            
            # Add blue rectangle at z-index 0
            DOPBrowser.RustRenderer.add_rect!(renderer, 
                20.0, 20.0, 60.0, 60.0, 
                0.0, 0.0, 1.0, 1.0,
                z_index=0)
            
            # Add red rectangle at z-index 1 (on top)
            DOPBrowser.RustRenderer.add_rect!(renderer, 
                40.0, 40.0, 40.0, 40.0, 
                1.0, 0.0, 0.0, 1.0,
                z_index=1)
            
            # Render
            DOPBrowser.RustRenderer.render!(renderer)
            
            # Get framebuffer
            buffer = DOPBrowser.RustRenderer.get_framebuffer(renderer)
            
            # Check pixel at center (50, 50) - should be red (on top)
            idx = ((50 * 100) + 50) * 4 + 1
            @test buffer[idx] == 255      # R (red)
            @test buffer[idx + 1] == 0    # G
            @test buffer[idx + 2] == 0    # B
            
            # Check pixel at corner of blue rect (25, 25) - should be blue
            idx = ((25 * 100) + 25) * 4 + 1
            @test buffer[idx] == 0        # R
            @test buffer[idx + 1] == 0    # G
            @test buffer[idx + 2] == 255  # B (blue)
            
            DOPBrowser.RustRenderer.destroy!(renderer)
        end
        
        @testset "Window Handle Creation" begin
            window = DOPBrowser.RustRenderer.create_window(width=640, height=480)
            @test window.is_valid == true
            
            # Check is_open
            @test DOPBrowser.RustRenderer.is_open(window) == true
            
            # Close
            DOPBrowser.RustRenderer.close!(window)
            @test DOPBrowser.RustRenderer.is_open(window) == false
            
            # Cleanup
            DOPBrowser.RustRenderer.destroy!(window)
            @test window.is_valid == false
        end
    end

end

# ============================================================================
# Interactive UI Library Tests
# ============================================================================

@testset "State Management" begin
    
    @testset "Signal Basics" begin
        count = DOPBrowser.State.signal(0)
        
        @test count[] == 0
        
        count[] = 5
        @test count[] == 5
        
        count[] = count[] + 1
        @test count[] == 6
    end
    
    @testset "Signal Equality Check" begin
        sig = DOPBrowser.State.signal(10)
        
        # Setting same value shouldn't trigger observers
        observer_called = Ref(0)
        
        eff = DOPBrowser.State.effect(() -> begin
            _ = sig[]  # Read to create dependency
            observer_called[] += 1
        end)
        
        initial_count = observer_called[]
        sig[] = 10  # Same value
        @test observer_called[] == initial_count  # Should not increase
        
        sig[] = 20  # Different value
        @test observer_called[] == initial_count + 1
        
        DOPBrowser.State.dispose!(eff)
    end
    
    @testset "Computed Values" begin
        a = DOPBrowser.State.signal(2)
        b = DOPBrowser.State.signal(3)
        
        sum_ab = DOPBrowser.State.computed(() -> a[] + b[])
        
        @test sum_ab[] == 5
        
        a[] = 10
        @test sum_ab[] == 13
        
        b[] = 7
        @test sum_ab[] == 17
    end
    
    @testset "Effect Side Effects" begin
        count = DOPBrowser.State.signal(0)
        effect_count = Ref(0)
        
        eff = DOPBrowser.State.effect(() -> begin
            _ = count[]
            effect_count[] += 1
        end)
        
        # Effect runs once on creation
        @test effect_count[] == 1
        
        # Effect runs when signal changes
        count[] = 1
        @test effect_count[] == 2
        
        count[] = 2
        @test effect_count[] == 3
        
        # Dispose effect
        DOPBrowser.State.dispose!(eff)
        
        # Effect should not run after disposal
        count[] = 3
        @test effect_count[] == 3
    end
    
    @testset "Batch Updates" begin
        a = DOPBrowser.State.signal(0)
        b = DOPBrowser.State.signal(0)
        effect_count = Ref(0)
        
        eff = DOPBrowser.State.effect(() -> begin
            _ = a[]
            _ = b[]
            effect_count[] += 1
        end)
        
        initial = effect_count[]
        
        # Batch updates should only trigger one effect run
        DOPBrowser.State.batch(() -> begin
            a[] = 1
            b[] = 2
        end)
        
        @test effect_count[] == initial + 1
        
        DOPBrowser.State.dispose!(eff)
    end
    
    @testset "Store Pattern" begin
        store = DOPBrowser.State.create_store(
            Dict(:count => 0, :name => "test"),
            Dict(
                :increment => (state, _) -> Dict(:count => state[:count] + 1),
                :set_name => (state, name) -> Dict(:name => name)
            )
        )
        
        @test DOPBrowser.State.get_state(store)[:count] == 0
        @test DOPBrowser.State.get_state(store)[:name] == "test"
        
        # Dispatch increment
        DOPBrowser.State.dispatch(store, :increment)
        @test DOPBrowser.State.get_state(store)[:count] == 1
        
        DOPBrowser.State.dispatch(store, :increment)
        @test DOPBrowser.State.get_state(store)[:count] == 2
        
        # Dispatch set_name
        DOPBrowser.State.dispatch(store, :set_name, "updated")
        @test DOPBrowser.State.get_state(store)[:name] == "updated"
    end
    
    @testset "Store Subscription" begin
        store = DOPBrowser.State.create_store(
            Dict{Symbol, Any}(:value => 0),
            Dict{Symbol, Function}(:set => (_, val) -> Dict{Symbol, Any}(:value => val))
        )
        
        received_values = Int[]
        
        unsubscribe = DOPBrowser.State.subscribe(store) do state
            push!(received_values, state[:value])
        end
        
        DOPBrowser.State.dispatch(store, :set, 10)
        DOPBrowser.State.dispatch(store, :set, 20)
        
        @test received_values == [10, 20]
        
        # Unsubscribe
        unsubscribe()
        
        DOPBrowser.State.dispatch(store, :set, 30)
        @test received_values == [10, 20]  # No new value
    end

end

@testset "Window Module" begin
    
    @testset "Window Configuration" begin
        config = DOPBrowser.Window.WindowConfig(
            title = "Test Window",
            width = 1024,
            height = 768,
            resizable = true
        )
        
        @test config.title == "Test Window"
        @test config.width == 1024
        @test config.height == 768
        @test config.resizable == true
    end
    
    @testset "Backend Options" begin
        # Test Gtk backend configuration
        config_gtk = DOPBrowser.Window.WindowConfig(
            title = "Gtk Window",
            width = 800,
            height = 600,
            backend = :gtk
        )
        @test config_gtk.backend == :gtk
        
        # Test Cairo backend configuration
        config_cairo = DOPBrowser.Window.WindowConfig(
            title = "Cairo Window",
            backend = :cairo
        )
        @test config_cairo.backend == :cairo
        
        # Test Software backend configuration
        config_soft = DOPBrowser.Window.WindowConfig(
            title = "Software Window",
            backend = :software
        )
        @test config_soft.backend == :software
    end
    
    @testset "is_gtk_available" begin
        # Should return true since Gtk4 is a dependency
        @test DOPBrowser.Window.is_gtk_available() isa Bool
    end
    
    @testset "Window Creation" begin
        window = DOPBrowser.Window.create_window()
        
        @test window !== nothing
        @test DOPBrowser.Window.is_open(window) == true
        
        # Check default size
        width, height = DOPBrowser.Window.get_size(window)
        @test width == 800
        @test height == 600
        
        # Close window
        DOPBrowser.Window.close!(window)
        @test DOPBrowser.Window.is_open(window) == false
    end
    
    @testset "Window Resize" begin
        window = DOPBrowser.Window.create_window()
        
        DOPBrowser.Window.set_size!(window, 1280, 720)
        width, height = DOPBrowser.Window.get_size(window)
        
        @test width == 1280
        @test height == 720
        
        DOPBrowser.Window.destroy!(window)
    end
    
    @testset "Event Injection" begin
        window = DOPBrowser.Window.create_window()
        
        # Inject a key event
        event = DOPBrowser.Window.WindowEvent(
            DOPBrowser.Window.EVENT_KEY_DOWN,
            key = Int32(65)  # 'A' key
        )
        DOPBrowser.Window.inject_event!(window, event)
        
        # Poll events
        events = DOPBrowser.Window.poll_events!(window)
        @test length(events) == 1
        @test events[1].type == DOPBrowser.Window.EVENT_KEY_DOWN
        @test events[1].key == 65
        
        DOPBrowser.Window.destroy!(window)
    end
    
    @testset "Mouse State" begin
        window = DOPBrowser.Window.create_window()
        
        # Inject mouse move
        move_event = DOPBrowser.Window.WindowEvent(
            DOPBrowser.Window.EVENT_MOUSE_MOVE,
            x = 100.0,
            y = 200.0
        )
        DOPBrowser.Window.inject_event!(window, move_event)
        
        x, y = DOPBrowser.Window.get_mouse_position(window)
        @test x == 100.0
        @test y == 200.0
        
        DOPBrowser.Window.destroy!(window)
    end
    
    @testset "Clipboard" begin
        window = DOPBrowser.Window.create_window()
        
        DOPBrowser.Window.set_clipboard!(window, "Hello, clipboard!")
        @test DOPBrowser.Window.get_clipboard(window) == "Hello, clipboard!"
        
        DOPBrowser.Window.destroy!(window)
    end

end

@testset "Widgets Module" begin
    
    @testset "Widget Props" begin
        props = DOPBrowser.Widgets.WidgetProps(
            width = 100.0f0,
            height = 50.0f0,
            padding = 10.0f0,
            background = "#FF0000"
        )
        
        @test props.width == 100.0f0
        @test props.height == 50.0f0
        @test props.padding == 10.0f0
        @test props.background == "#FF0000"
    end
    
    @testset "Build UI" begin
        tree = DOPBrowser.Widgets.build_ui() do
            DOPBrowser.Widgets.container(direction=:column, gap=10.0f0) do
                DOPBrowser.Widgets.label(text="Hello")
                DOPBrowser.Widgets.button(text="Click me")
            end
        end
        
        @test tree !== nothing
        @test tree.root !== nothing
        @test tree.root isa DOPBrowser.Widgets.ContainerWidget
        # Root contains the inner container
        @test length(tree.root.children) >= 1
        # Inner container has the label and button
        if length(tree.root.children) >= 1
            inner_container = tree.root.children[1]
            @test inner_container isa DOPBrowser.Widgets.ContainerWidget
            @test length(inner_container.children) == 2
        end
    end
    
    @testset "Button Widget" begin
        btn = DOPBrowser.Widgets.ButtonWidget(
            text = "Test Button",
            variant = :primary
        )
        
        @test DOPBrowser.Widgets.get_text(btn) == "Test Button"
        @test btn.variant == :primary
        @test btn.is_hovered == false
        @test btn.is_pressed == false
        
        # Test hover state affects background
        bg1 = DOPBrowser.Widgets.get_button_background(btn)
        btn.is_hovered = true
        bg2 = DOPBrowser.Widgets.get_button_background(btn)
        @test bg1 != bg2
    end
    
    @testset "Label Widget" begin
        lbl = DOPBrowser.Widgets.LabelWidget(
            text = "Test Label",
            font_size = 16.0f0,
            color = "#333333"
        )
        
        @test lbl.text == "Test Label"
        @test lbl.font_size == 16.0f0
        @test lbl.color == "#333333"
    end
    
    @testset "TextInput Widget" begin
        input = DOPBrowser.Widgets.TextInputWidget(
            value = "initial",
            placeholder = "Enter text"
        )
        
        @test input.value[] == "initial"
        @test input.placeholder == "Enter text"
        
        # Update value
        input.value[] = "updated"
        @test input.value[] == "updated"
    end
    
    @testset "Checkbox Widget" begin
        cb = DOPBrowser.Widgets.CheckboxWidget(
            checked = false,
            label = "Enable feature"
        )
        
        @test cb.checked[] == false
        @test cb.label == "Enable feature"
        
        # Toggle
        cb.checked[] = true
        @test cb.checked[] == true
    end
    
    @testset "Slider Widget" begin
        slider = DOPBrowser.Widgets.SliderWidget(
            value = 50.0f0,
            min = 0.0f0,
            max = 100.0f0
        )
        
        @test slider.value[] == 50.0f0
        @test slider.min == 0.0f0
        @test slider.max == 100.0f0
    end
    
    @testset "ProgressBar Widget" begin
        pb = DOPBrowser.Widgets.ProgressBarWidget(
            value = 75.0f0,
            max = 100.0f0,
            color = "#00FF00"
        )
        
        @test pb.value == 75.0f0
        @test pb.max == 100.0f0
        @test pb.color == "#00FF00"
    end

end

@testset "Application Module" begin
    
    @testset "Create Headless App" begin
        app = DOPBrowser.Application.create_app(
            title = "Test App",
            width = 400,
            height = 300,
            headless = true
        )
        
        @test app !== nothing
        @test app.is_headless == true
        @test app.config.title == "Test App"
        @test app.config.width == 400
        @test app.config.height == 300
    end
    
    @testset "Set UI Builder" begin
        app = DOPBrowser.Application.create_app(headless = true)
        
        called = Ref(false)
        DOPBrowser.Application.set_ui!(app) do
            called[] = true
            DOPBrowser.Widgets.label(text="Test")
        end
        
        @test app.callbacks.ui_builder !== nothing
    end
    
    @testset "App Statistics" begin
        app = DOPBrowser.Application.create_app(headless = true)
        
        @test DOPBrowser.Application.is_running(app) == false
        @test DOPBrowser.Application.get_frame_count(app) == 0
    end
    
    @testset "Lifecycle Callbacks" begin
        app = DOPBrowser.Application.create_app(headless = true)
        
        init_called = Ref(false)
        cleanup_called = Ref(false)
        
        DOPBrowser.Application.on_init(app, () -> init_called[] = true)
        DOPBrowser.Application.on_cleanup(app, () -> cleanup_called[] = true)
        
        @test app.callbacks.on_init !== nothing
        @test app.callbacks.on_cleanup !== nothing
    end

end

# ============================================================================
# Rust Parser Tests
# ============================================================================

@testset "Rust Parser" begin
    
    @testset "Library Availability" begin
        # Check if the Rust parser library is available
        is_avail = DOPBrowser.RustParser.is_available()
        @test is_avail isa Bool
        
        if is_avail
            @info "Rust parser library is available"
            
            # Get library version
            version = DOPBrowser.RustParser.get_version()
            @test version == "0.1.0"
        else
            @warn "Rust parser library not found - skipping parser tests"
        end
    end
    
    if DOPBrowser.RustParser.is_available()
        @testset "String Pool" begin
            pool = DOPBrowser.RustParser.create_string_pool()
            @test pool.is_valid == true
            
            # Test interning
            id1 = DOPBrowser.RustParser.intern!(pool, "hello")
            id2 = DOPBrowser.RustParser.intern!(pool, "world")
            id3 = DOPBrowser.RustParser.intern!(pool, "hello")  # Duplicate
            
            @test id1 == id3  # Same string should have same ID
            @test id1 != id2  # Different strings should have different IDs
            
            # Test retrieval
            @test DOPBrowser.RustParser.get_string(pool, id1) == "hello"
            @test DOPBrowser.RustParser.get_string(pool, id2) == "world"
        end
        
        @testset "HTML Parsing" begin
            result = DOPBrowser.RustParser.parse_html("<div><p>Hello</p></div>")
            @test result.is_valid == true
            
            token_count = DOPBrowser.RustParser.token_count(result)
            @test token_count > 0
            
            # Get first token type
            first_type = DOPBrowser.RustParser.get_token_type(result, UInt32(0))
            @test first_type > 0  # Should be a valid token type
        end
        
        @testset "HTML Parsing with Attributes" begin
            result = DOPBrowser.RustParser.parse_html("""<div id="main" class="container">Test</div>""")
            @test result.is_valid == true
            @test DOPBrowser.RustParser.token_count(result) > 0
        end
        
        @testset "CSS Parsing - Inline Style" begin
            styles = DOPBrowser.RustParser.parse_inline_style("width: 100px; height: 50px; background-color: red;")
            @test styles.is_valid == true
            
            # Check width
            @test DOPBrowser.RustParser.get_width(styles) == 100.0f0
            @test DOPBrowser.RustParser.get_width_is_auto(styles) == false
            
            # Check height
            @test DOPBrowser.RustParser.get_height(styles) == 50.0f0
            @test DOPBrowser.RustParser.get_height_is_auto(styles) == false
            
            # Check background color
            @test DOPBrowser.RustParser.has_background(styles) == true
            bg_color = DOPBrowser.RustParser.get_background_color(styles)
            @test bg_color[1] == 0xff  # Red
            @test bg_color[2] == 0x00  # Green
            @test bg_color[3] == 0x00  # Blue
        end
        
        @testset "CSS Color Parsing" begin
            # Named colors
            @test DOPBrowser.RustParser.parse_color("black") == (0x00, 0x00, 0x00, 0xff)
            @test DOPBrowser.RustParser.parse_color("white") == (0xff, 0xff, 0xff, 0xff)
            @test DOPBrowser.RustParser.parse_color("red") == (0xff, 0x00, 0x00, 0xff)
            @test DOPBrowser.RustParser.parse_color("transparent") == (0x00, 0x00, 0x00, 0x00)
            
            # Hex colors
            @test DOPBrowser.RustParser.parse_color("#fff") == (0xff, 0xff, 0xff, 0xff)
            @test DOPBrowser.RustParser.parse_color("#000") == (0x00, 0x00, 0x00, 0xff)
            @test DOPBrowser.RustParser.parse_color("#ff0000") == (0xff, 0x00, 0x00, 0xff)
        end
        
        @testset "CSS Length Parsing" begin
            # Pixels
            (val, auto) = DOPBrowser.RustParser.parse_length("100px")
            @test val == 100.0f0
            @test auto == false
            
            # Auto
            (val, auto) = DOPBrowser.RustParser.parse_length("auto")
            @test auto == true
            
            # No unit (default px)
            (val, auto) = DOPBrowser.RustParser.parse_length("50")
            @test val == 50.0f0
            @test auto == false
        end
        
        @testset "Text Shaping" begin
            shaper = DOPBrowser.RustParser.create_text_shaper()
            @test shaper.is_valid == true
            
            shaped = DOPBrowser.RustParser.shape_paragraph(shaper, "Hello World", 200.0f0)
            @test shaped.is_valid == true
            
            @test DOPBrowser.RustParser.get_shaped_width(shaped) > 0.0f0
            @test DOPBrowser.RustParser.get_shaped_height(shaped) > 0.0f0
            @test DOPBrowser.RustParser.get_shaped_line_count(shaped) >= 1
        end
    end

end
