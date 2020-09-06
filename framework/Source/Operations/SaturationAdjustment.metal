#include <metal_stdlib>
#include "OperationShaderTypes.h"
using namespace metal;

typedef struct
{
    float saturation;
} SaturationUniform;
//饱和度调整
fragment half4 saturationFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                texture2d<half> inputTexture [[texture(0)]],
                                constant SaturationUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);

    half luminance = dot(color.rgb, luminanceWeighting);
    //将值限制在两个其他值之间并做融合，常用于颜色混合：
    //mix(x,y,a)   =  x*(1-a)+y*a
    return half4(mix(half3(luminance), color.rgb, half(uniform.saturation)), color.a);
}
