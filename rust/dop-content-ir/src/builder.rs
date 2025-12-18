//! Content IR Builder API
//!
//! This module provides a fluent builder API for constructing Content IR trees.

use crate::primitives::{NodeTable, NodeType};
use crate::properties::{PropertyTable, Direction, Pack, Align, Color};

/// Builder for constructing Content-- trees
pub struct ContentBuilder {
    nodes: NodeTable,
    properties: PropertyTable,
    current_parent: u32,
}

impl ContentBuilder {
    /// Create a new builder
    pub fn new() -> Self {
        let mut nodes = NodeTable::new();
        let mut properties = PropertyTable::new();
        
        // Create root node
        let root_id = nodes.create_node(NodeType::Root, 0, 0);
        properties.resize(1);
        
        Self {
            nodes,
            properties,
            current_parent: root_id,
        }
    }
    
    /// Begin a Stack container
    pub fn begin_stack(&mut self) -> &mut Self {
        let id = self.create_node(NodeType::Stack);
        self.current_parent = id;
        self
    }
    
    /// End the current container (move up to parent)
    pub fn end(&mut self) -> &mut Self {
        if self.current_parent > 0 {
            if let Some(node) = self.nodes.get_node(self.current_parent) {
                self.current_parent = node.parent;
            }
        }
        self
    }
    
    /// Add a Rect node
    pub fn rect(&mut self) -> &mut Self {
        self.create_node(NodeType::Rect);
        self
    }
    
    /// Begin a Paragraph node
    pub fn begin_paragraph(&mut self) -> &mut Self {
        let id = self.create_node(NodeType::Paragraph);
        self.current_parent = id;
        self
    }
    
    /// Add a Span node with text
    pub fn span(&mut self, text: &str) -> &mut Self {
        let id = self.create_node(NodeType::Span);
        let idx = id as usize - 1;
        if idx < self.properties.text_content.len() {
            self.properties.text_content[idx] = text.to_string();
        }
        self
    }
    
    /// Set direction on current node
    pub fn direction(&mut self, dir: Direction) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.direction.len() {
            self.properties.direction[idx] = dir;
        }
        self
    }
    
    /// Set pack on current node
    pub fn pack(&mut self, pack: Pack) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.pack.len() {
            self.properties.pack[idx] = pack;
        }
        self
    }
    
    /// Set align on current node
    pub fn align(&mut self, align: Align) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.align.len() {
            self.properties.align[idx] = align;
        }
        self
    }
    
    /// Set width on current node
    pub fn width(&mut self, w: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.width.len() {
            self.properties.width[idx] = w;
        }
        self
    }
    
    /// Set height on current node
    pub fn height(&mut self, h: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.height.len() {
            self.properties.height[idx] = h;
        }
        self
    }
    
    /// Set gap on current node
    pub fn gap(&mut self, gap: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.gap_row.len() {
            self.properties.gap_row[idx] = gap;
            self.properties.gap_col[idx] = gap;
        }
        self
    }
    
    /// Set fill color on last created node
    pub fn fill(&mut self, color: Color) -> &mut Self {
        let idx = (self.nodes.len() - 1).max(0);
        self.properties.set_fill(idx, color);
        self
    }
    
    /// Set fill color from hex string on last created node
    pub fn fill_hex(&mut self, hex: &str) -> &mut Self {
        if let Some(color) = Color::from_hex(hex) {
            self.fill(color);
        }
        self
    }
    
    /// Set inset (padding) on current node
    pub fn inset(&mut self, inset: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        self.properties.set_inset(idx, inset, inset, inset, inset);
        self
    }
    
    /// Set inset with individual sides
    pub fn inset_trbl(&mut self, top: f32, right: f32, bottom: f32, left: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        self.properties.set_inset(idx, top, right, bottom, left);
        self
    }
    
    /// Set border radius on last created node
    pub fn border_radius(&mut self, radius: f32) -> &mut Self {
        let idx = (self.nodes.len() - 1).max(0);
        if idx < self.properties.border_radius.len() {
            self.properties.border_radius[idx] = radius;
        }
        self
    }
    
    /// Set font size on current node
    pub fn font_size(&mut self, size: f32) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        if idx < self.properties.font_size.len() {
            self.properties.font_size[idx] = size;
        }
        self
    }
    
    /// Set text color on current node
    pub fn text_color(&mut self, color: Color) -> &mut Self {
        let idx = self.current_parent as usize - 1;
        self.properties.set_text_color(idx, color);
        self
    }
    
    /// Set text color from hex string on current node
    pub fn text_color_hex(&mut self, hex: &str) -> &mut Self {
        if let Some(color) = Color::from_hex(hex) {
            self.text_color(color);
        }
        self
    }
    
    /// Consume the builder and return the node and property tables
    pub fn build(self) -> (NodeTable, PropertyTable) {
        (self.nodes, self.properties)
    }
    
    /// Get references to the tables (for rendering without consuming)
    pub fn tables(&self) -> (&NodeTable, &PropertyTable) {
        (&self.nodes, &self.properties)
    }
    
    /// Get mutable references to the tables
    pub fn tables_mut(&mut self) -> (&mut NodeTable, &mut PropertyTable) {
        (&mut self.nodes, &mut self.properties)
    }
    
    // Internal helper to create a node
    fn create_node(&mut self, node_type: NodeType) -> u32 {
        let id = self.nodes.create_node(node_type, self.current_parent, 0);
        self.properties.resize(self.nodes.len());
        id
    }
}

impl Default for ContentBuilder {
    fn default() -> Self {
        Self::new()
    }
}
