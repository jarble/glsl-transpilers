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

  const builtins = new Set([
    "abs", "acos", "asin", "atan", "ceil", "cos", "exp", "floor",
    "log", "max", "min", "pow", "sin", "sqrt", "tan", "round",
    "clamp", "length", "normalize", "dot", "cross", "mix",
    "step", "smoothstep", "reflect", "refract", "distance",
    "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_PointSize",
    "gl_VertexID", "gl_InstanceID", "gl_FrontFacing",
    "sampler2D", "texture2D"
  ]);

  // Appends "compiled_" unless it is a core GLSL concept
  function formatId(name) {
    if (builtins.has(name) || name.startsWith("gl_")) {
        return name;
    }
    return "compiled_" + name;
  }

  // Maps types, ensuring user-defined structs also get the prefix
  function mapType(t) {
    if (typeMap[t]) return typeMap[t];
    return formatId(t);
  }

  // Handles dot-notation properties, protecting vector swizzles
  function mapAccessPart(prop) {
    if (/^[xyzwrgbastpq]{1,4}$/.test(prop)) {
        return prop;
    }
    return formatId(prop);
  }

  function mapFuncCall(name, argsStr) {
    if (typeMap[name]) {
        return typeMap[name] + "(" + argsStr + ")";
    }
    if (builtins.has(name)) {
        return name + "(" + argsStr + ")";
    }
    return formatId(name) + "(" + argsStr + ")";
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
  = "struct" __ name:Identifier _ "{" _ fields:StructFields _ "}" tail:(_ Identifier)? _ ";" _ c:Comment? {
      let fName = formatId(name);
      let res = "struct " + fName + " {\n" + fields + "\n}";
      // Handle immediate instantiation
      if (tail) {
          res += "\nvar " + formatId(tail[1]) + ": " + fName + ";";
      }
      return res + (c ? " " + c : "");
  }

StructFields
  = fields:(StructField _)* {
      return fields.map(f => f[0]).join("\n");
  }

StructField
  = c:Comment { 
      return c.split('\n').map(line => "    " + line).join('\n'); 
  }
  / type:Type __ name:Identifier array:ArraySuffix? _ ";" _ c:Comment? {
      let wgslType = mapType(type);
      if (array !== null) {
          wgslType = "array<" + wgslType + (array !== "" ? ", " + array : "") + ">";
      }
      return "    " + formatId(name) + ": " + wgslType + "," + (c ? " " + c : "");
  }

/* =====================================================
   // Functions & Parameters
   ===================================================== */

FuncDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
      const p = params ? params : "";
      const retType = mapType(type);
      const retStr = retType === "void" ? "" : " -> " + retType;
      return "fn " + formatId(name) + "(" + p + ")" + retStr + " {\n" + body + "\n}";
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
      return formatId(name) + ": " + wgslType;
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
  = "return" __ expr:Expression? _ ";" _ c:Comment? {
      return "return " + (expr ? expr : "") + ";" + (c ? " " + c : "");
  }

ExprStmt
  = expr:Expression _ ";" _ c:Comment? { 
      return expr + ";" + (c ? " " + c : ""); 
  }

VarDecl
  = type:Type __ name:Identifier array:ArraySuffix? _ init:("=" _ Initializer)? _ ";" _ c:Comment? {
      let wgslType = mapType(type);
      if (array !== null) {
          wgslType = "array<" + wgslType + (array !== "" ? ", " + array : "") + ">";
      }
      let decl = "var " + formatId(name) + ": " + wgslType;
      if (init) {
          decl += " = " + init[2];
      }
      return decl + ";" + (c ? " " + c : "");
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
  / id:Identifier { return formatId(id); }

PostfixExpr
  = name:Identifier parts:AccessPart+ {
      return formatId(name) + parts.join("");
  }

AccessPart
  = "." prop:Identifier { return "." + mapAccessPart(prop); }
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
