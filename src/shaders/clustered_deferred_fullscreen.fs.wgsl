@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_gBuffers}) @binding(0) var pixelSampler: sampler;
@group(${bindGroup_gBuffers}) @binding(1) var posBuffer: texture_2d<f32>;
@group(${bindGroup_gBuffers}) @binding(2) var diffuseBuffer: texture_2d<f32>;
@group(${bindGroup_gBuffers}) @binding(3) var norBuffer: texture_2d<f32>;

struct FragmentInput
{
    @location(0) uv: vec2f,
    @builtin(position) fragPos: vec4f
}

// Similar to the Forward+ fragment shader, but with vertex information coming from the G-buffer instead.
@fragment
fn main(in: FragmentInput) -> @location(0) vec4f {
    // TODO: read from buffers etc
    let finalColor = vec3f(in.uv, 1.0);
    return vec4f(finalColor, 1.0);
}