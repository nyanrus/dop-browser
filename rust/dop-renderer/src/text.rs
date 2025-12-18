//! Text rendering module using fontdue
//!
//! Provides font loading and text rasterization for the renderer.

use fontdue::layout::{CoordinateSystem, Layout, LayoutSettings, TextStyle};
use fontdue::{Font, FontSettings, Metrics};
use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;

/// A text rendering command
#[repr(C)]
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

impl Default for TextCommand {
    fn default() -> Self {
        Self {
            text: String::new(),
            x: 0.0,
            y: 0.0,
            font_size: 16.0,
            color_r: 0.0,
            color_g: 0.0,
            color_b: 0.0,
            color_a: 1.0,
            font_id: 0,
        }
    }
}

/// Text shaping result
#[derive(Debug, Clone)]
pub struct ShapedText {
    pub width: f32,
    pub height: f32,
    pub line_count: u32,
    pub glyphs: Vec<ShapedGlyph>,
}

/// A shaped glyph
#[derive(Debug, Clone)]
pub struct ShapedGlyph {
    pub x: f32,
    pub y: f32,
    pub width: u32,
    pub height: u32,
    pub bitmap: Vec<u8>,
}

/// Font manager for loading and caching fonts
pub struct FontManager {
    fonts: HashMap<u32, Arc<Font>>,
    default_font: Option<Arc<Font>>,
    next_id: u32,
    // Cache glyph metrics to avoid rasterizing when only metrics are needed
    metrics_cache: RefCell<HashMap<u64, Metrics>>,
}

impl Default for FontManager {
    fn default() -> Self {
        Self::new()
    }
}

impl FontManager {
    pub fn new() -> Self {
        let mut manager = Self {
            fonts: HashMap::new(),
            default_font: None,
            next_id: 1,
            metrics_cache: RefCell::new(HashMap::new()),
        };

        // Load default embedded font
        manager.load_default_font();

        manager
    }

    /// Load the default embedded font (a basic monospace font)
    fn load_default_font(&mut self) {
        // Try to find a system font
        let font_paths = get_system_font_paths();

        for path in font_paths {
            if let Ok(data) = std::fs::read(&path) {
                if let Ok(font) = Font::from_bytes(data, FontSettings::default()) {
                    let font = Arc::new(font);
                    self.default_font = Some(font.clone());
                    self.fonts.insert(0, font);
                    return;
                }
            }
        }

        // If no system font found, we'll work without a default font
        log::warn!("No system font found for default font loading");
    }

    /// Load a font from file
    pub fn load_font(&mut self, path: &str) -> Option<u32> {
        match std::fs::read(path) {
            Ok(data) => self.load_font_from_bytes(&data),
            Err(e) => {
                log::warn!("Failed to read font file {}: {}", path, e);
                None
            }
        }
    }

    /// Load a font from bytes
    pub fn load_font_from_bytes(&mut self, data: &[u8]) -> Option<u32> {
        match Font::from_bytes(data.to_vec(), FontSettings::default()) {
            Ok(font) => {
                let id = self.next_id;
                self.next_id += 1;
                let font = Arc::new(font);
                if self.default_font.is_none() {
                    self.default_font = Some(font.clone());
                }
                self.fonts.insert(id, font);
                Some(id)
            }
            Err(e) => {
                log::warn!("Failed to parse font: {}", e);
                None
            }
        }
    }

    /// Get a font by ID (0 = default)
    pub fn get_font(&self, id: u32) -> Option<&Arc<Font>> {
        if id == 0 {
            self.default_font.as_ref()
        } else {
            self.fonts.get(&id)
        }
    }

    /// Internal: compute a cache key for a glyph metrics lookup
    fn metrics_cache_key(ch: char, font_size: f32, font_id: u32) -> u64 {
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        ch.hash(&mut hasher);
        // Quantize font size to avoid floating point hash instability
        let size_key: u32 = (font_size * 100.0).round() as u32;
        size_key.hash(&mut hasher);
        font_id.hash(&mut hasher);
        hasher.finish()
    }

