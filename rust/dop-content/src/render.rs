//! Content-- Rendering
//!
//! This module provides rendering functionality for Content-- trees.

use crate::primitives::{NodeTable, NodeType};
use crate::properties::PropertyTable;

/// Render command for GPU
#[derive(Clone, Debug)]
pub enum RenderCommand {
    /// Draw a filled rectangle
    FillRect {
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        r: u8,
        g: u8,
        b: u8,
        a: u8,
        border_radius: f32,
    },
    /// Draw text
    DrawText {
        x: f32,
        y: f32,
        text: String,
        font_size: f32,
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    },
}

/// Layout state for a node
#[derive(Clone, Debug, Default)]
struct LayoutState {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
}

/// Render the Content-- tree to a list of render commands
pub fn render(nodes: &NodeTable, props: &PropertyTable, viewport_width: f32, viewport_height: f32) -> Vec<RenderCommand> {
    let mut commands = Vec::new();
    let mut layout_states = vec![LayoutState::default(); nodes.len()];
    
    // Simple layout pass - start from root
    if !nodes.is_empty() {
        layout_states[0].width = viewport_width;
        layout_states[0].height = viewport_height;
        layout_node(nodes, props, 1, 0.0, 0.0, viewport_width, viewport_height, &mut layout_states);
    }
    
    // Render pass
    render_node(nodes, props, 1, &layout_states, &mut commands);
    
    commands
}

/// Layout a single node recursively
fn layout_node(
    nodes: &NodeTable,
    props: &PropertyTable,
    node_id: u32,
    x: f32,
    y: f32,
    available_width: f32,
    available_height: f32,
    layout_states: &mut [LayoutState],
) {
    if node_id == 0 || node_id > nodes.len() as u32 {
        return;
    }
    
    let idx = node_id as usize - 1;
    let node_type = nodes.node_types[idx];
    
    // Get properties
    let width = if props.width[idx] > 0.0 {
        props.width[idx]
    } else {
        available_width
    };
    
    let height = if props.height[idx] > 0.0 {
        props.height[idx]
    } else {
        available_height
    };
    
    // Apply inset
    let inset_left = props.inset_left[idx];
    let inset_top = props.inset_top[idx];
    let inset_right = props.inset_right[idx];
    let inset_bottom = props.inset_bottom[idx];
    
    // Store layout
    layout_states[idx].x = x;
    layout_states[idx].y = y;
    layout_states[idx].width = width;
    layout_states[idx].height = height;
    
    // Layout children
    let children = nodes.get_children(node_id);
    if !children.is_empty() {
        let content_x = x + inset_left;
        let content_y = y + inset_top;
        let content_width = width - inset_left - inset_right;
        let content_height = height - inset_top - inset_bottom;
        
        match node_type {
            NodeType::Stack => {
                // Stack layout
                let direction = props.direction[idx];
                let gap_row = props.gap_row[idx];
                let gap_col = props.gap_col[idx];
                
                let mut curr_x = content_x;
                let mut curr_y = content_y;
                
                for child_id in children {
                    layout_node(
                        nodes,
                        props,
                        child_id,
                        curr_x,
                        curr_y,
                        content_width,
                        content_height,
                        layout_states,
                    );
                    
                    // Advance position based on direction
                    let child_idx = child_id as usize - 1;
                    match direction {
                        crate::properties::Direction::Down => {
                            curr_y += layout_states[child_idx].height + gap_row;
                        }
                        crate::properties::Direction::Right => {
                            curr_x += layout_states[child_idx].width + gap_col;
                        }
                        _ => {}
                    }
                }
            }
            NodeType::Paragraph => {
                // Paragraph layout - stack spans vertically
                let curr_x = content_x;
                let mut curr_y = content_y;
                
                for child_id in children {
                    layout_node(
                        nodes,
                        props,
                        child_id,
                        curr_x,
                        curr_y,
                        content_width,
                        20.0, // Default line height
                        layout_states,
                    );
                    curr_y += 20.0;
                }
            }
            _ => {
                // Default: stack children vertically
                let mut curr_y = content_y;
                for child_id in children {
                    layout_node(
                        nodes,
                        props,
                        child_id,
                        content_x,
                        curr_y,
                        content_width,
                        content_height,
                        layout_states,
                    );
                    let child_idx = child_id as usize - 1;
                    curr_y += layout_states[child_idx].height;
                }
            }
        }
    }
}

/// Render a single node recursively
fn render_node(
    nodes: &NodeTable,
    props: &PropertyTable,
    node_id: u32,
    layout_states: &[LayoutState],
    commands: &mut Vec<RenderCommand>,
) {
    if node_id == 0 || node_id > nodes.len() as u32 {
        return;
    }
    
    let idx = node_id as usize - 1;
    let node_type = nodes.node_types[idx];
    let layout = &layout_states[idx];
    
    // Render based on node type
    match node_type {
        NodeType::Rect | NodeType::Stack => {
            // Draw background if fill color is set
            if props.fill_a[idx] > 0 {
                commands.push(RenderCommand::FillRect {
                    x: layout.x,
                    y: layout.y,
                    width: layout.width,
                    height: layout.height,
                    r: props.fill_r[idx],
                    g: props.fill_g[idx],
                    b: props.fill_b[idx],
                    a: props.fill_a[idx],
                    border_radius: props.border_radius[idx],
                });
            }
        }
        NodeType::Span => {
            // Draw text
            if !props.text_content[idx].is_empty() {
                commands.push(RenderCommand::DrawText {
                    x: layout.x,
                    y: layout.y,
                    text: props.text_content[idx].clone(),
                    font_size: props.font_size[idx],
                    r: props.text_color_r[idx],
                    g: props.text_color_g[idx],
                    b: props.text_color_b[idx],
                    a: props.text_color_a[idx],
                });
            }
        }
        _ => {}
    }
    
    // Render children
    let children = nodes.get_children(node_id);
    for child_id in children {
        render_node(nodes, props, child_id, layout_states, commands);
    }
}
