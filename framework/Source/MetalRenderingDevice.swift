import Foundation
import Metal
import MetalPerformanceShaders

public let sharedMetalRenderingDevice = MetalRenderingDevice()
/// 设备Device，使用一个全局变量，防止多次初始化产生额外开销
public class MetalRenderingDevice {
    // MTLDevice
    // MTLCommandQueue
    
    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue
    public let shaderLibrary: MTLLibrary
    public let metalPerformanceShadersAreSupported: Bool
    
    /// 提供的简单叠加的渲染管线，省去自己生成的步骤，支持一个顶点输入，具体的，可以看着色器
    lazy var passthroughRenderState: MTLRenderPipelineState = {
        let (pipelineState, _) = generateRenderPipelineState(device:self, vertexFunctionName:"oneInputVertex", fragmentFunctionName:"passthroughFragment", operationName:"Passthrough")
        return pipelineState
    }()
    
    /// 提供的颜色混合渲染管线，省去自己生成的步骤，支持一个顶点输入，具体的，可以看着色器
    lazy var colorSwizzleRenderState: MTLRenderPipelineState = {
        let (pipelineState, _) = generateRenderPipelineState(device:self, vertexFunctionName:"oneInputVertex", fragmentFunctionName:"colorSwizzleFragment", operationName:"ColorSwizzle")
        return pipelineState
    }()
/// 初始化一些常用资源
    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {fatalError("Could not create Metal Device")}
        self.device = device
        
        guard let queue = self.device.makeCommandQueue() else {fatalError("Could not create command queue")}
        self.commandQueue = queue
        
        if #available(iOS 9, macOS 10.13, *) {
            self.metalPerformanceShadersAreSupported = MPSSupportsMTLDevice(device)
        } else {
            self.metalPerformanceShadersAreSupported = false
        }
        
        do {
            let frameworkBundle = Bundle(for: MetalRenderingDevice.self)
            let metalLibraryPath = frameworkBundle.path(forResource: "default", ofType: "metallib")!
            
            self.shaderLibrary = try device.makeLibrary(filepath:metalLibraryPath)
        } catch {
            fatalError("Could not load library")
        }
    }
}
