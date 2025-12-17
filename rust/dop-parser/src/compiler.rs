//! Content-- Compiler and JIT infrastructure
//!
//! This module provides:
//! - AOT compilation to zero-copy binary format
//! - JIT text shaping infrastructure
//! - Layout primitives (Stack, Grid, Scroll, Rect)
//! - Text primitives (Paragraph, Span, Link)

use std::collections::HashMap;
use zerocopy::{FromBytes, Immutable, IntoBytes, KnownLayout};

use crate::css_parser::Color;
use crate::string_interner::StringId;

/// Content-- binary format magic number "CMMB"
pub const MAGIC_NUMBER: u32 = 0x434D4D42;
/// Current binary format version
pub const FORMAT_VERSION: u32 = 1;

// ============================================================================
// Node Types
// ============================================================================

/// Content-- node type enum
#[derive(Clone, Copy, Debug, PartialEq, Eq, IntoBytes, Immutable, KnownLayout)]
#[repr(u8)]
pub enum NodeType {
    Root = 0,
    Stack = 1,
    Grid = 2,
    Scroll = 3,
    Rect = 4,
    Paragraph = 5,
    Span = 6,
    Link = 7,
    TextCluster = 8,
}

// ============================================================================
// Layout Properties
// ============================================================================

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

// ============================================================================
// Node Data Structures (SoA - Structure of Arrays)
// ============================================================================

/// Node table storing Content-- nodes in SoA format
#[derive(Default)]
pub struct NodeTable {
    /// Node types
    pub node_types: Vec<NodeType>,
    /// Parent node indices (0 = no parent)
    pub parents: Vec<u32>,
    /// First child node indices (0 = no children)
    pub first_children: Vec<u32>,
    /// Next sibling node indices (0 = no sibling)
    pub next_siblings: Vec<u32>,
    /// Style ID for each node
    pub style_ids: Vec<u32>,
}

impl NodeTable {
    /// Create a new empty node table
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Get the number of nodes
    pub fn len(&self) -> usize {
        self.node_types.len()
    }
    
    /// Check if the table is empty
    pub fn is_empty(&self) -> bool {
        self.node_types.is_empty()
    }
    
    /// Create a new node and return its ID (1-indexed)
    pub fn create_node(&mut self, node_type: NodeType, parent: u32, style_id: u32) -> u32 {
        let id = self.node_types.len() as u32 + 1;
        
        self.node_types.push(node_type);
        self.parents.push(parent);
        self.first_children.push(0);
        self.next_siblings.push(0);
        self.style_ids.push(style_id);
        
        // Update parent's child pointers
        if parent > 0 && parent <= self.node_types.len() as u32 {
            let parent_idx = parent as usize - 1;
            if self.first_children[parent_idx] == 0 {
                self.first_children[parent_idx] = id;
            } else {
                // Find last sibling and update
                let mut sibling = self.first_children[parent_idx];
                while self.next_siblings[sibling as usize - 1] != 0 {
                    sibling = self.next_siblings[sibling as usize - 1];
                }
                self.next_siblings[sibling as usize - 1] = id;
            }
        }
        
        id
    }
    
    /// Get children of a node
    pub fn get_children(&self, node_id: u32) -> Vec<u32> {
        if node_id == 0 || node_id > self.node_types.len() as u32 {
            return Vec::new();
        }
        
        let mut children = Vec::new();
        let mut child = self.first_children[node_id as usize - 1];
        while child != 0 {
            children.push(child);
            child = self.next_siblings[child as usize - 1];
        }
        children
    }
}

// ============================================================================
// Property Table
// ============================================================================

/// Property table storing node properties in SoA format
#[derive(Default)]
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
    
    // Text properties (for Span/Paragraph)
    pub text_id: Vec<StringId>,
    pub font_size: Vec<f32>,
    pub color_r: Vec<u8>,
    pub color_g: Vec<u8>,
    pub color_b: Vec<u8>,
    pub color_a: Vec<u8>,
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
        
        self.text_id.resize(n, StringId::NONE);
        self.font_size.resize(n, 16.0);
        self.color_r.resize(n, 0);
        self.color_g.resize(n, 0);
        self.color_b.resize(n, 0);
        self.color_a.resize(n, 255);
    }
}

