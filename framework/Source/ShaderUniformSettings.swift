import Foundation
import Metal
/// 名字的意思是着色器统一配置，里边存的都是着色器相关的东西，具体在使用shader时，在深入理解比较好，自己打印下内容
/*
 什么是uniform？
 - yuvConversionVideoRangeFragment 中的 YUVConversionUniform
 - thresholdFragment 中的 ThresholdUniform
 - brightnessFragment 中的 BrightnessUniform
 - exposureFragment 中的 ExposureUniform
 - contrastFragment 中的 ContrastUniform
 综上，我们可以推断出，Uniform是用于可控制的，即值可以改变的且存在于Fragment中的变量
 ShaderUniformSettings 就是为了记录以及改变这些变量。
 */
public class ShaderUniformSettings {
    /// 统一值数组
    private var uniformValues:[Float] = []
    /// 统一值偏移量
    /*
     func renderQuad(pipelineState:MTLRenderPipelineState,
     uniformSettings:ShaderUniformSettings? = nil,
     inputTextures:[UInt:Texture],
     useNormalizedTextureCoordinates:Bool = true,
     imageVertices:[Float] = standardImageVertices,
     outputTexture:Texture,
     outputOrientation:ImageOrientation = .portrait)
     */
    /// uniform偏移量 内存对齐
    private var uniformValueOffsets:[Int] = []
    /// 使用使用alpha通道
    public var colorUniformsUseAlpha:Bool = false
    /// 配置着色器统一值时的串行队列
    let shaderUniformSettingsQueue = DispatchQueue(
        label: "com.sunsetlakesoftware.GPUImage.shaderUniformSettings",
        attributes: [])
    /// 统一值的查找表 从着色器中获取，具体查看generate pipline部分 String为uniform变量名，Int为uniform变量对应的索引值
    let uniformLookupTable:[String:Int]
    
    /// 初始化 配置信息
    /// - Parameter uniformLookupTable: 一个字典数组，字典里包括名称+元组，元组中第一个元素是Int类型，第二个是MTLDataType类型
    public init(uniformLookupTable:[String:(Int, MTLDataType)]) {
        var convertedLookupTable:[String:Int] = [:]
        
        var orderedDatatypes = [MTLDataType](repeating:.float, count:uniformLookupTable.count)
        
        for (key, value) in uniformLookupTable {
            let (index, dataType) = value
            convertedLookupTable[key] = index
            orderedDatatypes[index] = dataType
        }
        
        self.uniformLookupTable = convertedLookupTable

        for dataType in orderedDatatypes {
            self.appendBufferSpace(for:dataType)
        }
    }
    /// 是否使用纵横比，意思是锁定比例，然后进行填充
    public var usesAspectRatio:Bool { get { return self.uniformLookupTable["aspectRatio"] != nil } }
    
    /// 根据索引值，获取偏移量对应的内部索引
    /// - Parameter index: 索引值
    /// - Returns: 索引值
    private func internalIndex(for index:Int) -> Int {
        if (index == 0) {
            return 0
        } else {
            return uniformValueOffsets[index - 1]
        }
    }
    
