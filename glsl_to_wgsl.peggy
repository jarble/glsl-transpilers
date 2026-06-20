{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "uint",
    bool: "bool",
    vec2: "glm::vec2",
    vec3: "glm::vec3",
    vec4: "glm::vec4",
    mat2: "glm::mat2",
    mat3: "glm::mat3",
    mat4: "glm::mat4",
    void: "void"
  };

  function mapType(t) {
    return typeMap[t] || t;
  }

  const builtinMap = {
    abs: "std::abs", acos: "std::acos", asin: "std::asin", atan: "std::atan",
    ceil: "std::ceil", cos: "std::cos", exp: "std::exp", floor: "std::floor",
    log: "std::log", max: "std::max", min: "std::min", pow: "std::pow",
    sin: "std::sin", sqrt: "std::sqrt", tan: "std::tan", round: "std::round",
    clamp: "glm::clamp", length: "glm::length", normalize: "glm::normalize",
    dot: "glm::dot", cross: "glm::cross", mix: "glm::mix",
    step: "glm::step", smoothstep: "glm::smoothstep"
  };

  function mapFuncCall(name, argsStr) {
    if (typeMap[name]) {
        return typeMap[name] + "(" + argsStr + ")";
    }
    const func = builtinMap[name] || name;
    return func + "(" + argsStr + ")";
  }
}

/* =====================================================
   // Entry & Top Level
   ===================================================== */

Start
  = _ items:(TopLevel _)* {
      return items.map(item => item[0]).join("\n\n");
  }

TopLevel
  = FuncDecl
  / VarDecl
  / Comment

/* =====================================================
   // Functions & Parameters
   ===================================================== */

FuncDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
      const p = params ? params : "";
      return mapType(type) + " " + name + "(" + p + ") {\n" + body + "\n}";
  }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return head + tail.map(t => ", " + t[3]).join("");
  }

ParamDecl
  = mod:("inout" / "out" / "in")? _ type:Type __ name:Identifier array:ArraySuffix? {
      let t = mapType(type);
      if (mod === "inout" || mod === "out") {
          t += "&";
      }
      return t + " " + name + (array ? array : "");
  }

/* =====================================================
   // Statements & Variables
   ===================================================== */

Statements
  = stmts:(Statement _)* {
      // Joins all statements (and comments) securely with newlines
      return stmts.map(s => s[0]).join("\n");
  }

Statement
  = c:Comment { 
      // Safely split block comments to ensure proper indentation for every line
      return c.split('\n').map(line => "    " + line).join('\n'); 
  }
  / v:VarDecl { return "    " + v; }
  / e:ExprStmt { return "    " + e; }
  / r:ReturnStmt { return "    " + r; }

ReturnStmt
  = "return" __ expr:Expression? _ ";" {
      return "return " + (expr ? expr : "") + ";";
  }

ExprStmt
  = expr:Expression _ ";" { return expr + ";"; }

VarDecl
  = type:Type __ name:Identifier array:ArraySuffix? _ init:("=" _ Initializer)? _ ";" {
      let decl = mapType(type) + " " + name + (array ? array : "");
      if (init) {
          decl += " = " + init[2];
      }
      return decl + ";";
  }

ArraySuffix
  = "[" _ size:Expression? _ "]" {
      return "[" + (size ? size : "") + "]";
  }

Initializer
  = ArrayInit / Expression

ArrayInit
  = type:Type? _ "[]" _ "(" _ args:ArgList _ ")" {
      return "{" + args + "}";
  }
  / "{" _ args:ArgList _ "}" {
      return "{" + args + "}";
  }

/* =====================================================
   // Expressions
   ===================================================== */

Expression
  = head:Term tail:(_ BinaryOp _ Term)* {
      return head + tail.map(t => " " + t[1] + " " + t[3]).join("");
  }

BinaryOp
  = "+=" / "-=" / "*=" / "/=" / "==" / "!=" / "<=" / ">=" / "&&" / "||" / "+" / "-" / "*" / "/" / "<" / ">" / "="

Term
  = FunctionCall
  / PostfixExpr
  / "(" _ expr:Expression _ ")" { return "(" + expr + ")"; }
  / Number
  / Identifier

PostfixExpr
  = name:Identifier parts:AccessPart+ {
      return name + parts.join("");
  }

AccessPart
  = "." prop:Identifier { return "." + prop; }
  / "[" _ idx:Expression _ "]" { return "[" + idx + "]"; }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      return mapFuncCall(name, args ? args : "");
  }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return head + tail.map(t => ", " + t[3]).join("");
  }

/* =====================================================
   // Tokens & Types
   ===================================================== */

Type
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / "void" / Identifier

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = num:$(
      [0-9]+ "." [0-9]*
    / "." [0-9]+
    / [0-9]+
  ) suffix:[fF]? {
      const isFloat = num.includes('.');
      return num + (suffix ? "f" : (isFloat ? "f" : "")); 
  }

Comment
  = c:$("//" (![\n\r] .)*) { return c; }
  / c:$("/*" (!"*/" .)* "*/") { return c; }

/* =====================================================
   // Whitespace
   ===================================================== */

_  = ( [ \t\r\n] )*
__ = ( [ \t\r\n] )+
