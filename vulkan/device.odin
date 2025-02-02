package vulk

import vk "vendor:vulkan"
import "core:fmt"
import "core:strings"

select_queues :: proc(gpu: vk.PhysicalDevice, surface: vk.SurfaceKHR) -> queue_family_indices{

	queue_family_count:u32
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queue_family_count, nil)
	queue_families := make([]vk.QueueFamilyProperties, queue_family_count)
	defer delete(queue_families)
	vk.GetPhysicalDeviceQueueFamilyProperties(gpu, &queue_family_count, raw_data(queue_families))

	indices: queue_family_indices

	indices.graphics_family = max(u32) // for checking later

	distinct_compute:bool = false
	distinct_transfer:bool = false
	distinct_sparse:bool = false
	/*
	for family, index in queue_families{
		present_support:b32=false
		vk.GetPhysicalDeviceSurfaceSupportKHR(gpu, u32(index), surface, &present_support)
		if(present_support == true && .GRAPHICS in family.queueFlags){
			indices.present_family = u32(index)
			indices.present_idx = 0
			indices.graphics_family = u32(index)
			indices.graphics_idx = 0
			break
		}
	}
	*/

	//select 0,0 for graphics, and another family for present. this will probably run on all gpus, but on nvidias might double up graphics and present

	for family, index in queue_families{
		if( .GRAPHICS in family.queueFlags){
			indices.graphics_family = u32(index)
			indices.graphics_idx = 0
		}
	}

	present_family_props: [dynamic]u32
	defer delete(present_family_props)

	for family, index in queue_families{
		present_support:b32 = false
		vk.GetPhysicalDeviceSurfaceSupportKHR(gpu, u32(index), surface, &present_support)
		if(present_support){
			append(&present_family_props, u32(index))
		}
	}

	indices.present_family = 0
	for prop in present_family_props{
		if(prop > indices.present_family){
			indices.present_family = prop
		}
	}
	indices.present_idx = 0
	

	
	//select compute queue
	for family, index in queue_families{
		if(index == int(indices.graphics_family) && family.queueCount <= 1) do continue
		if(.COMPUTE in family.queueFlags){
			//avoid graphics queue if in family 0
			start_queue:u32 = (index == int(indices.graphics_family)) ? 1 : 0
			if(start_queue < family.queueCount){
				indices.compute_family = u32(index)
				indices.compute_idx = start_queue
				distinct_compute = true
				break
			}
		}
	}

	//select transfer queue
	for family, index in queue_families{
		if(index == int(indices.graphics_family) && index == int(indices.compute_family) && family.queueCount <= 2) do continue
		if(index == int(indices.graphics_family) && family.queueCount <= 1) do continue
		if(index == int(indices.compute_family) && family.queueCount <= 1) do continue
		if(.TRANSFER in family.queueFlags || .COMPUTE in family.queueFlags){
			start_queue:u32=0
			if(index == int(indices.graphics_family) && index == int(indices.compute_family)){
				start_queue = 2
			} else if(index == int(indices.graphics_family) || index == int(indices.compute_family)){
				start_queue = 1
			}
			if(start_queue < family.queueCount){
				indices.transfer_family = u32(index)
				indices.transfer_idx = start_queue
				distinct_transfer = true
				break
			}
		}
	}

	//finally, select the sparse binding family
	for family, index in queue_families{
		if(index == int(indices.graphics_family) && (index == int(indices.compute_family)) && (index == int(indices.transfer_family)) && family.queueCount <= 3) do continue
		if(index == int(indices.graphics_family) && (index == int(indices.compute_family)) && family.queueCount <= 2) do continue
		if(index == int(indices.graphics_family) && (index == int(indices.transfer_family)) && family.queueCount <= 2) do continue
		if(index == int(indices.transfer_family) && (index == int(indices.compute_family)) && family.queueCount <= 2) do continue
		if(index == int(indices.graphics_family) && family.queueCount <= 1) do continue
		if(index == int(indices.compute_family) && family.queueCount <= 1) do continue
		if(index == int(indices.transfer_family) && family.queueCount <= 1) do continue
		if(.SPARSE_BINDING in family.queueFlags || .COMPUTE in family.queueFlags){
			start_queue:u32=0
			if(index == int(indices.graphics_family) && index == int(indices.compute_family) && index == int(indices.transfer_family)){
				start_queue = 3
			} else if((index == int(indices.graphics_family) && index == int(indices.compute_family)) ||
					  (index == int(indices.graphics_family) && index == int(indices.transfer_family)) ||
					  (index == int(indices.compute_family) && index == int(indices.transfer_family))){
				start_queue = 2
			} else if((index == int(indices.graphics_family)) || (index == int(indices.compute_family)) || (index == int(indices.transfer_family))){
				start_queue = 1
			}
			if(start_queue < family.queueCount){
				indices.sparse_family = u32(index)
				indices.sparse_idx = start_queue
				distinct_sparse = true
				break
			}


		}
	}

	//now, all queues are distinct or unset, queues that are not distinct must be set to a queue compatible with their command type
	//because of this, some queue families and indicies may be the same
	//this must be handled when creating device and retrieving queues/command pools

	if(distinct_compute == true){
		if(distinct_transfer == false){
			indices.transfer_family = indices.compute_family
			indices.transfer_idx = indices.compute_idx
		}
		if(distinct_sparse == false){
			indices.sparse_family = indices.graphics_family
			indices.sparse_idx = indices.graphics_idx
		}
	} else {
		indices.compute_family = indices.graphics_family
		indices.compute_idx = indices.graphics_idx
		if(distinct_transfer == false){
			indices.transfer_family = indices.graphics_family
			indices.transfer_idx = indices.graphics_idx
		}
		if(distinct_sparse == false){
			indices.sparse_family = indices.graphics_family
			indices.sparse_idx = indices.graphics_idx
		}
	}


	return indices
}

