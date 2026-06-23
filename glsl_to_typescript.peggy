{
  // 1. Type and Function Mapping
  const typeMap = {
    "float": "number", "int": "number", "uint": "number", "bool": "boolean",
    "vec2": "Vector2", "vec3": "Vector3", "vec4": "Vector4", "mat2": "Matrix2",
    "mat3": "Matrix3", "mat4": "Matrix4", "void": "void"
  };

  const builtinMap = {
    "abs": "Math.abs", "acos": "Math.acos", "asin": "Math.asin",
    "atan": "Math.atan2", "ceil": "Math.ceil", "cos": "Math.cos",
    "exp": "Math.exp", "floor": "Math.floor", "log": "Math.log",
    "max": "Math.max", "min": "Math.min", "pow": "Math.pow",
    "sin": "Math.sin", "sqrt": "Math.sqrt", "tan": "Math.tan",
    "sign": "Math.sign", "round": "Math.round", "trunc": "Math.trunc",
    "clamp": "clamp", "mix": "mix", "dot": "dot", "cross": "cross",
    "normalize": "normalize", "length": "length", "distance": "distance"
  };

  function prefixId(id) {
    if (builtinMap[id] || typeMap[id] || id === "main" || id === "gl_Position" || id === "gl_FragColor" || id === "gl_FragCoord") return id;
    return "compiled_" + id;
  }

  function mapType(t) { return typeMap[t] || prefixId(t); }
  function mapFunc(f) { return builtinMap[f] || prefixId(f); }
}

/* =====================================================
   Entry Point
   ===================================================== */
Start
  = _ items:(TopLevel (_ TopLevel)*)? _ {
      if (!items) return "";
      return [items[0]].concat(items[1].map(x => x[1])).join("\n\n");
    }

TopLevel
  = MacroDecl
  / StructDecl
  / FunctionDecl
  / GlobalVarDecl

/* =====================================================
   Macro Translations (#define)
   ===================================================== */
MacroDecl
  = "#" _ "define" __ name:Identifier _ "(" _ head:Identifier tail:(_ "," _ Identifier)* _ ")" _ body:$([^\r\n]*) {
      const params = [head, ...tail.map(t => t[3])].join(", ");
      return `function ${name}(${params}) {\n    return ${body.trim()};\n}`;
  }
  / "#" _ "define" __ name:Identifier __ body:$([^\r\n]*) {
      return `const ${name} = ${body.trim()};`;
  }

/* =====================================================
   Struct Declarations
   ===================================================== */
StructDecl
  = "struct" __ name:Identifier _ "{" _ members:(StructMember)+ "}" _ ";" {
      const m = members.join("\n    ");
      return `interface ${name} {\n    ${m}\n}`;
  }

StructMember
  = type:Type __ name:Identifier _ arr:ArraySuffix? _ ";" _ {
      return `${name}: ${mapType(type)}${arr ? "[]" : ""};`;
  }

/* =====================================================
   Functions & Variables
   ===================================================== */
FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block {
      const p = params ? params : "";
      return `function ${name}(${p}): ${mapType(type)} ${body}`;
  }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return [head].concat(tail.map(x => x[3])).join(", ");
  }

ParamDecl
  = qual:ParamQualifier? type:Type __ name:Identifier _ arr:ArraySuffix? {
      let tsType = mapType(type);
      if (arr) tsType += "[]";
      return `${name}: ${tsType}`;
  }

ParamQualifier
  = ("inout" / "in" / "out") __

GlobalVarDecl
  = qual:VarQualifier? type:Type __ name:Identifier _ arr:ArraySuffix? _ "=" _ expr:Expression _ ";" {
      const kw = (qual && qual.trim() === "const") ? "const" : "let";
      return `${kw} ${name}: ${mapType(type)}${arr ? "[]" : ""} = ${expr};`;
  }
  / qual:VarQualifier? type:Type __ name:Identifier _ arr:ArraySuffix? _ ";" {
      return `let ${name}: ${mapType(type)}${arr ? "[]" : ""};`;
  }

VarQualifier
  = ("const" / "uniform" / "varying" / "attribute") __ { return text(); }

/* =====================================================
   Control Flow & Statements
   ===================================================== */
Block
  = "{" _ stmts:(Statement _)* "}" {
      const s = stmts.map(x => x[0]).join("\n    ");
      return `{\n    ${s}\n}`;
  }

Statement
  = StructDecl
  / Block
  / IfStmt
  / ForStmt
  / WhileStmt
  / BreakStmt
  / ContinueStmt
  / ReturnStmt
  / DeclStmt
  / ExprStmt

BreakStmt
  = "break" _ ";" { return "break;"; }

ContinueStmt
  = "continue" _ ";" { return "continue;"; }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ trueBlock:Statement falseBlock:(_ "else" _ Statement)? {
      let res = `if (${cond}) ${trueBlock}`;
      if (falseBlock) res += ` else ${falseBlock[3]}`;
      return res;
  }

