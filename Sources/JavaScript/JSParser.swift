import Foundation

public final class JSParser {
  private let tokens: [JSToken]
  private var current = 0
  private var allowIn = true

  public init(source: String) throws {
    tokens = try JSLexer.tokenize(source)
  }

  public func parseProgram() throws -> [JSStatement] {
    var statements: [JSStatement] = []
    while !isAtEnd { statements.append(try declaration()) }
    return statements
  }

  private func declaration() throws -> JSStatement {
    if checkKeyword("async") && peekNextIsKeyword("function") && !peekNextHasLineBreak() {
      advance()
      advance()
      return try functionDeclaration(isAsync: true)
    }
    if matchKeyword("function") { return try functionDeclaration(isAsync: false) }
    if matchKeyword("class") { return try classDeclaration() }
    if checkKeyword("import") && !peekNextIsSymbol("(") {
      advance()
      return try importDeclaration()
    }
    if matchKeyword("export") { return try exportDeclaration() }
    if checkKeyword("let") {
      let saved = current
      advance()
      if checkSymbol("{") || checkSymbol("[") {
        current = saved
        return try variableDeclaration()
      }
      if case .identifier = peek.kind {
        advance()
        if checkKeyword("in") || checkKeyword("of") || checkSymbol("=") || checkSymbol(";")
          || checkSymbol(",") || checkSymbol("]")
        {
          current = saved
          return try variableDeclaration()
        }
        current = saved
        return try statement()
      }
      current = saved
      return try statement()
    }
    if checkKeyword("const") || checkKeyword("var") { return try variableDeclaration() }
    return try statement()
  }

  private func variableDeclaration() throws -> JSStatement {
    let kind: JSVariableKind
    if matchKeyword("let") { kind = .letDecl } else if matchKeyword("const") { kind = .constDecl }
    else if matchKeyword("var") { kind = .varDecl } else {
      throw JSError.syntax("Expected declaration at \(peek.offset)")
    }
    var declarators: [(JSPattern, JSExpression?)] = []
    repeat {
      let pattern = try parsePattern(allowDefault: false)
      var initializer: JSExpression?
      if matchSymbol("=") { initializer = try assignment() }
      declarators.append((pattern, initializer))
    } while matchSymbol(",")
    try consumeTerminator()
    return .variable(kind, declarators)
  }

  private func functionDeclaration(isAsync: Bool) throws -> JSStatement {
    if matchSymbol("*") { throw JSError.syntax("Generators are not yet supported") }
    guard let name = optionalName() else {
      throw JSError.syntax("Expected function name at \(peek.offset)")
    }
    let (params, body) = try functionSignatureAndBody()
    return .function(name, params, body, isAsync)
  }

  private func classDeclaration() throws -> JSStatement {
    let def = try classDef()
    return .classDecl(def.name, def)
  }

  private func classDef() throws -> JSClassDef {
    var name: String?
    if case .identifier(let value) = peek.kind {
      advance()
      name = value
    }
    var superclass: JSExpression?
    if matchKeyword("extends") {
      superclass = try assignment()
    }
    try consumeSymbol("{", "Expected '{' for class body")
    var members: [JSClassMember] = []
    while !checkSymbol("}") && !isAtEnd {
      if let member = try classMember() { members.append(member) }
    }
    try consumeSymbol("}", "Expected '}' for class body")
    return JSClassDef(name: name, superclass: superclass, members: members)
  }

  private func classMember() throws -> JSClassMember? {
    if matchSymbol(";") { return nil }
    var isStatic = false
    var isAsync = false
    if checkIdentifier("static") && !peekNextIsSymbol("(") {
      advance()
      isStatic = true
    }
    if checkKeyword("async") && !peekNextHasLineBreak() && !peekNextIsSymbol("(")
      && !peekNextIsSymbol(";") && !peekNextIsSymbol("}") && !peekNextIsSymbol("=")
    {
      advance()
      isAsync = true
    }
    if matchSymbol("*") { throw JSError.syntax("Generators are not yet supported") }
    if checkIdentifier("get") && peekNextIsPropertyName() {
      advance()
      let name = try propertyName()
      try consumeSymbol("(", "Expected '(' after getter")
      try consumeSymbol(")", "Expected ')' after getter")
      try consumeSymbol("{", "Expected '{' for getter body")
      return JSClassMember(kind: .getter, name: name, body: try block(), isStatic: isStatic)
    }
    if checkIdentifier("set") && peekNextIsPropertyName() {
      advance()
      let name = try propertyName()
      try consumeSymbol("(", "Expected '(' after setter")
      let param = try consumeIdentifier("Expected setter parameter")
      try consumeSymbol(")", "Expected ')' after setter parameter")
      try consumeSymbol("{", "Expected '{' for setter body")
      let pattern = JSPattern.identifier(param, nil)
      return JSClassMember(
        kind: .setter, name: name, params: [pattern], body: try block(), isStatic: isStatic)
    }
    if case .identifier(let name) = peek.kind, name.hasPrefix("#") {
      throw JSError.syntax("Private class members are not yet supported")
    }
    let name = try propertyName()
    if matchSymbol("=") {
      let value = try assignment()
      try consumeTerminator()
      return JSClassMember(kind: .field, name: name, isStatic: isStatic, fieldInit: value)
    }
    if checkSymbol("(") {
      let (params, body) = try functionSignatureAndBody()
      let kind: JSMethodKind = name == "constructor" && !isStatic ? .constructor : .method
      return JSClassMember(kind: kind, name: name, params: params, body: body, isStatic: isStatic,
        isAsync: isAsync)
    }
    if checkSymbol(";") {
      advance()
      return JSClassMember(kind: .field, name: name, isStatic: isStatic)
    }
    throw JSError.syntax("Expected class member at \(peek.offset)")
  }

