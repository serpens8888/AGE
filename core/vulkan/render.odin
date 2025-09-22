package vulk

import "core:fmt"
import "core:math/linalg"
import vk "vendor:vulkan"
import "vma"


FRAMES_IN_FLIGHT :: 2
TRI_INDICES: []Index : {0, 1, 2}
RECT_INDICES: []Index : {0, 1, 2, 0, 2, 3}


Render_State :: struct {
    image_available:   [FRAMES_IN_FLIGHT]vk.Semaphore,
    render_finished:   [FRAMES_IN_FLIGHT]vk.Semaphore,
    in_flight:         [FRAMES_IN_FLIGHT]vk.Fence,
    current_frame:     u32, //current frame in flight
    image_index:       u32, //the index of the current swapchain image
    pool:              vk.CommandPool, //a command pool for this rendering thread
    cmds:              [FRAMES_IN_FLIGHT]vk.CommandBuffer,

    //scratch space
    scratch_allocator: vma.Allocator,
    verts:             Allocated_Buffer, //scratch vertex buffer 
    vert_offset:       u32, //current offset into the vertex buffer
    indices:           Allocated_Buffer, //scratch index buffer
    index_offset:      u32,
}




draw_rectangle :: proc(x, y, w, h: f32, state: ^Render_State) {
    bl: Vertex = {
        pos = {x, y, 0},
        uv  = {1, 0},
    }

    tl: Vertex = {
        pos = {x, y + h, 0},
        uv  = {0, 0},
    }

    tr: Vertex = {
        pos = {x + w, y + h, 0},
        uv  = {0, 1},
    }

    br: Vertex = {
        pos = {x + w, y, 0},
        uv  = {1, 1},
    }

    assert(
        write_verts(
            state.verts,
            state.scratch_allocator,
            uintptr(state.vert_offset * size_of(Vertex)),
            {bl, tl, tr, br},
        ) ==
        nil,
    )

    new_rect_indices := RECT_INDICES
    for &i in new_rect_indices {
        i += Index(state.vert_offset)
    }

    assert(
        write_indices(
            state.indices,
            state.scratch_allocator,
            uintptr(state.index_offset * size_of(Index)),
            new_rect_indices,
        ) ==
        nil,
    )


    cmd := state.cmds[state.current_frame]

    state.vert_offset += 4

    state.index_offset += 6

}

draw_batch :: proc(state: ^Render_State) {
    cmd := state.cmds[state.current_frame]
    vk.CmdDrawIndexed(cmd, state.index_offset, 1, 0, 0, 0)
}




@(require_results)
create_render_state :: proc(
    ctx: Context,
    pool: vk.CommandPool,
    scratch_allocator: vma.Allocator,
) -> (
    state: Render_State,
    err: Error,
) {

    for &sem in state.image_available {
        sem = create_semaphore(ctx.device) or_return
    }

    for &sem in state.render_finished {
        sem = create_semaphore(ctx.device) or_return
    }

    for &fence in state.in_flight {
        fence = create_fence(ctx.device, {.SIGNALED}) or_return
    }

    state.pool = pool

    alloc_info := make_command_buffer_allocate_info(
        state.pool,
        FRAMES_IN_FLIGHT,
    )
    vk.AllocateCommandBuffers(ctx.device, &alloc_info, raw_data(state.cmds[:]))

    state.scratch_allocator = scratch_allocator

    state.indices = create_index_buffer_empty(
        ctx.device,
        ctx.allocator,
        100000,
    ) or_return

    vma.map_memory(
        ctx.allocator,
        state.indices.allocation,
        &state.indices.mapped_ptr,
    ) or_return


    state.verts = create_vertex_buffer_empty(
        ctx.device,
        ctx.allocator,
        100000,
    ) or_return

    vma.map_memory(
        ctx.allocator,
        state.verts.allocation,
        &state.verts.mapped_ptr,
    ) or_return

    return
}

destroy_render_state :: proc(ctx: Context, state: ^Render_State) {
    for &sem in state.image_available {
        vk.DestroySemaphore(ctx.device, sem, nil)
    }

    for &sem in state.render_finished {
        vk.DestroySemaphore(ctx.device, sem, nil)
    }

    for &fence in state.in_flight {
        vk.DestroyFence(ctx.device, fence, nil)
    }

    vk.FreeCommandBuffers(
        ctx.device,
        state.pool,
        FRAMES_IN_FLIGHT,
        raw_data(state.cmds[:]),
    )

    free_buffer(ctx.allocator, state.indices)
    free_buffer(ctx.allocator, state.verts)
}


