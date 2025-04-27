package vulk

import vk "vendor:vulkan"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:reflect"
import "base:runtime"

@(require_results)
create_instance :: proc() -> (instance: vk.Instance, err: Error){
	version: u32
	check_vk(vk.EnumerateInstanceVersion(&version)) or_return
	major := (version >> 22) & 0x7F
	minor := (version >> 12) & 0x3FF
	patch := version & 0xFFF
	fmt.printf("vulkan version: %d.%d.%d\n", major, minor, patch)

	application_info: vk.ApplicationInfo = {
		sType = .APPLICATION_INFO,
		pApplicationName = "an application",
		applicationVersion = vk.MAKE_VERSION(0,0,0),
		pEngineName = "an engine",
		engineVersion = vk.MAKE_VERSION(0,0,0),
		apiVersion = vk.MAKE_VERSION(1,3,0),
	}

	requested_extensions := make([dynamic]cstring)
	defer delete(requested_extensions) //deleting a dynamic array does not take an allocator

	append(&requested_extensions, "VK_EXT_debug_utils")	
	append(&requested_extensions, "VK_KHR_surface")	
	when ODIN_OS == .Windows{ append(&requested_extensions, "VK_KHR_win32_surface") }
	when ODIN_OS == .Linux{ append(&requested_extensions, "VK_KHR_xlib_surface", "VK_KHR_xcb_surface", "VK_KHR_wayland_surface")}
	when ODIN_OS == .Darwin{ append(&requested_extensions, "VK_EXT_metal_surface")}

	requested_layers: []cstring

	when ODIN_DEBUG{
		requested_layers = get_layers() or_return
		defer delete(requested_layers)
		append(&requested_extensions, "VK_EXT_debug_utils")
	}

	validate_instance_extensions(requested_extensions) or_return

	create_info: vk.InstanceCreateInfo = {
		sType = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &application_info,
		enabledExtensionCount = u32(len(requested_extensions)),
		ppEnabledExtensionNames = raw_data(requested_extensions),
		enabledLayerCount = u32(len(requested_layers)),
		ppEnabledLayerNames = raw_data(requested_layers)
	}

	when ODIN_DEBUG{
		debug_info := get_debug_messenger_create_info()
		create_info.pNext = &debug_info
	}

	check_vk(vk.CreateInstance(&create_info, nil, &instance)) or_return


	return

}

@(require_results)
get_layers :: proc() -> (requested_layers: []cstring, err: Error){
		requested_layers = make([]cstring, 1)
		requested_layers[0] = "VK_LAYER_KHRONOS_validation"

		layer_count: u32
		check_vk(vk.EnumerateInstanceLayerProperties(&layer_count, nil)) or_return

		available_layers := make([]vk.LayerProperties, layer_count) or_return
		defer delete(available_layers)

		check_vk(vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))) or_return

		layer_map := make(map[cstring]bool)
		defer delete(layer_map)

		for layer in available_layers {
			layer_name := layer.layerName //[256]u8
			layer_str := (string(layer_name[0:256]))
			layer_cstr := strings.clone_to_cstring(layer_str)
			layer_map[layer_cstr] = true //flag that the layer is there
		}

		for layer in requested_layers {
			if (layer_map[layer] != true){
				panic("failed to find requested validation layers") //check if all out requested layers are there
			}
		}
		
		//cloned to cstring, now free them
		for layer in layer_map{
			delete(layer)
		}

		return
}


@(require_results)
validate_instance_extensions :: proc(requested_extensions: [dynamic]cstring) -> (err: Error){
	ext_count: u32
	check_vk(vk.EnumerateInstanceExtensionProperties(nil, &ext_count, nil)) or_return

	available_extensions := make([]vk.ExtensionProperties,ext_count) or_return
	defer delete(available_extensions)

	check_vk(vk.EnumerateInstanceExtensionProperties(nil, &ext_count, raw_data(available_extensions))) or_return

	extension_map := make(map[cstring]bool) 
	defer delete(extension_map)

	for ext in available_extensions{
		ext_name := ext.extensionName//[256]u8
		ext_str := string(ext_name[0:256])
		ext_cstr := cstring(strings.clone_to_cstring(ext_str))
		extension_map[ext_cstr] = true //flag that extension is supported
	}

	for ext in requested_extensions{
		if(extension_map[ext] != true){
			panic("failed to find requested instance extension") //make sure all requested extensions are supported
		}
	}


	//delete cloned cstrings
	for ext in extension_map{
			delete(ext)
	}

	return

}

debug_callback_linux :: proc "cdecl" (severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr) -> b32{

	context = runtime.default_context()

	severity_string:string
	if .ERROR in severity{ severity_string = "error" }
	if .WARNING in severity{ severity_string = "warning" }
	if .VERBOSE in severity{ severity_string = "verbose"; return false} // early returns to stop clutter in the command line
	if .INFO in severity{ severity_string = "info"; return false } 		// delete if verbose or info is needed

	type_string:string
	if .GENERAL in message_type{ type_string = "general" }
	if .VALIDATION in message_type{ type_string = "validation" }
	if .PERFORMANCE in message_type{ type_string = "performance" }
	if .DEVICE_ADDRESS_BINDING in message_type{ type_string = "device address binding" }
	
	message: string
	if(callback_data != nil){
		message = string(cstring(callback_data.pMessage))
	}

	fmt.eprintf("severity: %s | type: %s | message: %s\n", severity_string, type_string, message)


	return false
}

debug_callback_windows :: proc "stdcall" (severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr) -> b32{

	context = runtime.default_context()

	severity_string:string
	if .ERROR in severity{ severity_string = "error" }
	if .WARNING in severity{ severity_string = "warning" }
	if .VERBOSE in severity{ severity_string = "verbose"; return false} // early returns to stop clutter in the command line
	if .INFO in severity{ severity_string = "info"; return false } 		// delete if verbose or info is needed

	type_string:string
	if .GENERAL in message_type{ type_string = "general" }
	if .VALIDATION in message_type{ type_string = "validation" }
	if .PERFORMANCE in message_type{ type_string = "performance" }
	if .DEVICE_ADDRESS_BINDING in message_type{ type_string = "device address binding" }
	
	message: string
	if(callback_data != nil){
		message = string(cstring(callback_data.pMessage))
	}

	fmt.eprintf("severity: %s | type: %s | message: %s\n", severity_string, type_string, message)


	return false
}

@(require_results)
get_debug_messenger_create_info :: proc() -> vk.DebugUtilsMessengerCreateInfoEXT{
    info: vk.DebugUtilsMessengerCreateInfoEXT =  {
		sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = { .ERROR, .WARNING, .VERBOSE, .INFO },
		messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING },
	}
    when(ODIN_OS == .Windows){
        info.pfnUserCallback = debug_callback_windows
    } else{
        info.pfnUserCallback = debug_callback_linux
    }

    return info
}

@(require_results)
create_debug_messenger :: proc(instance: vk.Instance) -> (debug_messenger: vk.DebugUtilsMessengerEXT, err: Error){

	ci := get_debug_messenger_create_info()

	check_vk(vk.CreateDebugUtilsMessengerEXT(instance, &ci, nil, &debug_messenger)) or_return

	return
}

















