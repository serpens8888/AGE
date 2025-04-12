// Vertex Shader: Hardcoded 6 vertices to cover the screen and compute UVs.
struct VSOutput {
    float4 position : SV_Position;
    float2 uv       : TEXCOORD0;
};

[shader("vertex")]
VSOutput vertexMain(uint vertexID : SV_VertexID)
{
    // Two triangles forming a full screen quad
    float2 positions[6] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2( 1.0,  1.0),
        float2(-1.0, -1.0),
        float2( 1.0,  1.0),
        float2(-1.0,  1.0)
    };

    VSOutput output;
    float2 pos = positions[vertexID];
    output.position = float4(pos, 0.0, 1.0);
    // Map from clip-space (-1,1) to UV (0,1)
    output.uv = pos * 0.5 + 0.5;
    return output;
}

// Fragment Shader: Draws UV coordinates as color.
[shader("fragment")]
float4 fragmentMain(VSOutput input) : SV_Target
{
    // UV coordinates are used to color the fragment (R=U, G=V).
    return float4(input.uv, 1.0, 1.0);
}
