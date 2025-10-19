import { vec3 } from 'wgpu-matrix';
import { canvas, device } from '../renderer';

import * as shaders from '../shaders/shaders';
import { Camera } from './camera';

// h in [0, 1]
function hueToRgb(h: number) {
  const f = (n: number, k = (n + h * 6) % 6) =>
    1 - Math.max(Math.min(k, 4 - k, 1), 0);
  return vec3.lerp(vec3.create(1, 1, 1), vec3.create(f(5), f(3), f(1)), 0.8);
}

export class Lights {
  private camera: Camera;

  numLights = 150;
  static readonly maxNumLights = 5000;
  static readonly numFloatsPerLight = 8; // vec3f is aligned at 16 byte boundaries

  static readonly lightIntensity = 0.1;

  static readonly numFloatsPerCluster =
    1 + 3 + shaders.constants.maxLightsPerCluster; // extra space for padding

  lightsArray = new Float32Array(
    Lights.maxNumLights * Lights.numFloatsPerLight,
  );
  lightSetStorageBuffer: GPUBuffer;
  clusterSetStorageBuffer!: GPUBuffer;

  timeUniformBuffer: GPUBuffer;

  moveLightsComputeBindGroupLayout: GPUBindGroupLayout;
  moveLightsComputeBindGroup: GPUBindGroup;
  moveLightsComputePipeline: GPUComputePipeline;

  // these are assigned in `setupClusteringPipeline`
  numClusters!: [number, number];
  clusteringComputeBindGroupLayout!: GPUBindGroupLayout;
  clusteringComputeBindGroup!: GPUBindGroup;
  clusteringComputePipeline!: GPUComputePipeline;

