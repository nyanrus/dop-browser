//! Content IR Properties
//!
//! This module defines property tables and enums for Content IR nodes.

use zerocopy::{Immutable, IntoBytes, KnownLayout};

/// Direction enum for Stack layout
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, IntoBytes, Immutable, KnownLayout)]
#[repr(u8)]
pub enum Direction {
    #[default]
    Down = 0,
    Up = 1,
    Right = 2,
    Left = 3,
}

/// Pack (justify-content equivalent)
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, IntoBytes, Immutable, KnownLayout)]
#[repr(u8)]
pub enum Pack {
    #[default]
    Start = 0,
    End = 1,
    Center = 2,
    SpaceBetween = 3,
    SpaceAround = 4,
    SpaceEvenly = 5,
}

/// Align (align-items equivalent)
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, IntoBytes, Immutable, KnownLayout)]
#[repr(u8)]
pub enum Align {
    #[default]
    Start = 0,
    End = 1,
    Center = 2,
    Stretch = 3,
}

/// RGBA color
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Color {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Color {
    pub fn new(r: u8, g: u8, b: u8, a: u8) -> Self {
        Self { r, g, b, a }
    }
    
    pub fn from_hex(hex: &str) -> Option<Self> {
        let hex = hex.trim_start_matches('#');
        if hex.len() == 6 {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
            Some(Self::new(r, g, b, 255))
        } else if hex.len() == 8 {
            let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
            let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
            let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
            let a = u8::from_str_radix(&hex[6..8], 16).ok()?;
            Some(Self::new(r, g, b, a))
        } else {
            None
        }
    }
    
    pub fn transparent() -> Self {
        Self::new(0, 0, 0, 0)
    }
    
    pub fn white() -> Self {
        Self::new(255, 255, 255, 255)
    }
    
    pub fn black() -> Self {
        Self::new(0, 0, 0, 255)
    }
}

/// Property table storing node properties in SoA format
#[derive(Default, Debug)]
pub struct PropertyTable {
    // Layout properties
    pub direction: Vec<Direction>,
    pub pack: Vec<Pack>,
    pub align: Vec<Align>,
    pub width: Vec<f32>,
    pub height: Vec<f32>,
    pub gap_row: Vec<f32>,
    pub gap_col: Vec<f32>,
    
    // Inset (padding equivalent)
    pub inset_top: Vec<f32>,
    pub inset_right: Vec<f32>,
    pub inset_bottom: Vec<f32>,
    pub inset_left: Vec<f32>,
    
    // Offset (margin equivalent)
    pub offset_top: Vec<f32>,
    pub offset_right: Vec<f32>,
    pub offset_bottom: Vec<f32>,
    pub offset_left: Vec<f32>,
    
    // Fill color
    pub fill_r: Vec<u8>,
    pub fill_g: Vec<u8>,
    pub fill_b: Vec<u8>,
    pub fill_a: Vec<u8>,
    
    // Border radius
    pub border_radius: Vec<f32>,
    
    // Text content (for Span/Paragraph)
    pub text_content: Vec<String>,
    pub font_size: Vec<f32>,
    pub text_color_r: Vec<u8>,
    pub text_color_g: Vec<u8>,
    pub text_color_b: Vec<u8>,
    pub text_color_a: Vec<u8>,
}

impl PropertyTable {
    /// Create a new empty property table
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Resize all arrays to accommodate n nodes
    pub fn resize(&mut self, n: usize) {
        self.direction.resize(n, Direction::Down);
        self.pack.resize(n, Pack::Start);
        self.align.resize(n, Align::Start);
        self.width.resize(n, 0.0);
        self.height.resize(n, 0.0);
        self.gap_row.resize(n, 0.0);
        self.gap_col.resize(n, 0.0);
        
        self.inset_top.resize(n, 0.0);
        self.inset_right.resize(n, 0.0);
        self.inset_bottom.resize(n, 0.0);
        self.inset_left.resize(n, 0.0);
        
        self.offset_top.resize(n, 0.0);
        self.offset_right.resize(n, 0.0);
        self.offset_bottom.resize(n, 0.0);
        self.offset_left.resize(n, 0.0);
        
        self.fill_r.resize(n, 0);
        self.fill_g.resize(n, 0);
        self.fill_b.resize(n, 0);
        self.fill_a.resize(n, 0);
        
        self.border_radius.resize(n, 0.0);
        
        self.text_content.resize(n, String::new());
        self.font_size.resize(n, 16.0);
        self.text_color_r.resize(n, 0);
        self.text_color_g.resize(n, 0);
        self.text_color_b.resize(n, 0);
        self.text_color_a.resize(n, 255);
    }
    
    /// Set properties for a node
    pub fn set_fill(&mut self, idx: usize, color: Color) {
        if idx < self.fill_r.len() {
            self.fill_r[idx] = color.r;
            self.fill_g[idx] = color.g;
            self.fill_b[idx] = color.b;
            self.fill_a[idx] = color.a;
        }
    }
    
    pub fn set_text_color(&mut self, idx: usize, color: Color) {
        if idx < self.text_color_r.len() {
            self.text_color_r[idx] = color.r;
            self.text_color_g[idx] = color.g;
            self.text_color_b[idx] = color.b;
            self.text_color_a[idx] = color.a;
        }
    }
    
    pub fn set_inset(&mut self, idx: usize, top: f32, right: f32, bottom: f32, left: f32) {
        if idx < self.inset_top.len() {
            self.inset_top[idx] = top;
            self.inset_right[idx] = right;
            self.inset_bottom[idx] = bottom;
            self.inset_left[idx] = left;
        }
    }
}
