
struct v_in{
	[vk_location(0)] float3 pos;
	[vk_location(1)] float3 normal;
	[vk_location(2)] float2 uv;
    [vk_location(3)] uint32_t material;
};

struct v_out{
    float4 position : SV_Position;
    float2 uv;
};


[shader("vertex")]
v_out vertexMain(v_in input, uint id : SV_VertexID){
    v_out out;
    out.position = float4(input.pos, 1.0);
    out.uv = input.uv;
    return out;
}


[shader("fragment")]
float4 fragmentMain(v_out input) : SV_Target{
    return  float4(input.uv, 0.0, 1.0);
}












