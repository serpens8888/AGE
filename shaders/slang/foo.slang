struct v_in{
	[vk_location(0)] float2 position;
	[vk_location(1)] float2 uv;
};


struct v_out {
	float4 pos : SV_Position;
	float2 uv;
	
};

[shader("vertex")]
v_out vertexMain(v_in input, uint vertexID : SV_VertexID){
	
	v_out output;

	output.pos = float4(input.position, 0.0, 1.0);
	output.uv = input.uv;


    return output;


}
static const float pi = 3.1415926535;

[shader("fragment")]
float4 fragmentMain(in v_out input) : SV_Target {
	float2 uv = input.uv;
	float4 pos = input.pos;
	float4 final = {0.0,0.0,0.0,1.0};

	float sin_sample = (sin(uv.x*pi*10) + 1)/2;

	if(uv.y > sin_sample){
		final = {1.0,1.0,1.0,1.0};
	}


    return final;
    
    
}
