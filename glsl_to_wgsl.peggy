{
  const typeMap = {
    float: "f32",
    int: "i32",
    uint: "u32",
    bool: "bool",
    vec2: "vec2f",
    vec3: "vec3f",
    vec4: "vec4f",
    mat2: "mat2x2f",
    mat3: "mat3x3f",
    mat4: "mat4x4f",
    void: "void"
  }; [cite: 1]

  const glslBuiltins = new Set([
    "float", "int", "uint", "bool", "void", "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
    "abs", "acos", "asin", "atan", "ceil", "cos", "exp", "floor", "log", 
    "max", "min", "pow", "sin", "sqrt", "tan", "round", "clamp", "length", 
    "normalize", "dot", "cross", "mix", "step", "smoothstep", "fract", 
    "inversesqrt", "distance", "reflect", "refract", "mod", "sign",
    "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing", 
    "gl_PointSize", "gl_VertexID", "gl_InstanceID"
  ]);

  function mapIdentifier(name) {
    if (glslBuiltins.has(name)) return name;
    return "compiled_" + name;
  }

  function mapType(t){
    return typeMap[t] || mapIdentifier(t); [cite: 2]
  }

  function mapFuncCall(name, args) {
    args = args || []; [cite: 3]
    switch(name) {
        case "mix": return "mix(" + args.join(", ") + ")";
        case "fract": return "fract(" + args.join(", ") + ")"; [cite: 4]
        case "inversesqrt": return "inverseSqrt(" + args.join(", ") + ")";
        // Automatically handles custom 'compiled_X' functions seamlessly
        default: return mapIdentifier(name) + "(" + args.join(", ") + ")"; [cite: 5, 6]
    }
  }
}

/* =====================================================
   Entry & Top Level
   ===================================================== */

Start
  = _ items:(TopLevel (_ TopLevel)*)? _ { [cite: 7]
    if (!items) return "";
    return items[0] + items[1].map(i => "\n\n" + i[1]).join(""); [cite: 8]
  }

TopLevel
  = FunctionDecl
  / StructDecl
  / GlobalVarDecl

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:StructField* _ "}" _ instance:Identifier? _ ";" { [cite: 9]
    let mappedName = mapIdentifier(name);
    let structDef = "struct " + mappedName + " {\n" + fields.join("") + "}"; [cite: 10]
    if (instance) {
        return structDef + "\n\nvar<private> " + mapIdentifier(instance) + ": " + mappedName + ";"; [cite: 11]
    }
    return structDef;
  }

StructField
  = pre:_ type:Type __ name:Identifier _ ";" _ { [cite: 12]
    // Struct properties skip the prefixer so internal keys stay clean
    return pre + name + ": " + mapType(type) + ",\n"; [cite: 13]
  }

GlobalVarDecl
  = type:Type __ head:SingleVarDecl tail:(_ "," _ SingleVarDecl)* _ ";" {
    const mappedType = mapType(type);
    const decls = [head].concat(tail.map(t => t[3])); [cite: 14]
    return decls.map(decl => {
      return "var<private> " + decl.name + ": " + mappedType + (decl.init ? " = " + decl.init : "") + ";";
    }).join("\n"); [cite: 15]
  }

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
    let retType = mapType(type);
    let retStr = retType === "void" ? "" : " -> " + retType; [cite: 16]
    return "fn " + mapIdentifier(name) + "(" + (params || "") + ")" + retStr + " {\n" + body + "\n}"; [cite: 17, 18]
  }

ParamList
  = head:Param tail:(_ "," _ Param)* {
    return head + tail.map(t => ", " + t[3]).join(""); [cite: 19]
  }

Param
  = type:Type __ name:Identifier {
    return mapIdentifier(name) + ": " + mapType(type); [cite: 20]
  }

/* =====================================================
   Statements & Control Flow
   ===================================================== */

Statements
  = stmts:(Statement / _)* {
    return stmts.join(""); [cite: 21]
  }

Statement
  = Block
  / VarDecl
  / IfStmt
  / ForStmt
  / WhileStmt
  / SwitchStmt
  / ReturnStmt
  / ExprStmt

Block
  = "{" _ stmts:Statements _ "}" {
    return "{\n" + stmts + "}"; [cite: 22]
  }

VarDecl
  = type:Type __ head:SingleVarDecl tail:(_ "," _ SingleVarDecl)* _ ";" {
    const mappedType = mapType(type);
    const decls = [head].concat(tail.map(t => t[3])); [cite: 23]
    return decls.map(decl => {
      return "var " + decl.name + ": " + mappedType + (decl.init ? " = " + decl.init : "") + ";";
    }).join("\n"); [cite: 24]
  }

SingleVarDecl
  = name:Identifier init:(_ "=" _ Expression)? {
    // Apply prefix to variable name declarations
    return { name: mapIdentifier(name), init: init ? init[3] : null }; [cite: 25]
  }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ trueBlock:Statement falseBlock:(_ "else" _ Statement)? { [cite: 26]
    let tb = trueBlock.trim().startsWith("{") ? trueBlock : "{\n" + trueBlock + "\n}"; [cite: 27]
    let res = "if " + cond + " " + tb; [cite: 28]
    if (falseBlock) {
      let fb = falseBlock[3].trim().startsWith("{") ? falseBlock[3] : "{\n" + falseBlock[3] + "\n}"; [cite: 29]
      res += " else " + fb;
    }
    return res; [cite: 30]
  }

