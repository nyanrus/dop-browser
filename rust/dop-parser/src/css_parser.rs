//! CSS Parser using cssparser
//!
//! Provides CSS parsing with support for:
//! - Inline styles
//! - Color parsing (hex, rgb, rgba, named colors)
//! - Length parsing (px, %, em, mm, auto)
//! - Comprehensive CSS property support

use cssparser::{Parser, ParserInput, Token as CssToken, ToCss};
use std::collections::HashMap;
use zerocopy::{FromBytes, Immutable, IntoBytes, KnownLayout};

/// Position constants
pub const POSITION_STATIC: u8 = 0;
pub const POSITION_RELATIVE: u8 = 1;
pub const POSITION_ABSOLUTE: u8 = 2;
pub const POSITION_FIXED: u8 = 3;

/// Display constants
pub const DISPLAY_NONE: u8 = 0;
pub const DISPLAY_BLOCK: u8 = 1;
pub const DISPLAY_INLINE: u8 = 2;
pub const DISPLAY_TABLE: u8 = 3;
pub const DISPLAY_TABLE_CELL: u8 = 4;
pub const DISPLAY_TABLE_ROW: u8 = 5;
pub const DISPLAY_INLINE_BLOCK: u8 = 6;

/// Overflow constants
pub const OVERFLOW_VISIBLE: u8 = 0;
pub const OVERFLOW_HIDDEN: u8 = 1;

/// Float constants
pub const FLOAT_NONE: u8 = 0;
pub const FLOAT_LEFT: u8 = 1;
pub const FLOAT_RIGHT: u8 = 2;

/// Clear constants
pub const CLEAR_NONE: u8 = 0;
pub const CLEAR_LEFT: u8 = 1;
pub const CLEAR_RIGHT: u8 = 2;
pub const CLEAR_BOTH: u8 = 3;

/// Border style constants
pub const BORDER_STYLE_NONE: u8 = 0;
pub const BORDER_STYLE_SOLID: u8 = 1;
pub const BORDER_STYLE_DOTTED: u8 = 2;
pub const BORDER_STYLE_DASHED: u8 = 3;

/// RGBA color
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, FromBytes, IntoBytes, Immutable, KnownLayout)]
#[repr(C)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Color {
    pub const TRANSPARENT: Color = Color { r: 0, g: 0, b: 0, a: 0 };
    pub const BLACK: Color = Color { r: 0, g: 0, b: 0, a: 255 };
    pub const WHITE: Color = Color { r: 255, g: 255, b: 255, a: 255 };
    
    pub fn new(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }
}

/// Length value with auto flag
#[derive(Clone, Copy, Debug, Default)]
pub struct Length {
    pub value: f32,
    pub is_auto: bool,
}

impl Length {
    pub const AUTO: Length = Length { value: 0.0, is_auto: true };
    
    pub fn px(value: f32) -> Self {
        Self { value, is_auto: false }
    }
}

/// Computed CSS styles for a node
#[derive(Clone, Debug)]
pub struct CssStyles {
    // Positioning
    pub position: u8,
    pub float: u8,
    pub clear: u8,
    pub top: Length,
    pub right: Length,
    pub bottom: Length,
    pub left: Length,
    pub z_index: i32,
    
    // Box model
    pub width: Length,
    pub height: Length,
    pub min_width: Length,
    pub max_width: Length,
    pub min_height: Length,
    pub max_height: Length,
    pub margin_top: f32,
    pub margin_right: f32,
    pub margin_bottom: f32,
    pub margin_left: f32,
    pub padding_top: f32,
    pub padding_right: f32,
    pub padding_bottom: f32,
    pub padding_left: f32,
    
    // Borders
    pub border_top_width: f32,
    pub border_right_width: f32,
    pub border_bottom_width: f32,
    pub border_left_width: f32,
    pub border_top_style: u8,
    pub border_right_style: u8,
    pub border_bottom_style: u8,
    pub border_left_style: u8,
    pub border_top_color: Color,
    pub border_right_color: Color,
    pub border_bottom_color: Color,
    pub border_left_color: Color,
    
