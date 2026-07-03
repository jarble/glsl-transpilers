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
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Intercepts built-in GLSL variables and functions to map to WGSL
  function mapFuncCall(name, args) {
    args = args || [];
    
    // Polyfill GLSL math built-ins to WGSL equivalents if needed
    switch(name) {
        case "mix": return "mix(" + args.join(", ") + ")";
        case "fract": return "fract(" + args.join(", ") + ")";
        case "inversesqrt": return "inverseSqrt(" + args.join(", ") + ")";
        default: return "compiled_" + name + "(" + args.join(", ") + ")";
    }
  }
}

/* =====================================================
   Entry & Top Level
   ===================================================== */

Start
  = _ items:(TopLevel (_ TopLevel)*)? _ {
    if (!items) return "";
    return items[0] + items[1].map(i => i[0] + i[1]).join("");
  }

TopLevel
  = FunctionDecl
  / StructDecl
  / GlobalVarDecl

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:StructField* _ "}" _ instance:Identifier? _ ";" {
    let structDef = "struct compiled_" + name + " {\n" + fields.join("") + "\n}";
    if (instance) {
        return structDef + "\nvar<private> compiled_" + instance + ": compiled_" + name + ";";
    }
    return structDef;
  }

StructField
  = pre:_ type:Type __ name:Identifier _ ";" _ {
    // WGSL structs use comma-separated fields
    return pre + "compiled_" + name + ": " + mapType(type) + ",\n";
  }

GlobalVarDecl
  = type:Type __ name:Identifier init:(_ "=" _ Expression)? _ ";" {
    return "var<private> compiled_" + name + ": " + mapType(type) + (init ? " = " + init[3] : "") + ";";
  }

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
    let retType = mapType(type);
    let retStr = retType === "void" ? "" : " -> " + retType;
    return "fn compiled_" + name + "(" + (params || "") + ")" + retStr + " {\n" + body + "}";
  }

ParamList
  = head:Param tail:(_ "," _ Param)* {
    return head + tail.map(t => ", " + t[3]).join("");
  }

Param
  = type:Type __ name:Identifier {
    return "compiled_" + name + ": " + mapType(type);
  }

/* =====================================================
   Statements & Control Flow
   ===================================================== */

Statements
  = stmts:(Statement / _)* {
    return stmts.join("");
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
    return "{\n" + stmts + "}";
  }

VarDecl
  = type:Type __ head:SingleVarDecl tail:(_ "," _ SingleVarDecl)* _ ";" {
      const mappedType = mapType(type);
      let decls = [head];
      
      if (tail && tail.length > 0) {
        decls = decls.concat(tail.map(t => t[3]));
      }

      return decls.map(decl => {
        let finalType = mappedType;
        if (decl.size) {
            finalType = "array<" + mappedType + ", " + decl.size + ">";
        }
        return "var compiled_" + decl.name + ": " + finalType + (decl.init ? " = " + decl.init : "") + ";";
      }).join("\n");
  }

SingleVarDecl
  = name:Identifier _ isArray:("[" _ Number _ "]")? init:(_ "=" _ Expression)? {
      return { 
        name: name, 
        size: isArray ? isArray[2] : null, 
        init: init ? init[3] : null
      };
  }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ trueBlock:Statement falseBlock:(_ "else" _ Statement)? {
    let tb = trueBlock.trim().startsWith("{") ? trueBlock : "{\n" + trueBlock + "\n}";
    let res = "if " + cond + " " + tb;
    if (falseBlock) {
      let fb = falseBlock[3].trim().startsWith("{") ? falseBlock[3] : "{\n" + falseBlock[3] + "\n}";
      res += " else " + fb;
    }
    return res;
  }

ForStmt
  = "for" _ "(" _ init:(VarDecl / ExprStmt / ";") _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Statement {
    let initStr = init === ";" ? "" : init.trim().replace(/;$/, "");
    let b = body.trim().startsWith("{") ? body : "{\n" + body + "\n}";
    return "for(" + initStr + "; " + (cond || "") + "; " + (update || "") + ") " + b;
  }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement {
    let b = body.trim().startsWith("{") ? body : "{\n" + body + "\n}";
    return "while " + cond + " " + b;
  }

SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ clauses:SwitchClause* _ "}" {
    // WGSL drops the parentheses around the switch expression
    return "switch " + expr + " {" + clauses.join("") + "\n}";
  }

SwitchClause
  = pre:_ "case" __ val:Expression _ ":" _ stmts:CaseStmts {
    // Injects the WGSL-required '{'
    return pre + "case " + val + ": {" + stmts + pre + "}";
  }
  / pre:_ "default" _ ":" _ stmts:CaseStmts {
    return pre + "default: {" + stmts + pre + "}";
  }

