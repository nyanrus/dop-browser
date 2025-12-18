//! GPU rendering module using wgpu
//!
//! Provides hardware-accelerated 2D rendering for the browser.

use std::sync::Arc;
use wgpu::util::DeviceExt;
use winit::window::Window;

/// A vertex for 2D rendering
#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Vertex {
    pub position: [f32; 2],
    pub tex_coords: [f32; 2],
    pub color: [f32; 4],
}

impl Vertex {
    const ATTRIBS: [wgpu::VertexAttribute; 3] =
        wgpu::vertex_attr_array![0 => Float32x2, 1 => Float32x2, 2 => Float32x4];

    pub fn desc() -> wgpu::VertexBufferLayout<'static> {
        wgpu::VertexBufferLayout {
            array_stride: std::mem::size_of::<Vertex>() as wgpu::BufferAddress,
            step_mode: wgpu::VertexStepMode::Vertex,
            attributes: &Self::ATTRIBS,
        }
    }
}

/// A render command for drawing a rectangle
#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct RenderCommand {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
    pub color_r: f32,
    pub color_g: f32,
    pub color_b: f32,
    pub color_a: f32,
    pub texture_id: u32,
    pub z_index: i32,
}

impl Default for RenderCommand {
    fn default() -> Self {
        Self {
            x: 0.0,
            y: 0.0,
            width: 0.0,
            height: 0.0,
            color_r: 1.0,
            color_g: 1.0,
            color_b: 1.0,
            color_a: 1.0,
            texture_id: 0,
            z_index: 0,
        }
    }
}

/// GPU uniform buffer for view projection
#[repr(C)]
#[derive(Debug, Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Uniforms {
    view_proj: [[f32; 4]; 4],
}

impl Uniforms {
    fn new(width: f32, height: f32) -> Self {
        // Orthographic projection matrix for 2D rendering
        // Maps from pixel coordinates (0,0)-(width,height) to NDC (-1,-1)-(1,1)
        let view_proj = [
            [2.0 / width, 0.0, 0.0, 0.0],
            [0.0, -2.0 / height, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [-1.0, 1.0, 0.0, 1.0],
        ];
        Self { view_proj }
    }
}

/// The main wgpu renderer
#[allow(dead_code)]
pub struct WgpuRenderer {
    surface: wgpu::Surface<'static>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: (u32, u32),
    render_pipeline: wgpu::RenderPipeline,
    texture_pipeline: wgpu::RenderPipeline,
    texture_bind_group_layout: wgpu::BindGroupLayout,
    sampler: wgpu::Sampler,
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    uniform_buffer: wgpu::Buffer,
    uniform_bind_group: wgpu::BindGroup,
    vertices: Vec<Vertex>,
    indices: Vec<u32>,
    commands: Vec<RenderCommand>,
    clear_color: wgpu::Color,
    max_vertices: usize,
    max_indices: usize,
}

impl WgpuRenderer {
    /// Create a new renderer for the given window
    /// Returns Err(String) when initialization fails (no adapter, device, or surface caps)
    pub async fn new(window: Arc<Window>) -> Result<Self, String> {
        let size = window.inner_size();
        let width = size.width.max(1);
        let height = size.height.max(1);

        // Create wgpu instance
        let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
            backends: wgpu::Backends::all(),
            ..Default::default()
        });

        // Create surface
        let surface = instance
            .create_surface(window)
            .map_err(|e| format!("Failed to create surface: {:?}", e))?;