ForStmt
  = "for" _ "(" _ init:(VarDecl / ExprStmt / ";") _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Statement {
    let initStr = init === ";" ? "" : init.trim().replace(/;$/, ""); [cite: 31]
    let b = body.trim().startsWith("{") ? body : "{\n" + body + "\n}"; [cite: 32]
    return "for(var " + initStr + "; " + (cond || "") + "; " + (update || "") + ") " + b; [cite: 33]
  }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement {
    let b = body.trim().startsWith("{") ? body : "{\n" + body + "\n}"; [cite: 34]
    return "while " + cond + " " + b; [cite: 35]
  }

SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ clauses:SwitchClause* _ "}" {
    return "switch " + expr + " {" + clauses.join("") + "\n}"; [cite: 36]
  }

SwitchClause
  = pre:_ "case" __ val:Expression _ ":" _ stmts:CaseStmts {
    return pre + "case " + val + ": {" + stmts + pre + "}"; [cite: 37]
  }
  / pre:_ "default" _ ":" _ stmts:CaseStmts {
    return pre + "default: {" + stmts + pre + "}"; [cite: 38]
  }

CaseStmts
  = items:( !("case" __ / "default" _ ":" / "}") item:(Statement / _) { return item; } )* {
    function flatten(arr) { return Array.isArray(arr) ? arr.map(flatten).join("") : arr; } [cite: 39]
    let body = flatten(items);
    return body.replace(/\bbreak\s*;/g, ""); [cite: 40]
  }

ReturnStmt
  = pre:_ "return" _ expr:Expression? _ ";" {
    return pre + "return" + (expr ? " " + expr : "") + ";"; [cite: 41]
  }

ExprStmt
  = pre:_ expr:Expression _ ";" {
    return pre + expr + ";"; [cite: 42]
  }

/* =====================================================
   Expressions
   ===================================================== */

Expression
  = ConditionalExpr

ConditionalExpr
  = cond:LogicOrExpr _ "?" _ trueExpr:Expression _ ":" _ falseExpr:ConditionalExpr { [cite: 43]
    return "select(" + falseExpr + ", " + trueExpr + ", " + cond + ")"; [cite: 44]
  }
  / AssignmentExpr

AssignmentExpr
  = left:PostfixExpr _ op:("="/"+="/"-="/"*="/"/=") _ right:AssignmentExpr {
    return left + " " + op + " " + right; [cite: 45]
  }
  / LogicOrExpr

LogicOrExpr
  = head:LogicAndExpr tail:(_ "||" _ LogicAndExpr)* {
    return head + tail.map(t => " || " + t[3]).join(""); [cite: 46]
  }

LogicAndExpr
  = head:EqualityExpr tail:(_ "&&" _ EqualityExpr)* {
    return head + tail.map(t => " && " + t[3]).join(""); [cite: 47]
  }

EqualityExpr
  = head:RelationalExpr tail:(_ ("=="/"!=") _ RelationalExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join(""); [cite: 48]
  }

RelationalExpr
  = head:AdditiveExpr tail:(_ ("<="/"<"/">="/">") _ AdditiveExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join(""); [cite: 49]
  }

AdditiveExpr
  = head:MultiplicativeExpr tail:(_ ("+"/"-") _ MultiplicativeExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join(""); [cite: 50]
  }

MultiplicativeExpr
  = head:UnaryExpr tail:(_ ("*"/"/") _ UnaryExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join(""); [cite: 51]
  }

UnaryExpr
  = op:("+"/"-"/"!") _ expr:UnaryExpr {
    return op + expr; [cite: 52]
  }
  / PostfixExpr

PostfixExpr
  = head:PrimaryExpr tail:PostfixPart* {
    return tail.reduce((acc, part) => part(acc), head); [cite: 53]
  }

PostfixPart
  = _ "[" _ idx:Expression _ "]" { return (acc) => acc + "[" + idx + "]"; } [cite: 54]
  / _ "." _ prop:Identifier { return (acc) => acc + "." + prop; } // Struct property access remains un-mapped! [cite: 55]
  / _ "(" _ args:ArgList? _ ")" { return (acc) => mapFuncCall(acc, args); } [cite: 56]
  / _ "++" { return (acc) => acc + " = " + acc + " + 1"; } [cite: 57]
  / _ "--" { return (acc) => acc + " = " + acc + " - 1"; } [cite: 58]

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
    return [head].concat(tail.map(t => t[3])); [cite: 59]
  }

PrimaryExpr
  = Number
  / id:Identifier { return mapIdentifier(id); } // Intercept all generic identifier uses
  / "(" _ expr:Expression _ ")" { return "(" + expr + ")"; } [cite: 60]

/* =====================================================
   Types, Tokens & Whitespace
   ===================================================== */

Type
  = "void" / "float" / "int" / "uint" / "bool" 
  / "vec2" / "vec3" / "vec4" 
  / "mat2" / "mat3" / "mat4" 
  / Identifier

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = num:$(
      ([0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+)
      ([eE] [+-]? [0-9]+)?
    )
    suffix:([fFuU])? { [cite: 61]
    const isFloat = num.includes('.') || num.includes('e') || num.includes('E'); [cite: 62]
    if (isFloat && !suffix) {
      return num + "f"; [cite: 63]
    }
    return num + (suffix ? suffix : ""); [cite: 64]
  }

_ "optional whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)* { return text(); } [cite: 65]

__ "mandatory whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)+ { return text(); } [cite: 66]

WhiteSpace
  = [ \t\n\r]

SingleLineComment
  = "//" (![\n\r] .)*

MultiLineComment
  = "/*" (!"*/" .)* "*/"
