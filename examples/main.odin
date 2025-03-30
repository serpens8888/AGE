package core

//main just for testing

import "core:fmt"
import "core:mem"
import "core:math/rand"
import "core:reflect"
import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import vulk "../core/vulkan"
import "../core/vulkan/vma"




//main just to test procs
main :: proc(){
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	vulk.load_vulkan()

    ctx: vulk.Context
    assert(vulk.init_context(&ctx, {}) == nil)
    defer vulk.destroy_context(&ctx)

    vulk.compile_slang("main.slang", "main.spv")

    output := vulk.create_storage_buffer(ctx.device, ctx.allocator, size_of(i32)*10)
    defer vulk.free_buffer(ctx.allocator, output)

    input := vulk.create_storage_buffer(ctx.device, ctx.allocator, size_of(i32)*10000)
    defer vulk.free_buffer(ctx.allocator, input)

    input_data: [10000]i32
    for &num, i in input_data{
        num = i32(i)+1
    }

    mem.copy(input.mapped_ptr, &input_data, 10000*size_of(i32))

    range: vk.PushConstantRange = {
        stageFlags = {.COMPUTE},
        offset = 0,
        size = size_of(vk.DeviceAddress)*2,
    }

    push_constants_data := new([size_of(vk.DeviceAddress)*2]u8)
    defer free(push_constants_data)

    mem.copy(push_constants_data, &output.address, 8)
    mem.copy(rawptr(uintptr(push_constants_data)+8), &input.address, 8)

    pl_layout := vulk.create_pipeline_layout(ctx.device, {}, {range})
    defer vk.DestroyPipelineLayout(ctx.device, pl_layout, nil)

    shader := vulk.create_shader_object(
        ctx.device, 
        "main.spv",
        "main",
        {.COMPUTE}, {}, {},
        {range}
    )
    defer vk.DestroyShaderEXT(ctx.device, shader, nil)

    stage: vk.ShaderStageFlags = {.COMPUTE}

    cmd: vk.CommandBuffer
    alloc_info := vulk.make_command_buffer_allocate_info(ctx.general_pool, 1)
    vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd)
    defer vk.FreeCommandBuffers(ctx.device, ctx.general_pool, 1, &cmd)

    begin_info := vulk.make_command_buffer_begin_info({.ONE_TIME_SUBMIT})
    vk.BeginCommandBuffer(cmd, &begin_info)

    vk.CmdPushConstants(cmd, pl_layout, stage, 0, range.size, push_constants_data)
    vk.CmdBindShadersEXT(cmd, 1, &stage, &shader)
    vk.CmdDispatch(cmd, 10, 1, 1)

    vk.EndCommandBuffer(cmd)

    cmd_submit_info := vulk.make_command_buffer_submit_info(cmd)
    submit_info := vulk.make_submit_info({cmd_submit_info}, {},{})

    vk.QueueSubmit2(ctx.general_queue, 1, &submit_info, {})

    vk.DeviceWaitIdle(ctx.device)

    computed_output := transmute(^[10]i32)(output.mapped_ptr)
    computed_sum: i32
    for i in 0..<10{
        computed_sum += computed_output[i]
    }

    fmt.println("compute output:",computed_sum,"!")

}





/*

    assert(sdl.Init({.EVENTS}) == true)

	window := sdl.CreateWindow("window", 1920, 1080, {.VULKAN, .RESIZABLE} )
	if( sdl.SetWindowMinimumSize(window, 1, 1) != true){
		panic("failed to set minimum window size")
	}

  	running := true
	event: sdl.Event
	for running {
		for sdl.PollEvent(&event){
			#partial switch event.type {

				case .QUIT: running = false

                case .KEY_DOWN: { 
                    if(event.key.key == sdl.K_ESCAPE){
                        running = false
                    }
                }

			}

		}
	}
*/

/*
 *struct iteration and value printing


    struct_info := type_info_of(<STRUCT>).variant.(reflect.Type_Info_Named).base.variant.(reflect.Type_Info_Struct)

    for i in 0..<struct_info.field_count{

        field := reflect.struct_field_at(typeid_of(type_of(<STRUCT INSTANCE>)), int(i))
        field_value := reflect.struct_field_value(properties.limits, field)

        fmt.printf("%s: %v\n", struct_info.names[i], field_value)
    }
*/



