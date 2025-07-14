package vulk

import "core:os"
import vk "vendor:vulkan"
import "vma"

Push_Constant_Data :: struct {
    color: vk.DeviceAddress, //8 byte pointer to a Color
}

create_shader_module :: proc(
    device: vk.Device,
    shader_path: string,
) -> (
    mod: vk.ShaderModule,
    err: Error,
) {

    code, read_err := os.read_entire_file_or_err(shader_path)
    assert(read_err == nil)
    defer delete(code)

    create_info: vk.ShaderModuleCreateInfo = {
        sType    = .SHADER_MODULE_CREATE_INFO,
        codeSize = len(code),
        pCode    = (^u32)(raw_data(code)),
    }

    check_vk(vk.CreateShaderModule(device, &create_info, nil, &mod)) or_return

    return
}



create_graphics_pipeline :: proc(
    device: vk.Device,
    graphics_mod: Graphics_Module,
    layout: vk.PipelineLayout,
    shader_mod: vk.ShaderModule,
) -> (
    pipeline: vk.Pipeline,
    err: Error,
) {

    vert_stage: vk.PipelineShaderStageCreateInfo = {
        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage  = {.VERTEX},
        module = shader_mod,
        pName  = "vertexMain",
    }

    frag_stage: vk.PipelineShaderStageCreateInfo = {
        sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
        stage  = {.FRAGMENT},
        module = shader_mod,
        pName  = "fragmentMain",
    }

    stages: []vk.PipelineShaderStageCreateInfo = {vert_stage, frag_stage}


    vertex_bindings: []vk.VertexInputBindingDescription = {get_binding_desc()}

    vertex_attruibutes: []vk.VertexInputAttributeDescription = {
        get_pos_attr_desc(),
        get_norm_attr_desc(),
        get_col_attr_desc(),
        get_uv_attr_desc(),
    }

    vertex_input: vk.PipelineVertexInputStateCreateInfo = {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = u32(len(vertex_bindings)),
        pVertexBindingDescriptions      = raw_data(vertex_bindings),
        vertexAttributeDescriptionCount = u32(len(vertex_attruibutes)),
        pVertexAttributeDescriptions    = raw_data(vertex_attruibutes),
    }


    input_assembly: vk.PipelineInputAssemblyStateCreateInfo = {
        sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology               = .TRIANGLE_LIST,
        primitiveRestartEnable = false,
    }

    //tesselation:  VkPipelineTessellationStateCreateInfo = {}

    viewport: vk.Viewport = {
        x        = 0.0,
        y        = 0.0,
        width    = f32(graphics_mod.swapchain.extent.width),
        height   = f32(graphics_mod.swapchain.extent.height),
        minDepth = 0.0,
        maxDepth = 1.0,
    }

    scissor: vk.Rect2D = {
        offset = {x = 0, y = 0},
        extent = {
            width = graphics_mod.swapchain.extent.width,
            height = graphics_mod.swapchain.extent.height,
        },
    }

    viewport_state: vk.PipelineViewportStateCreateInfo = {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        pViewports    = &viewport,
        scissorCount  = 1,
        pScissors     = &scissor,
    }

    rasterizer: vk.PipelineRasterizationStateCreateInfo = {
        sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        depthClampEnable        = false,
        rasterizerDiscardEnable = false,
        polygonMode             = .FILL,
        lineWidth               = 1.0,
        cullMode                = vk.CullModeFlags_NONE,
        frontFace               = .CLOCKWISE,
        depthBiasEnable         = false,
    }

    multisampling: vk.PipelineMultisampleStateCreateInfo = {
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        sampleShadingEnable  = false,
        rasterizationSamples = {._1},
    }

    depth_stencil: vk.PipelineDepthStencilStateCreateInfo = {
        sType                 = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable       = false,
        depthWriteEnable      = false,
        depthCompareOp        = .LESS,
        depthBoundsTestEnable = false,
        stencilTestEnable     = false,
    }

    attachment: vk.PipelineColorBlendAttachmentState = {
        // I SPEND 2 DAYS DEBUGGING BECAUSE I FORGOT TO ADD THIS ADJHASKDJAHSDKJASDHAKSJ 
        //RAAJHAJAJAAFSDLKFJSDL:KJFJSDL:FKJHDSFKLJSDHFLKJADSHDFKASHJFGADKHJFghdslkghjdfsbkjghlasdhf
        //GREEHAGAAGAAAAAAAAAAAAAAAAAAAAAAAGGGGGAGHGHGHGHGHGHGHHGGHGUHGUAHGUAHGAIUHSGKJASHR
        colorWriteMask      = {.R, .G, .B, .A}, //guh
        blendEnable         = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ZERO,
        alphaBlendOp        = .ADD,
    }

    color_blend: vk.PipelineColorBlendStateCreateInfo = {
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        logicOpEnable   = false,
        attachmentCount = 1,
        pAttachments    = &attachment,
    }

    dynamic_states: []vk.DynamicState = {.VIEWPORT, .SCISSOR}
    dynamic_state: vk.PipelineDynamicStateCreateInfo = {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = raw_data(dynamic_states),
    }

    color_format := graphics_mod.swapchain.format

    rendering_info: vk.PipelineRenderingCreateInfo = {
        sType                   = .PIPELINE_RENDERING_CREATE_INFO,
        colorAttachmentCount    = 1,
        pColorAttachmentFormats = &color_format,
    }


    pipeline_info: vk.GraphicsPipelineCreateInfo = {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        pNext               = &rendering_info,
        stageCount          = 2,
        pStages             = raw_data(stages),
        pVertexInputState   = &vertex_input,
        pInputAssemblyState = &input_assembly,
        //pTessellationState = &tesselation_state,
        pViewportState      = &viewport_state,
        pRasterizationState = &rasterizer,
        pMultisampleState   = &multisampling,
        pDepthStencilState  = &depth_stencil,
        pColorBlendState    = &color_blend,
        pDynamicState       = &dynamic_state,
        layout              = layout,
    }

    check_vk(
        vk.CreateGraphicsPipelines(
            device,
            0,
            1,
            &pipeline_info,
            nil,
            &pipeline,
        ),
    ) or_return


    return
}

@(require_results)
create_pipeline_layout :: proc(
    device: vk.Device,
    layouts: []vk.DescriptorSetLayout,
    ranges: []vk.PushConstantRange,
) -> (
    layout: vk.PipelineLayout,
    err: Error,
) {

    create_info: vk.PipelineLayoutCreateInfo = {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        setLayoutCount         = u32(len(layouts)),
        pSetLayouts            = raw_data(layouts),
        pushConstantRangeCount = u32(len(ranges)),
        pPushConstantRanges    = raw_data(ranges),
    }

    check_vk(
        vk.CreatePipelineLayout(device, &create_info, nil, &layout),
    ) or_return

    return
}

