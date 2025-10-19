// TODO-2: implement the Forward+ fragment shader

// See naive.fs.wgsl for basic fragment shader setup; this shader should use light clusters instead of looping over all lights

// ------------------------------------
// Shading process:
// ------------------------------------
// Determine which cluster contains the current fragment.
// Retrieve the number of lights that affect the current fragment from the cluster’s data.
// Initialize a variable to accumulate the total light contribution for the fragment.
// For each light in the cluster:
//     Access the light's properties using its index.
//     Calculate the contribution of the light based on its position, the fragment’s position, and the surface normal.
//     Add the calculated contribution to the total light accumulation.
// Multiply the fragment’s diffuse color by the accumulated light contribution.
// Return the final color, ensuring that the alpha component is set appropriately (typically to 1).

// camera is bound to 0
@group(${bindGroup_scene}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_scene}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_scene}) @binding(2) var<storage, read> clusterSet: ClusterSet;

@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f,
    @location(0) pos: vec3f,
    @location(1) viewPos: vec3f,
    @location(2) nor: vec3f,
    @location(3) uv: vec2f,
}


@fragment
fn main(in: FragmentInput) -> @location(0) vec4f
{
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    let clusterIndex = getClusterIndex(
      in.fragPos,
      in.viewPos.xyz,
      clusterSet.numClusters.x,
      clusterSet.numClusters.y,
      cameraUniforms.nearPlane,
      cameraUniforms.farPlane
    );

    var totalLightContrib = vec3f(0, 0, 0);
    // let cluster = clusterSet.clusters[1];
    let cluster = clusterSet.clusters[clusterIndex];

    // DEBUG
    let DEBUG_clusterLightCount = f32(cluster.numLights) / f32(${maxLightsPerCluster});
    // return vec4(vec3(DEBUG_clusterLightCount), 1);

    let DEBUG_clustercoords = getClusterCoordFromIndex(clusterIndex, clusterSet.numClusters);
    let DEBUG_bounds = getClusterBounds(
        DEBUG_clustercoords,
        cameraUniforms.nearPlane, cameraUniforms.farPlane, cameraUniforms.resolution, cameraUniforms.invProj
    );
    let DEBUG_bounds_view = vec3f(DEBUG_bounds.min.xy, -DEBUG_bounds.min.z * 0.05);
    let DEBUG_supposedClusterZIndex = getClusterZCoordFromViewPos(in.viewPos.z, cameraUniforms.nearPlane, cameraUniforms.farPlane);
    let DEBUG_ZDepth = f32(DEBUG_supposedClusterZIndex) / f32(${numClusterSlicesZ});


    for (var i = 0u; i < cluster.numLights; i++) {
        let light = lightSet.lights[cluster.lightIndices[i]];
        totalLightContrib += calculateLightContrib(light, in.pos, normalize(in.nor));
    }

    // var finalColor = in.fragPos.xyz;
    // var finalColor = mix(diffuseColor.rgb * totalLightContrib, generateClusterColor(clusterIndex), 0.2);
    // var finalColor = diffuseColor.rgb * 0.25 + vec3f(vec2f(DEBUG_clustercoords.xy) * 0.1, 1.0);
    // var finalColor = diffuseColor.rgb * 0.25 + DEBUG_bounds_view;
    // var finalColor = vec3f(vec2f(in.fragPos.xy) / vec2f(cameraUniforms.resolution), 0.0);
    var finalColor = diffuseColor.rgb * 0.25
                     + diffuseColor.rgb * totalLightContrib * 0.5
                     + generateClusterColor(clusterIndex) * (DEBUG_clusterLightCount * 0.225 + 0.025);
    // var finalColor = vec3(DEBUG_ZDepth);
    return vec4(finalColor, 1);
}

// For debugging purposes, copied from:
// https://github.com/carlos-lopez-garces/Penn-CIS-5650-Project4-WebGPU-Forward-Plus-and-Clustered-Deferred/blob/main/src/shaders/forward_plus.fs.wgsl
fn generateClusterColor(clusterIndex: u32) -> vec3<f32> {
    let hueStep = 5u;
    let hue = f32((clusterIndex * hueStep) % 360u) / 360.0;

    let c = 1.0;
    let x = c * (1.0 - abs(fract(hue * 6.0) * 2.0 - 1.0));
    let m = 0.0;

    var r: f32;
    var g: f32;
    var b: f32;

    if (0.0 <= hue && hue < 1.0 / 6.0) {
        r = c; g = x; b = m;
    } else if (1.0 / 6.0 <= hue && hue < 2.0 / 6.0) {
        r = x; g = c; b = m;
    } else if (2.0 / 6.0 <= hue && hue < 3.0 / 6.0) {
        r = m; g = c; b = x;
    } else if (3.0 / 6.0 <= hue && hue < 4.0 / 6.0) {
        r = m; g = x; b = c;
    } else if (4.0 / 6.0 <= hue && hue < 5.0 / 6.0) {
        r = x; g = m; b = c;
    } else {
        r = c; g = m; b = x;
    }

    return vec3<f32>(r, g, b);
}