  private func importDeclaration() throws -> JSStatement {
    var specifiers: [JSImportSpecifier] = []
    if case .string(let path) = peek.kind {
      advance()
      return .importDecl(specifiers, path)
    }
    if matchSymbol("*") {
      try consumeKeyword("as", "Expected 'as' after '*'")
      specifiers.append(.namespace(try consumeIdentifier("Expected namespace name")))
    } else if case .identifier(let name) = peek.kind, !isSpecifierBraceAhead() {
      advance()
      specifiers.append(.default(name))
      if matchSymbol(",") {
        if matchSymbol("*") {
          try consumeKeyword("as", "Expected 'as' after '*'")
          specifiers.append(.namespace(try consumeIdentifier("Expected namespace name")))
        } else if checkSymbol("{") {
          try importNamed(into: &specifiers)
        }
      }
    } else if checkSymbol("{") {
      try importNamed(into: &specifiers)
    } else {
      throw JSError.syntax("Expected import specifier at \(peek.offset)")
    }
    try consumeKeyword("from", "Expected 'from' in import")
    guard case .string(let path) = peek.kind else {
      throw JSError.syntax("Expected module path at \(peek.offset)")
    }
    advance()
    try consumeTerminator()
    return .importDecl(specifiers, path)
  }

  private func isSpecifierBraceAhead() -> Bool { checkSymbol("{") }

  private func importNamed(into specifiers: inout [JSImportSpecifier]) throws {
    try consumeSymbol("{", "Expected '{' for named imports")
    while !checkSymbol("}") && !isAtEnd {
      let first = try contextualIdentifier("Expected import name")
      var imported = first
      var local = first
      if matchKeyword("as") {
        local = try contextualIdentifier("Expected local name")
      }
      specifiers.append(.named(imported: imported, local: local))
      if !matchSymbol(",") { break }
    }
    try consumeSymbol("}", "Expected '}' for named imports")
  }

  private func exportDeclaration() throws -> JSStatement {
    if matchKeyword("default") {
      if matchKeyword("function") {
        let hasStar = matchSymbol("*")
        if hasStar { throw JSError.syntax("Generators are not yet supported") }
        let name = optionalName()
        let (params, body) = try functionSignatureAndBody()
        return .exportDecl(.declaration(.function(name, params, body, false)))
      }
      if matchKeyword("class") {
        let def = try classDef()
        return .exportDecl(.declaration(.classDecl(def.name, def)))
      }
      if checkKeyword("async") && peekNextIsKeyword("function") {
        advance()
        _ = matchKeyword("function")
        let hasStar = matchSymbol("*")
        if hasStar { throw JSError.syntax("Generators are not yet supported") }
        let name = optionalName()
        let (params, body) = try functionSignatureAndBody()
        return .exportDecl(.declaration(.function(name, params, body, true)))
      }
      let value = try assignment()
      try consumeTerminator()
      return .exportDecl(.defaultExpr(value))
    }
    if matchSymbol("*") {
      if matchKeyword("from") {
        guard case .string(let path) = peek.kind else {
          throw JSError.syntax("Expected module path at \(peek.offset)")
        }
        advance()
        try consumeTerminator()
        return .exportDecl(.all(from: path))
      }
      throw JSError.syntax("Expected 'from' after '*' at \(peek.offset)")
    }
    if checkSymbol("{") {
      advance()
      var pairs: [(exported: String, local: String)] = []
      while !checkSymbol("}") && !isAtEnd {
        let local = try contextualIdentifier("Expected export name")
        var exported = local
        if matchKeyword("as") { exported = try contextualIdentifier("Expected export alias") }
        pairs.append((exported: exported, local: local))
        if !matchSymbol(",") { break }
      }
      try consumeSymbol("}", "Expected '}' for named exports")
      try consumeTerminator()
      return .exportDecl(.named(pairs))
    }
    let decl = try declaration()
    return .exportDecl(.declaration(decl))
  }

