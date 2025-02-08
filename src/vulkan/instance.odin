package vulk

import vk "vendor:vulkan"
import "core:fmt"
import "core:mem"
import "core:strings"
import "base:runtime"


create_instance :: proc(ctx: ^vk_context){
	
	version : u32 = 0
	vk.EnumerateInstanceVersion(&version)
	major := (version >> 22) & 0x7F
	minor := (version >> 12) & 0x3FF
	patch := version & 0xFFF

	fmt.println("version:", major, ".", minor, ".", patch)
	assert(minor>=3)

	app_info: vk.ApplicationInfo
	app_info.sType = .APPLICATION_INFO
	app_info.pNext = nil
	app_info.pApplicationName = "application"
	app_info.applicationVersion = vk.MAKE_VERSION(0,0,0)
	app_info.pEngineName = "engine"
	app_info.engineVersion = vk.MAKE_VERSION(0,0,0)
	app_info.apiVersion = vk.MAKE_VERSION(1,4,0)

	requested_extensions: [dynamic]cstring
	defer delete(requested_extensions)

	append(&requested_extensions, "VK_KHR_surface")
	when ODIN_OS == .Windows{append(&requested_extensions, "VK_KHR_win32_surface") }
	when ODIN_OS == .Linux{append(&requested_extensions, "VK_KHR_xlib_surface", "VK_KHR_xcb_surface", "VK_KHR_wayland_surface")}
	when ODIN_OS == .Darwin{append(&requested_extensions, "VK_EXT_metal_surface")}

	layer_count: u32 = 0
	requested_layers: []cstring = {"VK_LAYER_KHRONOS_validation"}
	when ODIN_DEBUG{
		append(&requested_extensions, "VK_EXT_debug_utils")

		vk.EnumerateInstanceLayerProperties(&layer_count, nil)
		available_layers, errr:= make([]vk.LayerProperties, layer_count, context.temp_allocator)
		vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(available_layers))

		layer_map := make(map[cstring]bool, context.temp_allocator)
		for layer in available_layers {
			layer_name := layer.layerName
			layer_str := (string(layer_name[0:256]))
			layer_map[cstring(strings.clone_to_cstring(layer_str, context.temp_allocator))] = true
		}

		for layer in requested_layers {
			if (layer_map[layer] != true){
				panic("failed to find requested validation layers")
			}
		}
	}

	ext_count: u32
	vk.EnumerateInstanceExtensionProperties(nil, &ext_count, nil)
	available_extensions, err := make([]vk.ExtensionProperties,ext_count, context.temp_allocator)
	vk.EnumerateInstanceExtensionProperties(nil, &ext_count, raw_data(available_extensions));
	extension_map := make(map[cstring]bool, context.temp_allocator) 

	for ext in available_extensions{
		ext_name := ext.extensionName
		ext_str := string(ext_name[0:256])
		extension_map[cstring(strings.clone_to_cstring(ext_str, context.temp_allocator))] = true
	}

	for ext in requested_extensions{
		if(extension_map[ext] != true){
			panic("failed to find requested instance extension")
		}
	}

	instance_info: vk.InstanceCreateInfo
	instance_info.sType = .INSTANCE_CREATE_INFO
	instance_info.pApplicationInfo = &app_info
	instance_info.enabledExtensionCount = u32(len(requested_extensions))
	instance_info.ppEnabledExtensionNames = raw_data(requested_extensions)
	instance_info.enabledLayerCount = u32(len(requested_layers))
	instance_info.ppEnabledLayerNames = raw_data(requested_layers); // if debug is disabled, layer count is zero and this data is ignored

	when ODIN_DEBUG{
		debug_messenger_ci := get_debug_messenger_create_info()
		instance_info.pNext = &debug_messenger_ci
	}


	instance :vk.Instance = ---	
	assert(vk.CreateInstance != nil)
	result := vk.CreateInstance(&instance_info, nil, &instance)
	if result != .SUCCESS{
		panic("failed to create instance")
	}

	free_all(context.temp_allocator)

	ctx.instance = instance

}

get_debug_messenger_create_info ::proc() -> vk.DebugUtilsMessengerCreateInfoEXT{
	messenger_create_info: vk.DebugUtilsMessengerCreateInfoEXT
	messenger_create_info.sType = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT
	messenger_create_info.messageSeverity = { .ERROR, .WARNING, .VERBOSE, .INFO }
	messenger_create_info.messageType = {.GENERAL, .VALIDATION, .PERFORMANCE, .DEVICE_ADDRESS_BINDING }
	messenger_create_info.pfnUserCallback = debug_callback
	return messenger_create_info
}

create_debug_messenger :: proc(ctx: ^vk_context){

	messenger_create_info: vk.DebugUtilsMessengerCreateInfoEXT = get_debug_messenger_create_info()

	debug_messenger: vk.DebugUtilsMessengerEXT

	result := vk.CreateDebugUtilsMessengerEXT(ctx.instance, &messenger_create_info, nil, &debug_messenger)
	if result != .SUCCESS{
		panic("failed to create debug utils messenger")
	}

	ctx.debug_messenger = debug_messenger

}

debug_callback :: proc "stdcall" (severity: vk.DebugUtilsMessageSeverityFlagsEXT,
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
	
	message:string
	if(callback_data != nil){
		message = string(cstring(callback_data.pMessage))
	}
	
	fmt.eprintln("severity: ", severity_string, "\ntype: ", type_string, "\nmessage: ", message ,"\n")

	if .ERROR in severity{
		panic("unrecoverable vulkan error")
	}

	return false;

}