    /// Get glyph metrics using a cache to avoid expensive rasterize() calls
    fn get_glyph_metrics(&self, font: &Font, ch: char, font_size: f32, font_id: u32) -> Metrics {
        let key = Self::metrics_cache_key(ch, font_size, font_id);

        if let Some(m) = self.metrics_cache.borrow().get(&key) {
            return *m;
        }

        // fontdue provides `metrics` that does not produce a bitmap
        let m = font.metrics(ch, font_size);
        self.metrics_cache.borrow_mut().insert(key, m);
        m
    }

    /// Measure text width and height
    pub fn measure_text(&self, text: &str, font_size: f32, font_id: u32) -> (f32, f32) {
        let font = match self.get_font(font_id) {
            Some(f) => f,
            None => return (text.len() as f32 * font_size * 0.6, font_size),
        };

        // Support newlines: measure each line and return max width and total height
        let lines: Vec<&str> = text.split('\n').collect();
        let mut max_width = 0.0f32;
        let mut total_height = 0.0f32;

        let line_height = font_size * 1.2;

        for line in lines {
            let mut line_width = 0.0f32;
            for c in line.chars() {
                let metrics = self.get_glyph_metrics(font, c, font_size, font_id);
                line_width += metrics.advance_width;
            }
            max_width = max_width.max(line_width);
            total_height += line_height;
        }

        (max_width, total_height.max(font_size))
    }

    /// Shape and rasterize text
    pub fn shape_text(&self, text: &str, font_size: f32, font_id: u32) -> ShapedText {
        let font = match self.get_font(font_id) {
            Some(f) => f,
            None => {
                return ShapedText {
                    width: text.len() as f32 * font_size * 0.6,
                    height: font_size,
                    line_count: 1,
                    glyphs: Vec::new(),
                }
            }
        };

        // Use fontdue's layout module to layout the whole string, which
        // allows ligatures and proper glyph positioning instead of
        // rasterizing per-character.
        let mut glyphs = Vec::new();
        let mut max_line_width = 0.0f32;
        let mut total_height = 0.0f32;

        let lines: Vec<&str> = text.split('\n').collect();
        let line_height = font_size * 1.2;

        let mut layout = Layout::new(CoordinateSystem::PositiveYDown);

        for (li, line) in lines.iter().enumerate() {
            // Reset layout for each line
            layout.reset(&LayoutSettings {
                max_width: None,
                ..LayoutSettings::default()
            });

            // Append the whole line at once. font_index 0 refers to our single font.
            layout.append(&[font.as_ref()], &TextStyle::new(line, font_size, 0));

            // Collect glyphs from the layout result
            let mut line_max_x = 0.0f32;
            for glyph in layout.glyphs() {
                // glyph has position and a glyph key referencing the font/glyph index
                let gx = glyph.x;
                let gy = glyph.y;

                // Rasterize by glyph index to preserve ligatures and combined glyph shapes.
                // `glyph.glyph_index` / `glyph.key.glyph_index` depending on fontdue version.
                // Try common field names; fall back to rasterizing by character if needed.
                // glyph.key is a field containing the glyph index for the font
                let (metrics, bitmap) = {
                    let gindex = glyph.key.glyph_index;
                    // rasterize by glyph index (fontdue uses rasterize_indexed)
                    font.rasterize_indexed(gindex, font_size)
                };

                glyphs.push(ShapedGlyph {
                    x: gx,
                    y: (li as f32) * line_height + gy,
                    width: metrics.width as u32,
                    height: metrics.height as u32,
                    bitmap,
                });

                line_max_x = line_max_x.max(gx + metrics.advance_width);
            }

            max_line_width = max_line_width.max(line_max_x);
            total_height += line_height;
        }

        ShapedText {
            width: max_line_width,
            height: total_height.max(font_size),
            line_count: lines.len() as u32,
            glyphs,
        }
    }

