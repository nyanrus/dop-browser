//! Software rendering module using tiny-skia
//!
//! Provides CPU-based 2D rendering for headless and fallback scenarios.

#[cfg(feature = "software")]
use tiny_skia::{Color, Paint, PathBuilder, Pixmap, Rect, Transform};

use crate::renderer::RenderCommand;
use crate::text::FontManager;

/// Software renderer using tiny-skia
pub struct SoftwareRenderer {
    pixmap: Pixmap,
    width: u32,
    height: u32,
    commands: Vec<RenderCommand>,
    text_commands: Vec<TextCommand>,
    clear_color: (u8, u8, u8, u8),
    font_manager: FontManager,
}

/// Text command for software rendering
#[derive(Debug, Clone)]
pub struct TextCommand {
    pub text: String,
    pub x: f32,
    pub y: f32,
    pub font_size: f32,
    pub color_r: f32,
    pub color_g: f32,
    pub color_b: f32,
    pub color_a: f32,
    pub font_id: u32,
}

impl SoftwareRenderer {
    /// Create a new software renderer with the given dimensions
    pub fn new(width: u32, height: u32) -> Self {
        let pixmap = Pixmap::new(width.max(1), height.max(1))
            .expect("Failed to create pixmap");
        
        Self {
            pixmap,
            width: width.max(1),
            height: height.max(1),
            commands: Vec::new(),
            text_commands: Vec::new(),
            clear_color: (255, 255, 255, 255), // White by default
            font_manager: FontManager::new(),
        }
    }

    /// Get the current size
    pub fn size(&self) -> (u32, u32) {
        (self.width, self.height)
    }

    /// Resize the renderer
    pub fn resize(&mut self, width: u32, height: u32) {
        let w = width.max(1);
        let h = height.max(1);
        if w != self.width || h != self.height {
            self.width = w;
            self.height = h;
            self.pixmap = Pixmap::new(w, h).expect("Failed to create pixmap");
        }
    }

    /// Set the clear color
    pub fn set_clear_color(&mut self, r: f32, g: f32, b: f32, a: f32) {
        self.clear_color = (
            (r * 255.0) as u8,
            (g * 255.0) as u8,
            (b * 255.0) as u8,
            (a * 255.0) as u8,
        );
    }

    /// Clear all render commands
    pub fn clear(&mut self) {
        self.commands.clear();
        self.text_commands.clear();
    }

    /// Add a rectangle render command
    pub fn add_rect(&mut self, cmd: RenderCommand) {
        self.commands.push(cmd);
    }

    /// Add a text render command
    pub fn add_text(&mut self, text_cmd: TextCommand) {
        self.text_commands.push(text_cmd);
    }

    /// Get a reference to the font manager
    pub fn font_manager(&self) -> &FontManager {
        &self.font_manager
    }

    /// Get a mutable reference to the font manager
    pub fn font_manager_mut(&mut self) -> &mut FontManager {
        &mut self.font_manager
    }

    /// Render all commands to the pixmap
    pub fn render(&mut self) {
        // Clear pixmap with clear color
        let (r, g, b, a) = self.clear_color;
        self.pixmap.fill(Color::from_rgba8(r, g, b, a));

        // Sort commands by z-index
        self.commands.sort_by_key(|c| c.z_index);

        // Clone commands to iterate over them
        let commands: Vec<RenderCommand> = self.commands.clone();

        // Render each rectangle
        for cmd in &commands {
            self.render_rect(cmd);
        }

        // Render text commands
        let text_commands: Vec<TextCommand> = self.text_commands.clone();
        for text_cmd in &text_commands {
            self.render_text(&text_cmd);
        }
    }

    /// Render a single rectangle command
    fn render_rect(&mut self, cmd: &RenderCommand) {
        if cmd.width <= 0.0 || cmd.height <= 0.0 {
            return;
        }

        let rect = match Rect::from_xywh(cmd.x, cmd.y, cmd.width, cmd.height) {
            Some(r) => r,
            None => return,
        };

        let mut paint = Paint::default();
        paint.set_color(Color::from_rgba(
            cmd.color_r,
            cmd.color_g,
            cmd.color_b,
            cmd.color_a,
        ).unwrap_or(Color::BLACK));
        paint.anti_alias = true;

        // Create a filled rectangle path
        let path = PathBuilder::from_rect(rect);
        
        self.pixmap.fill_path(
            &path,
            &paint,
            tiny_skia::FillRule::Winding,
            Transform::identity(),
            None,
        );
    }

