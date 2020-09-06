#include <metal_stdlib>
using namespace metal;

#ifndef OPERATIONSHADERTYPES_H
#define OPERATIONSHADERTYPES_H

// 亮度常量
constant half3 luminanceWeighting = half3(0.2125, 0.7154, 0.0721);  // Values from "Graphics Shaders: Theory and Practice" by Bailey and Cunningham
// 单输入顶点
struct SingleInputVertexIO
{
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
};
// 双输入顶点
struct TwoInputVertexIO
{
    float4 position [[position]];
    float2 textureCoordinate [[user(texturecoord)]];
    float2 textureCoordinate2 [[user(texturecoord2)]];
};

#endif
