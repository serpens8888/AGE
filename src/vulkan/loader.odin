package vulk

import "core:dynlib"
import "core:fmt"
import vk "vendor:vulkan"

VkGetInstanceProcAddr :: proc "system" (instance: vk.Instance, procname: cstring) -> vk.ProcVoidFunction  


load_vulkan :: proc() {
	lib_name :string
	when (ODIN_OS == .Windows){
		lib_name = "vulkan-1"
	} else {
		lib_name = "vulkan"
	}

	lib, loaded := dynlib.load_library(lib_name)
	assert(loaded == true)

	fmt.println(lib_name, "was successfully loaded")

    // Cast to the correct function type
    get_instance_proc_addr := cast(VkGetInstanceProcAddr)(
        dynlib.symbol_address(lib, "vkGetInstanceProcAddr")
    )

    assert(get_instance_proc_addr != nil)

	vk.load_proc_addresses(rawptr(get_instance_proc_addr));

	assert(vk.CreateInstance != nil)
	
}


/* 
	initVulkan :: proc() {
    // load_proc_addresses_global :: proc(vk_get_instance_proc_addr: rawptr)
    vk.load_proc_addresses((rawptr)(glfw.GetInstanceProcAddress));

    instance : vk.Instance = createVkInstance();
    
    // load_proc_addresses_instance :: proc(instance: Instance)
    vk.load_proc_addresses(instance)

    physicalDevice : vk.PhysicalDevice = pickPhysicalDevice()
    device : vk.Device = createLogicalDevice(physicalDevice)
    
    // load_proc_addresses_device :: proc(device: Device)
    vk.load_proc_addresses(device)
}
*/