  private func statement() throws -> JSStatement {
    if matchKeyword("debugger") {
      try consumeTerminator()
      return .debuggerStmt
    }
    if matchKeyword("return") {
      if checkSymbol(";") {
        advance()
        return .returnValue(nil)
      }
      if checkSymbol("}") || isAtEnd || peek.lineTerminatorBefore {
        return .returnValue(nil)
      }
      let value = try expression()
      try consumeTerminator()
      return .returnValue(value)
    }
    if matchKeyword("throw") {
      if peek.lineTerminatorBefore {
        throw JSError.syntax("Illegal newline after throw at \(peek.offset)")
      }
      let value = try expression()
      try consumeTerminator()
      return .throwStmt(value)
    }
    if matchKeyword("if") {
      try consumeSymbol("(", "Expected '(' after if")
      let condition = try expression()
      try consumeSymbol(")", "Expected ')' after condition")
      let thenBranch = try statement()
      let elseBranch = matchKeyword("else") ? try statement() : nil
      return .conditional(condition, thenBranch, elseBranch)
    }
    if matchKeyword("while") {
      try consumeSymbol("(", "Expected '(' after while")
      let condition = try expression()
      try consumeSymbol(")", "Expected ')' after condition")
      return .whileLoop(condition, try statement())
    }
    if matchKeyword("do") {
      let body = try statement()
      try consumeKeyword("while", "Expected 'while' after do")
      try consumeSymbol("(", "Expected '(' after while")
      let condition = try expression()
      try consumeSymbol(")", "Expected ')' after condition")
      _ = matchSymbol(";")
      return .doWhile(body, condition)
    }
    if matchKeyword("for") { return try forStatement() }
    if matchKeyword("break") {
      var label: String?
      if case .identifier(let name) = peek.kind, !peek.lineTerminatorBefore {
        advance()
        label = name
      }
      try consumeTerminator()
      return .breakStmt(label)
    }
    if matchKeyword("continue") {
      var label: String?
      if case .identifier(let name) = peek.kind, !peek.lineTerminatorBefore {
        advance()
        label = name
      }
      try consumeTerminator()
      return .continueStmt(label)
    }
    if matchKeyword("switch") {
      try consumeSymbol("(", "Expected '(' after switch")
      let value = try expression()
      try consumeSymbol(")", "Expected ')' after switch value")
      try consumeSymbol("{", "Expected '{' for switch body")
      var cases: [JSSwitchCase] = []
      while !checkSymbol("}") && !isAtEnd {
        if matchKeyword("case") {
          let test = try expression()
          try consumeSymbol(":", "Expected ':' after case")
          var body: [JSStatement] = []
          while !checkSymbol("}") && !isAtEnd && !checkKeyword("case")
            && !checkKeyword("default")
          {
            body.append(try declaration())
          }
          cases.append(JSSwitchCase(test: test, body: body))
        } else if matchKeyword("default") {
          try consumeSymbol(":", "Expected ':' after default")
          var body: [JSStatement] = []
          while !checkSymbol("}") && !isAtEnd && !checkKeyword("case")
            && !checkKeyword("default")
          {
            body.append(try declaration())
          }
          cases.append(JSSwitchCase(test: nil, body: body))
        } else {
          throw JSError.syntax("Expected case or default at \(peek.offset)")
        }
      }
      try consumeSymbol("}", "Expected '}' for switch body")
      return .switchStmt(value, cases)
    }
    if matchKeyword("try") { return try tryStatement() }
    if matchKeyword("with") {
      throw JSError.syntax("The with statement is not supported")
    }
    if matchSymbol("{") { return .block(try block()) }
    if matchSymbol(";") { return .expression(.literal(.undefined)) }
    if case .identifier(let name) = peek.kind, peekNextIsSymbol(":") {
      advance()
      advance()
      return .labeled(name, try statement())
    }
    let value = try expression()
    try consumeTerminator()
    return .expression(value)
  }

  private func tryStatement() throws -> JSStatement {
    try consumeSymbol("{", "Expected '{' after try")
    let body = try block()
    var catchPattern: JSPattern?
    var catchBody: [JSStatement]?
    if matchKeyword("catch") {
      if matchSymbol("(") {
        catchPattern = try parsePattern()
        try consumeSymbol(")", "Expected ')' after catch parameter")
      }
      try consumeSymbol("{", "Expected '{' after catch")
      catchBody = try block()
    }
    var finallyBody: [JSStatement]?
    if matchKeyword("finally") {
      try consumeSymbol("{", "Expected '{' after finally")
      finallyBody = try block()
    }
    if catchBody == nil && finallyBody == nil {
      throw JSError.syntax("Expected catch or finally at \(peek.offset)")
    }
    return .tryStmt(body, catchPattern, catchBody, finallyBody)
  }

  private func forStatement() throws -> JSStatement {
    try consumeSymbol("(", "Expected '(' after for")
    if matchSymbol(";") {
      let test = checkSymbol(";") ? nil : try expression()
      try consumeSymbol(";", "Expected ';' in for")
      let update = checkSymbol(")") ? nil : try expression()
      try consumeSymbol(")", "Expected ')' after for")
      return .forLoop(nil, test, update, try statement())
    }
    if checkKeyword("var") || checkKeyword("let") || checkKeyword("const") {
      let kind: JSVariableKind
      if matchKeyword("let") { kind = .letDecl } else if matchKeyword("const") { kind = .constDecl }
      else {
        advance()
        kind = .varDecl
      }
      let pattern = try parsePattern()
      if matchKeyword("in") {
        let target = try expression()
        try consumeSymbol(")", "Expected ')' after for-in")
        return .forIn(.declaration(kind, pattern), target, try statement())
      }
      if matchKeyword("of") {
        let target = try expression()
        try consumeSymbol(")", "Expected ')' after for-of")
        return .forOf(.declaration(kind, pattern), target, try statement())
      }
      var initializer: JSExpression?
      if matchSymbol("=") {
        let saved = allowIn
        allowIn = false
        initializer = try assignment()
        allowIn = saved
      }
      try consumeSymbol(";", "Expected ';' in for")
      let test = checkSymbol(";") ? nil : try expression()
      try consumeSymbol(";", "Expected ';' in for")
      let update = checkSymbol(")") ? nil : try expression()
      try consumeSymbol(")", "Expected ')' after for")
      let initStatement: JSStatement = .variable(kind, [(pattern, initializer)])
      return .forLoop(initStatement, test, update, try statement())
    }
    let saved = allowIn
    allowIn = false
    let candidate = try expression()
    allowIn = saved
    if matchKeyword("in") {
      let target = try expression()
      try consumeSymbol(")", "Expected ')' after for-in")
      return .forIn(.expression(candidate), target, try statement())
    }
    if matchKeyword("of") {
      let target = try expression()
      try consumeSymbol(")", "Expected ')' after for-of")
      return .forOf(.expression(candidate), target, try statement())
    }
    try consumeSymbol(";", "Expected ';' in for")
    let test = checkSymbol(";") ? nil : try expression()
    try consumeSymbol(";", "Expected ';' in for")
    let update = checkSymbol(")") ? nil : try expression()
    try consumeSymbol(")", "Expected ')' after for")
    return .forLoop(.expression(candidate), test, update, try statement())
  }

