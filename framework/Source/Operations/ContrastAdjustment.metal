#include <metal_stdlib>
#include "OperationShaderTypes.h"
using namespace metal;

typedef struct
{
    float contrast;
} ContrastUniform;

fragment half4 contrastFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                texture2d<half> inputTexture [[texture(0)]],
                                constant ContrastUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    // photoshop调节对比度的公式 nRGB = RGB + (RGB - Threshold) * Contrast
    // Threshold是平均亮度 默认选0.5
    return half4(((color.rgb + (color.rgb - half3(0.5)) * uniform.contrast)), color.a);
}