  constructor(camera: Camera) {
    this.camera = camera;

    this.lightSetStorageBuffer = device.createBuffer({
      label: 'lights',
      size: 16 + this.lightsArray.byteLength, // 16 for numLights + padding
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    this.populateLightsBuffer();
    this.updateLightSetUniformNumLights();

    this.timeUniformBuffer = device.createBuffer({
      label: 'time uniform',
      size: 4,
      usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    });

    this.moveLightsComputeBindGroupLayout = device.createBindGroupLayout({
      label: 'move lights compute bind group layout',
      entries: [
        {
          // lightSet
          binding: 0,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'storage' },
        },
        {
          // time
          binding: 1,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'uniform' },
        },
      ],
    });

    this.moveLightsComputeBindGroup = device.createBindGroup({
      label: 'move lights compute bind group',
      layout: this.moveLightsComputeBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.lightSetStorageBuffer },
        },
        {
          binding: 1,
          resource: { buffer: this.timeUniformBuffer },
        },
      ],
    });

    this.moveLightsComputePipeline = device.createComputePipeline({
      label: 'move lights compute pipeline',
      layout: device.createPipelineLayout({
        label: 'move lights compute pipeline layout',
        bindGroupLayouts: [this.moveLightsComputeBindGroupLayout],
      }),
      compute: {
        module: device.createShaderModule({
          label: 'move lights compute shader',
          code: shaders.moveLightsComputeSrc,
        }),
        entryPoint: 'main',
      },
    });

    // initialize layouts, pipelines, textures, etc. needed for light clustering here
    this.setupClusteringPipeline();
  }

  private setupClusteringPipeline() {
    const devicePixelRatio = window.devicePixelRatio;
    const [screenWidth, screenHeight] = [
      canvas.clientWidth * devicePixelRatio,
      canvas.clientHeight * devicePixelRatio,
    ];
    const [clustersX, clustersY, clustersZ] = [
      Math.ceil(screenWidth / shaders.constants.clusterSizeXY),
      Math.ceil(screenHeight / shaders.constants.clusterSizeXY),
      shaders.constants.numClusterSlicesZ,
    ];
    this.numClusters = [clustersX, clustersY];

    this.clusterSetStorageBuffer = device.createBuffer({
      label: 'clusters',
      size: 16 + clustersX * clustersY * clustersZ * Lights.numFloatsPerCluster,
      //    ^ 16 for numClusters + padding, plus (num clusters times floats per cluster)
      usage: GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_DST,
    });
    // populate numClusters
    this.updateClusterSetUniformNumClusters(clustersX, clustersY);

    this.clusteringComputeBindGroupLayout = device.createBindGroupLayout({
      label: 'clustering compute bind group layout',
      entries: [
        {
          binding: 0,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'uniform' },
        },
        {
          // lightSet
          binding: 1,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'read-only-storage' },
        },
        {
          // clusterSet
          binding: 2,
          visibility: GPUShaderStage.COMPUTE,
          buffer: { type: 'storage' },
        },
      ],
    });

    this.clusteringComputeBindGroup = device.createBindGroup({
      label: 'clustering compute bind group layout',
      layout: this.clusteringComputeBindGroupLayout,
      entries: [
        {
          binding: 0,
          resource: { buffer: this.camera.uniformsBuffer },
        },
        {
          binding: 1,
          resource: { buffer: this.lightSetStorageBuffer },
        },
        {
          binding: 2,
          resource: { buffer: this.clusterSetStorageBuffer },
        },
      ],
    });

    this.clusteringComputePipeline = device.createComputePipeline({
      label: 'clustering compute pipeline',
      layout: device.createPipelineLayout({
        label: 'clustering compute pipeline layout',
        bindGroupLayouts: [this.clusteringComputeBindGroupLayout],
      }),
      compute: {
        module: device.createShaderModule({
          label: 'clustering compute shader',
          code: shaders.clusteringComputeSrc,
        }),
        entryPoint: 'main',
      },
    });
  }

  private populateLightsBuffer() {
    for (let lightIdx = 0; lightIdx < Lights.maxNumLights; ++lightIdx) {
      // light pos is set by compute shader so no need to set it here
      const lightColor = vec3.scale(
        hueToRgb(Math.random()),
        Lights.lightIntensity,
      );
      this.lightsArray.set(lightColor, lightIdx * Lights.numFloatsPerLight + 4);
    }

    device.queue.writeBuffer(this.lightSetStorageBuffer, 16, this.lightsArray);
  }

  updateLightSetUniformNumLights() {
    device.queue.writeBuffer(
      this.lightSetStorageBuffer,
      0,
      new Uint32Array([this.numLights]),
    );
  }

  updateClusterSetUniformNumClusters(x: number, y: number) {
    device.queue.writeBuffer(
      this.clusterSetStorageBuffer,
      0,
      new Uint32Array([x, y]),
    );
  }

  doLightClustering(encoder: GPUCommandEncoder) {
    // implementing clustering here allows for reusing the code in both Forward+ and Clustered Deferred
    const computePass = encoder.beginComputePass();
    computePass.setPipeline(this.clusteringComputePipeline);
    computePass.setBindGroup(
      shaders.constants.bindGroup_clustering,
      this.clusteringComputeBindGroup,
    );

    const [clustersX, clustersY] = this.numClusters;
    const clustersZ = shaders.constants.numClusterSlicesZ;

    computePass.dispatchWorkgroups(clustersX, clustersY, clustersZ);
    computePass.end();
  }

  // CHECKITOUT: this is where the light movement compute shader is dispatched from the host
  onFrame(time: number) {
    device.queue.writeBuffer(
      this.timeUniformBuffer,
      0,
      new Float32Array([time]),
    );

    // not using same encoder as render pass so this doesn't interfere with measuring actual rendering performance
    const encoder = device.createCommandEncoder();

    const computePass = encoder.beginComputePass();
    computePass.setPipeline(this.moveLightsComputePipeline);

    computePass.setBindGroup(0, this.moveLightsComputeBindGroup);

    const workgroupCount = Math.ceil(
      this.numLights / shaders.constants.moveLightsWorkgroupSize,
    );
    computePass.dispatchWorkgroups(workgroupCount);

    computePass.end();

    device.queue.submit([encoder.finish()]);
  }
}
