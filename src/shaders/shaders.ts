// CHECKITOUT: this file loads all the shaders and preprocesses them with some common code

// @ts-expect-error TODO: use this
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import { Camera } from '../stage/camera';

import commonRaw from './common.wgsl?raw';

import naiveVertRaw from './naive.vs.wgsl?raw';
import naiveFragRaw from './naive.fs.wgsl?raw';

import forwardPlusFragRaw from './forward_plus.fs.wgsl?raw';

import clusteredDeferredFragRaw from './clustered_deferred.fs.wgsl?raw';
import clusteredDeferredFullscreenVertRaw from './clustered_deferred_fullscreen.vs.wgsl?raw';
import clusteredDeferredFullscreenFragRaw from './clustered_deferred_fullscreen.fs.wgsl?raw';

import moveLightsComputeRaw from './move_lights.cs.wgsl?raw';
import clusteringComputeRaw from './clustering.cs.wgsl?raw';

// CONSTANTS (for use in shaders)
// =================================

// CHECKITOUT: feel free to add more constants here and to refer to them in your shader code

// Note that these are declared in a somewhat roundabout way because otherwise minification will drop variables
// that are unused in host side code.
export const constants = {
  bindGroup_scene: 0,
  bindGroup_model: 1,
  bindGroup_material: 2,

  moveLightsWorkgroupSize: 128,

  lightRadius: 2,

  // cluster things!
  bindGroup_clustering: 0,

  maxLightsPerCluster: 128,
  clusterSizeXY: 128,
  numClusterSlicesZ: 32,

  clusteringWorkgroupSize: 128,
};

// =================================

function evalShaderRaw(raw: string) {
  return raw.replace(/\$\{(\w+)\}/g, (_, key) => {
    if (!(key in constants)) {
      console.error(`Constant '${key}' not found!`);
      return '';
    }
    return String(constants[key as keyof typeof constants]);
  });
}

const commonSrc: string = evalShaderRaw(commonRaw);

function processShaderRaw(raw: string) {
  return commonSrc + evalShaderRaw(raw);
}

export const naiveVertSrc: string = processShaderRaw(naiveVertRaw);
export const naiveFragSrc: string = processShaderRaw(naiveFragRaw);

export const forwardPlusFragSrc: string = processShaderRaw(forwardPlusFragRaw);

export const clusteredDeferredFragSrc: string = processShaderRaw(
  clusteredDeferredFragRaw,
);
export const clusteredDeferredFullscreenVertSrc: string = processShaderRaw(
  clusteredDeferredFullscreenVertRaw,
);
export const clusteredDeferredFullscreenFragSrc: string = processShaderRaw(
  clusteredDeferredFullscreenFragRaw,
);

export const moveLightsComputeSrc: string =
  processShaderRaw(moveLightsComputeRaw);
export const clusteringComputeSrc: string =
  processShaderRaw(clusteringComputeRaw);