    // Display & visibility
    pub display: u8,
    pub visibility: bool,
    pub overflow: u8,
    pub line_height: f32,
    pub line_height_normal: bool,
    pub font_size: f32,
    
    // Colors & content
    pub background_color: Color,
    pub color: Color,
    pub has_background: bool,
}

impl Default for CssStyles {
    fn default() -> Self {
        Self {
            position: POSITION_STATIC,
            float: FLOAT_NONE,
            clear: CLEAR_NONE,
            top: Length::AUTO,
            right: Length::AUTO,
            bottom: Length::AUTO,
            left: Length::AUTO,
            z_index: 0,
            
            width: Length::AUTO,
            height: Length::AUTO,
            min_width: Length::px(0.0),
            max_width: Length::px(f32::INFINITY),
            min_height: Length::px(0.0),
            max_height: Length::px(f32::INFINITY),
            margin_top: 0.0,
            margin_right: 0.0,
            margin_bottom: 0.0,
            margin_left: 0.0,
            padding_top: 0.0,
            padding_right: 0.0,
            padding_bottom: 0.0,
            padding_left: 0.0,
            
            border_top_width: 0.0,
            border_right_width: 0.0,
            border_bottom_width: 0.0,
            border_left_width: 0.0,
            border_top_style: BORDER_STYLE_NONE,
            border_right_style: BORDER_STYLE_NONE,
            border_bottom_style: BORDER_STYLE_NONE,
            border_left_style: BORDER_STYLE_NONE,
            border_top_color: Color::BLACK,
            border_right_color: Color::BLACK,
            border_bottom_color: Color::BLACK,
            border_left_color: Color::BLACK,
            
            display: DISPLAY_BLOCK,
            visibility: true,
            overflow: OVERFLOW_VISIBLE,
            line_height: 16.0,
            line_height_normal: true,
            font_size: 16.0,
            
            background_color: Color::TRANSPARENT,
            color: Color::BLACK,
            has_background: false,
        }
    }
}

/// Named color lookup table
fn get_named_color(name: &str) -> Option<Color> {
    match name.to_lowercase().as_str() {
        "black" => Some(Color::new(0x00, 0x00, 0x00, 0xff)),
        "white" => Some(Color::new(0xff, 0xff, 0xff, 0xff)),
        "red" => Some(Color::new(0xff, 0x00, 0x00, 0xff)),
        "green" => Some(Color::new(0x00, 0x80, 0x00, 0xff)),
        "lime" => Some(Color::new(0x00, 0xff, 0x00, 0xff)),
        "blue" => Some(Color::new(0x00, 0x00, 0xff, 0xff)),
        "yellow" => Some(Color::new(0xff, 0xff, 0x00, 0xff)),
        "cyan" | "aqua" => Some(Color::new(0x00, 0xff, 0xff, 0xff)),
        "magenta" | "fuchsia" => Some(Color::new(0xff, 0x00, 0xff, 0xff)),
        "gray" | "grey" => Some(Color::new(0x80, 0x80, 0x80, 0xff)),
        "transparent" => Some(Color::TRANSPARENT),
        "orange" => Some(Color::new(0xff, 0xa5, 0x00, 0xff)),
        "purple" => Some(Color::new(0x80, 0x00, 0x80, 0xff)),
        "navy" => Some(Color::new(0x00, 0x00, 0x80, 0xff)),
        "maroon" => Some(Color::new(0x80, 0x00, 0x00, 0xff)),
        "olive" => Some(Color::new(0x80, 0x80, 0x00, 0xff)),
        "teal" => Some(Color::new(0x00, 0x80, 0x80, 0xff)),
        "silver" => Some(Color::new(0xc0, 0xc0, 0xc0, 0xff)),
        _ => None,
    }
}