    /// Rasterize text to a bitmap buffer
    pub fn rasterize_text(
        &self,
        text: &str,
        font_size: f32,
        font_id: u32,
        color: (u8, u8, u8, u8),
    ) -> (Vec<u8>, u32, u32) {
        let font = match self.get_font(font_id) {
            Some(f) => f,
            None => {
                // Return empty buffer if no font
                return (Vec::new(), 0, 0);
            }
        };

        // Support multi-line text. For each line compute glyph metrics and per-line
        // ascent/descent so lines can be stacked.
        let lines: Vec<&str> = text.split('\n').collect();

        struct GlyphDatum {
            metrics: Metrics,
            bitmap: Vec<u8>,
            x: f32,
        }

        let mut lines_glyphs: Vec<Vec<GlyphDatum>> = Vec::new();
        let mut line_ascent: Vec<f32> = Vec::new();
        let mut line_descent: Vec<f32> = Vec::new();
        let mut max_width = 0.0f32;
        let mut total_height = 0.0f32;
        let line_height = font_size * 1.2;

        // Use fontdue's layout per-line so ligatures and proper positioning are preserved.
        let mut layout = Layout::new(CoordinateSystem::PositiveYDown);

        for line in lines.iter() {
            layout.reset(&LayoutSettings {
                max_width: None,
                ..LayoutSettings::default()
            });

            layout.append(&[font.as_ref()], &TextStyle::new(line, font_size, 0));

            let mut glyphs_line: Vec<GlyphDatum> = Vec::new();
            let mut max_ascent = 0.0f32;
            let mut max_descent = 0.0f32;
            let mut line_width = 0.0f32;

            for glyph in layout.glyphs() {
                // Position for this glyph
                let glyph_x = glyph.x;
                let _glyph_y = glyph.y;

                // Rasterize by glyph index when available to support ligatures
                let (metrics, bitmap) = {
                    let gindex = glyph.key.glyph_index;
                    font.rasterize_indexed(gindex, font_size)
                };

                let ascent = metrics.ymin as f32 + metrics.height as f32;
                let descent = -metrics.ymin as f32;

                max_ascent = max_ascent.max(ascent);
                max_descent = max_descent.max(descent);

                glyphs_line.push(GlyphDatum {
                    metrics,
                    bitmap,
                    x: glyph_x,
                });

                line_width = line_width.max(glyph_x + metrics.advance_width);
            }

            lines_glyphs.push(glyphs_line);
            line_ascent.push(max_ascent);
            line_descent.push(max_descent);

            max_width = max_width.max(line_width);
            let used_height = (max_ascent + max_descent).max(line_height);
            total_height += used_height;
        }

        let width = max_width.ceil() as u32;
        let height = total_height.ceil().max(font_size) as u32;

        if width == 0 || height == 0 {
            return (Vec::new(), 0, 0);
        }

        // Create RGBA buffer
        let mut buffer = vec![0u8; (width * height * 4) as usize];

        // Second pass: render glyphs line by line
        let mut y_cursor = 0.0f32;
        for (li, glyphs_line) in lines_glyphs.into_iter().enumerate() {
            let ascent = line_ascent[li];
            let descent = line_descent[li];
            let used_height = (ascent + descent).max(line_height);
            let baseline = y_cursor + ascent;

            for g in glyphs_line {
                let metrics = g.metrics;
                let bitmap = g.bitmap;

                if bitmap.is_empty() {
                    continue;
                }

                let glyph_x = g.x;
                let glyph_y = baseline - metrics.ymin as f32 - metrics.height as f32;

                for gy in 0..metrics.height {
                    for gx in 0..metrics.width {
                        let src_idx = gy * metrics.width + gx;
                        let alpha = bitmap[src_idx];

                        if alpha == 0 {
                            continue;
                        }

                        let px = (glyph_x + gx as f32) as i32;
                        let py = (glyph_y + gy as f32) as i32;

                        if px >= 0 && py >= 0 && (px as u32) < width && (py as u32) < height {
                            let dst_idx = ((py as u32 * width + px as u32) * 4) as usize;

                            // Alpha blend
                            let a = (alpha as f32 / 255.0) * (color.3 as f32 / 255.0);
                            buffer[dst_idx] =
                                ((color.0 as f32 * a) + (buffer[dst_idx] as f32 * (1.0 - a))) as u8;
                            buffer[dst_idx + 1] = ((color.1 as f32 * a)
                                + (buffer[dst_idx + 1] as f32 * (1.0 - a)))
                                as u8;
                            buffer[dst_idx + 2] = ((color.2 as f32 * a)
                                + (buffer[dst_idx + 2] as f32 * (1.0 - a)))
                                as u8;
                            buffer[dst_idx + 3] =
                                ((a * 255.0) + (buffer[dst_idx + 3] as f32 * (1.0 - a))) as u8;
                        }
                    }
                }
            }

            y_cursor += used_height;
        }

        (buffer, width, height)
    }
}

