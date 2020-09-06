/// 颜色翻转滤镜
public class ColorInversion: BasicOperation {
    public init() {
        super.init(fragmentFunctionName:"colorInversionFragment", numberOfInputs:1)
    }
}
