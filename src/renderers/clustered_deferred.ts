import * as renderer from '../renderer';
import * as shaders from '../shaders/shaders';
import { Stage } from '../stage/stage';

export class ClusteredDeferredRenderer extends renderer.Renderer {
  // TODO-3: add layouts, pipelines, textures, etc. needed for Forward+ here
  // you may need extra uniforms such as the camera view matrix and the canvas resolution

  private readonly sceneUniformsBindGroupLayout: GPUBindGroupLayout;
  private readonly sceneUniformsBindGroup: GPUBindGroup;

  private readonly gBuffersBindGroupLayout: GPUBindGroupLayout;
  private readonly gBuffersBindGroup: GPUBindGroup;

  // might need views for these
  private readonly pixelSampler: GPUSampler;
  private readonly depthTexture: GPUTexture;
  private readonly depthTextureView: GPUTextureView;
  private readonly posTexture: GPUTexture;
  private readonly posTextureView: GPUTextureView;
  private readonly diffuseTexture: GPUTexture;
  private readonly diffuseTextureView: GPUTextureView;
  private readonly norTexture: GPUTexture;
  private readonly norTextureView: GPUTextureView;

  private readonly gBuffersRenderPipeline: GPURenderPipeline;
  private readonly fullscreenRenderPipeline: GPURenderPipeline;