select_gpu :: proc(ctx: ^vk_context){

	gpu_count:u32
	vk.EnumeratePhysicalDevices(ctx.instance, &gpu_count, nil)
	assert(gpu_count != 0)
	gpus:[]vk.PhysicalDevice = make([]vk.PhysicalDevice, gpu_count)
	defer delete(gpus)
	vk.EnumeratePhysicalDevices(ctx.instance, &gpu_count, raw_data(gpus))

	gpu := pick_gpu(gpus, ctx^)

	gpu_properties: vk.PhysicalDeviceProperties
	vk.GetPhysicalDeviceProperties(gpu, &gpu_properties)
	fmt.println("selected gpu: ", string(gpu_properties.deviceName[:]))

	ctx.gpu = gpu
}


pick_gpu :: proc(gpus: []vk.PhysicalDevice, ctx: vk_context) -> vk.PhysicalDevice{
	gpu_prop :: struct{
		gpu: vk.PhysicalDevice,
		points: uint,
	}

	props: []gpu_prop = make([]gpu_prop, len(gpus));
	for i in 0..<len(props){
		props[i].gpu = gpus[i]
		props[i].points = 0
	}
	
	defer delete(props)

	
	unviable_gpus:uint = 0

	for i in 0..<len(props){


		features: vk.PhysicalDeviceFeatures
		properties: vk.PhysicalDeviceProperties
		
		vk.GetPhysicalDeviceFeatures(props[i].gpu, &features)
		vk.GetPhysicalDeviceProperties(props[i].gpu, &properties)

		ext_count:u32 = 0
		vk.EnumerateDeviceExtensionProperties(props[i].gpu, nil, &ext_count, nil)
		exts:[]vk.ExtensionProperties = make([]vk.ExtensionProperties, ext_count)
		defer delete(exts)
		vk.EnumerateDeviceExtensionProperties(props[i].gpu, nil, &ext_count, raw_data(exts))

		ext_map:map[cstring]bool
		defer delete(ext_map)

		for ext in exts{
			ext_name := ext.extensionName
			ext_str := string(ext_name[0:256])
			ext_map[cstring(strings.clone_to_cstring(ext_str, context.temp_allocator))] = true
		}
		defer free_all(context.temp_allocator)

		requested_exts :[]cstring = {"VK_KHR_swapchain", "VK_KHR_dynamic_rendering", "VK_EXT_shader_object", "VK_EXT_descriptor_buffer", "VK_AMD_device_coherent_memory"}

		
		for ext in requested_exts{
			if(ext_map[ext] != true){
				props[i].points = 0
				unviable_gpus += 1
				continue
			}
		}

		indices := select_queues(props[i].gpu, ctx.display.surface)

		if(features.geometryShader != true || indices.graphics_family == max(u32)){
			props[i].points = 0
			unviable_gpus += 1
			continue
		}


		if(properties.deviceType ==  .DISCRETE_GPU){
			props[i].points += 1000000000
		}

		props[i].points += uint(properties.limits.maxImageDimension2D)
		props[i].points += uint(properties.limits.maxPushConstantsSize)
		props[i].points += uint(properties.limits.maxMemoryAllocationCount)
	}

	assert(unviable_gpus < len(props))

	best_gpu: gpu_prop

	for i in 0..<len(props){
		if(best_gpu.points < props[i].points){
			best_gpu = props[i]
		}
	}

	return best_gpu.gpu
}