    /// Render a text command
    fn render_text(&mut self, cmd: &TextCommand) {
        if cmd.text.is_empty() {
            return;
        }

        let color = (
            (cmd.color_r * 255.0) as u8,
            (cmd.color_g * 255.0) as u8,
            (cmd.color_b * 255.0) as u8,
            (cmd.color_a * 255.0) as u8,
        );

        let (text_buffer, text_w, text_h) = self.font_manager.rasterize_text(
            &cmd.text,
            cmd.font_size,
            cmd.font_id,
            color,
        );

        if text_buffer.is_empty() || text_w == 0 || text_h == 0 {
            return;
        }

        // Blit text to pixmap
        let tx = cmd.x as i32;
        let ty = cmd.y as i32;
        let pixmap_data = self.pixmap.data_mut();
        let w = self.width as i32;
        let h = self.height as i32;

        for ty_off in 0..text_h as i32 {
            for tx_off in 0..text_w as i32 {
                let px = tx + tx_off;
                let py = ty + ty_off;

                if px >= 0 && py >= 0 && px < w && py < h {
                    let src_idx = ((ty_off as u32 * text_w + tx_off as u32) * 4) as usize;
                    let dst_idx = ((py * w + px) * 4) as usize;

                    if src_idx + 3 < text_buffer.len() && dst_idx + 3 < pixmap_data.len() {
                        let src_a = text_buffer[src_idx + 3] as f32 / 255.0;
                        if src_a > 0.0 {
                            let inv_a = 1.0 - src_a;
                            pixmap_data[dst_idx] = ((text_buffer[src_idx] as f32 * src_a
                                + pixmap_data[dst_idx] as f32 * inv_a) as u8)
                                .min(255);
                            pixmap_data[dst_idx + 1] = ((text_buffer[src_idx + 1] as f32 * src_a
                                + pixmap_data[dst_idx + 1] as f32 * inv_a) as u8)
                                .min(255);
                            pixmap_data[dst_idx + 2] = ((text_buffer[src_idx + 2] as f32 * src_a
                                + pixmap_data[dst_idx + 2] as f32 * inv_a) as u8)
                                .min(255);
                            pixmap_data[dst_idx + 3] = ((src_a * 255.0
                                + pixmap_data[dst_idx + 3] as f32 * inv_a) as u8)
                                .min(255);
                        }
                    }
                }
            }
        }
    }

    /// Get the framebuffer as raw RGBA bytes
    pub fn get_framebuffer(&self) -> &[u8] {
        self.pixmap.data()
    }

    /// Get a copy of the framebuffer
    pub fn get_framebuffer_copy(&self) -> Vec<u8> {
        self.pixmap.data().to_vec()
    }

    /// Get the framebuffer size in bytes
    pub fn get_framebuffer_size(&self) -> usize {
        self.pixmap.data().len()
    }

    /// Export the framebuffer to a PNG file
    pub fn export_png(&self, path: &str) -> Result<(), Box<dyn std::error::Error>> {
        let file = std::fs::File::create(path)?;
        let w = std::io::BufWriter::new(file);
        let mut encoder = png::Encoder::new(w, self.width, self.height);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);

        let mut writer = encoder.write_header()?;
        writer.write_image_data(self.pixmap.data())?;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_software_renderer_creation() {
        let renderer = SoftwareRenderer::new(100, 100);
        assert_eq!(renderer.size(), (100, 100));
    }

    #[test]
    fn test_software_renderer_clear_color() {
        let mut renderer = SoftwareRenderer::new(100, 100);
        renderer.set_clear_color(1.0, 0.0, 0.0, 1.0);
        renderer.render();

        let data = renderer.get_framebuffer();
        // First pixel should be red
        assert_eq!(data[0], 255); // R
        assert_eq!(data[1], 0);   // G
        assert_eq!(data[2], 0);   // B
        assert_eq!(data[3], 255); // A
    }

    #[test]
    fn test_software_renderer_add_rect() {
        let mut renderer = SoftwareRenderer::new(100, 100);
        renderer.set_clear_color(1.0, 1.0, 1.0, 1.0);
        renderer.add_rect(RenderCommand {
            x: 10.0,
            y: 10.0,
            width: 50.0,
            height: 50.0,
            color_r: 0.0,
            color_g: 0.0,
            color_b: 1.0,
            color_a: 1.0,
            texture_id: 0,
            z_index: 0,
        });
        renderer.render();

        let data = renderer.get_framebuffer();
        // Check a pixel inside the rectangle (at 25, 25)
        let idx = ((25 * 100) + 25) * 4;
        assert_eq!(data[idx], 0);     // R
        assert_eq!(data[idx + 1], 0); // G
        assert_eq!(data[idx + 2], 255); // B
        assert_eq!(data[idx + 3], 255); // A
    }
}
