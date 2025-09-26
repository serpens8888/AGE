package vulk

import "core:fmt"
import "core:mem"
import vk "vendor:vulkan"

SAMPLER_ARRAY_BINDING :: 0
MAX_SAMPLERS :: 100 //I doubt anyone needs this many

IMAGE_ARRAY_BINDING :: 1 //the image binding is on the end so it is dynamic
MAX_IMAGES :: 1000

Descriptor_Manager :: struct {
    layout:        vk.DescriptorSetLayout,
    pool:          vk.DescriptorPool,
    sets:          [FRAMES_IN_FLIGHT]vk.DescriptorSet,
    image_count:   u32,
    sampler_count: u32,
}


create_descriptors :: proc(
    device: vk.Device,
) -> (
    manager: Descriptor_Manager,
    err: Error,
) {

    sampler_binding: vk.DescriptorSetLayoutBinding = {
        binding         = SAMPLER_ARRAY_BINDING,
        descriptorType  = .SAMPLER,
        descriptorCount = MAX_SAMPLERS,
        stageFlags      = {.FRAGMENT},
    }

    sampler_flags: vk.DescriptorBindingFlags = {}

    image_binding: vk.DescriptorSetLayoutBinding = {
        binding         = IMAGE_ARRAY_BINDING,
        descriptorType  = .SAMPLED_IMAGE,
        descriptorCount = MAX_IMAGES,
        stageFlags      = {.FRAGMENT},
    }

    image_flags: vk.DescriptorBindingFlags = {
        .VARIABLE_DESCRIPTOR_COUNT,
        .PARTIALLY_BOUND,
        .UPDATE_AFTER_BIND,
    }


    flags: []vk.DescriptorBindingFlags = {image_flags, sampler_flags}
    bindings: []vk.DescriptorSetLayoutBinding = {
        image_binding,
        sampler_binding,
    }

    flag_info: vk.DescriptorSetLayoutBindingFlagsCreateInfo = {
        sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
        bindingCount  = u32(len(flags)),
        pBindingFlags = raw_data(flags),
    }

    layout_info: vk.DescriptorSetLayoutCreateInfo = {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        pNext        = &flag_info,
        flags        = {.UPDATE_AFTER_BIND_POOL},
        bindingCount = u32(len(bindings)),
        pBindings    = raw_data(bindings),
    }

    vk.CreateDescriptorSetLayout(
        device,
        &layout_info,
        nil,
        &manager.layout,
    ) or_return

    image_pool_size: vk.DescriptorPoolSize = {
        type            = .SAMPLED_IMAGE,
        descriptorCount = FRAMES_IN_FLIGHT * MAX_IMAGES,
    }

    sampler_pool_size: vk.DescriptorPoolSize = {
        type            = .SAMPLER,
        descriptorCount = FRAMES_IN_FLIGHT * MAX_SAMPLERS,
    }

    pool_sizes: []vk.DescriptorPoolSize = {sampler_pool_size, image_pool_size}


    pool_info: vk.DescriptorPoolCreateInfo = {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        flags         = {.UPDATE_AFTER_BIND},
        maxSets       = FRAMES_IN_FLIGHT,
        poolSizeCount = u32(len(pool_sizes)),
        pPoolSizes    = raw_data(pool_sizes),
    }

    vk.CreateDescriptorPool(device, &pool_info, nil, &manager.pool) or_return


    counts: [FRAMES_IN_FLIGHT]u32
    for &count in counts {count = MAX_IMAGES}     //count represents the actual amount of space for images allocated less than or equal to descriptorCount
    count_info: vk.DescriptorSetVariableDescriptorCountAllocateInfo = {
        sType              = .DESCRIPTOR_SET_VARIABLE_DESCRIPTOR_COUNT_ALLOCATE_INFO,
        descriptorSetCount = u32(len(counts)),
        pDescriptorCounts  = raw_data(counts[:]),
    }

    layouts: [FRAMES_IN_FLIGHT]vk.DescriptorSetLayout
    for &l in layouts {l = manager.layout}

    alloc_info: vk.DescriptorSetAllocateInfo = {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        pNext              = &count_info,
        descriptorPool     = manager.pool,
        descriptorSetCount = FRAMES_IN_FLIGHT,
        pSetLayouts        = raw_data(layouts[:]),
    }

    vk.AllocateDescriptorSets(
        device,
        &alloc_info,
        raw_data(manager.sets[:]),
    ) or_return


    return
}

destroy_desriptors :: proc(device: vk.Device, manager: Descriptor_Manager) {
    vk.DestroyDescriptorPool(device, manager.pool, nil)
    vk.DestroyDescriptorSetLayout(device, manager.layout, nil)
}

add_sampled_image :: proc(
    device: vk.Device,
    manager: ^Descriptor_Manager,
    state: Render_State,
    view: vk.ImageView,
) {

    image_info: vk.DescriptorImageInfo = {
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
        imageView   = view,
    }

    for set in manager.sets {

        write: vk.WriteDescriptorSet = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = IMAGE_ARRAY_BINDING,
            dstArrayElement = manager.image_count,
            descriptorCount = 1,
            descriptorType  = .SAMPLED_IMAGE,
            pImageInfo      = &image_info,
        }

        vk.UpdateDescriptorSets(device, 1, &write, 0, nil)

    }

    manager.image_count += 1
}

add_sampler :: proc(
    device: vk.Device,
    manager: ^Descriptor_Manager,
    state: Render_State,
    sampler: vk.Sampler,
) {

    image_info: vk.DescriptorImageInfo = {
        sampler = sampler,
    }

    for &set in manager.sets {

        write: vk.WriteDescriptorSet = {
            sType           = .WRITE_DESCRIPTOR_SET,
            dstSet          = set,
            dstBinding      = SAMPLER_ARRAY_BINDING,
            dstArrayElement = manager.sampler_count,
            descriptorCount = 1,
            descriptorType  = .SAMPLER,
            pImageInfo      = &image_info,
        }

        vk.UpdateDescriptorSets(device, 1, &write, 0, nil)
    }

    manager.sampler_count += 1
}

