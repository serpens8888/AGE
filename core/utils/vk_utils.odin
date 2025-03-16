package util

import vk "vendor:vulkan"
import "core:fmt"
import "core:reflect"
import "core:strings"
import "core:os"
import "core:mem"
import "core:c/libc"

check_vk :: proc(res: vk.Result, loc := #caller_location){
	if(res != .SUCCESS){
		sb: strings.Builder //no need to deallocate anything, we're about to crash!
		msg := fmt.sbprintf(&sb, "vulkan result was not .SUCCESS, result = %s", reflect.enum_string(res))
		panic(msg, loc)
	}
}


compile_slang :: proc(shader_path: string, spirv_path: string){
	sb, err := strings.builder_make_none()
	assert(err == .None)
	defer delete(sb.buf)

	cmd := fmt.sbprintf(&sb, "slangc %s -target spirv -o %s\000", shader_path, spirv_path)
	libc.system(strings.unsafe_string_to_cstring(cmd))
}





