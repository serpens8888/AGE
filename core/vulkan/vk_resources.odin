package vulk

import vk "vendor:vulkan"
import "vma"
import "core:os"

@(require_results)
create_pipeline_layout :: proc(
    device: vk.Device,
    layouts: []vk.DescriptorSetLayout,
    ranges: []vk.PushConstantRange
) -> (layout: vk.PipelineLayout, err: Error){
    
    create_info: vk.PipelineLayoutCreateInfo = {
        sType = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount = u32(len(layouts)),
        pSetLayouts = raw_data(layouts),
        pushConstantRangeCount = u32(len(ranges)),
        pPushConstantRanges = raw_data(ranges),
    }

    check_vk(vk.CreatePipelineLayout(device, &create_info, nil, &layout)) or_return

    return
}