  private func block() throws -> [JSStatement] {
    var statements: [JSStatement] = []
    while !checkSymbol("}") && !isAtEnd { statements.append(try declaration()) }
    try consumeSymbol("}", "Expected '}'")
    return statements
  }

  private func parsePattern(allowDefault: Bool = true) throws -> JSPattern {
    if matchSymbol("{") {
      var entries: [(key: String, pattern: JSPattern)] = []
      var rest: String?
      while !checkSymbol("}") && !isAtEnd {
        if matchSymbol("...") {
          rest = try consumeIdentifier("Expected rest name")
          _ = matchSymbol(",")
          break
        }
        let key: String
        switch peek.kind {
        case .identifier(let value), .string(let value):
          key = value
          advance()
        case .number(let value):
          key = numberKey(value)
          advance()
        case .symbol("["):
          throw JSError.syntax("Computed keys in destructuring are not yet supported")
        default: throw JSError.syntax("Expected property name at \(peek.offset)")
        }
        var pattern: JSPattern
        if matchSymbol(":") {
          pattern = try parsePattern()
        } else {
          var fallback: JSExpression?
          if matchSymbol("=") { fallback = try assignment() }
          pattern = .identifier(key, fallback)
        }
        entries.append((key: key, pattern: pattern))
        if !matchSymbol(",") { break }
      }
      try consumeSymbol("}", "Expected '}' in pattern")
      return .object(entries, rest: rest)
    }
    if matchSymbol("[") {
      var elements: [JSPattern?] = []
      var rest: JSPattern?
      while !checkSymbol("]") && !isAtEnd {
        if matchSymbol(",") {
          elements.append(nil)
          continue
        }
        if matchSymbol("...") {
          rest = try parsePattern()
          _ = matchSymbol(",")
          break
        }
        elements.append(try parsePattern())
        if !matchSymbol(",") { break }
      }
      try consumeSymbol("]", "Expected ']' in pattern")
      return .array(elements, rest: rest)
    }
    if matchSymbol("...") {
      return .rest(try consumeIdentifier("Expected rest name"))
    }
    let name = try consumeIdentifier("Expected binding name")
    var fallback: JSExpression?
    if allowDefault && matchSymbol("=") { fallback = try assignment() }
    return .identifier(name, fallback)
  }

  private func expression() throws -> JSExpression { try sequence() }

  private func sequence() throws -> JSExpression {
    let first = try assignment()
    if !checkSymbol(",") { return first }
    var items = [first]
    while matchSymbol(",") { items.append(try assignment()) }
    return .sequence(items)
  }

  private func assignment() throws -> JSExpression {
    if checkKeyword("async") && !peekHasLineBreakAfterAsync() {
      if let arrow = try tryParseAsyncArrow() { return arrow }
    }
    if case .identifier(let name) = peek.kind, peekNextIsSymbol("=>") {
      advance()
      advance()
      return try arrowBody(params: [.identifier(name, nil)], isAsync: false)
    }
    if checkSymbol("(") {
      if let arrow = try tryParseParenArrow() { return arrow }
    }
    let left = try ternary()
    if matchSymbol("=") {
      let right = try assignment()
      if let pattern = patternFromExpression(left) {
        return .patternAssign(pattern, right)
      }
      return .assignment(left, right)
    }
    if let op = matchAnySymbol(["+=", "-=", "*=", "/=", "%=", "**=", "&=", "|=", "^=",
      "&&=", "||=", "??=", "<<=", ">>=", ">>>="])
    {
      let right = try assignment()
      return .compoundAssignment(op, left, right)
    }
    return left
  }

  private func peekHasLineBreakAfterAsync() -> Bool {
    guard current + 1 < tokens.count else { return true }
    return tokens[current + 1].lineTerminatorBefore
  }

  private func tryParseAsyncArrow() throws -> JSExpression? {
    let saved = current
    advance()
    if case .identifier(let name) = peek.kind, current + 1 < tokens.count,
      tokens[current + 1].kind == .symbol("=>")
    {
      advance()
      advance()
      return try arrowBody(params: [.identifier(name, nil)], isAsync: true)
    }
    if checkSymbol("(") {
      do {
        let params = try parseArrowParams()
        guard matchSymbol("=>") else {
          current = saved
          return nil
        }
        return try arrowBody(params: params, isAsync: true)
      } catch {
        current = saved
        return nil
      }
    }
    current = saved
    return nil
  }

  private func tryParseParenArrow() throws -> JSExpression? {
    let saved = current
    do {
      let params = try parseArrowParams()
      guard matchSymbol("=>") else {
        current = saved
        return nil
      }
      return try arrowBody(params: params, isAsync: false)
    } catch {
      current = saved
      return nil
    }
  }