// ============================================================================
// Flattened Style (AOT output)
// ============================================================================

/// Flattened style with all inheritance resolved (AOT output)
#[derive(Clone, Copy, Debug, Default, FromBytes, IntoBytes, Immutable, KnownLayout)]
#[repr(C, packed)]
pub struct FlatStyle {
    pub direction: u8,
    pub pack: u8,
    pub align: u8,
    pub _pad0: u8,
    
    pub gap_row: f32,
    pub gap_col: f32,
    
    pub width: f32,
    pub height: f32,
    pub min_width: f32,
    pub min_height: f32,
    pub max_width: f32,
    pub max_height: f32,
    
    pub inset_top: f32,
    pub inset_right: f32,
    pub inset_bottom: f32,
    pub inset_left: f32,
    
    pub offset_top: f32,
    pub offset_right: f32,
    pub offset_bottom: f32,
    pub offset_left: f32,
    
    pub fill_r: u8,
    pub fill_g: u8,
    pub fill_b: u8,
    pub fill_a: u8,
    
    pub round: f32,
    
    pub checksum: u64,
}

// ============================================================================
// Style Table
// ============================================================================

/// Style definition before flattening
#[derive(Clone, Debug, Default)]
pub struct StyleDef {
    pub id: u32,
    pub parent_id: u32,
    pub properties: HashMap<String, PropertyValue>,
}

/// Property value enum
#[derive(Clone, Debug)]
pub enum PropertyValue {
    Float(f32),
    Int(i32),
    Color(Color),
    String(String),
    Direction(Direction),
    Pack(Pack),
    Align(Align),
}

/// Style table for managing styles
#[derive(Default)]
pub struct StyleTable {
    /// Style definitions
    pub definitions: Vec<StyleDef>,
    /// Flattened styles (after AOT)
    pub flattened: Vec<FlatStyle>,
}

impl StyleTable {
    /// Create a new style table
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Create a new style and return its ID
    pub fn create_style(&mut self, id: u32) -> u32 {
        let def = StyleDef {
            id,
            parent_id: 0,
            properties: HashMap::new(),
        };
        self.definitions.push(def);
        id
    }
    
    /// Set inheritance parent
    pub fn inherit_style(&mut self, style_id: u32, parent_id: u32) {
        if let Some(def) = self.definitions.iter_mut().find(|d| d.id == style_id) {
            def.parent_id = parent_id;
        }
    }
    
    /// Set a style property
    pub fn set_property(&mut self, style_id: u32, name: &str, value: PropertyValue) {
        if let Some(def) = self.definitions.iter_mut().find(|d| d.id == style_id) {
            def.properties.insert(name.to_string(), value);
        }
    }
    
