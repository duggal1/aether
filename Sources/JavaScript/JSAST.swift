import Foundation

public enum JSLiteral {
  case number(Double)
  case bigint(String)
  case string(String)
  case bool(Bool)
  case null
  case undefined
  case regex(pattern: String, flags: String)
}

public enum JSVariableKind {
  case varDecl
  case letDecl
  case constDecl
}

public indirect enum JSPattern {
  case identifier(String, JSExpression?)
  case object([(key: String, pattern: JSPattern)], rest: String?)
  case array([JSPattern?], rest: JSPattern?)
  case rest(String)
}

public enum JSArrayElement {
  case value(JSExpression)
  case hole
  case spread(JSExpression)
}

public indirect enum JSObjectMember {
  case property(String, JSExpression)
  case shorthand(String)
  case computed(JSExpression, JSExpression)
  case spread(JSExpression)
  case method(String, [JSPattern], [JSStatement], Bool)
  case getter(String, [JSStatement])
  case setter(String, String, [JSStatement])
}

public indirect enum JSArrowBody {
  case expression(JSExpression)
  case block([JSStatement])
}

public struct JSClassMember {
  public var kind: JSMethodKind
  public var name: String
  public var params: [JSPattern]
  public var body: [JSStatement]
  public var isStatic: Bool
  public var isAsync: Bool
  public var fieldInit: JSExpression?

  public init(
    kind: JSMethodKind, name: String, params: [JSPattern] = [], body: [JSStatement] = [],
    isStatic: Bool = false, isAsync: Bool = false, fieldInit: JSExpression? = nil
  ) {
    self.kind = kind
    self.name = name
    self.params = params
    self.body = body
    self.isStatic = isStatic
    self.isAsync = isAsync
    self.fieldInit = fieldInit
  }
}

public enum JSMethodKind {
  case constructor
  case method
  case getter
  case setter
  case field
}

public struct JSClassDef {
  public var name: String?
  public var superclass: JSExpression?
  public var members: [JSClassMember]

  public init(name: String? = nil, superclass: JSExpression? = nil, members: [JSClassMember] = []) {
    self.name = name
    self.superclass = superclass
    self.members = members
  }
}

public indirect enum JSExpression {
  case literal(JSLiteral)
  case identifier(String)
  case thisExpr
  case superExpr
  case array([JSArrayElement])
  case object([JSObjectMember])
  case unary(String, JSExpression)
  case binary(String, JSExpression, JSExpression)
  case ternary(JSExpression, JSExpression, JSExpression)
  case sequence([JSExpression])
  case assignment(JSExpression, JSExpression)
  case patternAssign(JSPattern, JSExpression)
  case compoundAssignment(String, JSExpression, JSExpression)
  case update(String, JSExpression, Bool)
  case member(JSExpression, String)
  case optionalMember(JSExpression, String)
  case computed(JSExpression, JSExpression)
  case optionalComputed(JSExpression, JSExpression)
  case call(JSExpression, [JSExpression])
  case optionalCall(JSExpression, [JSExpression])
  case newExpr(JSExpression, [JSExpression])
  case function([JSPattern], [JSStatement], Bool)
  case arrow([JSPattern], JSArrowBody, Bool)
  case template([String], [JSExpression])
  case taggedTemplate(JSExpression, [String], [JSExpression])
  case classExpr(JSClassDef)
  case awaitExpr(JSExpression)
  case yieldExpr(JSExpression?)
  case spread(JSExpression)
  case dynamicImport(JSExpression)
}

public enum JSForBinding {
  case declaration(JSVariableKind, JSPattern)
  case expression(JSExpression)
}

public struct JSSwitchCase {
  public var test: JSExpression?
  public var body: [JSStatement]

  public init(test: JSExpression? = nil, body: [JSStatement] = []) {
    self.test = test
    self.body = body
  }
}

public enum JSImportSpecifier {
  case `default`(String)
  case named(imported: String, local: String)
  case namespace(String)
}

public indirect enum JSExport {
  case declaration(JSStatement)
  case named([(exported: String, local: String)])
  case all(from: String?)
  case defaultExpr(JSExpression)
}

public indirect enum JSStatement {
  case variable(JSVariableKind, [(JSPattern, JSExpression?)])
  case expression(JSExpression)
  case function(String?, [JSPattern], [JSStatement], Bool)
  case returnValue(JSExpression?)
  case block([JSStatement])
  case conditional(JSExpression, JSStatement, JSStatement?)
  case whileLoop(JSExpression, JSStatement)
  case doWhile(JSStatement, JSExpression)
  case forLoop(JSStatement?, JSExpression?, JSExpression?, JSStatement)
  case forIn(JSForBinding, JSExpression, JSStatement)
  case forOf(JSForBinding, JSExpression, JSStatement)
  case breakStmt(String?)
  case continueStmt(String?)
  case throwStmt(JSExpression)
  case tryStmt([JSStatement], JSPattern?, [JSStatement]?, [JSStatement]?)
  case switchStmt(JSExpression, [JSSwitchCase])
  case labeled(String, JSStatement)
  case debuggerStmt
  case classDecl(String?, JSClassDef)
  case importDecl([JSImportSpecifier], String)
  case exportDecl(JSExport)
}