  private func parseArrowParams() throws -> [JSPattern] {
    try consumeSymbol("(", "Expected '('")
    var params: [JSPattern] = []
    if !checkSymbol(")") {
      repeat {
        if matchSymbol("...") {
          params.append(.rest(try consumeIdentifier("Expected rest parameter")))
          break
        }
        params.append(try parseArrowParam())
      } while matchSymbol(",")
    }
    try consumeSymbol(")", "Expected ')'")
    return params
  }

  private func parseArrowParam() throws -> JSPattern {
    if checkSymbol("{") || checkSymbol("[") {
      return try parsePatternAllowingDefault()
    }
    let name = try consumeIdentifier("Expected parameter name")
    if matchSymbol("=") { return .identifier(name, try assignment()) }
    return .identifier(name, nil)
  }

  private func parsePatternAllowingDefault() throws -> JSPattern {
    let pattern = try parsePattern()
    return pattern
  }

  private func arrowBody(params: [JSPattern], isAsync: Bool) throws -> JSExpression {
    if matchSymbol("{") {
      return .arrow(params, .block(try block()), isAsync)
    }
    return .arrow(params, .expression(try assignment()), isAsync)
  }

  private func ternary() throws -> JSExpression {
    let condition = try nullish()
    guard matchSymbol("?") else { return condition }
    let thenBranch = try assignment()
    try consumeSymbol(":", "Expected ':' in conditional")
    return .ternary(condition, thenBranch, try assignment())
  }

  private func nullish() throws -> JSExpression {
    let left = try logicalOr()
    guard checkSymbol("??") else { return left }
    if case .binary(let op, _, _) = left, op == "&&" || op == "||" {
      throw JSError.syntax("Mixing ?? with && or || requires parentheses")
    }
    var result = left
    while matchSymbol("??") {
      let right = try logicalOr()
      if case .binary(let op, _, _) = right, op == "&&" || op == "||" {
        throw JSError.syntax("Mixing ?? with && or || requires parentheses")
      }
      result = .binary("??", result, right)
    }
    return result
  }

  private func logicalOr() throws -> JSExpression {
    var expression = try logicalAnd()
    while matchSymbol("||") { expression = .binary("||", expression, try logicalAnd()) }
    return expression
  }

  private func logicalAnd() throws -> JSExpression {
    var expression = try bitwiseOr()
    while matchSymbol("&&") { expression = .binary("&&", expression, try bitwiseOr()) }
    return expression
  }

  private func bitwiseOr() throws -> JSExpression {
    var expression = try bitwiseXor()
    while checkSymbol("|") && !peekNextIsSymbol("|") {
      advance()
      expression = .binary("|", expression, try bitwiseXor())
    }
    return expression
  }

  private func bitwiseXor() throws -> JSExpression {
    var expression = try bitwiseAnd()
    while matchSymbol("^") { expression = .binary("^", expression, try bitwiseAnd()) }
    return expression
  }

  private func bitwiseAnd() throws -> JSExpression {
    var expression = try equality()
    while checkSymbol("&") && !peekNextIsSymbol("&") {
      advance()
      expression = .binary("&", expression, try equality())
    }
    return expression
  }

  private func equality() throws -> JSExpression {
    var expression = try relational()
    while let op = matchAnySymbol(["==", "!=", "===", "!=="]) {
      expression = .binary(op, expression, try relational())
    }
    return expression
  }

  private func relational() throws -> JSExpression {
    var expression = try shift()
    while true {
      if let op = matchAnySymbol(["<", "<=", ">", ">="]) {
        expression = .binary(op, expression, try shift())
      } else if matchKeyword("instanceof") {
        expression = .binary("instanceof", expression, try shift())
      } else if allowIn && checkKeyword("in") {
        advance()
        expression = .binary("in", expression, try shift())
      } else {
        break
      }
    }
    return expression
  }

  private func shift() throws -> JSExpression {
    var expression = try term()
    while let op = matchAnySymbol(["<<", ">>", ">>>"]) {
      expression = .binary(op, expression, try term())
    }
    return expression
  }

  private func term() throws -> JSExpression {
    var expression = try factor()
    while let op = matchAnySymbol(["+", "-"]) {
      expression = .binary(op, expression, try factor())
    }
    return expression
  }

  private func factor() throws -> JSExpression {
    var expression = try exponent()
    while let op = matchAnySymbol(["*", "/", "%"]) {
      expression = .binary(op, expression, try exponent())
    }
    return expression
  }

  private func exponent() throws -> JSExpression {
    let base = try unary()
    if matchSymbol("**") {
      return .binary("**", base, try exponent())
    }
    return base
  }

  private func unary() throws -> JSExpression {
    if matchKeyword("await") { return .awaitExpr(try unary()) }
    if let op = matchAnySymbol(["!", "-", "+", "~"]) { return .unary(op, try unary()) }
    if matchKeyword("typeof") { return .unary("typeof", try unary()) }
    if matchKeyword("void") { return .unary("void", try unary()) }
    if matchKeyword("delete") { return .unary("delete", try unary()) }
    if checkSymbol("++") || checkSymbol("--") {
      let op = peekSymbol()!
      advance()
      return .update(op, try unary(), true)
    }
    return try postfix()
  }

  private func postfix() throws -> JSExpression {
    var expression = try newExpression()
    if (checkSymbol("++") || checkSymbol("--")) && !peek.lineTerminatorBefore {
      let op = peekSymbol()!
      advance()
      return .update(op, expression, false)
    }
    return expression
  }