    /// Flatten all styles (AOT operation)
    /// Resolves all inheritance chains
    pub fn flatten(&mut self) {
        self.flattened.clear();
        
        for def in &self.definitions {
            let mut flat = FlatStyle::default();
            
            // Start with defaults
            flat.max_width = f32::MAX;
            flat.max_height = f32::MAX;
            
            // Apply parent properties first (inheritance)
            if def.parent_id > 0 {
                if let Some(parent_flat) = self.flattened.iter().find(|_| false) {
                    flat = *parent_flat;
                }
            }
            
            // Apply own properties
            for (name, value) in &def.properties {
                match (name.as_str(), value) {
                    ("direction", PropertyValue::Direction(d)) => flat.direction = *d as u8,
                    ("pack", PropertyValue::Pack(p)) => flat.pack = *p as u8,
                    ("align", PropertyValue::Align(a)) => flat.align = *a as u8,
                    ("width", PropertyValue::Float(v)) => flat.width = *v,
                    ("height", PropertyValue::Float(v)) => flat.height = *v,
                    ("gap_row", PropertyValue::Float(v)) => flat.gap_row = *v,
                    ("gap_col", PropertyValue::Float(v)) => flat.gap_col = *v,
                    ("inset_top", PropertyValue::Float(v)) => flat.inset_top = *v,
                    ("inset_right", PropertyValue::Float(v)) => flat.inset_right = *v,
                    ("inset_bottom", PropertyValue::Float(v)) => flat.inset_bottom = *v,
                    ("inset_left", PropertyValue::Float(v)) => flat.inset_left = *v,
                    ("offset_top", PropertyValue::Float(v)) => flat.offset_top = *v,
                    ("offset_right", PropertyValue::Float(v)) => flat.offset_right = *v,
                    ("offset_bottom", PropertyValue::Float(v)) => flat.offset_bottom = *v,
                    ("offset_left", PropertyValue::Float(v)) => flat.offset_left = *v,
                    ("fill", PropertyValue::Color(c)) => {
                        flat.fill_r = c.r;
                        flat.fill_g = c.g;
                        flat.fill_b = c.b;
                        flat.fill_a = c.a;
                    }
                    ("round", PropertyValue::Float(v)) => flat.round = *v,
                    _ => {}
                }
            }
            
            // Compute checksum
            flat.checksum = compute_style_checksum(&flat);
            
            self.flattened.push(flat);
        }
    }
    
    /// Get flattened style by index
    pub fn get_flat(&self, index: usize) -> Option<&FlatStyle> {
        self.flattened.get(index)
    }
}

/// Compute checksum for a flattened style
fn compute_style_checksum(style: &FlatStyle) -> u64 {
    let bytes = zerocopy::IntoBytes::as_bytes(style);
    let mut hash: u64 = 0;
    for &b in bytes.iter().take(bytes.len() - 8) {
        // Skip checksum field itself
        hash = hash.wrapping_mul(31).wrapping_add(b as u64);
    }
    hash
}

// ============================================================================
// Compiled Unit
// ============================================================================

/// A compiled Content-- unit ready for runtime
#[derive(Default)]
pub struct CompiledUnit {
    pub nodes: NodeTable,
    pub properties: PropertyTable,
    pub styles: Vec<FlatStyle>,
    pub environment_id: u32,
    pub version: u32,
    pub checksum: u64,
}

impl CompiledUnit {
    /// Create a new compiled unit
    pub fn new() -> Self {
        Self {
            version: FORMAT_VERSION,
            ..Default::default()
        }
    }
    
    /// Compute checksum for the unit
    pub fn compute_checksum(&mut self) {
        let n = self.nodes.len();
        let mut h = n as u64;
        h = h.wrapping_mul(31).wrapping_add(self.environment_id as u64);
        h = h.wrapping_mul(31).wrapping_add(self.styles.len() as u64);
        self.checksum = h;
    }
    
    /// Write the compiled unit to bytes (binary format)
    pub fn write_binary(&self) -> Vec<u8> {
        let mut buf = Vec::new();
        
        // Magic number
        buf.extend_from_slice(&MAGIC_NUMBER.to_le_bytes());
        
        // Version
        buf.extend_from_slice(&self.version.to_le_bytes());
        
        // Environment ID
        buf.extend_from_slice(&self.environment_id.to_le_bytes());
        
        // Checksum
        buf.extend_from_slice(&self.checksum.to_le_bytes());
        
        // Node count
        let n = self.nodes.len() as u32;
        buf.extend_from_slice(&n.to_le_bytes());
        
        // Node data (packed)
        for i in 0..self.nodes.len() {
            buf.push(self.nodes.node_types[i] as u8);
            buf.extend_from_slice(&self.nodes.parents[i].to_le_bytes());
            buf.extend_from_slice(&self.nodes.first_children[i].to_le_bytes());
            buf.extend_from_slice(&self.nodes.next_siblings[i].to_le_bytes());
            buf.extend_from_slice(&self.nodes.style_ids[i].to_le_bytes());
        }
        
        // Style count
        let s = self.styles.len() as u32;
        buf.extend_from_slice(&s.to_le_bytes());
        
        // Style data (using zerocopy)
        for style in &self.styles {
            buf.extend_from_slice(zerocopy::IntoBytes::as_bytes(style));
        }
        
        buf
    }
    
