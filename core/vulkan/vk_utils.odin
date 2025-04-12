package vulk

import vk "vendor:vulkan"
import sdl "vendor:sdl3"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:os"
import "core:mem"
import "core:c/libc"

@(require_results)
check_vk :: #force_inline proc(res: vk.Result) -> Error{
	if(res != .SUCCESS){
        return res
	}
    return nil
}


compile_slang :: proc(shader_path: string, spirv_path: string){
	sb, err := strings.builder_make_none()
	assert(err == .None)
	defer delete(sb.buf)

	cmd := fmt.sbprintf(&sb, "slangc %s -target spirv -o %s\000", shader_path, spirv_path)
	libc.system(strings.unsafe_string_to_cstring(cmd))
}

begin_single_time_cmd :: proc(device: vk.Device, pool: vk.CommandPool) -> (cmd: vk.CommandBuffer, err: Error){
    alloc_info := make_command_buffer_allocate_info(pool, 1)

    check_vk(vk.AllocateCommandBuffers(device, &alloc_info, &cmd)) or_return

    begin_info := make_command_buffer_begin_info({.ONE_TIME_SUBMIT})

    check_vk(vk.BeginCommandBuffer(cmd, &begin_info)) or_return

    return
}

submit_single_time_cmd :: proc(device: vk.Device, pool: vk.CommandPool, queue: vk.Queue, cmd: ^vk.CommandBuffer) -> (err: Error){
    
    check_vk(vk.EndCommandBuffer(cmd^)) or_return

    cmd_submit_info := make_command_buffer_submit_info(cmd^)

    submit_info := make_submit_info({cmd_submit_info}, {}, {})

    check_vk(vk.QueueSubmit2(queue, 1, &submit_info, {})) or_return

    check_vk(vk.QueueWaitIdle(queue)) or_return

    vk.FreeCommandBuffers(device, pool, 1, cmd)

    return
}





