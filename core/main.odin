package core

import vulk "vulkan"
import aud "audio"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "core:fmt" 
import "core:math" 
import "core:math/rand" 
 
//this function has a period of 2, which makes it much nicer for looping
main :: proc(){

    fmt.println("a")
    vulk.compile_slang("core/main.slang", "core/main.spv")


    vulk.load_vulkan()

    ctx: vulk.Context
    assert(vulk.init_context(&ctx, {}) == nil)
    defer vulk.destroy_context(&ctx)

    assert(sdl.Init({.VIDEO, .AUDIO}))
    defer sdl.Quit()

    mod, gfx_err := vulk.create_graphics_module(&ctx, "foo", 1024, 1024, {})
    defer vulk.destroy_graphics_module(&ctx, &mod)

    general_pool: vk.CommandPool

    pool_info: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = ctx.general_queue.family,
        flags = {.RESET_COMMAND_BUFFER},
    }

    vk.CreateCommandPool(ctx.device, &pool_info, nil, &general_pool)
    defer vk.DestroyCommandPool(ctx.device, general_pool, nil)

    cmd: vk.CommandBuffer
    alloc_info := vulk.make_command_buffer_allocate_info(general_pool, 1)
    vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd)
    defer vk.FreeCommandBuffers(ctx.device, general_pool, 1, &cmd)

    sem, sem_err := vulk.create_semaphore(ctx.device)
    defer vk.DestroySemaphore(ctx.device, sem, nil)

    device, stream, aud_err := aud.initialize_audio(2, 48000)
    assert(aud_err == nil)
    osc := aud.saw_oscillator(10, 48000)
    chunk := new([48000*10]f32)
    for i in 0..<48000*5{
        data := ((rand.float32_normal(-0.8, 0.1)) * 0.2) + aud.next(&osc) * 0.1
        chunk[i*2] = data/2
        chunk[i*2+1] = data/2
    }
    sdl.PutAudioStreamData(stream, chunk, 48000*10*4)



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

}