/// Parse a CSS color value
pub fn parse_color(value: &str) -> Color {
    let value = value.trim().to_lowercase();
    
    // Named colors
    if let Some(color) = get_named_color(&value) {
        return color;
    }
    
    // Hex colors
    if value.starts_with('#') {
        let hex = &value[1..];
        if hex.len() == 3 {
            // #rgb -> #rrggbb
            let r = u8::from_str_radix(&hex[0..1], 16).unwrap_or(0) * 17;
            let g = u8::from_str_radix(&hex[1..2], 16).unwrap_or(0) * 17;
            let b = u8::from_str_radix(&hex[2..3], 16).unwrap_or(0) * 17;
            return Color::new(r, g, b, 255);
        } else if hex.len() == 6 {
            let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(0);
            let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(0);
            let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(0);
            return Color::new(r, g, b, 255);
        } else if hex.len() == 8 {
            let r = u8::from_str_radix(&hex[0..2], 16).unwrap_or(0);
            let g = u8::from_str_radix(&hex[2..4], 16).unwrap_or(0);
            let b = u8::from_str_radix(&hex[4..6], 16).unwrap_or(0);
            let a = u8::from_str_radix(&hex[6..8], 16).unwrap_or(255);
            return Color::new(r, g, b, a);
        }
    }
    
    // rgb() and rgba()
    if value.starts_with("rgb") {
        // Extract numbers using regex-like parsing
        let numbers: Vec<&str> = value
            .trim_start_matches("rgba")
            .trim_start_matches("rgb")
            .trim_start_matches('(')
            .trim_end_matches(')')
            .split(|c| c == ',' || c == ' ')
            .filter(|s| !s.is_empty())
            .collect();
        
        if numbers.len() >= 3 {
            let r = numbers[0].trim().parse::<u8>().unwrap_or(0);
            let g = numbers[1].trim().parse::<u8>().unwrap_or(0);
            let b = numbers[2].trim().parse::<u8>().unwrap_or(0);
            let a = if numbers.len() >= 4 {
                let alpha = numbers[3].trim().parse::<f32>().unwrap_or(1.0);
                (alpha * 255.0) as u8
            } else {
                255
            };
            return Color::new(r, g, b, a);
        }
    }
    
    Color::TRANSPARENT
}

/// Parse a CSS length value
pub fn parse_length(value: &str, _container_size: f32) -> Length {
    let value = value.trim().to_lowercase();
    
    if value == "auto" {
        return Length::AUTO;
    }
    
    // Percentage
    if value.ends_with('%') {
        if let Ok(num) = value[..value.len()-1].parse::<f32>() {
            return Length::px(num / 100.0 * _container_size);
        }
    }
    
    // Pixels (default unit)
    let num_str = value.trim_end_matches("px");
    if let Ok(num) = num_str.parse::<f32>() {
        return Length::px(num);
    }
    
    // em units (assume 16px base)
    if value.ends_with("em") {
        if let Ok(num) = value[..value.len()-2].parse::<f32>() {
            return Length::px(num * 16.0);
        }
    }
    
    // mm units (1mm = 3.7795275591 pixels at 96 DPI)
    if value.ends_with("mm") {
        if let Ok(num) = value[..value.len()-2].parse::<f32>() {
            return Length::px(num * 3.7795275591);
        }
    }
    
    Length::AUTO
}

/// Parse inline style string into CssStyles
pub fn parse_inline_style(style_str: &str) -> CssStyles {
    let mut styles = CssStyles::default();
    
    // Split by semicolon and process each declaration
    for decl in style_str.split(';') {
        let decl = decl.trim();
        if decl.is_empty() {
            continue;
        }
        
        if let Some(colon_idx) = decl.find(':') {
            let prop = decl[..colon_idx].trim().to_lowercase();
            let val = decl[colon_idx + 1..].trim();
            apply_property(&mut styles, &prop, val);
        }
    }
    
    styles
}