    /// Read a compiled unit from bytes (binary format)
    pub fn read_binary(data: &[u8]) -> Option<Self> {
        if data.len() < 24 {
            return None;
        }
        
        let mut offset = 0;
        
        // Check magic number
        let magic = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
        if magic != MAGIC_NUMBER {
            return None;
        }
        offset += 4;
        
        let mut unit = Self::new();
        
        // Version
        unit.version = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
        offset += 4;
        
        // Environment ID
        unit.environment_id = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
        offset += 4;
        
        // Checksum
        unit.checksum = u64::from_le_bytes(data[offset..offset+8].try_into().ok()?);
        offset += 8;
        
        // Node count
        let n = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?) as usize;
        offset += 4;
        
        // Node data
        for _ in 0..n {
            if offset + 17 > data.len() {
                return None;
            }
            
            let node_type = match data[offset] {
                0 => NodeType::Root,
                1 => NodeType::Stack,
                2 => NodeType::Grid,
                3 => NodeType::Scroll,
                4 => NodeType::Rect,
                5 => NodeType::Paragraph,
                6 => NodeType::Span,
                7 => NodeType::Link,
                8 => NodeType::TextCluster,
                _ => NodeType::Root,
            };
            offset += 1;
            
            let parent = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
            offset += 4;
            
            let first_child = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
            offset += 4;
            
            let next_sibling = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
            offset += 4;
            
            let style_id = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?);
            offset += 4;
            
            unit.nodes.node_types.push(node_type);
            unit.nodes.parents.push(parent);
            unit.nodes.first_children.push(first_child);
            unit.nodes.next_siblings.push(next_sibling);
            unit.nodes.style_ids.push(style_id);
        }
        
        // Style count
        if offset + 4 > data.len() {
            return None;
        }
        let s = u32::from_le_bytes(data[offset..offset+4].try_into().ok()?) as usize;
        offset += 4;
        
        // Style data
        let style_size = std::mem::size_of::<FlatStyle>();
        for _ in 0..s {
            if offset + style_size > data.len() {
                return None;
            }
            
            if let Ok(style) = FlatStyle::read_from_bytes(&data[offset..offset+style_size]) {
                unit.styles.push(style);
            }
            offset += style_size;
        }
        
        Some(unit)
    }
}

// ============================================================================
// JIT Text Shaping
// ============================================================================

/// Shaped paragraph result
#[derive(Clone, Debug)]
pub struct ShapedParagraph {
    pub text_hash: u64,
    pub max_width: f32,
    pub width: f32,
    pub height: f32,
    pub line_count: u32,
    pub clusters: Vec<TextCluster>,
}

/// Text cluster for GPU rendering
#[derive(Clone, Copy, Debug, Default)]
pub struct TextCluster {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub glyph_start: u32,
    pub glyph_count: u32,
}

/// JIT text shaper with caching
pub struct TextShaper {
    cache: HashMap<(u64, i32), ShapedParagraph>,
    font_size: f32,
    line_height: f32,
}

impl Default for TextShaper {
    fn default() -> Self {
        Self::new()
    }
}

impl TextShaper {
    /// Create a new text shaper
    pub fn new() -> Self {
        Self {
            cache: HashMap::new(),
            font_size: 16.0,
            line_height: 1.2,
        }
    }
    
