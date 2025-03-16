struct UBO{
	float4x4 model;
	float4x4 view;
	float4x4 proj;
	float time;
};

layout(set = 0, binding = 0) uniform Texture2D []textures;
layout(set = 0, binding = 1) uniform SamplerState []samplers;

struct v_in{
	[vk_location(0)] float3 pos;
	[vk_location(1)] float3 normal;
	[vk_location(2)] float2 uv;
};


struct v_out {
	float4 pos : SV_Position;
	float2 uv;
	
};

static const float pi = 3.1415926535;

[shader("vertex")]
v_out vertexMain(v_in input, uniform UBO* ubo){
	
	v_out output;


	output.pos =  mul(mul(mul(ubo.proj, ubo.view), ubo.model), float4(input.pos, 1.0));

	//output.pos = {input.pos, 1.0};

	output.uv = input.uv;

    return output;
}



[shader("fragment")]
float4 fragmentMain(in v_out input, uniform UBO* ubo) : SV_Target {
	float2 uv = input.uv;
	float4 pos = input.pos;

	float r = sin(ubo.time)/2 + 0.5;
	float g = cos(ubo.time)/2 + 0.5;
	float b = cos(ubo.time)/2 + 0.5;
	
	float4 col = textures[1].Sample(samplers[0], uv);

	return float4(col.r * r, col.g * g, col.b * b, col.a * 1);
	


    
    
}
