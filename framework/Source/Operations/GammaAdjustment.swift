//伽玛滤镜 让rbg信息呈现非线性增长 里边是指数函数
public class GammaAdjustment: BasicOperation {
    public var gamma:Float = 1.0 { didSet { uniformSettings["gamma"] = gamma } }
    
    public init() {
        super.init(fragmentFunctionName:"gammaFragment", numberOfInputs:1)
        
        ({gamma = 1.0})()
    }
}
