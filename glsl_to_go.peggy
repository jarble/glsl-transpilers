{
  const typeMap = {
    float: "float32", int: "int32", uint: "uint32", bool: "bool",
    vec2: "Vector2", vec3: "Vector3", vec4: "Vector4",
    mat2: "Matrix2", mat3: "Matrix3", mat4: "Matrix4", void: ""
  };

  const builtInVars = new Set([
    "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing",
    "gl_PointSize", "gl_VertexID", "gl_InstanceID"
  ]);

  function mapType(t) { return typeMap[t] !== undefined ? typeMap[t] : t; }

  // Appends "compiled_" to all user-defined variables and functions
  function mapVariable(name) {
    if (builtInVars.has(name)) return name;
    return "compiled_" + name;
  }

  // Translates built-in GLSL functions into Go 'math' or 'glmath' package calls
  function mapFuncCall(name, args) {
    const safeArgs = args || [];
    const a = safeArgs[0] || "";
    const b = safeArgs[1] || "";
    const c = safeArgs[2] || "";

    switch(name) {
      // Inline Math Expressions & Shader Math
      case "mix": return `glmath.Mix(${a}, ${b}, ${c})`;
      case "clamp": return `glmath.Clamp(${a}, ${b}, ${c})`;
      case "fract": return `glmath.Fract(${a})`;
      case "step": return `glmath.Step(${a}, ${b})`;
      case "smoothstep": return `glmath.Smoothstep(${a}, ${b}, ${c})`;
      case "mod": return `math.Mod(${a}, ${b})`;
      
      // Standard Library Math
      case "sin": return `math.Sin(${a})`;
      case "cos": return `math.Cos(${a})`;
      case "tan": return `math.Tan(${a})`;
      case "asin": return `math.Asin(${a})`;
      case "acos": return `math.Acos(${a})`;
      case "atan": return safeArgs.length === 2 ? `math.Atan2(${a}, ${b})` : `math.Atan(${a})`;
      case "pow": return `math.Pow(${a}, ${b})`;
      case "exp": return `math.Exp(${a})`;
      case "log": return `math.Log(${a})`;
      case "exp2": return `math.Exp2(${a})`;
      case "log2": return `math.Log2(${a})`;
      case "abs": return `math.Abs(${a})`;
      case "max": return `math.Max(${a}, ${b})`;
      case "min": return `math.Min(${a}, ${b})`;
      case "floor": return `math.Floor(${a})`;
      case "ceil": return `math.Ceil(${a})`;
      case "sqrt": return `math.Sqrt(${a})`;
      case "inversesqrt": return `(1.0 / math.Sqrt(${a}))`;
      
      // Geometric functions
      case "length": return `glmath.Length(${a})`;
      case "distance": return `glmath.Distance(${a}, ${b})`;
      case "dot": return `glmath.Dot(${a}, ${b})`;
      case "cross": return `glmath.Cross(${a}, ${b})`;
      case "normalize": return `glmath.Normalize(${a})`;
      case "reflect": return `glmath.Reflect(${a}, ${b})`;

      // Constructors and User-Defined
      case "vec2": case "vec3": case "vec4":
      case "mat2": case "mat3": case "mat4":
        return `${mapType(name)}{${safeArgs.join(", ")}}`;
      default:
        return `${mapVariable(name)}(${safeArgs.join(", ")})`;
    }
  }
}

/* ===================================================== */
/* Entry */
/* ===================================================== */

Start
  = _ items:(TopLevel*) _ { return items.join("\n"); }

TopLevel
  = StructDecl / GlobalVarDecl / FunctionDecl / MacroDecl / CommentStmt

/* ===================================================== */
/* Whitespace & Comments (Captured for preservation) */
/* ===================================================== */

CommentStmt = pre:_ c:Comment { return pre + c; }
Comment = SingleLineComment / MultiLineComment

SingleLineComment = c:$("//" [^\r\n]*) { return c; }
MultiLineComment = c:$("/*" (!"*/" .)* "*/") { return c; }