  private func newExpression() throws -> JSExpression {
    if matchKeyword("new") {
      if checkSymbol(".") {
        throw JSError.syntax("new.target is not yet supported")
      }
      let callee = try memberBase()
      var args: [JSExpression] = []
      if matchSymbol("(") {
        if !checkSymbol(")") {
          repeat { args.append(try assignmentAsArgument()) } while matchSymbol(",")
        }
        try consumeSymbol(")", "Expected ')' after arguments")
      }
      return try callSuffix(.newExpr(callee, args))
    }
    return try call()
  }

  private func call() throws -> JSExpression {
    try callSuffix(try memberBase())
  }

  private func callSuffix(_ base: JSExpression) throws -> JSExpression {
    var expression = base
    while true {
      if matchSymbol("(") {
        var args: [JSExpression] = []
        if !checkSymbol(")") {
          repeat { args.append(try assignmentAsArgument()) } while matchSymbol(",")
        }
        try consumeSymbol(")", "Expected ')' after arguments")
        expression = .call(expression, args)
      } else if matchSymbol("?.") {
        if matchSymbol("(") {
          var args: [JSExpression] = []
          if !checkSymbol(")") {
            repeat { args.append(try assignmentAsArgument()) } while matchSymbol(",")
          }
          try consumeSymbol(")", "Expected ')' after arguments")
          expression = .optionalCall(expression, args)
        } else if checkSymbol("[") {
          let key = try self.expression()
          try consumeSymbol("]", "Expected ']'")
          expression = .optionalComputed(expression, key)
        } else {
          let name = try consumePropertyKey()
          expression = .optionalMember(expression, name)
        }
      } else if checkSymbol("${") {
        throw JSError.syntax("Unexpected template substitution")
      } else if matchSymbol(".") {
        let name = try consumePropertyKey()
        expression = .member(expression, name)
      } else if checkSymbol("[") {
        let key = try self.expression()
        try consumeSymbol("]", "Expected ']'")
        expression = .computed(expression, key)
      } else {
        break
      }
    }
    if checkSymbol("`") && !peek.lineTerminatorBefore {
      let (strings, values) = try templateLiteral()
      return .taggedTemplate(expression, strings, values)
    }
    return expression
  }

  private func assignmentAsArgument() throws -> JSExpression {
    if matchSymbol("...") { return .spread(try assignment()) }
    return try assignment()
  }

  private func memberBase() throws -> JSExpression {
    var expression = try primary()
    while true {
      if matchSymbol(".") {
        expression = .member(expression, try consumePropertyKey())
      } else if matchSymbol("[") {
        let key = try self.expression()
        try consumeSymbol("]", "Expected ']'")
        expression = .computed(expression, key)
      } else {
        break
      }
    }
    return expression
  }

  private func primary() throws -> JSExpression {
    if case .number(let value) = peek.kind {
      advance()
      return .literal(.number(value))
    }
    if case .bigint(let text) = peek.kind {
      advance()
      return .literal(.bigint(text))
    }
    if case .string(let value) = peek.kind {
      advance()
      return .literal(.string(value))
    }
    if case .regex(let pattern, let flags) = peek.kind {
      advance()
      return .literal(.regex(pattern: pattern, flags: flags))
    }
    if matchKeyword("true") { return .literal(.bool(true)) }
    if matchKeyword("false") { return .literal(.bool(false)) }
    if matchKeyword("null") { return .literal(.null) }
    if matchKeyword("undefined") { return .literal(.undefined) }
    if matchKeyword("this") { return .thisExpr }
    if matchKeyword("super") { return .superExpr }
    if matchKeyword("yield") {
      if checkSymbol(";") || checkSymbol("}") || checkSymbol(")") || checkSymbol(",")
        || checkSymbol(":") || isAtEnd
      {
        return .identifier("yield")
      }
      if peek.lineTerminatorBefore { return .identifier("yield") }
      let value: JSExpression? = canStartExpression() ? try assignment() : nil
      return .yieldExpr(value)
    }
    if checkKeyword("async") && peekNextIsKeyword("function") && !peekNextHasLineBreak() {
      advance()
      advance()
      if matchSymbol("*") { throw JSError.syntax("Generators are not yet supported") }
      let name = optionalName()
      let (params, body) = try functionSignatureAndBody()
      _ = name
      return .function(params, body, true)
    }
    if matchKeyword("function") {
      if matchSymbol("*") { throw JSError.syntax("Generators are not yet supported") }
      _ = optionalName()
      let (params, body) = try functionSignatureAndBody()
      return .function(params, body, false)
    }
    if matchKeyword("class") { return .classExpr(try classDef()) }
    if matchKeyword("import") {
      if matchSymbol("(") {
        let path = try expression()
        try consumeSymbol(")", "Expected ')' after import")
        return .dynamicImport(path)
      }
      throw JSError.syntax("Expected '(' after import at \(peek.offset)")
    }
    if matchKeyword("new") {
      current -= 1
      return try newExpression()
    }
    if case .identifier(let name) = peek.kind {
      advance()
      return .identifier(name)
    }
    if case .keyword(let word) = peek.kind, isContextualKeyword(word) {
      advance()
      return .identifier(word)
    }
    if matchSymbol("(") {
      if matchSymbol(")") {
        throw JSError.syntax("Expected expression at \(peek.offset)")
      }
      let value = try expression()
      try consumeSymbol(")", "Expected ')'")
      return value
    }
    if matchSymbol("[") { return try arrayLiteral() }
    if matchSymbol("{") { return try objectLiteral() }
    if checkSymbol("`") {
      let parsed = try templateLiteral()
      return .template(parsed.0, parsed.1)
    }
    throw JSError.syntax("Expected expression at \(peek.offset)")
  }

