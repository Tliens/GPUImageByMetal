import Foundation
import Metal
/// 顶点输入VertexFunctionName
public func defaultVertexFunctionNameForInputs(_ inputCount:UInt) -> String {
    switch inputCount {
    case 1:
        return "oneInputVertex"
    case 2:
        return "twoInputVertex"
    default:
        return "oneInputVertex"
    }
}
/// 基础操作，中间层父类
open class BasicOperation: ImageProcessingOperation {
    /// 最大输入数量
    public let maximumInputs: UInt
    /// 目标容器
    public let targets = TargetContainer()
    /// 输入容器
    public let sources = SourceContainer()
    /// 激活下一帧的透传
    public var activatePassthroughOnNextFrame: Bool = false
    /// uniform管理器
    public var uniformSettings:ShaderUniformSettings
    /// 是否使用 metalshader
    public var useMetalPerformanceShaders: Bool = false {
        didSet {
            if !sharedMetalRenderingDevice.metalPerformanceShadersAreSupported {
                print("Warning: Metal Performance Shaders are not supported on this device")
                useMetalPerformanceShaders = false
            }
        }
    }
    /// 渲染管线
    let renderPipelineState: MTLRenderPipelineState
    /// 操作名称
    let operationName: String
    /// 输入的纹理们 key：第几个源传递过来，value：Texture
    var inputTextures = [UInt:Texture]()
    /// 信号量控制
    let textureInputSemaphore = DispatchSemaphore(value:1)
    /// 是否使用归一化纹理坐标
    var useNormalizedTextureCoordinates = true
    /// 命令编码 输入的inputTextures 输出的Texture
    var metalPerformanceShaderPathway: ((MTLCommandBuffer, [UInt:Texture], Texture) -> ())?

    public init(vertexFunctionName: String? = nil, fragmentFunctionName: String, numberOfInputs: UInt = 1, operationName: String = #file) {
        self.maximumInputs = numberOfInputs
        self.operationName = operationName
        
        let concreteVertexFunctionName = vertexFunctionName ?? defaultVertexFunctionNameForInputs(numberOfInputs)
        let (pipelineState, lookupTable) = generateRenderPipelineState(device:sharedMetalRenderingDevice, vertexFunctionName:concreteVertexFunctionName, fragmentFunctionName:fragmentFunctionName, operationName:operationName)
        self.renderPipelineState = pipelineState
        self.uniformSettings = ShaderUniformSettings(uniformLookupTable:lookupTable)
    }
    /// 把当前存在的纹理传给目标，atIndex表示指定，如：有新的target时
    public func transmitPreviousImage(to target: ImageConsumer, atIndex: UInt) {
        // TODO: Finish implementation later
    }
    /// 传来了新的纹理
    public func newTextureAvailable(_ texture: Texture, fromSourceIndex: UInt) {
        let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
        defer {
            textureInputSemaphore.signal()
        }
        // 记录
        inputTextures[fromSourceIndex] = texture
        
        /// 如果输入的纹理数量大于maximumInputs 或者 激活 PassthroughOnNextFrame
        if (UInt(inputTextures.count) >= maximumInputs) || activatePassthroughOnNextFrame {
            let outputWidth:Int
            let outputHeight:Int
            
            let firstInputTexture = inputTextures[0]!
            if firstInputTexture.orientation.rotationNeeded(for:.portrait).flipsDimensions() {
                outputWidth = firstInputTexture.texture.height
                outputHeight = firstInputTexture.texture.width
            } else {
                outputWidth = firstInputTexture.texture.width
                outputHeight = firstInputTexture.texture.height
            }

            if uniformSettings.usesAspectRatio {
                let outputRotation = firstInputTexture.orientation.rotationNeeded(for:.portrait)
                uniformSettings["aspectRatio"] = firstInputTexture.aspectRatio(for: outputRotation)
            }
            
            guard let commandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else {return}

            let outputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation: .portrait, width: outputWidth, height: outputHeight, timingStyle: firstInputTexture.timingStyle)
            
            guard (!activatePassthroughOnNextFrame) else { // Use this to allow a bootstrap of cyclical processing, like with a low pass filter
                activatePassthroughOnNextFrame = false
                // TODO: Render rotated passthrough image here
                /// 移出 videoFrame 类型的纹理
                removeTransientInputs()
                textureInputSemaphore.signal()
                // 分发纹理
                updateTargetsWithTexture(outputTexture)
                let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)

                return
            }
            
            if let alternateRenderingFunction = metalPerformanceShaderPathway, useMetalPerformanceShaders {
                var rotatedInputTextures: [UInt:Texture]
                if (firstInputTexture.orientation.rotationNeeded(for:.portrait) != .noRotation) {
                    let rotationOutputTexture = Texture(device:sharedMetalRenderingDevice.device, orientation: .portrait, width: outputWidth, height: outputHeight)
                    guard let rotationCommandBuffer = sharedMetalRenderingDevice.commandQueue.makeCommandBuffer() else {return}
                    rotationCommandBuffer.renderQuad(pipelineState: sharedMetalRenderingDevice.passthroughRenderState, uniformSettings: uniformSettings, inputTextures: inputTextures, useNormalizedTextureCoordinates: useNormalizedTextureCoordinates, outputTexture: rotationOutputTexture)
                    rotationCommandBuffer.commit()
                    rotatedInputTextures = inputTextures
                    rotatedInputTextures[0] = rotationOutputTexture
                } else {
                    rotatedInputTextures = inputTextures
                }
                alternateRenderingFunction(commandBuffer, rotatedInputTextures, outputTexture)
            } else {
                internalRenderFunction(commandBuffer: commandBuffer, outputTexture: outputTexture)
            }
            commandBuffer.commit()
            
            removeTransientInputs()
            textureInputSemaphore.signal()
            updateTargetsWithTexture(outputTexture)
            let _ = textureInputSemaphore.wait(timeout:DispatchTime.distantFuture)
        }
    }
    /// 移出视音频帧
    func removeTransientInputs() {
        for index in 0..<self.maximumInputs {
            if let texture = inputTextures[index], texture.timingStyle.isTransient() {
                inputTextures[index] = nil
            }
        }
    }
    /// 内部提交渲染指令
    func internalRenderFunction(commandBuffer: MTLCommandBuffer, outputTexture: Texture) {
        commandBuffer.renderQuad(pipelineState: renderPipelineState, uniformSettings: uniformSettings, inputTextures: inputTextures, useNormalizedTextureCoordinates: useNormalizedTextureCoordinates, outputTexture: outputTexture)
    }
}
