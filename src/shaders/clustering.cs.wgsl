@group(${bindGroup_clustering}) @binding(0) var<uniform> cameraUniforms: CameraUniforms;
@group(${bindGroup_clustering}) @binding(1) var<storage, read> lightSet: LightSet;
@group(${bindGroup_clustering}) @binding(2) var<storage, read_write> clusterSet: ClusterSet;


// Assigning lights to clusters
@compute
@workgroup_size(${clusteringWorkgroupSize})
fn main(@builtin(global_invocation_id) globalIdx: vec3u) {
    let clusterIdx = getClusterIndexFromCoord(globalIdx, clusterSet.numClusters);

    // Get cluster bounds and planes
    let bounds = getClusterBounds(
        globalIdx,
        cameraUniforms.nearPlane, cameraUniforms.farPlane, cameraUniforms.resolution, cameraUniforms.invProj
    );
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