  private func templateLiteral() throws -> ([String], [JSExpression]) {
    try consumeSymbol("`", "Expected template start")
    guard case .templateChunk(let first) = peek.kind else {
      throw JSError.syntax("Expected template text at \(peek.offset)")
    }
    advance()
    var strings = [first]
    var values: [JSExpression] = []
    while matchSymbol("${") {
      values.append(try expression())
      try consumeSymbol("}", "Expected '}' in template")
      guard case .templateChunk(let chunk) = peek.kind else {
        throw JSError.syntax("Expected template text at \(peek.offset)")
      }
      advance()
      strings.append(chunk)
    }
    try consumeSymbol("`", "Expected template end")
    return (strings, values)
  }

  private func arrayLiteral() throws -> JSExpression {
    var elements: [JSArrayElement] = []
    if !checkSymbol("]") {
      repeat {
        if matchSymbol(",") {
          elements.append(.hole)
          if checkSymbol("]") { break }
          continue
        }
        if matchSymbol("...") {
          elements.append(.spread(try assignment()))
        } else {
          elements.append(.value(try assignment()))
        }
      } while matchSymbol(",")
    }
    try consumeSymbol("]", "Expected ']'")
    return .array(elements)
  }

  private func objectLiteral() throws -> JSExpression {
    var members: [JSObjectMember] = []
    if !checkSymbol("}") {
      repeat {
        if matchSymbol("...") {
          members.append(.spread(try assignment()))
          continue
        }
        if checkIdentifier("get") && peekNextIsPropertyName() {
          advance()
          let name = try propertyName()
          if checkSymbol("(") {
            try consumeSymbol("(", "Expected '('")
            try consumeSymbol(")", "Expected ')'")
            try consumeSymbol("{", "Expected '{' for getter")
            members.append(.getter(name, try block()))
            continue
          }
        }
        if checkIdentifier("set") && peekNextIsPropertyName() {
          advance()
          let name = try propertyName()
          if checkSymbol("(") {
            try consumeSymbol("(", "Expected '('")
            let param = try consumePropertyKey()
            try consumeSymbol(")", "Expected ')'")
            try consumeSymbol("{", "Expected '{' for setter")
            members.append(.setter(name, param, try block()))
            continue
          }
        }
        if checkIdentifier("async") && !peekNextHasLineBreak()
          && (peekNextIsPropertyName() || peekNextIsSymbol("*"))
        {
          advance()
          if matchSymbol("*") {
            throw JSError.syntax("Generators are not yet supported")
          }
          let name = try propertyName()
          let (params, body) = try functionSignatureAndBody()
          members.append(.method(name, params, body, true))
          continue
        }
        if matchSymbol("*") {
          throw JSError.syntax("Generators are not yet supported")
        }
        let key = try propertyName()
        if case .identifier(let name) = peek.kind, name == key, !peekNextIsSymbol("(") {
          advance()
          if matchSymbol("=") {
            throw JSError.syntax("Unexpected '=' in object literal at \(peek.offset)")
          }
          members.append(.shorthand(key))
          continue
        }
        if checkSymbol("(") {
          let (params, body) = try functionSignatureAndBody()
          members.append(.method(key, params, body, false))
          continue
        }
        try consumeSymbol(":", "Expected ':' after object key")
        members.append(.property(key, try assignment()))
      } while matchSymbol(",")
    }
    try consumeSymbol("}", "Expected '}'")
    return .object(members)
  }

  private func propertyName() throws -> String {
    switch peek.kind {
    case .identifier(let value), .string(let value):
      advance()
      return value
    case .number(let value):
      advance()
      return numberKey(value)
    case .keyword(let value):
      advance()
      return value
    default:
      throw JSError.syntax("Expected property name at \(peek.offset)")
    }
  }

  private func consumePropertyKey() throws -> String {
    if case .identifier(let value) = peek.kind {
      advance()
      return value
    }
    if case .keyword(let value) = peek.kind {
      advance()
      return value
    }
    throw JSError.syntax("Expected name at \(peek.offset)")
  }

  private func numberKey(_ value: Double) -> String {
    value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
  }

  private func patternFromExpression(_ expression: JSExpression) -> JSPattern? {
    switch expression {
    case .identifier(let name):
      return .identifier(name, nil)
    case .assignment(let target, let fallback):
      if case .identifier(let name) = target { return .identifier(name, fallback) }
      return nil
    case .object(let members):
      var entries: [(key: String, pattern: JSPattern)] = []
      var rest: String?
      for member in members {
        switch member {
        case .property(let key, let value):
          guard let pattern = patternFromExpression(value) else { return nil }
          entries.append((key: key, pattern: pattern))
        case .shorthand(let name):
          entries.append((key: name, pattern: .identifier(name, nil)))
        case .spread(let value):
          guard case .identifier(let name) = value else { return nil }
          rest = name
        default:
          return nil
        }
      }
      return .object(entries, rest: rest)
    case .array(let elements):
      var patterns: [JSPattern?] = []
      var rest: JSPattern?
      for element in elements {
        switch element {
        case .value(let value):
          guard let pattern = patternFromExpression(value) else { return nil }
          patterns.append(pattern)
        case .hole:
          patterns.append(nil)
        case .spread(let value):
          guard case .identifier(let name) = value else { return nil }
          rest = .identifier(name, nil)
        }
      }
      return .array(patterns, rest: rest)
    default:
      return nil
    }
  }

