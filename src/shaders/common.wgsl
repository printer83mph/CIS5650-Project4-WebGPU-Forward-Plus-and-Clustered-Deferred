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

fn getClusterIndexFromCoord(clusterCoord: vec3u, numClusters: vec2u) -> u32 {
    return clusterCoord.x +
           clusterCoord.y * numClusters.x +
           clusterCoord.z * numClusters.x * numClusters.y;
    // ^ let's use the above for macthing debug images

    // we lay out clusters in the array from major y -> x -> z minor
    // return clusterCoord.z
    //        + clusterCoord.x * ${numClusterSlicesZ}
    //        + clusterCoord.y * ${numClusterSlicesZ} * numClustersX;
}

fn getClusterCoordFromIndex(clusterIndex: u32, numClusters: vec2u) -> vec3u {
    let numClustersXY = numClusters.x * numClusters.y;
        let z = clusterIndex / numClustersXY;
        let xy = clusterIndex % numClustersXY;
        let y = xy / numClusters.x;
        let x = xy % numClusters.x;
        return vec3u(x, y, z);
}

fn getClusterZCoordFromViewPos(viewPosZ: f32, nearPlane: f32, farPlane: f32) -> u32 {
    // uniform
    // let t = clamp((-viewPosZ - nearPlane) / (farPlane - nearPlane), 0.0, 1.0 - 1.0e-5);
    // return u32(floor(t * f32(${numClusterSlicesZ})));
    
    // using log
    let clusterDepthLog = log2(farPlane / nearPlane) / f32(${numClusterSlicesZ});
    return u32(log2(-viewPosZ / nearPlane) / clusterDepthLog);
}

fn getClusterViewPosZFromCoord(clusterCoordZ: u32, nearPlane: f32, farPlane: f32) -> f32 {
    // uniform
    // let t = (clusterCoordZ + 0.5) / f32(${numClusterSlicesZ});
    // return u32(-nearPlane - t * (farPlane - nearPlane));

    // using log
    let clusterDepthLog = log2(farPlane / nearPlane) / f32(${numClusterSlicesZ});
    return -nearPlane * exp2(f32(clusterCoordZ) * clusterDepthLog);
}

fn getClusterXYCoord(fragPos: vec4f) -> vec2u {
    return vec2u(
        floor( fragPos.xy / f32(${clusterSizeXY}) )
    );
}

// viewPos should be frag pos in view space
fn getClusterIndex(fragPos: vec4f, viewPos: vec3f,
                   numClustersX: u32, numClustersY: u32,
                   nearPlane: f32, farPlane: f32) -> u32
{
    let clusterXYCoord = getClusterXYCoord(fragPos);
    let clusterZCoord = getClusterZCoordFromViewPos(viewPos.z, nearPlane, farPlane);

    return getClusterIndexFromCoord(vec3u(clusterXYCoord, clusterZCoord), vec2u(numClustersX, numClustersY));
}

struct AABB {
    min: vec3f,
    max: vec3f
}

// this spits out AABB with XY in NDC and Z in view space (negative)
fn getClusterBounds(clusterCoord: vec3u, nearPlane: f32, farPlane: f32, resolution: vec2u, invProj: mat4x4f) -> AABB
{
    let fragmentPos    = clusterCoord.xy * ${clusterSizeXY};
    let fragmentMaxPos = fragmentPos + vec2u(${clusterSizeXY});

    // get XY bounds in NDC
    let xy1 = ((vec2f(fragmentPos) / vec2f(resolution)) * 2.0 - 1.0) * vec2f(1.0, -1.0);
    let xy2 = ((vec2f(fragmentMaxPos) / vec2f(resolution)) * 2.0 - 1.0) * vec2f(1.0, -1.0);
    let ndcMinXY = min(xy1, xy2);
    let ndcMaxXY = max(xy1, xy2);

    let z1 = getClusterViewPosZFromCoord(clusterCoord.z, nearPlane, farPlane);
    let z2 = getClusterViewPosZFromCoord(clusterCoord.z + 1u, nearPlane, farPlane);

    return AABB(vec3f(ndcMinXY, min(z1, z2)), vec3f(ndcMaxXY, max(z1, z2)));
}

struct Plane {
    normal: vec3f,
    distance: f32
}

// take AABB with XY in NDC and Z in view space (negative), and unproject X and Y to view space
fn unproject(pos: vec3f, invProj: mat4x4f) -> vec3f {
    let ndc = vec4f(pos.xy, 1.0, 1.0);
    let view = invProj * ndc;
    let viewPos = view.xyz / view.w;
    let scale = pos.z / viewPos.z;
    return viewPos * scale;
}

// We expect p1, p2, and p3 to be in a CCW order (right hand rule)
fn getPlaneFromPoints(p1: vec3f, p2: vec3f, p3: vec3f) -> Plane {
    let normal = normalize(cross(p2 - p1, p3 - p1));
    let dist = dot(normal, p1);
    return Plane(normal, dist);
}

// these planes will point outward from the bounding box
fn getViewSpaceClusterPlanes(bounds: AABB, invProj: mat4x4f) -> array<Plane, 6>
{
    let p_xyz = unproject(bounds.min, invProj);
    let p_Xyz = unproject(vec3f(bounds.max.x, bounds.min.yz), invProj);
    let p_xYz = unproject(vec3f(bounds.min.x, bounds.max.y, bounds.min.z), invProj);
    let p_xyZ = unproject(vec3f(bounds.min.xy, bounds.max.z), invProj);
    let p_XYz = unproject(vec3f(bounds.max.xy, bounds.min.z), invProj);
    let p_xYZ = unproject(vec3f(bounds.min.x, bounds.max.yz), invProj);
    let p_XyZ = unproject(vec3f(bounds.max.x, bounds.min.y, bounds.max.z), invProj);
    let p_XYZ = unproject(bounds.max, invProj);

    return array(
        getPlaneFromPoints(p_xyz, p_xyZ, p_xYz), // -X
        getPlaneFromPoints(p_xyz, p_Xyz, p_xyZ), // -Y
        getPlaneFromPoints(p_xyz, p_xYz, p_Xyz), // -Z
        getPlaneFromPoints(p_XYZ, p_XyZ, p_XYz), // +X
        getPlaneFromPoints(p_XYZ, p_XYz, p_xYZ), // +Y
        getPlaneFromPoints(p_XYZ, p_xYZ, p_XyZ)  // +Z
    );
}

// check if a sphere intersects a bunch of outward facing planes
fn checkSphereClusterIntersection(clusterPlanes: array<Plane, 6>,
                                  sphereCenter: vec3f, sphereRadius: f32) -> bool
{
    for (var i = 0u; i < 6; i++) {
        let plane = clusterPlanes[i];
        if (dot(plane.normal, sphereCenter) - plane.distance > sphereRadius) {
            return false;
        }
    }
    return true;
}