_ = ws:([ \t\r\n] / Comment)* { return ws.join(""); }
__ = ws:([ \t\r\n] / Comment)+ { return ws.join(""); }

/* ===================================================== */
/* Structs */
/* ===================================================== */

StructDecl
  = pre:_ "struct" headName:(__ Identifier)? _ "{" _ fields:(StructField)* _ "}" _ tailName:Identifier? _ ";" {
      const hName = headName ? headName[1] : null;
      const structName = hName || tailName || "AnonymousStruct";
      const goStructName = mapVariable(structName);
      
      let result = pre + `type ${goStructName} struct {\n${fields.join("\n")}\n}`;
      
      if (tailName) {
          result += `\n${pre}var ${mapVariable(tailName)} ${goStructName}`;
      }
      return result;
  }

StructField
  = pre:_ t:Type __ id:Identifier _ ";" { 
      return pre + `  ${id} ${mapType(t)}`; 
  }

/* ===================================================== */
/* Globals & Variables */
/* ===================================================== */

GlobalVarDecl
  = pre:_ qual:(StorageQualifier __)? t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
      const val = init ? ` = ${init[2]}` : "";
      return pre + `var ${mapVariable(id)} ${mapType(t)}${val}`;
  }

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

LocalVarDecl
  = pre:_ t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
      const val = init ? ` = ${init[2]}` : "";
      return pre + `var ${mapVariable(id)} ${mapType(t)}${val}`;
  }

/* ===================================================== */
/* Functions & Macros */
/* ===================================================== */

FunctionDecl
  = pre:_ ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block {
      const returnType = mapType(ret);
      const retStr = returnType ? ` ${returnType}` : "";
      return pre + `func ${mapVariable(name)}(${params ? params : ""})${retStr} ${body}`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)* { 
      return [head, ...tail.map(t => t[3])].join(", "); 
  }

Param
  = qual:(ParamQualifier __)? t:Type __ id:Identifier { 
      return `${mapVariable(id)} ${mapType(t)}`; 
  }

ParamQualifier
  = "inout" / "in" / "out"

MacroDecl
  = pre:_ "#" _ "define" __ name:Identifier _ "(" _ head:Identifier tail:(_ "," _ Identifier)* _ ")" _ body:$([^\r\n]*) {
      const params = [head, ...tail.map(t => t[3])].join(", ");
      return pre + `func ${mapVariable(name)}(${params}) {\n    return ${body.trim()}\n}`;
  }
  / pre:_ "#" _ "define" __ name:Identifier __ body:$([^\r\n]*) {
      return pre + `const ${mapVariable(name)} = ${body.trim()}`;
  }

/* ===================================================== */
/* Statements & Control Flow */
/* ===================================================== */

Block
  = "{" _ stmts:(Statement)* _ "}" { return `{\n${stmts.join("\n")}\n}`; }

Statement
  = Block / IfStmt / SwitchStmt / ForStmt / WhileStmt / DoWhileStmt / BreakStmt / ContinueStmt / ReturnStmt / LocalVarDecl / ExprStmt / CommentStmt

BreakStmt = pre:_ "break" _ ";" { return pre + "break"; }
ContinueStmt = pre:_ "continue" _ ";" { return pre + "continue"; }
ReturnStmt = pre:_ "return" _ expr:Expression? _ ";" { return pre + "return" + (expr ? " " + expr : ""); }

ExprStmt
  = pre:_ expr:Expression _ ";" { return pre + expr; }

IfStmt
  = pre:_ "if" _ "(" _ cond:Expression _ ")" _ thenBlock:Statement elsePart:(_ "else" _ Statement)? {
      return pre + `if ${cond} ${thenBlock}` + (elsePart ? ` else ${elsePart[3]}` : "");
  }

SwitchStmt
  = pre:_ "switch" _ "(" _ expr:Expression _ ")" _ "{" _ cases:(CaseClause _)* "}" {
      return pre + `switch ${expr} {\n` + cases.map(x => x[0]).join("") + `\n}`;
  }