@(require_results)
begin_rendering :: proc(
    ctx: Context,
    mod: ^Graphics_Module,
    state: ^Render_State,
) -> vk.CommandBuffer {

    cmd := state.cmds[state.current_frame]

    vk.WaitForFences(
        ctx.device,
        1,
        &state.in_flight[state.current_frame],
        true,
        max(u64),
    )
    vk.ResetFences(ctx.device, 1, &state.in_flight[state.current_frame])

    image_index: u32
    result := vk.AcquireNextImageKHR(
        ctx.device,
        mod.swapchain.handle,
        max(u64),
        state.image_available[state.current_frame],
        0,
        &image_index,
    )

    if (result == .ERROR_OUT_OF_DATE_KHR) {
        _ = recreate_swapchain(ctx, mod)
    } else if (result != .SUCCESS && result != .SUBOPTIMAL_KHR) {
        panic("failed to retrieve swapchain image")
    }

    state.image_index = image_index

    vk.ResetCommandBuffer(cmd, {})

    begin_info := vk.CommandBufferBeginInfo {
        sType = .COMMAND_BUFFER_BEGIN_INFO,
        flags = {.ONE_TIME_SUBMIT},
    }

    vk.BeginCommandBuffer(cmd, &begin_info)

    image_subresource_range: vk.ImageSubresourceRange = {
        aspectMask     = {.COLOR},
        baseMipLevel   = 0,
        levelCount     = 1,
        baseArrayLayer = 0,
        layerCount     = 1,
    }

    color_barrier: vk.ImageMemoryBarrier = {
        sType               = .IMAGE_MEMORY_BARRIER,
        srcAccessMask       = {},
        dstAccessMask       = {.COLOR_ATTACHMENT_WRITE},
        oldLayout           = .UNDEFINED,
        newLayout           = .COLOR_ATTACHMENT_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image               = mod.swapchain.images[state.image_index],
        subresourceRange    = image_subresource_range,
    }

    vk.CmdPipelineBarrier(
        cmd,
        {.TOP_OF_PIPE}, // srcStageMask: No prior operations
        {.COLOR_ATTACHMENT_OUTPUT}, // dstStageMask: Wait for color attachment stage
        {}, // dependencyFlags
        0,
        nil, // memory barriers
        0,
        nil, // buffer memory barriers
        1,
        &color_barrier, // image memory barriers
    )

    render_area := vk.Rect2D {
        offset = {0, 0},
        extent = mod.swapchain.extent,
    }

    viewport: vk.Viewport = {
        x        = 0,
        y        = 0,
        width    = f32(mod.swapchain.extent.width),
        height   = f32(mod.swapchain.extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    vk.CmdSetViewport(cmd, 0, 1, &viewport)
    vk.CmdSetScissor(cmd, 0, 1, &render_area)

    clear_color := vk.ClearValue {
        color = {float32 = {0.0, 0.0, 0.0, 1.0}},
    }

    color_attachment := vk.RenderingAttachmentInfo {
        sType       = .RENDERING_ATTACHMENT_INFO,
        imageView   = mod.swapchain.views[image_index],
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp      = .CLEAR,
        storeOp     = .STORE,
        clearValue  = clear_color,
    }

    rendering_info := vk.RenderingInfo {
        sType                = .RENDERING_INFO,
        renderArea           = render_area,
        layerCount           = 1,
        colorAttachmentCount = 1,
        pColorAttachments    = &color_attachment,
    }

    vk.CmdBeginRendering(cmd, &rendering_info)

    offsets: []vk.DeviceSize = {0}
    vk.CmdBindVertexBuffers(cmd, 0, 1, &state.verts.handle, raw_data(offsets))
    vk.CmdBindIndexBuffer(cmd, state.indices.handle, 0, .UINT32)

    return cmd
}

end_rendering :: proc(
    ctx: Context,
    mod: ^Graphics_Module,
    state: ^Render_State,
) {
    cmd := state.cmds[state.current_frame]

    vk.CmdEndRendering(cmd)

    image_subresource_range: vk.ImageSubresourceRange = {
        aspectMask     = {.COLOR},
        baseMipLevel   = 0,
        levelCount     = 1,
        baseArrayLayer = 0,
        layerCount     = 1,
    }

    present_barrier: vk.ImageMemoryBarrier = {
        sType               = .IMAGE_MEMORY_BARRIER,
        srcAccessMask       = {.COLOR_ATTACHMENT_WRITE},
        dstAccessMask       = {.MEMORY_READ},
        oldLayout           = .COLOR_ATTACHMENT_OPTIMAL,
        newLayout           = .PRESENT_SRC_KHR,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image               = mod.swapchain.images[state.image_index],
        subresourceRange    = image_subresource_range,
    }

    vk.CmdPipelineBarrier(
        cmd,
        {.COLOR_ATTACHMENT_OUTPUT},
        {.BOTTOM_OF_PIPE},
        {},
        0,
        nil,
        0,
        nil,
        1,
        &present_barrier,
    )


    vk.EndCommandBuffer(cmd)

    wait_stages := vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT}
    submit_info := vk.SubmitInfo {
        sType                = .SUBMIT_INFO,
        waitSemaphoreCount   = 1,
        pWaitSemaphores      = &state.image_available[state.current_frame],
        pWaitDstStageMask    = &wait_stages,
        commandBufferCount   = 1,
        pCommandBuffers      = &cmd,
        signalSemaphoreCount = 1,
        pSignalSemaphores    = &state.render_finished[state.current_frame],
    }
    vk.QueueSubmit(
        ctx.queue.handle,
        1,
        &submit_info,
        state.in_flight[state.current_frame],
    )

    present_info := vk.PresentInfoKHR {
        sType              = .PRESENT_INFO_KHR,
        waitSemaphoreCount = 1,
        pWaitSemaphores    = &state.render_finished[state.current_frame],
        swapchainCount     = 1,
        pSwapchains        = &mod.swapchain.handle,
        pImageIndices      = &state.image_index,
    }
    result := vk.QueuePresentKHR(ctx.queue.handle, &present_info)
    if (result == .ERROR_OUT_OF_DATE_KHR || result == .SUBOPTIMAL_KHR) {
        _ = recreate_swapchain(ctx, mod)
    } else if (result != .SUCCESS) {
        panic("failed to present swapchain image")
    }

    state.current_frame = (state.current_frame + 1) % FRAMES_IN_FLIGHT

    state.vert_offset = 0
    state.index_offset = 0
}

