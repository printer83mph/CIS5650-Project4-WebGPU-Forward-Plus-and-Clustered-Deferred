// CHECKITOUT: code that you add here will be prepended to all shaders

struct Light {
    pos: vec3f,
    color: vec3f
}

struct LightSet {
    numLights: u32,
    lights: array<Light>
}

struct Cluster {
    numLights: u32,
    lightIndices: array<u32, ${maxLightsPerCluster}>
}

// DONE-2: a ClusterSet struct similar to LightSet
struct ClusterSet {
    numClusters: vec2u,
    clusters: array<Cluster>
}

struct CameraUniforms {
    // DONE-1.3: add an entry for the view proj mat (of type mat4x4f)
    viewProj: mat4x4f,
    nearPlane: f32,
    farPlane: f32,
    resolution: vec2u,
    viewMat: mat4x4f,
    invProj: mat4x4f
}

// CHECKITOUT: this special attenuation function ensures lights don't affect geometry outside the maximum light radius
fn rangeAttenuation(distance: f32) -> f32 {
    return clamp(1.f - pow(distance / ${lightRadius}, 4.f), 0.f, 1.f) / (distance * distance);
}

fn calculateLightContrib(light: Light, posWorld: vec3f, nor: vec3f) -> vec3f {
    let vecToLight = light.pos - posWorld;
    let distToLight = length(vecToLight);

    let lambert = max(dot(nor, normalize(vecToLight)), 0.f);
    return light.color * lambert * rangeAttenuation(distToLight);
}

// All ye cluster logic below

fn getClusterZCoord(viewPosZ: f32, nearPlane: f32, farPlane: f32) -> u32 {
    // using log
    let clusterDepthLog = log2(farPlane / nearPlane) / ${numClusterSlicesZ}.f;
    // TODO: verify this works
    return u32(log2(-viewPosZ / nearPlane) / clusterDepthLog);
}

fn getClusterIndexFromCoord(clusterCoord: vec3u, numClusters: vec2u) -> u32 {
    // we lay out clusters in the array from major y -> x -> z minor
    return clusterCoord.x +
           clusterCoord.y * numClusters.x +
           clusterCoord.z * numClusters.x * numClusters.y;
    // ^ let's use the above for macthing debug images
    // return clusterCoord.z
    //        + clusterCoord.x * ${numClusterSlicesZ}
    //        + clusterCoord.y * ${numClusterSlicesZ} * numClustersX;

}

// viewPos should be frag pos in view space
fn getClusterIndex(fragPos: vec4f, viewPos: vec3f,
                   numClustersX: u32, numClustersY: u32,
                   nearPlane: f32, farPlane: f32) -> u32
{
    let clusterXYCoord = vec2u(
        floor( fragPos.xy / f32(${clusterSizeXY}) )
    );
    let clusterZCoord = getClusterZCoord(viewPos.z, nearPlane, farPlane);

    return getClusterIndexFromCoord(vec3u(clusterXYCoord, clusterZCoord), vec2u(numClustersX, numClustersY));
}
