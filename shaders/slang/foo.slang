struct v_in{
	[vk_location(0)] float2 position;
	[vk_location(1)] float2 uv;
};


struct v_out {
	float4 position : SV_Position;
	float2 uv;
	
};

[shader("vertex")]
v_out vertexMain(v_in input, uint vertexID : SV_VertexID){
	
	v_out output;

	output.position = float4(input.position, 0.0, 1.0);
	output.uv = input.uv;


    return output;


}

[shader("fragment")]
float4 fragmentMain(in v_out input) : SV_Target {
	float2 uv = input.uv;


    return float4( uv.x, uv.y, 0.0, 1.0);
    
    
}
