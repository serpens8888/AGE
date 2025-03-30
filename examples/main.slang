

#define ALIGN(size,alignment) (size + alignment - 1) & ~(alignment-1)




struct Input{
    int32_t buf[10000];
};

struct Output{
    int32_t buf[10];
};

groupshared int32_t shared_memory[1024];

[shader("compute")]
[numthreads(1024, 1, 1)]
void reduce(uint3 id : SV_DispatchThreadID, uint3 gid : SV_GroupID, uint3 gtid : SV_GroupThreadID, Output* out, Input* in){

    if(id.x < 10000){
        shared_memory[gtid.x] = in.buf[id.x];
    } else{
        shared_memory[gtid.x] = 0;
    }

    GroupMemoryBarrierWithGroupSync();

    for(uint offset = 512; offset > 0; offset >>= 1){
        if(gtid.x < offset){
            shared_memory[gtid.x] += shared_memory[gtid.x+offset];
        }
        GroupMemoryBarrierWithGroupSync();
    }
    
    out.buf[gid.x] = shared_memory[0];
}





















/*
struct Input{
    float[8] buf;
};

struct Output{
    float[8] buf;
};

[shader("compute")]
[numthreads(8, 1, 1)]
void reverseArray(uint3 id : SV_DispatchThreadID, Output* out, Input* in){
    out.buf[id.x] = in.buf[7-id.x];

}
*/