    /// Shape a paragraph (JIT operation)
    /// Results are cached by (text_hash, max_width)
    pub fn shape_paragraph(&mut self, text: &str, max_width: f32) -> ShapedParagraph {
        let text_hash = compute_text_hash(text);
        let width_key = (max_width * 10.0) as i32; // Cache with some precision
        
        let cache_key = (text_hash, width_key);
        
        if let Some(cached) = self.cache.get(&cache_key) {
            return cached.clone();
        }
        
        // Simplified shaping (real implementation would use harfbuzz/freetype)
        let char_width = self.font_size * 0.6; // Approximate
        let chars_per_line = (max_width / char_width).floor() as usize;
        
        let mut lines = Vec::new();
        let mut current_line = String::new();
        
        for word in text.split_whitespace() {
            if current_line.len() + word.len() + 1 > chars_per_line && !current_line.is_empty() {
                lines.push(current_line);
                current_line = word.to_string();
            } else {
                if !current_line.is_empty() {
                    current_line.push(' ');
                }
                current_line.push_str(word);
            }
        }
        if !current_line.is_empty() {
            lines.push(current_line);
        }
        
        let line_height_px = self.font_size * self.line_height;
        let total_height = lines.len() as f32 * line_height_px;
        let max_line_width = lines.iter()
            .map(|l| l.len() as f32 * char_width)
            .fold(0.0f32, f32::max);
        
        // Create clusters (one per line for simplicity)
        let clusters: Vec<TextCluster> = lines.iter()
            .enumerate()
            .map(|(i, line)| TextCluster {
                x: 0.0,
                y: i as f32 * line_height_px,
                width: line.len() as f32 * char_width,
                height: line_height_px,
                glyph_start: 0,
                glyph_count: line.len() as u32,
            })
            .collect();
        
        let shaped = ShapedParagraph {
            text_hash,
            max_width,
            width: max_line_width,
            height: total_height.max(line_height_px),
            line_count: lines.len() as u32,
            clusters,
        };
        
        self.cache.insert(cache_key, shaped.clone());
        shaped
    }
    
    /// Clear the cache
    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }
    
    /// Set font size for shaping
    pub fn set_font_size(&mut self, size: f32) {
        if (self.font_size - size).abs() > 0.01 {
            self.font_size = size;
            self.cache.clear(); // Invalidate cache on font size change
        }
    }
}

/// Compute a hash for text content
fn compute_text_hash(text: &str) -> u64 {
    let mut hash: u64 = 0;
    for byte in text.bytes() {
        hash = hash.wrapping_mul(31).wrapping_add(byte as u64);
    }
    hash
}

// ============================================================================
// Compiler Context
// ============================================================================

/// Compiler options
#[derive(Clone, Debug)]
pub struct CompileOptions {
    pub optimize_level: i32,
    pub flatten_styles: bool,
    pub inline_macros: bool,
    pub generate_sourcemap: bool,
    pub target_environments: Vec<u32>,
}

impl Default for CompileOptions {
    fn default() -> Self {
        Self {
            optimize_level: 1,
            flatten_styles: true,
            inline_macros: true,
            generate_sourcemap: false,
            target_environments: Vec::new(),
        }
    }
}

/// Compiler context
#[derive(Default)]
pub struct CompilerContext {
    pub style_table: StyleTable,
    pub units: HashMap<u32, CompiledUnit>,
    pub options: CompileOptions,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

impl CompilerContext {
    /// Create a new compiler context
    pub fn new() -> Self {
        Self {
            options: CompileOptions::default(),
            ..Default::default()
        }
    }
    
    /// Create with custom options
    pub fn with_options(options: CompileOptions) -> Self {
        Self {
            options,
            ..Default::default()
        }
    }
    
    /// Compile nodes to binary format
    pub fn compile(&mut self, source_nodes: &NodeTable, source_props: &PropertyTable) -> bool {
        // Flatten styles if enabled
        if self.options.flatten_styles {
            self.style_table.flatten();
        }
        
        // Compile for each target environment
        if self.options.target_environments.is_empty() {
            let unit = self.compile_unit(source_nodes, source_props, 0);
            self.units.insert(0, unit);
        } else {
            for &env_id in &self.options.target_environments.clone() {
                let unit = self.compile_unit(source_nodes, source_props, env_id);
                self.units.insert(env_id, unit);
            }
        }
        
        self.errors.is_empty()
    }
    
