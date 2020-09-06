#include <metal_stdlib>
#include "OperationShaderTypes.h"

using namespace metal;

vertex SingleInputVertexIO oneInputVertex(const device packed_float2 *position [[buffer(0)]],
                                          const device packed_float2 *texturecoord [[buffer(1)]],
                                          uint vid [[vertex_id]])
{
    SingleInputVertexIO outputVertices;
    //vid 坐标对应的索引值
    // position[vid] vid对应的顶底坐标
    // texturecoord[vid] vid对应的纹理顶点坐标
    outputVertices.position = float4(position[vid], 0, 1.0);
    outputVertices.textureCoordinate = texturecoord[vid];
    
    return outputVertices;
}

fragment half4 passthroughFragment(SingleInputVertexIO fragmentInput [[stage_in]],
                                   texture2d<half> inputTexture [[texture(0)]])
{
    constexpr sampler quadSampler;
    //纹理通过采样器、纹理坐标，获得该点的corlor信息
    half4 color = inputTexture.sample(quadSampler, fragmentInput.textureCoordinate);
    
    return color;
}

vertex TwoInputVertexIO twoInputVertex(const device packed_float2 *position [[buffer(0)]],
                                       const device packed_float2 *texturecoord [[buffer(1)]],
                                       const device packed_float2 *texturecoord2 [[buffer(2)]],
                                       uint vid [[vertex_id]])
{
    TwoInputVertexIO outputVertices;
    
    outputVertices.position = float4(position[vid], 0, 1.0);
    outputVertices.textureCoordinate = texturecoord[vid];
    outputVertices.textureCoordinate2 = texturecoord2[vid];

    return outputVertices;
}
