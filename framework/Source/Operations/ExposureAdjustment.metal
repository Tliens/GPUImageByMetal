#include <metal_stdlib>
#include "OperationShaderTypes.h"
using namespace metal;

typedef struct
{
    float exposure;
} ExposureUniform;
// 曝光
fragment half4 exposureFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                  texture2d<half> inputTexture [[texture(0)]],
                                  constant ExposureUniform& uniform [[ buffer(1) ]])
{
    constexpr sampler quadSampler;
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    // pow(x,y) x的y次方
    return half4((color.rgb * pow(2.0, uniform.exposure)), color.a);
}
