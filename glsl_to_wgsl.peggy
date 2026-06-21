{
  const typeMap = {
    float: "f32",
    int: "i32",
    uint: "u32",
    bool: "bool",
    vec2: "vec2<f32>",
    vec3: "vec3<f32>",
    vec4: "vec4<f32>",
    mat2: "mat2x2<f32>",
    mat3: "mat3x3<f32>",
    mat4: "mat4x4<f32>",
    void: "void"
  };

  function mapType(t) {
    return typeMap[t] || t;
  }

  // WGSL natively shares most of GLSL's built-in math function names
  function mapFuncCall(name, argsStr) {
    if (typeMap[name]) {
        return typeMap[name] + "(" + argsStr + ")";
    }
    return name + "(" + argsStr + ")";
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
  = StructDecl
  / FuncDecl
  / VarDecl
  / Comment

/* =====================================================
   // Structs
   ===================================================== */

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:StructFields _ "}" tail:(_ Identifier)? _ ";" {
      // WGSL structs do not have trailing semicolons
      let res = "struct " + name + " {\n" + fields + "\n}";
      // Handle immediate instantiation: struct Light { ... } myLight;
      if (tail) {
          res += "\nvar " + tail[1] + ": " + name + ";";
      }
      return res;
  }

StructFields
  = fields:(StructField _)* {
      return fields.map(f => f[0]).join("\n");
  }

StructField
  = c:Comment { 
      return c.split('\n').map(line => "    " + line).join('\n'); 
  }
  / type:Type __ name:Identifier array:ArraySuffix? _ ";" {
      let wgslType = mapType(type);
      if (array !== null) {
          wgslType = "array<" + wgslType + (array !== "" ? ", " + array : "") + ">";
      }
      // WGSL fields are comma-separated
      return "    " + name + ": " + wgslType + ",";
  }

/* =====================================================
   // Functions & Parameters
   ===================================================== */

FuncDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
      const p = params ? params : "";
      const retType = mapType(type);
      const retStr = retType === "void" ? "" : " -> " + retType;
      return "fn " + name + "(" + p + ")" + retStr + " {\n" + body + "\n}";
  }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return head + tail.map(t => ", " + t[3]).join("");
  }

ParamDecl
  = mod:("inout" / "out" / "in")? _ type:Type __ name:Identifier array:ArraySuffix? {
      let wgslType = mapType(type);
      if (array !== null) {
          wgslType = "array<" + wgslType + (array !== "" ? ", " + array : "") + ">";
      }
      if (mod === "inout" || mod === "out") {
          wgslType = "ptr<function, " + wgslType + ">";
      }
      return name + ": " + wgslType;
  }

/* =====================================================
   // Statements & Variables
   ===================================================== */

Statements
  = stmts:(Statement _)* {
      return stmts.map(s => s[0]).join("\n");
  }

Statement
  = c:Comment { 
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
      let wgslType = mapType(type);
      if (array !== null) {
          wgslType = "array<" + wgslType + (array !== "" ? ", " + array : "") + ">";
      }
      let decl = "var " + name + ": " + wgslType;
      if (init) {
          decl += " = " + init[2];
      }
      return decl + ";";
  }

ArraySuffix
  = "[" _ size:Expression? _ "]" {
      return size ? size : "";
  }

Initializer
  = ArrayInit / Expression

ArrayInit
  = type:Type? _ "[]" _ "(" _ args:ArgList _ ")" {
      return "array(" + args + ")";
  }
  / "{" _ args:ArgList _ "}" {
      return "array(" + args + ")";
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
  ) suffix:[fFuU]? {
      // WGSL requires explicit float typing; appending 'f' ensures C-style floats correctly cast to f32
      const isFloat = num.includes('.');
      if (isFloat && !suffix) {
          return num + "f";
      }
      return num + (suffix ? suffix : ""); 
  }

Comment
  = c:$("//" (![\n\r] .)*) { return c; }
  / c:$("/*" (!"*/" .)* "*/") { return c; }

/* =====================================================
   // Whitespace
   ===================================================== */

_  = ( [ \t\r\n] )*
__ = ( [ \t\r\n] )+
