/// 自定义宽高结构，还好有命名空间，不然这样的名字要出问题，不建议这样命名
/// 还记得NSOperation吗？如果之前你自定义一个Operation，那么就和现在的官方冲突了
public struct Size {
    public let width:Float
    public let height:Float
    
    public init(width:Float, height:Float) {
        self.width = width
        self.height = height
    }
}