        // Request adapter
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            })
            .await
            .ok_or_else(|| "Failed to find a suitable GPU adapter".to_string())?;

        // Request device and queue
        let (device, queue) = adapter
            .request_device(
                &wgpu::DeviceDescriptor {
                    required_features: wgpu::Features::empty(),
                    required_limits: wgpu::Limits::default(),
                    label: None,
                    memory_hints: Default::default(),
                },
                None,
            )
            .await
            .map_err(|e| format!("Failed to create device: {:?}", e))?;

        // Configure surface
        let surface_caps = surface.get_capabilities(&adapter);
        if surface_caps.formats.is_empty() {
            return Err("Surface has no supported formats".to_string());
        }
        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width,
            height,
            present_mode: wgpu::PresentMode::AutoVsync,
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &config);

        // Create shader module
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shader.wgsl").into()),
        });

        // Create uniform buffer
        let uniforms = Uniforms::new(width as f32, height as f32);
        let uniform_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("Uniform Buffer"),
            contents: bytemuck::cast_slice(&[uniforms]),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        // Create bind group layout
        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::VERTEX,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
            label: Some("uniform_bind_group_layout"),
        });

        // Create bind group
        let uniform_bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            layout: &bind_group_layout,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform_buffer.as_entire_binding(),
            }],
            label: Some("uniform_bind_group"),
        });

        // Create render pipeline layout
        let render_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Render Pipeline Layout"),
                bind_group_layouts: &[&bind_group_layout],
                push_constant_ranges: &[],
            });

        // Create texture bind group layout and sampler for presenting CPU bitmaps
        let texture_bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("texture_bind_group_layout"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        view_dimension: wgpu::TextureViewDimension::D2,
                        sample_type: wgpu::TextureSampleType::Float { filterable: true },
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        });

        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some("present_sampler"),
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            address_mode_w: wgpu::AddressMode::ClampToEdge,
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::FilterMode::Nearest,
            ..Default::default()
        });

        // Create render pipeline (vertex color)
        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Render Pipeline"),
            layout: Some(&render_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[Vertex::desc()],
                compilation_options: wgpu::PipelineCompilationOptions::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_color"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: wgpu::PipelineCompilationOptions::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: None,
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview: None,
            cache: None,
        });

        // Create vertex and index buffers
        let max_vertices = 65536;
        let max_indices = 98304;

        let vertex_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Vertex Buffer"),
            size: (max_vertices * std::mem::size_of::<Vertex>()) as wgpu::BufferAddress,
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let index_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Index Buffer"),
            size: (max_indices * std::mem::size_of::<u32>()) as wgpu::BufferAddress,
            usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        // Create a pipeline that samples a single texture and draws a fullscreen quad
        let texture_pipeline = {
            let pipeline_layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Texture Pipeline Layout"),
                bind_group_layouts: &[&bind_group_layout, &texture_bind_group_layout],
                push_constant_ranges: &[],
            });

            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("Texture Pipeline"),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_main"),
                    buffers: &[Vertex::desc()],
                    compilation_options: wgpu::PipelineCompilationOptions::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_texture"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: config.format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: wgpu::PipelineCompilationOptions::default(),
                }),
                primitive: wgpu::PrimitiveState {
                    topology: wgpu::PrimitiveTopology::TriangleList,
                    strip_index_format: None,
                    front_face: wgpu::FrontFace::Ccw,
                    cull_mode: None,
                    polygon_mode: wgpu::PolygonMode::Fill,
                    unclipped_depth: false,
                    conservative: false,
                },
                depth_stencil: None,
                multisample: wgpu::MultisampleState {
                    count: 1,
                    mask: !0,
                    alpha_to_coverage_enabled: false,
                },
                multiview: None,
                cache: None,
            })
        };

        Ok(Self {
            surface,
            device,
            queue,
            config,
            size: (width, height),
            render_pipeline,
            texture_pipeline,
            texture_bind_group_layout,
            sampler,
            vertex_buffer,
            index_buffer,
            uniform_buffer,
            uniform_bind_group,
            vertices: Vec::with_capacity(max_vertices),
            indices: Vec::with_capacity(max_indices),
            commands: Vec::new(),
            clear_color: wgpu::Color::WHITE,
            max_vertices,
            max_indices,
        })
    }

    /// Present an RGBA8888 CPU buffer to the surface by uploading it as a texture
    pub fn present_rgba(&mut self, data: &[u8], src_w: u32, src_h: u32) -> Result<(), wgpu::SurfaceError> {
        // Basic sanity checks and debug logging to help track intermittent crashes
        log::debug!(
            "present_rgba: requested present {}x{} (renderer size {}x{}), data_len={}",
            src_w,
            src_h,
            self.size.0,
            self.size.1,
            data.len()
        );

        // Validate input buffer length
        let expected = (src_w as usize).saturating_mul(src_h as usize).saturating_mul(4);
        if data.len() < expected || src_w == 0 || src_h == 0 {
            log::warn!(
                "present_rgba: invalid buffer size: data_len={} expected={} src_w={} src_h={}",
                data.len(),
                expected,
                src_w,
                src_h
            );
            // Avoid crashing the GPU path on invalid inputs
            return Ok(());
        }

        // Create texture from data
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Present Texture"),
            size: wgpu::Extent3d {
                width: src_w,
                height: src_h,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8UnormSrgb,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        // Write data into the texture. Some backends (Vulkan) require the bytes
        // per row (pitch) used for buffer->texture copies to be aligned to
        // wgpu::COPY_BYTES_PER_ROW_ALIGNMENT (256). To be robust we pad each
        // row to that alignment when needed.
        let bytes_per_row_unpadded = 4u32.checked_mul(src_w).unwrap_or(0);
        let align = wgpu::COPY_BYTES_PER_ROW_ALIGNMENT as u32;
        let padded_bytes_per_row = if bytes_per_row_unpadded % align == 0 {
            bytes_per_row_unpadded
        } else {
            ((bytes_per_row_unpadded + align - 1) / align) * align
        };
        // Log chosen upload path
        log::debug!(
            "present_rgba: bytes_per_row_unpadded={} padded_bytes_per_row={}",
            bytes_per_row_unpadded,
            padded_bytes_per_row
        );

        if padded_bytes_per_row == bytes_per_row_unpadded {
            // Fast path: no padding required
            log::debug!("present_rgba: using fast path upload");
            self.queue.write_texture(
                wgpu::ImageCopyTexture {
                    texture: &texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                data,
                wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row_unpadded),
                    rows_per_image: Some(src_h),
                },
                wgpu::Extent3d {
                    width: src_w,
                    height: src_h,
                    depth_or_array_layers: 1,
                },
            );
        } else {
            // Create a padded staging buffer and copy rows into it
            log::debug!("present_rgba: creating padded staging buffer (rows={} padded_row_bytes={})", src_h, padded_bytes_per_row);
            let mut padded: Vec<u8> = vec![0u8; (padded_bytes_per_row * src_h) as usize];
            for row in 0..src_h as usize {
                let src_offset = row * (bytes_per_row_unpadded as usize);
                let dst_offset = row * (padded_bytes_per_row as usize);
                padded[dst_offset..dst_offset + (bytes_per_row_unpadded as usize)]
                    .copy_from_slice(&data[src_offset..src_offset + (bytes_per_row_unpadded as usize)]);
            }

            self.queue.write_texture(
                wgpu::ImageCopyTexture {
                    texture: &texture,
                    mip_level: 0,
                    origin: wgpu::Origin3d::ZERO,
                    aspect: wgpu::TextureAspect::All,
                },
                &padded,
                wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(padded_bytes_per_row),
                    rows_per_image: Some(src_h),
                },
                wgpu::Extent3d {
                    width: src_w,
                    height: src_h,
                    depth_or_array_layers: 1,
                },
            );
        }

        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());

        // Create bind group for this texture
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            layout: &self.texture_bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&self.sampler),
                },
            ],
            label: Some("present_bind_group"),
        });

        // Build a fullscreen quad
        let w = self.size.0 as f32;
        let h = self.size.1 as f32;
        let vertices = vec![
            Vertex { position: [0.0, 0.0], tex_coords: [0.0, 0.0], color: [1.0, 1.0, 1.0, 1.0] },
            Vertex { position: [w, 0.0], tex_coords: [1.0, 0.0], color: [1.0, 1.0, 1.0, 1.0] },
            Vertex { position: [w, h], tex_coords: [1.0, 1.0], color: [1.0, 1.0, 1.0, 1.0] },
            Vertex { position: [0.0, h], tex_coords: [0.0, 1.0], color: [1.0, 1.0, 1.0, 1.0] },
        ];
        let indices: Vec<u32> = vec![0, 1, 2, 0, 2, 3];

        // Upload vertex/index data
        self.queue.write_buffer(&self.vertex_buffer, 0, bytemuck::cast_slice(&vertices));
        self.queue.write_buffer(&self.index_buffer, 0, bytemuck::cast_slice(&indices));

        // Acquire surface texture
        log::debug!("present_rgba: acquiring current surface texture");
        let output = match self.surface.get_current_texture() {
            Ok(o) => o,
            Err(e) => {
                log::warn!("present_rgba: get_current_texture failed: {:?}", e);
                return Err(e);
            }
        };
        let view_out = output.texture.create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder = self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some("Present Encoder") });

        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Present Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view_out,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(self.clear_color),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });

            render_pass.set_pipeline(&self.texture_pipeline);
            render_pass.set_bind_group(0, &self.uniform_bind_group, &[]);
            render_pass.set_bind_group(1, &bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
            render_pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint32);
            render_pass.draw_indexed(0..6, 0, 0..1);
        }

        self.queue.submit(std::iter::once(encoder.finish()));
        log::debug!("present_rgba: submitted commands, calling present()");
        output.present();
        log::debug!("present_rgba: present() completed");

        Ok(())
    }

    /// Resize the renderer
    pub fn resize(&mut self, width: u32, height: u32) {
        if width > 0 && height > 0 {
            self.size = (width, height);
            self.config.width = width;
            self.config.height = height;
            self.surface.configure(&self.device, &self.config);

            // Update uniforms
            let uniforms = Uniforms::new(width as f32, height as f32);
            self.queue
                .write_buffer(&self.uniform_buffer, 0, bytemuck::cast_slice(&[uniforms]));
        }
    }

    /// Set the clear color
    pub fn set_clear_color(&mut self, r: f32, g: f32, b: f32, a: f32) {
        self.clear_color = wgpu::Color {
            r: r as f64,
            g: g as f64,
            b: b as f64,
            a: a as f64,
        };
    }

    /// Clear all render commands
    pub fn clear(&mut self) {
        self.commands.clear();
        self.vertices.clear();
        self.indices.clear();
    }

    /// Add a rectangle render command
    pub fn add_rect(&mut self, cmd: RenderCommand) {
        self.commands.push(cmd);
    }

    /// Build vertex and index buffers from commands
    fn build_buffers(&mut self) {
        self.vertices.clear();
        self.indices.clear();

        // Sort commands by z-index
        self.commands.sort_by_key(|c| c.z_index);

        for cmd in &self.commands {
            let base_index = self.vertices.len() as u32;

            let x = cmd.x;
            let y = cmd.y;
            let w = cmd.width;
            let h = cmd.height;
            let color = [cmd.color_r, cmd.color_g, cmd.color_b, cmd.color_a];

            // Add 4 vertices for the quad
            self.vertices.push(Vertex {
                position: [x, y],
                tex_coords: [0.0, 0.0],
                color,
            });
            self.vertices.push(Vertex {
                position: [x + w, y],
                tex_coords: [1.0, 0.0],
                color,
            });
            self.vertices.push(Vertex {
                position: [x + w, y + h],
                tex_coords: [1.0, 1.0],
                color,
            });
            self.vertices.push(Vertex {
                position: [x, y + h],
                tex_coords: [0.0, 1.0],
                color,
            });

            // Add 6 indices for 2 triangles
            self.indices.push(base_index);
            self.indices.push(base_index + 1);
            self.indices.push(base_index + 2);
            self.indices.push(base_index);
            self.indices.push(base_index + 2);
            self.indices.push(base_index + 3);
        }
    }

    /// Render the current frame
    pub fn render(&mut self) -> Result<(), wgpu::SurfaceError> {
        // Build buffers from commands
        self.build_buffers();

        // Get surface texture
        let output = self.surface.get_current_texture()?;
        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        // Upload vertex data
        if !self.vertices.is_empty() {
            self.queue
                .write_buffer(&self.vertex_buffer, 0, bytemuck::cast_slice(&self.vertices));
        }

        // Upload index data
        if !self.indices.is_empty() {
            self.queue
                .write_buffer(&self.index_buffer, 0, bytemuck::cast_slice(&self.indices));
        }

        // Create command encoder
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });

        // Begin render pass
        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(self.clear_color),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });

            if !self.indices.is_empty() {
                render_pass.set_pipeline(&self.render_pipeline);
                render_pass.set_bind_group(0, &self.uniform_bind_group, &[]);
                render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..));
                render_pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint32);
                render_pass.draw_indexed(0..self.indices.len() as u32, 0, 0..1);
            }
        }

        // Submit commands
        self.queue.submit(std::iter::once(encoder.finish()));
        output.present();

        Ok(())
    }

    /// Get the current size
    pub fn size(&self) -> (u32, u32) {
        self.size
    }

    /// Read framebuffer pixels (for PNG export)
    pub fn read_pixels(&self) -> Vec<u8> {
        let (width, height) = self.size;
        let size = (width * height * 4) as usize;
        let mut pixels = vec![0u8; size];

        // Create a texture to copy into
        let texture = self.device.create_texture(&wgpu::TextureDescriptor {
            label: Some("Copy Texture"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: self.config.format,
            usage: wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });

        // Create a buffer to copy texture data into
        let bytes_per_row = (width * 4 + 255) & !255; // Align to 256 bytes
        let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("Pixel Buffer"),
            size: (bytes_per_row * height) as wgpu::BufferAddress,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        // Submit copy command
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Copy Encoder"),
            });

        encoder.copy_texture_to_buffer(
            wgpu::ImageCopyTexture {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            wgpu::ImageCopyBuffer {
                buffer: &buffer,
                layout: wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(bytes_per_row),
                    rows_per_image: Some(height),
                },
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );

        self.queue.submit(std::iter::once(encoder.finish()));

        // Map buffer and copy data
        let buffer_slice = buffer.slice(..);
        let (tx, rx) = std::sync::mpsc::channel();
        buffer_slice.map_async(wgpu::MapMode::Read, move |result| {
            tx.send(result).unwrap();
        });
        self.device.poll(wgpu::Maintain::Wait);

        if rx.recv().unwrap().is_ok() {
            let data = buffer_slice.get_mapped_range();
            for y in 0..height {
                let src_start = (y * bytes_per_row) as usize;
                let dst_start = (y * width * 4) as usize;
                pixels[dst_start..dst_start + (width * 4) as usize]
                    .copy_from_slice(&data[src_start..src_start + (width * 4) as usize]);
            }
        }

        pixels
    }
}