/// Get system font paths based on OS
fn get_system_font_paths() -> Vec<String> {
    let mut paths = Vec::new();

    #[cfg(target_os = "linux")]
    {
        paths.push("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf".to_string());
        paths.push("/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf".to_string());
        paths.push("/usr/share/fonts/TTF/DejaVuSans.ttf".to_string());
        paths.push("/usr/share/fonts/noto/NotoSans-Regular.ttf".to_string());
        paths.push("/usr/share/fonts/google-noto/NotoSans-Regular.ttf".to_string());
        paths.push("/usr/share/fonts/truetype/freefont/FreeSans.ttf".to_string());
    }

    #[cfg(target_os = "macos")]
    {
        paths.push("/System/Library/Fonts/Helvetica.ttc".to_string());
        paths.push("/Library/Fonts/Arial.ttf".to_string());
        paths.push("/System/Library/Fonts/SFNSText.ttf".to_string());
    }

    #[cfg(target_os = "windows")]
    {
        paths.push("C:\\Windows\\Fonts\\arial.ttf".to_string());
        paths.push("C:\\Windows\\Fonts\\segoeui.ttf".to_string());
        paths.push("C:\\Windows\\Fonts\\tahoma.ttf".to_string());
    }

    paths
}

/// Text shaper for paragraph layout
pub struct TextShaper {
    font_manager: FontManager,
    cache: HashMap<u64, ShapedText>,
}

impl Default for TextShaper {
    fn default() -> Self {
        Self::new()
    }
}

impl TextShaper {
    pub fn new() -> Self {
        Self {
            font_manager: FontManager::new(),
            cache: HashMap::new(),
        }
    }

    /// Get font manager
    pub fn font_manager(&self) -> &FontManager {
        &self.font_manager
    }

    /// Get mutable font manager
    pub fn font_manager_mut(&mut self) -> &mut FontManager {
        &mut self.font_manager
    }

    /// Shape a paragraph with word wrapping
    pub fn shape_paragraph(&mut self, text: &str, max_width: f32, font_size: f32) -> ShapedText {
        // Simple hash for caching
        let hash = text_hash(text, max_width, font_size);

        if let Some(cached) = self.cache.get(&hash) {
            return cached.clone();
        }

        // Simple word wrapping
        let mut lines: Vec<&str> = Vec::new();
        let mut current_line_start = 0;
        let mut current_width = 0.0f32;
        let mut last_space = 0;

        for (i, c) in text.char_indices() {
            let char_width = self
                .font_manager
                .measure_text(&c.to_string(), font_size, 0)
                .0;

            if c == ' ' {
                last_space = i;
            }

            current_width += char_width;

            if current_width > max_width && last_space > current_line_start {
                lines.push(&text[current_line_start..last_space]);
                current_line_start = last_space + 1;
                current_width = 0.0;
            }
        }

        if current_line_start < text.len() {
            lines.push(&text[current_line_start..]);
        }

        let line_height = font_size * 1.2;
        let mut total_height = 0.0f32;
        let mut max_line_width = 0.0f32;

        for line in &lines {
            let (w, _) = self.font_manager.measure_text(line, font_size, 0);
            max_line_width = max_line_width.max(w);
            total_height += line_height;
        }

        let result = ShapedText {
            width: max_line_width.min(max_width),
            height: total_height,
            line_count: lines.len() as u32,
            glyphs: Vec::new(), // Glyphs would be filled for actual rendering
        };

        self.cache.insert(hash, result.clone());
        result
    }

    /// Clear the cache
    pub fn clear_cache(&mut self) {
        self.cache.clear();
    }
}

fn text_hash(text: &str, max_width: f32, font_size: f32) -> u64 {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};

    let mut hasher = DefaultHasher::new();
    text.hash(&mut hasher);
    max_width.to_bits().hash(&mut hasher);
    font_size.to_bits().hash(&mut hasher);
    hasher.finish()
}
