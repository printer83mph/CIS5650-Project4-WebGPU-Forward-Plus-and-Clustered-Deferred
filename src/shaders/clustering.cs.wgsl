@group(${bindGroup_clustering}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_clustering}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_clustering}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;


// TODO: prob move a bunch of these to common.wgsl
struct AABB {
    min: vec3f,
    max: vec3f
}

struct Plane {
    normal: vec3f,
    distance: f32
}

// this spits out AABB in clip space
fn getClusterBounds(clusterCoord: vec3u) -> AABB {
    let fragmentPos    = clusterCoord.xy * ${clusterSizeXY};
    let fragmentMaxPos = fragmentPos + ${clusterSizeXY};

    let ndcMin = ((vec2f(fragmentPos)    / vec2f(cameraUniforms.resolution)) * 2.0 - 1.0) * vec2f(1.0, -1.0);
    let ndcMax = ((vec2f(fragmentMaxPos) / vec2f(cameraUniforms.resolution)) * 2.0 - 1.0) * vec2f(1.0, -1.0);

    let actualMinXY = max(min(ndcMin, ndcMax), vec2f(-1.0, -1.0));
    let actualMaxXY = min(max(ndcMin, ndcMax), vec2f( 1.0,  1.0));

    let clusterDepthLog = log2(cameraUniforms.farPlane / cameraUniforms.nearPlane)
                        / f32(${numClusterSlicesZ});

    let farZ = -cameraUniforms.nearPlane * exp2(f32(clusterCoord.z) * clusterDepthLog);
    let nearZ = -cameraUniforms.nearPlane * exp2(f32(clusterCoord.z + 1u) * clusterDepthLog);

    return AABB(
        vec3f(actualMinXY, farZ),
        vec3f(actualMaxXY, nearZ)
    );
}

// for converting AABB coords into view space
fn clipToViewSpace(pos: vec3f, invProj: mat4x4f) -> vec3f {
    let viewPos = invProj * vec4f(pos, 1.0);
    return viewPos.xyz / viewPos.w;
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
    let p_xyz = clipToViewSpace(bounds.min, invProj);
    let p_Xyz = clipToViewSpace(vec3f(bounds.max.x, bounds.min.yz), invProj);
    let p_xYz = clipToViewSpace(vec3f(bounds.min.x, bounds.max.y, bounds.min.z), invProj);
    let p_xyZ = clipToViewSpace(vec3f(bounds.min.xy, bounds.max.z), invProj);
    let p_XYz = clipToViewSpace(vec3f(bounds.max.xy, bounds.min.z), invProj);
    let p_xYZ = clipToViewSpace(vec3f(bounds.min.x, bounds.max.yz), invProj);
    let p_XyZ = clipToViewSpace(vec3f(bounds.max.x, bounds.min.y, bounds.max.z), invProj);
    let p_XYZ = clipToViewSpace(bounds.max, invProj);

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

// Assigning lights to clusters
@compute
@workgroup_size(${clusteringWorkgroupSize})
fn main(@builtin(global_invocation_id) globalIdx: vec3u) {
    let clusterIdx = getClusterIndexFromCoord(globalIdx, clusterSet.numClusters);

    // Get cluster bounds and planes
    let bounds = getClusterBounds(globalIdx);
    let clusterPlanes = getViewSpaceClusterPlanes(bounds, cameraUniforms.invProj);

    // Initialize a counter for the number of lights in this cluster
    var lightCount = 0u;

    for (var lightIdx = 0u; lightIdx < lightSet.numLights; lightIdx++) {
        let light = lightSet.lights[lightIdx];

        // Light pos has gotta be in view space
        let lightPosView = (cameraUniforms.viewMat * vec4f(light.pos, 1.0)).xyz;

        // Check if the light intersects with the cluster’s bounding box (AABB)
        if (checkSphereClusterIntersection(clusterPlanes, lightPosView, ${lightRadius})
            // Stop adding lights if the maximum number of lights is reached.
            && lightCount < ${maxLightsPerCluster})
        {
                // If it does, add the light to the cluster's light list
                clusterSet.clusters[clusterIdx].lightIndices[lightCount] = lightIdx;
                lightCount++;
        }
    }

    // Store the number of lights assigned to this cluster
    clusterSet.clusters[clusterIdx].numLights = lightCount;
}