create_queue_ci :: proc(family_index:u32, priority: ^f32) -> vk.DeviceQueueCreateInfo{
	return vk.DeviceQueueCreateInfo{
		sType = .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex = family_index,
		queueCount = 1,
		pQueuePriorities = priority,
		flags = nil,
		pNext = nil,
	}
}

create_device :: proc(ctx: ^vk_context){
	//! sets device, queues, and command pools
	indices := select_queues(ctx.gpu, ctx.display.surface)
	
	//checks if a queue was not available and needs an alias to an available queue 
	//no graphics alias because no graphics support is a crash
	compute_graphics_alias: bool = false
	transfer_graphics_alias: bool = false
	sparse_graphics_alias: bool = false
	transfer_compute_alias: bool = false
	sparse_compute_alias: bool = false
	
	//I cant think of a clever algorithm for this, we will just check all the cases for distinct queues/fallbacks

	if(indices.compute_family == indices.graphics_family && indices.compute_idx == indices.graphics_idx){
		compute_graphics_alias = true
	}
	if(indices.transfer_family == indices.graphics_family && indices.transfer_idx == indices.graphics_idx){
		transfer_graphics_alias = true
	}
	if(indices.sparse_family == indices.graphics_family && indices.sparse_idx == indices.graphics_idx){
		sparse_graphics_alias = true
	}
	if(compute_graphics_alias == false){
		if(indices.transfer_family == indices.compute_family && indices.transfer_idx == indices.compute_idx){
			transfer_compute_alias = true
		}
		if(indices.sparse_family == indices.compute_family && indices.sparse_idx == indices.compute_idx){
			sparse_compute_alias = true
		}
	}

	qfs : [dynamic]u32 = {indices.graphics_family, indices.compute_family, indices.transfer_family, indices.sparse_family}
	defer delete(qfs)

	//remove queues in same fmaily and fallbacks
	if(compute_graphics_alias){
		ordered_remove(&qfs, 1)
	}
	if(transfer_graphics_alias | transfer_compute_alias){
		ordered_remove(&qfs, 2)
	}
	if(sparse_graphics_alias | sparse_compute_alias){
		ordered_remove(&qfs, 3)
	}

	for family, index in qfs{
		for family2, index2 in qfs{
			if(index == index2){ continue }
			if(family == family2){ ordered_remove(&qfs, index2) }
		}
	}

	//maps family to the amount of queues that are used in said family
	qf_map :map[u32]u32
	defer delete(qf_map)
	

	for family in qfs{
		if(indices.graphics_family == family){
			qf_map[family] += 1
		}
		if(indices.compute_family == family){
			qf_map[family] += 1
		}
		if(indices.transfer_family == family){
			qf_map[family] += 1
		}
		if(indices.sparse_family == family){
			qf_map[family] += 1
		}
	}

	queue_cis: []vk.DeviceQueueCreateInfo = make([]vk.DeviceQueueCreateInfo, len(qfs))
	defer delete(queue_cis)

	for i in 0..<len(queue_cis){
		//create priority array that is 1.0 for all queues in family (I dont care about priority that much)
		priorities : []f32 = make([]f32, qf_map[qfs[i]])
		defer delete(priorities)
		for i in 0..<len(priorities){
			priorities[i] = 1.0	
		}

		//set queue creation info
		queue_cis[i].sType = .DEVICE_QUEUE_CREATE_INFO
		queue_cis[i].queueFamilyIndex = qfs[i]
		queue_cis[i].queueCount = qf_map[qfs[i]]
		queue_cis[i].pQueuePriorities = raw_data(priorities)
	}



	//dynamic rendering is in core
	physical_device_features2: vk.PhysicalDeviceFeatures2 = {
		sType = .PHYSICAL_DEVICE_FEATURES_2
	}
	dynamic_rendering: vk.PhysicalDeviceDynamicRenderingFeaturesKHR = {
		sType = .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
		dynamicRendering = true
	}
	shader_obj: vk.PhysicalDeviceShaderObjectFeaturesEXT = {
		sType = .PHYSICAL_DEVICE_SHADER_OBJECT_FEATURES_EXT,
		shaderObject = true,
	}
	desc_buf: vk.PhysicalDeviceDescriptorBufferFeaturesEXT = {
		sType = .PHYSICAL_DEVICE_DESCRIPTOR_BUFFER_FEATURES_EXT,
		descriptorBuffer = true,
	}
	coherent_memory: vk.PhysicalDeviceCoherentMemoryFeaturesAMD = {
		sType = .PHYSICAL_DEVICE_COHERENT_MEMORY_FEATURES_AMD,
		deviceCoherentMemory = true
	}

	physical_device_features2.pNext = &dynamic_rendering
	dynamic_rendering.pNext = &shader_obj
	shader_obj.pNext = &desc_buf
	desc_buf.pNext = &coherent_memory;


	device_exts :[]cstring = {"VK_KHR_swapchain", "VK_KHR_dynamic_rendering", "VK_EXT_shader_object", "VK_EXT_descriptor_buffer", "VK_AMD_device_coherent_memory"}
	
	device_ci: vk.DeviceCreateInfo = {
		sType = .DEVICE_CREATE_INFO,
		pNext = &physical_device_features2,
		pQueueCreateInfos = raw_data(queue_cis),
		queueCreateInfoCount = u32(len(queue_cis)),
		ppEnabledExtensionNames = raw_data(device_exts),
		enabledExtensionCount = u32(len(device_exts)),
	}

	result := vk.CreateDevice(ctx.gpu, &device_ci, nil, &ctx.device)
	assert(result == .SUCCESS)


	vk.GetDeviceQueue(ctx.device, indices.present_family, indices.present_idx, &ctx.queues.present_queue)
	vk.GetDeviceQueue(ctx.device, indices.graphics_family, indices.graphics_idx, &ctx.queues.graphics_queue)

	if(compute_graphics_alias){
		ctx.queues.compute_queue = ctx.queues.graphics_queue
	} else {
		vk.GetDeviceQueue(ctx.device, indices.compute_family, indices.compute_idx, &ctx.queues.compute_queue)
	}

	if(transfer_graphics_alias){
		ctx.queues.transfer_queue = ctx.queues.graphics_queue
	} else if(transfer_compute_alias){
		ctx.queues.transfer_queue = ctx.queues.compute_queue
	} else{
		vk.GetDeviceQueue(ctx.device, indices.transfer_family, indices.transfer_idx, &ctx.queues.transfer_queue)
	}

	if(sparse_graphics_alias){
		ctx.queues.sparse_queue = ctx.queues.graphics_queue
	} else if(sparse_compute_alias){
		ctx.queues.sparse_queue = ctx.queues.compute_queue
	} else{
		vk.GetDeviceQueue(ctx.device, indices.sparse_family, indices.sparse_idx, &ctx.queues.sparse_queue)
	}

	//command pools can only create command buffers for a specific family
	//for simplicities sake we will treat each queue as being from a different family

	graphics_pool_ci: vk.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics_family,

	}
	compute_pool_ci: vk.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.compute_family,

	}
	transfer_pool_ci: vk.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.transfer_family,

	}
	sparse_pool_ci: vk.CommandPoolCreateInfo = {
		sType = .COMMAND_POOL_CREATE_INFO,
		flags = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.sparse_family,

	}

	vk.CreateCommandPool(ctx.device, &graphics_pool_ci, nil, &ctx.queues.pools.graphics)
	vk.CreateCommandPool(ctx.device, &compute_pool_ci, nil, &ctx.queues.pools.compute)
	vk.CreateCommandPool(ctx.device, &transfer_pool_ci, nil, &ctx.queues.pools.transfer)
	vk.CreateCommandPool(ctx.device, &sparse_pool_ci, nil, &ctx.queues.pools.sparse)
}

