  constructor(stage: Stage) {
    super(stage);

    // ------------------------------------------------------------
    //  Uniforms
    // ------------------------------------------------------------

    this.sceneUniformsBindGroupLayout = renderer.device.createBindGroupLayout({
      label: 'scene uniforms bind group layout',
      entries: [
        {
          // camera uniforms
          binding: 0,
          visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
          buffer: { type: 'uniform' },
        },
        {
          // lightSet
          binding: 1,
          visibility: GPUShaderStage.FRAGMENT,
          buffer: { type: 'read-only-storage' },
        },
        {
          // clusterSet
          binding: 2,
          visibility: GPUShaderStage.FRAGMENT,
          buffer: { type: 'read-only-storage' },
        },
      ],
    });

    this.sceneUniformsBindGroup = renderer.device.createBindGroup({
      label: 'scene uniforms bind group',
      layout: this.sceneUniformsBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.camera.uniformsBuffer },
        },
        {
          binding: 1,
          resource: { buffer: this.lights.lightSetStorageBuffer },
        },
        {
          binding: 2,
          resource: { buffer: this.lights.clusterSetStorageBuffer },
        },
      ],
    });

    // ------------------------------------------------------------
    //  G-Buffers
    // ------------------------------------------------------------

    this.pixelSampler = renderer.device.createSampler({
      label: 'deferred pixel sampler',
      minFilter: 'nearest',
      magFilter: 'nearest',
      mipmapFilter: 'nearest',
      maxAnisotropy: 1,
      addressModeU: 'clamp-to-edge',
      addressModeV: 'clamp-to-edge',
    });

    const devicePixelRatio = window.devicePixelRatio;
    this.depthTexture = renderer.device.createTexture({
      size: [
        renderer.canvas.width * devicePixelRatio,
        renderer.canvas.height * devicePixelRatio,
      ],
      format: 'depth24plus',
      usage: GPUTextureUsage.RENDER_ATTACHMENT,
    });
    this.depthTextureView = this.depthTexture.createView();

    this.posTexture = renderer.device.createTexture({
      size: [
        renderer.canvas.width * devicePixelRatio,
        renderer.canvas.height * devicePixelRatio,
      ],
      format: 'rgba32float',
      usage:
        GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.posTextureView = this.posTexture.createView();

    this.diffuseTexture = renderer.device.createTexture({
      size: [
        renderer.canvas.width * devicePixelRatio,
        renderer.canvas.height * devicePixelRatio,
      ],
      format: 'rgba8unorm',
      usage:
        GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.diffuseTextureView = this.diffuseTexture.createView();

    this.norTexture = renderer.device.createTexture({
      size: [
        renderer.canvas.width * devicePixelRatio,
        renderer.canvas.height * devicePixelRatio,
      ],
      format: 'rgba16float',
      usage:
        GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
    });
    this.norTextureView = this.norTexture.createView();

    this.gBuffersBindGroupLayout = renderer.device.createBindGroupLayout({
      label: 'g-buffers bind group layout',
      entries: [
        {
          // pixel sampler
          binding: 0,
          visibility: GPUShaderStage.FRAGMENT,
          sampler: { type: 'non-filtering' },
        },
        {
          // pos buffer
          binding: 1,
          visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
          texture: { sampleType: 'unfilterable-float' },
        },
        {
          // diffuse buffer
          binding: 2,
          visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
          texture: { sampleType: 'unfilterable-float' },
        },
        {
          // nor buffer
          binding: 3,
          visibility: GPUShaderStage.COMPUTE | GPUShaderStage.FRAGMENT,
          texture: { sampleType: 'unfilterable-float' },
        },
      ],
    });

    this.gBuffersBindGroup = renderer.device.createBindGroup({
      label: 'g-buffers bind group',
      layout: this.gBuffersBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: this.pixelSampler,
        },
        {
          binding: 1,
          resource: this.posTextureView,
        },
        {
          binding: 2,
          resource: this.diffuseTextureView,
        },
        {
          binding: 3,
          resource: this.norTextureView,
        },
      ],
    });

    // ------------------------------------------------------------
    //  G-Buffer writing pipeline
    // ------------------------------------------------------------

    this.gBuffersRenderPipeline = renderer.device.createRenderPipeline({
      label: 'g-buffers render pipeline',
      layout: renderer.device.createPipelineLayout({
        label: 'g-buffers render pipeline layout',
        bindGroupLayouts: [
          this.sceneUniformsBindGroupLayout,
          renderer.modelBindGroupLayout,
          renderer.materialBindGroupLayout,
        ],
      }),
      depthStencil: {
        depthWriteEnabled: true,
        depthCompare: 'less',
        format: 'depth24plus',
      },
      vertex: {
        module: renderer.device.createShaderModule({
          label: 'naive vert shader',
          code: shaders.naiveVertSrc,
        }),
        buffers: [renderer.vertexBufferLayout],
      },
      fragment: {
        module: renderer.device.createShaderModule({
          label: 'deferred g-buffers frag shader',
          code: shaders.clusteredDeferredFragSrc,
        }),
        targets: [
          { format: 'rgba32float' },
          { format: 'rgba8unorm' },
          { format: 'rgba16float' },
        ],
      },
    });

    // ------------------------------------------------------------
    //  Deferred fullscreen shading pipeline
    // ------------------------------------------------------------

    this.fullscreenRenderPipeline = renderer.device.createRenderPipeline({
      label: 'deferred fullscreen render pipeline',
      layout: renderer.device.createPipelineLayout({
        label: 'deferred fullscreen render pipeline layout',
        bindGroupLayouts: [
          this.sceneUniformsBindGroupLayout,
          this.gBuffersBindGroupLayout,
        ],
      }),
      vertex: {
        module: renderer.device.createShaderModule({
          label: 'deferred fullscreen vert shader',
          code: shaders.clusteredDeferredFullscreenVertSrc,
        }),
        buffers: [],
      },
      fragment: {
        module: renderer.device.createShaderModule({
          label: 'deferred fullscreen frag shader',
          code: shaders.clusteredDeferredFullscreenFragSrc,
        }),
        targets: [{ format: renderer.canvasFormat }],
      },
    });
  }

  override draw() {
    const encoder = renderer.device.createCommandEncoder();
    const canvasTextureView = renderer.context.getCurrentTexture().createView();

    // run the clustering compute shader
    this.lights.doLightClustering(encoder);

    // run the G-buffer pass, outputting position, albedo, and normals
    const gBufferRenderPass = encoder.beginRenderPass({
      label: 'deferred g-buffer render pass',
      colorAttachments: [
        {
          view: this.posTextureView,
          clearValue: [0, 0, 0, 0],
          loadOp: 'clear',
          storeOp: 'store',
        },
        {
          view: this.diffuseTextureView,
          clearValue: [0, 0, 0, 0],
          loadOp: 'clear',
          storeOp: 'store',
        },
        {
          view: this.norTextureView,
          clearValue: [0, 0, 0, 0],
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
      depthStencilAttachment: {
        view: this.depthTextureView,
        depthClearValue: 1.0,
        depthLoadOp: 'clear',
        depthStoreOp: 'store',
      },
    });
    gBufferRenderPass.setPipeline(this.gBuffersRenderPipeline);

    gBufferRenderPass.setBindGroup(
      shaders.constants.bindGroup_scene,
      this.sceneUniformsBindGroup,
    );

    this.scene.iterate(
      (node) => {
        gBufferRenderPass.setBindGroup(
          shaders.constants.bindGroup_model,
          node.modelBindGroup,
        );
      },
      (material) => {
        gBufferRenderPass.setBindGroup(
          shaders.constants.bindGroup_material,
          material.materialBindGroup,
        );
      },
      (primitive) => {
        gBufferRenderPass.setVertexBuffer(0, primitive.vertexBuffer);
        gBufferRenderPass.setIndexBuffer(primitive.indexBuffer, 'uint32');
        gBufferRenderPass.drawIndexed(primitive.numIndices);
      },
    );

    gBufferRenderPass.end();

    // run the fullscreen pass, which reads from the G-buffer and performs lighting calculations
    const fullscreenRenderPass = encoder.beginRenderPass({
      label: 'deferred fullscreen render pass',
      colorAttachments: [
        {
          view: canvasTextureView,
          clearValue: [0, 0, 0, 0],
          loadOp: 'clear',
          storeOp: 'store',
        },
      ],
    });
    fullscreenRenderPass.setPipeline(this.fullscreenRenderPipeline);

    fullscreenRenderPass.setBindGroup(
      shaders.constants.bindGroup_scene,
      this.sceneUniformsBindGroup,
    );
    fullscreenRenderPass.setBindGroup(
      shaders.constants.bindGroup_gBuffers,
      this.gBuffersBindGroup,
    );

    // draw a single triangle :))))
    fullscreenRenderPass.draw(3);

    fullscreenRenderPass.end();

    renderer.device.queue.submit([encoder.finish()]);
  }
}
