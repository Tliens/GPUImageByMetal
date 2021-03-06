import Metal

/// 不同格式的YUV转RGB的矩阵

// BT.601, which is the standard for SDTV.
public let colorConversionMatrix601Default = Matrix3x3(rowMajorValues:[
    1.164,  1.164, 1.164,
    0.0, -0.392, 2.017,
    1.596, -0.813,   0.0
])

// BT.601 full range (ref: http://www.equasys.de/colorconversion.html)
public let colorConversionMatrix601FullRangeDefault = Matrix3x3(rowMajorValues:[
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
])

// BT.709, which is the standard for HDTV.
public let colorConversionMatrix709Default = Matrix3x3(rowMajorValues:[
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
])

/// YUV转RGB，Metal中处理的是rbg
///  - Parameter pipelineState 渲染管线状态
/// - Parameter lookupTable 渲染shader的信息
/// - Parameter luminanceTexture 亮度纹理
/// - Parameter chrominanceTexture 彩色纹理
/// - Parameter secondChrominanceTexture 第二个色度纹理
/// - Parameter resultTexture结果纹理
/// - Parameter colorConversionMatrix颜色转换矩阵

/*
 po lookupTable
 ▿ 1 element
   ▿ 0 : 2 elements
     - key : "colorConversionMatrix"
     ▿ value : 2 elements
       - .0 : 0
       - .1 : __C.MTLDataType
 */
public func convertYUVToRGB(pipelineState:MTLRenderPipelineState, lookupTable:[String:(Int, MTLDataType)], luminanceTexture:Texture, chrominanceTexture:Texture, secondChrominanceTexture:Texture? = nil, resultTexture:Texture, colorConversionMatrix:Matrix3x3) {
    let uniformSettings = ShaderUniformSettings(uniformLookupTable:lookupTable)
    uniformSettings["colorConversionMatrix"] = colorConversionMatrix
    
    guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else {return}
    
    let inputTextures:[UInt:Texture]
    if let secondChrominanceTexture = secondChrominanceTexture {
        inputTextures = [0:luminanceTexture, 1:chrominanceTexture, 2:secondChrominanceTexture]
    } else {
        inputTextures = [0:luminanceTexture, 1:chrominanceTexture]
    }
    
    commandBuffer.renderQuad(pipelineState:pipelineState, uniformSettings:uniformSettings, inputTextures:inputTextures, useNormalizedTextureCoordinates:true, outputTexture:resultTexture)
    commandBuffer.commit()
}