/// Apply a CSS property to styles
fn apply_property(styles: &mut CssStyles, prop: &str, val: &str) {
    let val_lower = val.to_lowercase();
    
    match prop {
        "position" => {
            styles.position = match val_lower.as_str() {
                "static" => POSITION_STATIC,
                "relative" => POSITION_RELATIVE,
                "absolute" => POSITION_ABSOLUTE,
                "fixed" => POSITION_FIXED,
                _ => POSITION_STATIC,
            };
        }
        
        "display" => {
            styles.display = match val_lower.as_str() {
                "none" => DISPLAY_NONE,
                "block" => DISPLAY_BLOCK,
                "inline" => DISPLAY_INLINE,
                "table" => DISPLAY_TABLE,
                "table-cell" => DISPLAY_TABLE_CELL,
                "table-row" => DISPLAY_TABLE_ROW,
                "inline-block" => DISPLAY_INLINE_BLOCK,
                _ => DISPLAY_BLOCK,
            };
        }
        
        "visibility" => {
            styles.visibility = val_lower != "hidden";
        }
        
        "overflow" => {
            styles.overflow = if val_lower == "hidden" {
                OVERFLOW_HIDDEN
            } else {
                OVERFLOW_VISIBLE
            };
        }
        
        "background-color" | "background" => {
            let color = parse_color(val);
            styles.background_color = color;
            styles.has_background = color.a > 0;
        }
        
        "color" => {
            styles.color = parse_color(val);
        }
        
        "width" => {
            styles.width = parse_length(val, 0.0);
        }
        
        "height" => {
            styles.height = parse_length(val, 0.0);
        }
        
        "top" => {
            styles.top = parse_length(val, 0.0);
        }
        
        "right" => {
            styles.right = parse_length(val, 0.0);
        }
        
        "bottom" => {
            styles.bottom = parse_length(val, 0.0);
        }
        
        "left" => {
            styles.left = parse_length(val, 0.0);
        }
        
        "z-index" => {
            if let Ok(z) = val.parse::<i32>() {
                styles.z_index = z;
            }
        }
        
        "margin" => {
            let values = parse_margin_shorthand(val);
            styles.margin_top = values.0;
            styles.margin_right = values.1;
            styles.margin_bottom = values.2;
            styles.margin_left = values.3;
        }
        
        "margin-top" => {
            styles.margin_top = parse_length(val, 0.0).value;
        }
        
        "margin-right" => {
            styles.margin_right = parse_length(val, 0.0).value;
        }
        
        "margin-bottom" => {
            styles.margin_bottom = parse_length(val, 0.0).value;
        }
        
        "margin-left" => {
            styles.margin_left = parse_length(val, 0.0).value;
        }
        
        "padding" => {
            let values = parse_margin_shorthand(val);
            styles.padding_top = values.0;
            styles.padding_right = values.1;
            styles.padding_bottom = values.2;
            styles.padding_left = values.3;
        }
        
        "padding-top" => {
            styles.padding_top = parse_length(val, 0.0).value;
        }
        
        "padding-right" => {
            styles.padding_right = parse_length(val, 0.0).value;
        }
        
        "padding-bottom" => {
            styles.padding_bottom = parse_length(val, 0.0).value;
        }
        
        "padding-left" => {
            styles.padding_left = parse_length(val, 0.0).value;
        }
        
        "float" => {
            styles.float = match val_lower.as_str() {
                "left" => FLOAT_LEFT,
                "right" => FLOAT_RIGHT,
                _ => FLOAT_NONE,
            };
        }
        
        "clear" => {
            styles.clear = match val_lower.as_str() {
                "left" => CLEAR_LEFT,
                "right" => CLEAR_RIGHT,
                "both" => CLEAR_BOTH,
                _ => CLEAR_NONE,
            };
        }
        
        "min-width" => {
            let len = parse_length(val, 0.0);
            if !len.is_auto {
                styles.min_width = len;
            }
        }
        
        "max-width" => {
            let len = parse_length(val, 0.0);
            if !len.is_auto {
                styles.max_width = len;
            }
        }
        
        "min-height" => {
            let len = parse_length(val, 0.0);
            if !len.is_auto {
                styles.min_height = len;
            }
        }
        
        "max-height" => {
            let len = parse_length(val, 0.0);
            if !len.is_auto {
                styles.max_height = len;
            }
        }
        
        "border" => {
            parse_border_shorthand(val, styles);
        }
        
        "border-width" => {
            let values = parse_margin_shorthand(val);
            styles.border_top_width = values.0;
            styles.border_right_width = values.1;
            styles.border_bottom_width = values.2;
            styles.border_left_width = values.3;
        }
        
        "border-style" => {
            let style = parse_border_style(&val_lower);
            styles.border_top_style = style;
            styles.border_right_style = style;
            styles.border_bottom_style = style;
            styles.border_left_style = style;
        }
        
        "border-color" => {
            let color = parse_color(val);
            styles.border_top_color = color;
            styles.border_right_color = color;
            styles.border_bottom_color = color;
            styles.border_left_color = color;
        }
        
        "line-height" => {
            if val_lower == "normal" {
                styles.line_height_normal = true;
            } else {
                let len = parse_length(val, 0.0);
                if !len.is_auto {
                    styles.line_height = len.value;
                    styles.line_height_normal = false;
                }
            }
        }
        
        "font-size" => {
            let len = parse_length(val, 0.0);
            if !len.is_auto {
                styles.font_size = len.value;
            }
        }
        
        _ => {}
    }
}