CaseStmts
  = items:( !("case" __ / "default" _ ":" / "}") item:(Statement / _) { return item; } )* {
    function flatten(arr) {
      return Array.isArray(arr) ? arr.map(flatten).join("") : arr;
    }
    let body = flatten(items);
    // Strip trailing GLSL 'break;' statements, leave returns intact
    return body.replace(/\bbreak\s*;/g, "");
  }

ReturnStmt
  = "return" _ expr:Expression? _ ";" {
    return "return" + (expr ? " " + expr : "") + ";";
  }

ExprStmt
  = expr:Expression _ ";" {
    return expr + ";";
  }

/* =====================================================
   Expressions
   ===================================================== */

Expression
  = AssignmentExpr

AssignmentExpr
  = left:PostfixExpr _ op:("="/"+="/"-="/"*="/"/=") _ right:AssignmentExpr {
    return left + " " + op + " " + right;
  }
  / ConditionalExpression

ConditionalExpression
  = cond:LogicOrExpr _ "?" _ trueExpr:Expression _ ":" _ falseExpr:ConditionalExpression {
      // Maps (cond ? true : false) -> select(false, true, cond)
      return "select(" + falseExpr + ", " + trueExpr + ", " + cond + ")";
    }
  / LogicOrExpr

LogicOrExpr
  = head:LogicAndExpr tail:(_ "||" _ LogicAndExpr)* {
    return head + tail.map(t => " || " + t[3]).join("");
  }

LogicAndExpr
  = head:EqualityExpr tail:(_ "&&" _ EqualityExpr)* {
    return head + tail.map(t => " && " + t[3]).join("");
  }

EqualityExpr
  = head:RelationalExpr tail:(_ ("=="/"!=") _ RelationalExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join("");
  }

RelationalExpr
  = head:AdditiveExpr tail:(_ ("<="/"<"/">="/">") _ AdditiveExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join("");
  }

AdditiveExpr
  = head:MultiplicativeExpr tail:(_ ("+"/"-") _ MultiplicativeExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join("");
  }

MultiplicativeExpr
  = head:UnaryExpr tail:(_ ("*"/"/") _ UnaryExpr)* {
    return head + tail.map(t => " " + t[1] + " " + t[3]).join("");
  }

UnaryExpr
  = op:("+"/"-"/"!") _ expr:UnaryExpr {
    return op + expr;
  }
  / PostfixExpr

PostfixExpr
  = head:PrimaryExpr tail:PostfixPart* {
    return tail.reduce((acc, part) => part(acc), head);
  }

PostfixPart
  = _ "[" _ idx:Expression _ "]" {
    return (acc) => acc + "[" + idx + "]";
  }
  / _ "." _ prop:Identifier {
    return (acc) => acc + "." + prop; // Note: You might want to filter swizzles here like in previous versions
  }
  / _ "(" _ args:ArgList? _ ")" {
    return (acc) => {
        // Prevent double prefixing if it's already a built-in wrapper
        let cleanName = acc.replace(/^compiled_/, "");
        if (cleanName === "array") return "array(" + (args ? args.join(", ") : "") + ")";
        return mapFuncCall(cleanName, args);
    };
  }
  / _ "++" {
    return (acc) => acc + " = " + acc + " + 1"; // WGSL doesn't support ++ in expressions natively
  }
  / _ "--" {
    return (acc) => acc + " = " + acc + " - 1";
  }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
    return [head].concat(tail.map(t => t[3]));
  }

PrimaryExpr
  = ArrayConstructor
  / Number
  / Identifier { 
      let t = text();
      // Only prefix non-keywords and non-builtins (expand this array as needed)
      if (["true", "false", "select", "array"].includes(t) || t.startsWith("gl_")) return t;
      return "compiled_" + t; 
    }
  / "(" _ expr:Expression _ ")" { return "(" + expr + ")"; }

ArrayConstructor
  = type:Type _ "[" _ size:Number _ "]" _ "(" _ args:ArgList? _ ")" {
      const mappedType = mapType(type);
      const argStr = args ? args.join(", ") : "";
      return "array<" + mappedType + ", " + size + ">(" + argStr + ")";
    }

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
    suffix:([fFuU])?
  {
    // Auto-append 'f' for WGSL floats if it's a decimal
    const isFloat = num.includes('.') || num.includes('e') || num.includes('E');
    if (isFloat && !suffix) {
      return num + "f";
    }
    return num + (suffix ? suffix : "");
  }

_ "optional whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)* { return text(); }

__ "mandatory whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)+ { return text(); }

WhiteSpace
  = [ \t\n\r]

SingleLineComment
  = "//" (![\n\r] .)*

MultiLineComment
  = "/*" (!"*/" .)* "*/"
