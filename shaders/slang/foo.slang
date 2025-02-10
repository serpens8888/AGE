struct UBO{
	float4x4 model;
	float4x4 view;
	float4x4 proj;
};

cbuffer uniform{
	[vk_binding(0)] UBO ubo;
};

struct v_in{
	[vk_location(0)] float3 pos;
	[vk_location(1)] float3 normal;
	[vk_location(2)] float2 uv;
};


struct v_out {
	float4 pos : SV_Position;
	float2 uv;
	
};

[shader("vertex")]
v_out vertexMain(v_in input, uint vertexID : SV_VertexID){
	
	v_out output;

	output.pos =  mul(mul(mul(ubo.proj, ubo.view), ubo.model), float4(input.pos, 1.0));

	output.uv = input.uv;

    return output;
}

static const float pi = 3.1415926535;

[shader("fragment")]
float4 fragmentMain(in v_out input) : SV_Target {
	float2 uv = input.uv;
	float4 pos = input.pos;

	float sin_sample = (sin(uv.x*pi*10) + 1)/2;
	float cos_sample = (cos(uv.x*pi*10) + 1)/2;
	float tan_sample = (tan(uv.y*pi*10) + 1)/2;

    return float4(sin_sample, cos_sample, tan_sample, 1.0);

    
    
}