CaseClause
  = "case" __ v:Expression ":" _ body:((Statement _)+)? {
      // Strips trailing 'break;' or 'break' logic, mapping perfectly to idiomatic Go
      const stmts = body ? body.map(x => x[0].replace(/break\s*;?\s*$/, "") + x[1]).join("") : "";
      return `case ${v}:\n${stmts}`;
  }
  / "default" ":" _ body:((Statement _)+)? {
      const stmts = body ? body.map(x => x[0].replace(/break\s*;?\s*$/, "") + x[1]).join("") : "";
      return `default:\n${stmts}`;
  }

ForStmt
  = pre:_ "for" _ "(" _ init:(LocalVarDecl / ExprStmt / ";") _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Statement {
      const i = init === ";" ? ";" : init.trim();
      return pre + `for ${i}; ${cond || ""}; ${update || ""} ${body}`;
  }

WhileStmt
  = pre:_ "while" _ "(" _ cond:Expression _ ")" _ body:Statement { 
      return pre + `for ${cond} ${body}`; 
  }

DoWhileStmt
  = pre:_ "do" _ body:Statement _ "while" _ "(" _ cond:Expression _ ")" _ ";" { 
      return pre + `for {\n${body}\nif !(${cond}) { break }\n}`; 
  }

/* ===================================================== */
/* Expressions */
/* ===================================================== */

Expression = AssignmentExpr

AssignmentExpr
  = lhs:Assignable _ op:AssignOp _ rhs:AssignmentExpr { return `${lhs} ${op} ${rhs}`; } 
  / Ternary

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

Ternary
  = cond:LogicalOr _ "?" _ t:Expression _ ":" _ f:Expression { return `glmath.Ternary(${cond}, ${t}, ${f})`; } 
  / LogicalOr

LogicalOr
  = head:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((a, t) => `${a} || ${t[3]}`, head); }

LogicalAnd
  = head:Equality tail:(_ "&&" _ Equality)* { return tail.reduce((a, t) => `${a} && ${t[3]}`, head); }

Equality
  = head:Relational tail:(_ ("=="/"!=") _ Relational)* { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, head); }

Relational
  = head:Additive tail:(_ ("<="/">="/"<"/">") _ Additive)* { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, head); }

Additive
  = head:Multiplicative tail:(_ ("+"/"-") _ Multiplicative)* { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, head); }

Multiplicative
  = head:Unary tail:(_ ("*"/"/"/"%") _ Unary)* { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, head); }

Unary
  = op:("++"/"--"/"!"/"-") _ e:Unary { return `${op}${e}`; } 
  / Postfix

Postfix
  = base:Primary tail:PostfixPart* { return tail.reduce((a, t) => t(a), base); }

PostfixPart
  = _ "[" _ idx:Expression _ "]" { return (b) => `${b}[${idx}]`; }
  / _ "." _ prop:Identifier { return (b) => `${b}.${prop}`; }
  / _ op:("++"/"--") { return (b) => `${b}${op}`; }

Primary
  = Number 
  / Boolean 
  / "(" _ e:Expression _ ")" { return `(${e})`; } 
  / FuncCall 
  / id:Identifier { return mapVariable(id); }

Boolean = "true" / "false"

FuncCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" { return mapFuncCall(name, args); }

ArgList
  = head:Expression tail:(_ "," _ Expression)* { return [head, ...tail.map(t=>t[3])]; }

Assignable
  = base:Identifier tail:PostfixPart* { return tail.reduce((a, t) => t(a), mapVariable(base)); }

/* ===================================================== */
/* Core Tokens & Types */
/* ===================================================== */

Type
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / "void" / Identifier

Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $([0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+) $([eE][+-]?[0-9]+)? $[fFuU]? {
      // Safely strips C/GLSL float suffixes and guarantees valid Go decimals
      let txt = text().replace(/[fFuU]$/i, '');
      if (txt.startsWith('.')) txt = '0' + txt;
      if (txt.endsWith('.')) txt = txt + '0';
      return txt;
  }