    /// Compile for a specific environment
    fn compile_unit(&mut self, source_nodes: &NodeTable, source_props: &PropertyTable, env_id: u32) -> CompiledUnit {
        let mut unit = CompiledUnit::new();
        unit.environment_id = env_id;
        
        let n = source_nodes.len();
        unit.properties.resize(n);
        
        // Copy nodes
        for i in 0..n {
            unit.nodes.node_types.push(source_nodes.node_types[i]);
            unit.nodes.parents.push(source_nodes.parents[i]);
            unit.nodes.first_children.push(source_nodes.first_children[i]);
            unit.nodes.next_siblings.push(source_nodes.next_siblings[i]);
            unit.nodes.style_ids.push(source_nodes.style_ids[i]);
            
            // Copy properties
            if i < source_props.direction.len() {
                unit.properties.direction[i] = source_props.direction[i];
                unit.properties.pack[i] = source_props.pack[i];
                unit.properties.align[i] = source_props.align[i];
                unit.properties.width[i] = source_props.width[i];
                unit.properties.height[i] = source_props.height[i];
                unit.properties.gap_row[i] = source_props.gap_row[i];
                unit.properties.gap_col[i] = source_props.gap_col[i];
                unit.properties.inset_top[i] = source_props.inset_top[i];
                unit.properties.inset_right[i] = source_props.inset_right[i];
                unit.properties.inset_bottom[i] = source_props.inset_bottom[i];
                unit.properties.inset_left[i] = source_props.inset_left[i];
                unit.properties.offset_top[i] = source_props.offset_top[i];
                unit.properties.offset_right[i] = source_props.offset_right[i];
                unit.properties.offset_bottom[i] = source_props.offset_bottom[i];
                unit.properties.offset_left[i] = source_props.offset_left[i];
                unit.properties.fill_r[i] = source_props.fill_r[i];
                unit.properties.fill_g[i] = source_props.fill_g[i];
                unit.properties.fill_b[i] = source_props.fill_b[i];
                unit.properties.fill_a[i] = source_props.fill_a[i];
            }
        }
        
        // Copy flattened styles
        for flat in &self.style_table.flattened {
            unit.styles.push(*flat);
        }
        
        unit.compute_checksum();
        unit
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_node_table() {
        let mut table = NodeTable::new();
        
        let root = table.create_node(NodeType::Root, 0, 0);
        assert_eq!(root, 1);
        
        let stack = table.create_node(NodeType::Stack, root, 0);
        assert_eq!(stack, 2);
        assert_eq!(table.parents[1], root);
        
        let children = table.get_children(root);
        assert_eq!(children, vec![stack]);
    }
    
    #[test]
    fn test_binary_roundtrip() {
        let mut unit = CompiledUnit::new();
        unit.nodes.create_node(NodeType::Root, 0, 0);
        unit.nodes.create_node(NodeType::Stack, 1, 0);
        unit.compute_checksum();
        
        let bytes = unit.write_binary();
        let restored = CompiledUnit::read_binary(&bytes).unwrap();
        
        assert_eq!(restored.nodes.len(), unit.nodes.len());
        assert_eq!(restored.checksum, unit.checksum);
    }
    
    #[test]
    fn test_text_shaper() {
        let mut shaper = TextShaper::new();
        
        let shaped = shaper.shape_paragraph("Hello World", 200.0);
        assert!(shaped.width > 0.0);
        assert!(shaped.height > 0.0);
        assert!(shaped.line_count >= 1);
        
        // Second call should hit cache
        let shaped2 = shaper.shape_paragraph("Hello World", 200.0);
        assert_eq!(shaped2.text_hash, shaped.text_hash);
    }
    
    #[test]
    fn test_style_flattening() {
        let mut table = StyleTable::new();
        
        table.create_style(1);
        table.set_property(1, "width", PropertyValue::Float(100.0));
        table.set_property(1, "height", PropertyValue::Float(50.0));
        
        table.flatten();
        
        assert_eq!(table.flattened.len(), 1);
        // Copy values to avoid unaligned access on packed struct
        let width = table.flattened[0].width;
        let height = table.flattened[0].height;
        assert_eq!(width, 100.0);
        assert_eq!(height, 50.0);
    }
}
