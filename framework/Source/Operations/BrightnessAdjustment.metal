#include <metal_stdlib>
#include "OperationShaderTypes.h"

using namespace metal;

typedef struct
{
    float brightness;
} BrightnessUniform;

//亮度调整滤镜 brightness是会发生变化的
fragment half4 brightnessFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  constant BrightnessUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    
    return half4(color.rgb + uniform.brightness, color.a);
}
