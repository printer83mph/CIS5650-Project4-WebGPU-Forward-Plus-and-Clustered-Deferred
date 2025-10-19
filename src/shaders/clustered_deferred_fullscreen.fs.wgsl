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
    let pos          = textureSample(posBuffer, pixelSampler, in.uv);
    let diffuseColor = textureSample(diffuseBuffer, pixelSampler, in.uv);
    let nor          = textureSample(norBuffer, pixelSampler, in.uv);

    let viewPos = cameraUniforms.viewMat * pos;
    
    let clusterIndex = getClusterIndex(
      in.fragPos,
      viewPos.xyz,
      clusterSet.numClusters.x,
      clusterSet.numClusters.y,
      cameraUniforms.nearPlane,
      cameraUniforms.farPlane
    );
    let cluster = clusterSet.clusters[clusterIndex];

    var totalLightContrib = vec3f(0, 0, 0);
    for (var i = 0u; i < cluster.numLights; i++) {
        let light = lightSet.lights[cluster.lightIndices[i]];
        totalLightContrib += calculateLightContrib(light, pos.xyz, nor.xyz);
    }

    // let finalColor = generateClusterColor(clusterIndex);
    let finalColor = diffuseColor.rgb * totalLightContrib;
    return vec4f(finalColor, 1.0);
}