  private func functionSignatureAndBody() throws -> ([JSPattern], [JSStatement]) {
    _ = optionalName()
    try consumeSymbol("(", "Expected '('")
    var params: [JSPattern] = []
    if !checkSymbol(")") {
      repeat {
        if matchSymbol("...") {
          params.append(.rest(try consumeIdentifier("Expected rest parameter")))
          break
        }
        params.append(try parseArrowParam())
      } while matchSymbol(",")
    }
    try consumeSymbol(")", "Expected ')'")
    try consumeSymbol("{", "Expected '{'")
    return (params, try block())
  }

  private func contextualIdentifier(_ message: String) throws -> String {
    if case .identifier(let value) = peek.kind {
      advance()
      return value
    }
    if case .keyword(let value) = peek.kind, isContextualKeyword(value) {
      advance()
      return value
    }
    throw JSError.syntax("\(message) at \(peek.offset)")
  }

  private func isContextualKeyword(_ word: String) -> Bool {
    ["async", "as", "from", "get", "set", "target", "of", "let", "static"].contains(word)
  }

  private func optionalName() -> String? {
    if case .identifier(let value) = peek.kind {
      advance()
      return value
    }
    return nil
  }

  private func optionalIdentifier() -> String? {
    if case .identifier(let value) = peek.kind {
      advance()
      return value
    }
    return nil
  }

  private func canStartExpression() -> Bool {
    switch peek.kind {
    case .number, .bigint, .string, .regex, .templateChunk, .identifier:
      return true
    case .keyword(let word):
      return word == "function" || word == "class" || word == "new" || word == "typeof"
        || word == "void" || word == "delete" || word == "this" || word == "super"
        || word == "true" || word == "false" || word == "null" || word == "undefined"
        || isContextualKeyword(word)
    case .symbol(let symbol):
      return symbol == "(" || symbol == "[" || symbol == "{" || symbol == "`"
        || symbol == "${" || symbol == "+" || symbol == "-" || symbol == "!"
        || symbol == "~" || symbol == "/" || symbol == "++" || symbol == "--"
    case .eof:
      return false
    }
  }

  private var peek: JSToken { tokens[min(current, tokens.count - 1)] }
  private var isAtEnd: Bool {
    if case .eof = peek.kind { return true }
    return false
  }
  private func peekSymbol() -> String? {
    if case .symbol(let value) = peek.kind { return value }
    return nil
  }

  @discardableResult private func advance() -> JSToken {
    let token = peek
    if !isAtEnd { current += 1 }
    return token
  }
  private func checkSymbol(_ symbol: String) -> Bool {
    if case .symbol(let value) = peek.kind { return value == symbol }
    return false
  }
  private func checkIdentifier(_ name: String) -> Bool {
    if case .identifier(let value) = peek.kind { return value == name }
    if case .keyword(let value) = peek.kind { return value == name }
    return false
  }
  private func checkKeyword(_ keyword: String) -> Bool {
    if case .keyword(let value) = peek.kind { return value == keyword }
    return false
  }
  private func peekNextIsKeyword(_ keyword: String) -> Bool {
    guard current + 1 < tokens.count else { return false }
    if case .keyword(let value) = tokens[current + 1].kind { return value == keyword }
    return false
  }
  private func peekNextIsSymbol(_ symbol: String) -> Bool {
    guard current + 1 < tokens.count else { return false }
    if case .symbol(let value) = tokens[current + 1].kind { return value == symbol }
    return false
  }
  private func peekNextHasLineBreak() -> Bool {
    guard current + 1 < tokens.count else { return false }
    return tokens[current + 1].lineTerminatorBefore
  }
  private func peekNextIsPropertyName() -> Bool {
    guard current + 1 < tokens.count else { return false }
    switch tokens[current + 1].kind {
    case .identifier, .string, .number, .keyword:
      return true
    default:
      return false
    }
  }
  private func matchSymbol(_ symbol: String) -> Bool {
    guard checkSymbol(symbol) else { return false }
    advance()
    return true
  }
  private func matchAnySymbol(_ symbols: [String]) -> String? {
    for symbol in symbols where checkSymbol(symbol) {
      advance()
      return symbol
    }
    return nil
  }
  private func matchKeyword(_ keyword: String) -> Bool {
    if case .keyword(let value) = peek.kind, value == keyword {
      advance()
      return true
    }
    return false
  }
  private func consumeSymbol(_ symbol: String, _ message: String) throws {
    guard matchSymbol(symbol) else { throw JSError.syntax("\(message) at \(peek.offset)") }
  }
  private func consumeKeyword(_ keyword: String, _ message: String) throws {
    guard matchKeyword(keyword) else { throw JSError.syntax("\(message) at \(peek.offset)") }
  }
  private func consumeIdentifier(_ message: String) throws -> String {
    if case .identifier(let value) = peek.kind {
      advance()
      return value
    }
    if case .keyword(let value) = peek.kind, isContextualKeyword(value) {
      advance()
      return value
    }
    throw JSError.syntax("\(message) at \(peek.offset)")
  }
  private func consumeTerminator() throws {
    if matchSymbol(";") { return }
    if checkSymbol("}") || isAtEnd || peek.lineTerminatorBefore { return }
    throw JSError.syntax("Expected ';' at \(peek.offset)")
  }
}