/// Parse margin/padding shorthand (1-4 values) into top, right, bottom, left
fn parse_margin_shorthand(val: &str) -> (f32, f32, f32, f32) {
    let parts: Vec<&str> = val.split_whitespace().collect();
    let values: Vec<f32> = parts
        .iter()
        .map(|p| parse_length(p, 0.0).value)
        .collect();
    
    match values.len() {
        1 => (values[0], values[0], values[0], values[0]),
        2 => (values[0], values[1], values[0], values[1]),
        3 => (values[0], values[1], values[2], values[1]),
        4 => (values[0], values[1], values[2], values[3]),
        _ => (0.0, 0.0, 0.0, 0.0),
    }
}

/// Parse border style value
fn parse_border_style(val: &str) -> u8 {
    match val.trim() {
        "solid" => BORDER_STYLE_SOLID,
        "dotted" => BORDER_STYLE_DOTTED,
        "dashed" => BORDER_STYLE_DASHED,
        _ => BORDER_STYLE_NONE,
    }
}

/// Parse border shorthand (e.g., "1px solid black")
fn parse_border_shorthand(val: &str, styles: &mut CssStyles) {
    let parts: Vec<&str> = val.split_whitespace().collect();
    
    for part in parts {
        let part_lower = part.to_lowercase();
        
        // Check if it's a width
        if part.chars().next().map_or(false, |c| c.is_ascii_digit()) {
            let len = parse_length(part, 0.0);
            styles.border_top_width = len.value;
            styles.border_right_width = len.value;
            styles.border_bottom_width = len.value;
            styles.border_left_width = len.value;
        }
        // Check if it's a style
        else if matches!(part_lower.as_str(), "solid" | "dotted" | "dashed" | "none") {
            let style = parse_border_style(&part_lower);
            styles.border_top_style = style;
            styles.border_right_style = style;
            styles.border_bottom_style = style;
            styles.border_left_style = style;
        }
        // Otherwise it's a color
        else {
            let color = parse_color(part);
            styles.border_top_color = color;
            styles.border_right_color = color;
            styles.border_bottom_color = color;
            styles.border_left_color = color;
        }
    }
}

/// CSS Rule for stylesheet parsing
#[derive(Clone, Debug)]
pub struct CssRule {
    pub selector: String,
    pub properties: HashMap<String, String>,
}

/// Parse a CSS stylesheet into rules
pub fn parse_stylesheet(css: &str) -> Vec<CssRule> {
    let mut rules = Vec::new();
    let mut input = ParserInput::new(css);
    let mut parser = Parser::new(&mut input);
    
    // Parse rule blocks
    while !parser.is_exhausted() {
        if let Ok(rule) = parse_rule(&mut parser) {
            rules.push(rule);
        } else {
            // Skip to next block on error
            let _ = parser.next();
        }
    }
    
    rules
}

