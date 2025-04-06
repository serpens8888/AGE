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
check_vk :: proc(res: vk.Result) -> Error{
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





