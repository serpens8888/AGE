

struct v_in{
	[vk_location(0)] float3 pos;
	[vk_location(1)] float3 normal;
    [vk_location(2)] float3 color;
	[vk_location(3)] float2 uv;
};

static float2 positions[3] = float2[](
    float2(0.0, -0.5),
    float2(0.5, 0.5),
    float2(-0.5, 0.5),
);

static float3 colors[3] = float3[](
    float3(1.0, 0.0, 0.0),
    float3(0.0, 1.0, 0.0),
    float3(0.0, 0.0, 1.0),
);

struct v_out{
    float4 position : SV_Position;
    float3 color : COLOR0;
    float2 uv;
};

[shader("vertex")]
v_out vertexMain(v_in input, uint id : SV_VertexID){
    v_out out;
    out.position = float4(input.pos, 1.0);
    out.color = input.color;
    out.uv = input.uv;
    return out;
}


// fragment shader entry point
[shader("fragment")]
float4 fragmentMain(v_out input, float4* color) : SV_Target{
    return *color + float4(input.uv, 1.0, 1.0);
}
