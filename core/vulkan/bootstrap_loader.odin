package vulk

import vk "vendor:vulkan"
import "core:fmt"
import "core:dynlib"


VkGetInstanceProcAddr :: proc "system" (instance: vk.Instance, procname: cstring) -> vk.ProcVoidFunction  

load_vulkan :: proc(){

	//choose correct library name
	lib_name :string
	
	when (ODIN_OS == .Windows){
		lib_name = "vulkan-1"
	} else {
		lib_name = "vulkan"
	}

	//load it in	
	lib, loaded := dynlib.load_library(lib_name)
	assert(loaded == true)

	fmt.printf("%s was successfully loaded\n", lib_name)

	//load the VkGetInstanceProcAddr function
	//this is used to retrieve function pointers for the vulkan instance functions
    get_instance_proc_addr := cast(VkGetInstanceProcAddr)(dynlib.symbol_address(lib, "vkGetInstanceProcAddr"))

	assert(get_instance_proc_addr != nil)

	//load all the function pointers for creating an instance, and ensure they are loaded

	vk.load_proc_addresses(rawptr(get_instance_proc_addr))

	assert(vk.CreateInstance != nil)

}
