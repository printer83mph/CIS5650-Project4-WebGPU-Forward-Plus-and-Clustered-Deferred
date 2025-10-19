struct VertexOutput
{
    @location(0) uv: vec2f,
    @builtin(position) fragPos: vec4f
}

// This shader should be very simple as it does not need all of the information passed by the the naive vertex shader.
@vertex
fn main(@builtin(vertex_index) id: u32) -> VertexOutput {
    var out = VertexOutput();

    // from https://wallisc.github.io/rendering/2021/04/18/Fullscreen-Pass.html
    out.uv = vec2f(
        f32((id << 1) & 2),
        f32(id & 2)
    );
    out.fragPos = vec4f(
        out.uv * vec2f(2, -2) + vec2f(-1.0, 1.0),
        0.0, 1.0
    );

    return out;
}