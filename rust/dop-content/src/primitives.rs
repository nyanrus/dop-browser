//! Content-- Primitives
//!
//! This module defines the core Content-- node types and node table structure.

use zerocopy::{Immutable, IntoBytes, KnownLayout};

/// Content-- node type enumeration
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

/// A single Content-- node (SoA row representation)
#[derive(Clone, Debug)]
pub struct ContentNode {
    pub node_type: NodeType,
    pub parent: u32,
    pub first_child: u32,
    pub next_sibling: u32,
    pub style_id: u32,
}

/// Node table storing Content-- nodes in Structure of Arrays (SoA) format
#[derive(Default, Debug)]
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
    
    /// Get a node by ID
    pub fn get_node(&self, id: u32) -> Option<ContentNode> {
        if id == 0 || id > self.node_types.len() as u32 {
            return None;
        }
        
        let idx = id as usize - 1;
        Some(ContentNode {
            node_type: self.node_types[idx],
            parent: self.parents[idx],
            first_child: self.first_children[idx],
            next_sibling: self.next_siblings[idx],
            style_id: self.style_ids[idx],
        })
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