/// Parse a single CSS rule
fn parse_rule(parser: &mut Parser) -> Result<CssRule, ()> {
    // Parse selector
    let mut selector = String::new();
    loop {
        let token = parser.next().map_err(|_| ())?;
        match token {
            CssToken::CurlyBracketBlock => break,
            _ => {
                selector.push_str(&token.to_css_string());
            }
        }
    }
    
    // Parse declarations
    let mut properties = HashMap::new();
    let _: Result<(), cssparser::ParseError<'_, ()>> = parser.parse_nested_block(|parser| {
        loop {
            let result: Result<(), ()> = (|| {
                // Parse property name
                let name = match parser.next() {
                    Ok(CssToken::Ident(name)) => name.to_string(),
                    _ => return Err(()),
                };
                
                // Expect colon
                match parser.next() {
                    Ok(CssToken::Colon) => {}
                    _ => return Err(()),
                }
                
                // Parse value until semicolon or end
                let mut value = String::new();
                loop {
                    match parser.next() {
                        Ok(CssToken::Semicolon) => break,
                        Err(_) => break,
                        Ok(token) => {
                            value.push_str(&token.to_css_string());
                        }
                    }
                }
                
                properties.insert(name, value.trim().to_string());
                Ok(())
            })();
            
            if result.is_err() {
                if parser.is_exhausted() {
                    break;
                }
            }
        }
        Ok(())
    });
    
    Ok(CssRule {
        selector: selector.trim().to_string(),
        properties,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_color_named() {
        assert_eq!(parse_color("black"), Color::new(0, 0, 0, 255));
        assert_eq!(parse_color("white"), Color::new(255, 255, 255, 255));
        assert_eq!(parse_color("red"), Color::new(255, 0, 0, 255));
        assert_eq!(parse_color("transparent"), Color::TRANSPARENT);
    }
    
    #[test]
    fn test_parse_color_hex() {
        assert_eq!(parse_color("#fff"), Color::new(255, 255, 255, 255));
        assert_eq!(parse_color("#000"), Color::new(0, 0, 0, 255));
        assert_eq!(parse_color("#ff0000"), Color::new(255, 0, 0, 255));
        assert_eq!(parse_color("#00ff00"), Color::new(0, 255, 0, 255));
    }
    
    #[test]
    fn test_parse_length() {
        let len = parse_length("100px", 0.0);
        assert_eq!(len.value, 100.0);
        assert!(!len.is_auto);
        
        let auto = parse_length("auto", 0.0);
        assert!(auto.is_auto);
        
        let no_unit = parse_length("50", 0.0);
        assert_eq!(no_unit.value, 50.0);
    }
    
    #[test]
    fn test_parse_inline_style() {
        let styles = parse_inline_style("width: 100px; height: 50px; background-color: red;");
        
        assert_eq!(styles.width.value, 100.0);
        assert!(!styles.width.is_auto);
        assert_eq!(styles.height.value, 50.0);
        assert_eq!(styles.background_color, Color::new(255, 0, 0, 255));
        assert!(styles.has_background);
    }
    
    #[test]
    fn test_parse_positioning() {
        let styles = parse_inline_style("position: absolute; top: 10px; left: 20px;");
        
        assert_eq!(styles.position, POSITION_ABSOLUTE);
        assert_eq!(styles.top.value, 10.0);
        assert!(!styles.top.is_auto);
        assert_eq!(styles.left.value, 20.0);
    }
    
    #[test]
    fn test_parse_margin_shorthand() {
        let (t, r, b, l) = parse_margin_shorthand("10px");
        assert_eq!((t, r, b, l), (10.0, 10.0, 10.0, 10.0));
        
        let (t, r, b, l) = parse_margin_shorthand("10px 20px");
        assert_eq!((t, r, b, l), (10.0, 20.0, 10.0, 20.0));
        
        let (t, r, b, l) = parse_margin_shorthand("10px 20px 30px 40px");
        assert_eq!((t, r, b, l), (10.0, 20.0, 30.0, 40.0));
    }
}
