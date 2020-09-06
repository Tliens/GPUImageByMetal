/*
 For a complete explanation behind the math of this shader, read this blog post:
 http://redqueengraphics.com/2018/07/26/metal-shaders-luminance/
 */

#include <metal_stdlib>
#include "OperationShaderTypes.h"
using namespace metal;

fragment half4 luminanceFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    //dot 两个数组点积、点乘 [1,2,3]·[4,5,6] = 1*1 + 2*3 + 3*6 = 1+6+18 = 25
    //luminanceWeighting为亮度常量
    half luminance = dot(color.rgb, luminanceWeighting);
    
    return half4(half3(luminance), color.a);
}
