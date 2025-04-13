package core

import vulk "vulkan"
import aud "audio"
import sdl "vendor:sdl3"
import vk "vendor:vulkan"
import "core:fmt" 
import "core:math" 
import "core:math/rand" 

verts: []vulk.Vertex = {
    {pos = {-1.0, -1.0, 0.0}, col = {1,0,0}},
    {pos = {1.0, 1.0, 0.0  }, col = {0,1,0}},
    {pos = {-1.0, 1.0, 0.0 }, col = {0,0,1}},
    {pos = {-1.0, -1.0, 0.0}, col = {1,0,0}},
    {pos = { 1.0, -1.0, 0.0}, col = {1,1,0}},
    {pos = { 1.0,  1.0, 0.0}, col = {0,1,0}},
}
 
//this function has a period of 2, which makes it much nicer for looping
main :: proc(){

    vulk.compile_slang("core/main.slang", "core/main.spv")

    vulk.load_vulkan()

    ctx: vulk.Context
    assert(vulk.init_context(&ctx) == nil)
    defer vulk.destroy_context(&ctx)

    assert(sdl.Init({.VIDEO, .AUDIO}))
    defer sdl.Quit()

    pool: vk.CommandPool

    pool_info: vk.CommandPoolCreateInfo = {
        sType = .COMMAND_POOL_CREATE_INFO,
        queueFamilyIndex = ctx.queue.family,
        flags = {.RESET_COMMAND_BUFFER},
    }

    vk.CreateCommandPool(ctx.device, &pool_info, nil, &pool)
    defer vk.DestroyCommandPool(ctx.device, pool, nil)

    vert_buf, vbuf_err := vulk.create_vertex_buffer(ctx.device, ctx.queue.handle, pool, ctx.allocator, verts)
    defer vulk.free_buffer(ctx.allocator, vert_buf)

    mod, gfx_err := vulk.create_graphics_module(&ctx, "foo", 1024, 1024, {})
    defer vulk.destroy_graphics_module(&ctx, &mod)

    layout, layout_err := vulk.create_pipeline_layout(ctx.device, {}, {})
    defer vk.DestroyPipelineLayout(ctx.device, layout, nil)

    shader_mod, shader_err := vulk.create_shader_module(ctx.device, "core/main.spv")
    defer vk.DestroyShaderModule(ctx.device, shader_mod, nil)

    pipeline, pl_err := vulk.create_graphics_pipeline(ctx.device, mod, layout, shader_mod)
    defer vk.DestroyPipeline(ctx.device, pipeline, nil)

    fmt.println(vbuf_err, gfx_err, layout_err, shader_err, pl_err)


    cmd: vk.CommandBuffer
    alloc_info := vulk.make_command_buffer_allocate_info(pool, 1)
    vk.AllocateCommandBuffers(ctx.device, &alloc_info, &cmd)
    defer vk.FreeCommandBuffers(ctx.device, pool, 1, &cmd)

    image_available, _ := vulk.create_semaphore(ctx.device)
    defer vk.DestroySemaphore(ctx.device, image_available, nil)
    
    render_finished, _ := vulk.create_semaphore(ctx.device)
    defer vk.DestroySemaphore(ctx.device, render_finished, nil)
    
    in_flight, _ := vulk.create_fence(ctx.device, {.SIGNALED})
    defer vk.DestroyFence(ctx.device, in_flight, nil)



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



            vk.WaitForFences(ctx.device, 1, &in_flight, true, max(u64))
            vk.ResetFences(ctx.device, 1, &in_flight)
            
            image_index: u32
            vk.AcquireNextImageKHR(ctx.device, mod.swapchain.handle, max(u64), image_available, 0, &image_index)
            
            vk.ResetCommandBuffer(cmd, {})
            
            begin_info := vk.CommandBufferBeginInfo{
                sType = .COMMAND_BUFFER_BEGIN_INFO,
                flags = {.ONE_TIME_SUBMIT},
            }

            vk.BeginCommandBuffer(cmd, &begin_info)

            image_subresource_range: vk.ImageSubresourceRange = {
                aspectMask = {.COLOR},
                baseMipLevel = 0,
                levelCount = 1,
               baseArrayLayer = 0,
                layerCount = 1,
            }

            color_barrier: vk.ImageMemoryBarrier = {
                sType = .IMAGE_MEMORY_BARRIER,
                srcAccessMask = {},
                dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
                oldLayout = .UNDEFINED,
                newLayout = .COLOR_ATTACHMENT_OPTIMAL,
                srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                image = mod.swapchain.images[image_index],
                subresourceRange = image_subresource_range
            }

            vk.CmdPipelineBarrier(
                cmd,
                {.TOP_OF_PIPE},              // srcStageMask: No prior operations
                {.COLOR_ATTACHMENT_OUTPUT},  // dstStageMask: Wait for color attachment stage
                {},                          // dependencyFlags
                0, nil,                      // memory barriers
                0, nil,                      // buffer memory barriers
                1, &color_barrier            // image memory barriers
            )

            render_area := vk.Rect2D{
                offset = {0, 0},
                extent = mod.swapchain.extent,
            }
            
            clear_color := vk.ClearValue{
                color = {float32 = {0.0, 0.0, 0.0, 1.0}},
            }
            
            color_attachment := vk.RenderingAttachmentInfo{
                sType = .RENDERING_ATTACHMENT_INFO,
                imageView = mod.swapchain.views[image_index],
                imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
                loadOp = .CLEAR,
                storeOp = .STORE,
                clearValue = clear_color,
            }
            
            rendering_info := vk.RenderingInfo{
                sType = .RENDERING_INFO,
                renderArea = render_area,
                layerCount = 1,
                colorAttachmentCount = 1,
                pColorAttachments = &color_attachment,
            }

            vk.CmdBeginRendering(cmd, &rendering_info)

                
            offsets: []vk.DeviceSize = {0}
            vk.CmdBindVertexBuffers( cmd, 0, 1, &vert_buf.handle, raw_data(offsets))

            vk.CmdBindPipeline(cmd, .GRAPHICS, pipeline)
            
            vk.CmdDraw(cmd, u32(len(verts)), 1, 0, 0)
            
            vk.CmdEndRendering(cmd)
            
            present_barrier: vk.ImageMemoryBarrier = {
                sType = .IMAGE_MEMORY_BARRIER,
                srcAccessMask = {.COLOR_ATTACHMENT_WRITE},
                dstAccessMask = {.MEMORY_READ},
                oldLayout = .COLOR_ATTACHMENT_OPTIMAL,
                newLayout = .PRESENT_SRC_KHR,
                srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
                image = mod.swapchain.images[image_index],
                subresourceRange = image_subresource_range
            }

            vk.CmdPipelineBarrier(
                cmd,
                {.COLOR_ATTACHMENT_OUTPUT},             
                {.BOTTOM_OF_PIPE},
                {},              
                0, nil,         
                0, nil,        
                1, &present_barrier           
            )


            vk.EndCommandBuffer(cmd)
            
            wait_stages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
            submit_info := vk.SubmitInfo{
                sType = .SUBMIT_INFO,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &image_available,
                pWaitDstStageMask = &wait_stages,
                commandBufferCount = 1,
                pCommandBuffers = &cmd,
                signalSemaphoreCount = 1,
                pSignalSemaphores = &render_finished,
            }
            vk.QueueSubmit(ctx.queue.handle, 1, &submit_info, in_flight)
            
            present_info := vk.PresentInfoKHR{
                sType = .PRESENT_INFO_KHR,
                waitSemaphoreCount = 1,
                pWaitSemaphores = &render_finished,
                swapchainCount = 1,
                pSwapchains = &mod.swapchain.handle,
                pImageIndices = &image_index,
            }
            vk.QueuePresentKHR(ctx.queue.handle, &present_info)
            
		}
	}

    vk.DeviceWaitIdle(ctx.device)

}


/*
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
*/