    // MARK: -
    // MARK: Subscript access
    /// 下角标访问，swift特性，可以定义在类（Class）、结构体（structure）和枚举（enumeration）
    /// 此处的根据key值进行读写uniformValues
    public subscript(key:String) -> Float {
        get {
            guard let index = uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
            return uniformValues[internalIndex(for:index)]
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                self.uniformValues[self.internalIndex(for:index)] = newValue
            }
        }
    }
    /// 此处的根据key值进行读写Color
    /// newValue类型与返回值相同
    public subscript(key:String) -> Color {
        get {
            // TODO: Fix this
            return Color(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray:[Float]
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                let startingIndex = self.internalIndex(for:index)
                if self.colorUniformsUseAlpha {
                    floatArray = newValue.toFloatArrayWithAlpha()
                    self.uniformValues[startingIndex] = floatArray[0]
                    self.uniformValues[startingIndex + 1] = floatArray[1]
                    self.uniformValues[startingIndex + 2] = floatArray[2]
                    self.uniformValues[startingIndex + 3] = floatArray[3]
                } else {
                    floatArray = newValue.toFloatArray()
                    self.uniformValues[startingIndex] = floatArray[0]
                    self.uniformValues[startingIndex + 1] = floatArray[1]
                    self.uniformValues[startingIndex + 2] = floatArray[2]
                }
            }
        }
    }
    /// 此处的根据key值进行读写Position，三维
    /// newValue类型与返回值相同
    public subscript(key:String) -> Position {
        get {
            // TODO: Fix this
            return Position(0.0, 0.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                var currentIndex = self.internalIndex(for:index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }
    /// 咦，我似乎明白了，这里写了这么多subscript的操作，而且是针对不同类型的
    /// 意味着 uniformValues 存的就是这些东西
    public subscript(key:String) -> Size {
        get {
            // TODO: Fix this
            return Size(width:0.0, height:0.0)
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                var currentIndex = self.internalIndex(for:index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    public subscript(key:String) -> Matrix3x3 {
        get {
            // TODO: Fix this
            return Matrix3x3.identity
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                var currentIndex = self.internalIndex(for:index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }

    public subscript(key:String) -> Matrix4x4 {
        get {
            // TODO: Fix this
            return Matrix4x4.identity
        }
        set(newValue) {
            shaderUniformSettingsQueue.async {
                let floatArray = newValue.toFloatArray()
                guard let index = self.uniformLookupTable[key] else {fatalError("Tried to access value of missing uniform: \(key), make sure this is present and used in your shader.")}
                var currentIndex = self.internalIndex(for:index)
                for floatValue in floatArray {
                    self.uniformValues[currentIndex] = floatValue
                    currentIndex += 1
                }
            }
        }
    }
    
    // MARK: -
    // MARK: Uniform buffer memory management
    /// buffer内存管理
    
    /// 增加 ？？？
    func appendBufferSpace(for dataType:MTLDataType) {
        let uniformSize:Int
        switch dataType {
            case .float: uniformSize = 1
            case .float2: uniformSize = 2
            case .float3: uniformSize = 4 // Hack to fix alignment issues
            case .float4: uniformSize = 4
            case .float3x3: uniformSize = 12
            case .float4x4: uniformSize = 16
            default: fatalError("Uniform data type of value: \(dataType.rawValue) not supported")
        }
        let blankValues = [Float](repeating:0.0, count:uniformSize)

        let lastOffset = alignPackingForOffset(uniformSize:uniformSize,
                                               lastOffset:uniformValueOffsets.last ?? 0)
        // uniformValues 是所有uniform经过内存对齐后的数据量
        uniformValues.append(contentsOf:blankValues)
        /// uniformValueOffsets 是某个uniform的数据的偏移量，通过偏移量和uniform的数据大小，就可以从uniformValues中取出真正的数据
        uniformValueOffsets.append(lastOffset + uniformSize)
    }
    /// 内存对齐处理
    func alignPackingForOffset(uniformSize:Int, lastOffset:Int) -> Int {
        let floatAlignment = (lastOffset + uniformSize) % 4
        let previousFloatAlignment = lastOffset % 4
        if (uniformSize > 1) && (floatAlignment != 0) && (previousFloatAlignment != 0){
            let paddingToAlignment = 4 - floatAlignment
            uniformValues.append(contentsOf:[Float](repeating:0.0, count:paddingToAlignment))
            uniformValueOffsets[uniformValueOffsets.count - 1] = lastOffset + paddingToAlignment
            return lastOffset + paddingToAlignment
        } else {
            return lastOffset
        }
    }
    /// 恢复设置
    public func restoreShaderSettings(renderEncoder:MTLRenderCommandEncoder) {
        shaderUniformSettingsQueue.sync {
            guard (uniformValues.count > 0) else { return }
            
            let uniformBuffer = sharedMetalRenderingDevice.device.makeBuffer(bytes: uniformValues,
                                                                             length: uniformValues.count * MemoryLayout<Float>.size,
                                                                             options: [])!
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)
        }
    }
}
/// Uniform 转换协议
public protocol UniformConvertible {
    func toFloatArray() -> [Float]
}

extension Float:UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [self]
    }
}

extension Double:UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [Float(self)]
    }
}

extension Color {
    func toFloatArray() -> [Float] {
        return [self.redComponent, self.greenComponent, self.blueComponent, 0.0]
    }

    func toFloatArrayWithAlpha() -> [Float] {
        return [self.redComponent, self.greenComponent, self.blueComponent, self.alphaComponent]
    }
}

extension Position:UniformConvertible {
    public func toFloatArray() -> [Float] {
        if let z = self.z {
            return [self.x, self.y, z, 0.0]
        } else {
            return [self.x, self.y]
        }
    }
}

extension Matrix3x3:UniformConvertible {
    public func toFloatArray() -> [Float] {
        // Row major, with zero-padding
        return [m11, m12, m13, 0.0, m21, m22, m23, 0.0, m31, m32, m33, 0.0]
//        return [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    }
}

extension Matrix4x4:UniformConvertible {
    public func toFloatArray() -> [Float] {
        // Row major
        return [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44]
//        return [m11, m21, m31, m41, m12, m22, m32, m42, m13, m23, m33, m43, m14, m24, m34, m44]
    }
}

extension Size:UniformConvertible {
    public func toFloatArray() -> [Float] {
        return [self.width, self.height]
    }
}