ForStmt
  = "for" _ "(" _ init:(DeclStmt / ExprStmt / ";") _ cond:Expression? _ ";" _ step:Expression? _ ")" _ body:Statement {
      const i = init === ";" ? ";" : init;
      const c = cond ? cond : "";
      const s = step ? step : "";
      return `for (${i} ${c}; ${s}) ${body}`;
  }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement {
      return `while (${cond}) ${body}`;
  }

ReturnStmt
  = "return" __ expr:Expression _ ";" { return `return ${expr};`; }
  / "return" _ ";" { return `return;`; }

DeclStmt
  = type:Type __ name:Identifier _ arr:ArraySuffix? _ "=" _ expr:Expression _ ";" {
      return `let ${name}: ${mapType(type)}${arr ? "[]" : ""} = ${expr};`;
  }
  / type:Type __ name:Identifier _ arr:ArraySuffix? _ ";" {
      return `let ${name}: ${mapType(type)}${arr ? "[]" : ""};`;
  }

ExprStmt
  = expr:Expression _ ";" { return `${expr};`; }

/* =====================================================
   Expressions
   ===================================================== */
Expression
  = AssignmentExpr

AssignmentExpr
  = left:PostfixExpr _ op:("=" / "+=" / "-=" / "*=" / "/=") _ right:AssignmentExpr {
      return `${left} ${op} ${right}`;
  }
  / LogicalOrExpr

LogicalOrExpr
  = head:LogicalAndExpr tail:(_ "||" _ LogicalAndExpr)* {
      return tail.reduce((result, element) => `${result} || ${element[3]}`, head);
  }

LogicalAndExpr
  = head:EqualityExpr tail:(_ "&&" _ EqualityExpr)* {
      return tail.reduce((result, element) => `${result} && ${element[3]}`, head);
  }

EqualityExpr
  = head:RelationalExpr tail:(_ ("==" / "!=") _ RelationalExpr)* {
      return tail.reduce((result, element) => {
          const op = element[1] === "==" ? "===" : "!=="; // Enforce strict equality
          return `${result} ${op} ${element[3]}`;
      }, head);
  }

RelationalExpr
  = head:AdditiveExpr tail:(_ ("<=" / ">=" / "<" / ">") _ AdditiveExpr)* {
      return tail.reduce((result, element) => `${result} ${element[1]} ${element[3]}`, head);
  }

AdditiveExpr
  = head:MultiplicativeExpr tail:(_ ("+" / "-") _ MultiplicativeExpr)* {
      return tail.reduce((result, element) => `${result} ${element[1]} ${element[3]}`, head);
  }

MultiplicativeExpr
  = head:UnaryExpr tail:(_ ("*" / "/") _ UnaryExpr)* {
      return tail.reduce((result, element) => `${result} ${element[1]} ${element[3]}`, head);
  }

UnaryExpr
  = op:("+" / "-" / "!") _ expr:UnaryExpr { return `${op}${expr}`; }
  / PostfixExpr

PostfixExpr
  = base:PrimaryExpr parts:PostfixPart* {
      return parts.reduce((result, part) => part(result), base);
  }

PostfixPart
  = _ "[" _ idx:Expression _ "]" {
      return (base) => `${base}[${idx}]`;
  }
  / _ "." prop:Identifier {
      return (base) => `${base}.${prop}`;
  }
  / _ "(" _ args:ArgList? _ ")" {
      return (base) => {
          const argStr = args ? args : "";
          return `${mapFunc(base)}(${argStr})`;
      };
  }
  / _ op:("++" / "--") {
      return (base) => `${base}${op}`;
  }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head].concat(tail.map(t => t[3])).join(", ");
  }

PrimaryExpr
  = ArrayConstructor // <-- Catches array initializers like vec3[](...)
  / Number
  / "true" { return "true"; }
  / "false" { return "false"; }
  / Identifier
  / "(" _ expr:Expression _ ")" { return `(${expr})`; }

ArrayConstructor
  // Matches float[4](...) and float[](...) and translates to TS array literals [...]
  = Type _ "[" _ Expression? _ "]" _ "(" _ args:ArgList? _ ")" {
      return `[${args ? args : ""}]`;
  }

/* =====================================================
   Lexical Tokens & Primitives
   ===================================================== */
Type
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4"
  / "mat2" / "mat3" / "mat4" / "void" / Identifier

ArraySuffix
  // Modified to consume potential indices: [4], [], etc.
  = "[" _ Expression? _ "]" { return true; }

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $( ([0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+) ([eE] [+-]? [0-9]+)? [fFuU]? )

/* =====================================================
   Whitespace & Comments
   ===================================================== */
_
  = (WhiteSpace / SingleLineComment / MultiLineComment)*

__
  = (WhiteSpace / SingleLineComment / MultiLineComment)+

WhiteSpace
  = [ \t\r\n]

SingleLineComment
  = "//" [^\r\n]*

MultiLineComment
  = "/*" (!"*/" .)* "*/"
