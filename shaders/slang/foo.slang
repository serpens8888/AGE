struct UBO{
	float4x4 model;
	float4x4 view;
	float4x4 proj;
	float time;
};


layout(set = 0, binding = 0) ConstantBuffer<UBO> ubo;
layout(set = 1, binding = 1) uniform Sampler2D tex_sampler;



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
static float time = ubo.time;

[shader("vertex")]
v_out vertexMain(v_in input, uint vertexID : SV_VertexID){
	
	v_out output;

	output.pos =  mul(mul(mul(ubo.proj, ubo.view), ubo.model), float4(input.pos, 1.0));

	output.uv = input.uv;

    return output;
}



[shader("fragment")]
float4 fragmentMain(in v_out input) : SV_Target {
	float2 uv = input.uv;
	float4 pos = input.pos;

	float r = abs(sin(time))/2*uv.x;
	float g = abs(cos(time))/2*uv.y;
	float b = abs(tan(time))/2*pos.z;
	


	return float4(tex_sampler.Sample(uv));
	


    
    
}
