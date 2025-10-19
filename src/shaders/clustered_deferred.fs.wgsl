@group(${bindGroup_material}) @binding(0) var diffuseTex: texture_2d<f32>;
@group(${bindGroup_material}) @binding(1) var diffuseTexSampler: sampler;

struct FragmentInput
{
    @builtin(position) fragPos: vec4f,
    @location(0) pos: vec3f,
    @location(1) viewPos: vec3f,
    @location(2) nor: vec3f,
    @location(3) uv: vec2f
}

struct FragmentOutput
{
    @location(0) pos: vec4f,
    @location(1) diffuse: vec4f,
    @location(2) nor: vec4f
}

// This shader should only store G-buffer information and should not do any shading.
@fragment
fn main(in: FragmentInput) -> FragmentOutput {
    let diffuseColor = textureSample(diffuseTex, diffuseTexSampler, in.uv);
    if (diffuseColor.a < 0.5f) {
        discard;
    }

    var out = FragmentOutput();

    out.pos     = vec4f(in.pos, 1.0);
    out.diffuse = vec4f(diffuseColor);
    out.nor     = vec4f(normalize(in.nor), 0.0);

    return out;
}