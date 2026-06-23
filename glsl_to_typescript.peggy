{
  const typeMap = {
    float: "number", int: "number", uint: "number", bool: "boolean",
    vec2: "Vector2", vec3: "Vector3", vec4: "Vector4",
    mat2: "Matrix2", mat3: "Matrix3", mat4: "Matrix4", void: "void"
  };

  const builtInVars = new Set([
    "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing",
    "gl_PointSize", "gl_VertexID", "gl_InstanceID"
  ]);

  function mapType(t) { return typeMap[t] || t; }

  // Appends "compiled_" to all user-defined variables and functions
  function mapVariable(name) {
    if (builtInVars.has(name)) return name;
    return "compiled_" + name;
  }

  // Translates built-in GLSL functions directly into TS inline expressions
  function mapFuncCall(name, args) {
    const safeArgs = args || [];
    const a = safeArgs[0] || "";
    const b = safeArgs[1] || "";
    const c = safeArgs[2] || "";

    switch(name) {
      // Inline Math Expressions
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "clamp": return `Math.min(Math.max(${a}, ${b}), ${c})`;
      case "fract": return `(${a} - Math.floor(${a}))`;
      case "step": return `(${b} < ${a} ? 0.0 : 1.0)`;
      case "smoothstep":
        const t = `Math.min(Math.max((${c} - ${a}) / (${b} - ${a}), 0.0), 1.0)`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;
      case "mod": return `(${a} - ${b} * Math.floor(${a} / ${b}))`;
      
      // Standard Library Math
      case "sin": return `Math.sin(${a})`;
      case "cos": return `Math.cos(${a})`;
      case "tan": return `Math.tan(${a})`;
      case "asin": return `Math.asin(${a})`;
      case "acos": return `Math.acos(${a})`;
      case "atan": return safeArgs.length === 2 ? `Math.atan2(${a}, ${b})` : `Math.atan(${a})`;
      case "pow": return `Math.pow(${a}, ${b})`;
      case "exp": return `Math.exp(${a})`;
      case "log": return `Math.log(${a})`;
      case "exp2": return `Math.pow(2.0, ${a})`;
      case "log2": return `Math.log2(${a})`;
      case "abs": return `Math.abs(${a})`;
      case "sign": return `Math.sign(${a})`;
      case "max": return `Math.max(${a}, ${b})`;
      case "min": return `Math.min(${a}, ${b})`;
      case "floor": return `Math.floor(${a})`;
      case "ceil": return `Math.ceil(${a})`;
      case "sqrt": return `Math.sqrt(${a})`;
      case "inversesqrt": return `(1.0 / Math.sqrt(${a}))`;
      
      // Geometric functions (Assuming standard TS Vector class/library)
      case "length": return `length(${a})`;
      case "distance": return `distance(${a}, ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      // Constructors and User-Defined
      case "vec2":
      case "vec3":
      case "vec4":
      case "mat2":
      case "mat3":
      case "mat4":
        return `new ${typeMap[name]}(${safeArgs.join(", ")})`;
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
      // Handle anonymous structs gracefully
      const structName = hName || tailName || "AnonymousStruct";
      const tsStructName = mapVariable(structName);
      
      let result = pre + `interface ${tsStructName} {\n${fields.join("\n")}\n}`;
      
      // If a trailing variable was declared inline, instantiate it
      if (tailName) {
          result += `\n${pre}let ${mapVariable(tailName)}: ${tsStructName};`;
      }
      return result;
  }

StructField
  = pre:_ t:Type __ id:Identifier _ ";" { 
      // Struct properties maintain their exact names without the 'compiled_' prefix
      return pre + `  ${id}: ${mapType(t)};`; 
  }

/* ===================================================== */
/* Globals & Variables */
/* ===================================================== */

GlobalVarDecl
  = pre:_ qual:(StorageQualifier __)? t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
      const kw = (qual && qual[0] === "const") ? "const" : "let";
      const val = init ? ` = ${init[2]}` : "";
      return pre + `${kw} ${mapVariable(id)}: ${mapType(t)}${val};`;
  }

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

LocalVarDecl
  = pre:_ t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
      const val = init ? ` = ${init[2]}` : "";
      return pre + `let ${mapVariable(id)}: ${mapType(t)}${val};`;
  }

/* ===================================================== */
/* Functions & Macros */
/* ===================================================== */

FunctionDecl
  = pre:_ ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block {
      return pre + `function ${mapVariable(name)}(${params ? params : ""}): ${mapType(ret)} ${body}`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)* { 
      return [head, ...tail.map(t => t[3])].join(", "); 
  }

Param
  = qual:(ParamQualifier __)? t:Type __ id:Identifier { 
      return `${mapVariable(id)}: ${mapType(t)}`; 
  }

ParamQualifier
  = "inout" / "in" / "out"

MacroDecl
  = pre:_ "#" _ "define" __ name:Identifier _ "(" _ head:Identifier tail:(_ "," _ Identifier)* _ ")" _ body:$([^\r\n]*) {
      const params = [head, ...tail.map(t => t[3])].join(", ");
      return pre + `function ${mapVariable(name)}(${params}) {\n    return ${body.trim()};\n}`;
  }
  / pre:_ "#" _ "define" __ name:Identifier __ body:$([^\r\n]*) {
      return pre + `const ${mapVariable(name)} = ${body.trim()};`;
  }

/* ===================================================== */
/* Statements & Control Flow */
/* ===================================================== */

Block
  = "{" _ stmts:(Statement)* _ "}" { return `{\n${stmts.join("\n")}\n}`; }

Statement
  = Block / IfStmt / ForStmt / WhileStmt / DoWhileStmt / BreakStmt / ContinueStmt / ReturnStmt / LocalVarDecl / ExprStmt / CommentStmt

BreakStmt = pre:_ "break" _ ";" { return pre + "break;"; }
ContinueStmt = pre:_ "continue" _ ";" { return pre + "continue;"; }
ReturnStmt = pre:_ "return" _ expr:Expression? _ ";" { return pre + "return" + (expr ? " " + expr : "") + ";"; }

ExprStmt
  = pre:_ expr:Expression _ ";" { return pre + expr + ";"; }

IfStmt
  = pre:_ "if" _ "(" _ cond:Expression _ ")" _ thenBlock:Statement elsePart:(_ "else" _ Statement)? {
      return pre + `if (${cond}) ${thenBlock}` + (elsePart ? ` else ${elsePart[3]}` : "");
  }

ForStmt
  = pre:_ "for" _ "(" _ init:(LocalVarDecl / ExprStmt / ";") _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Statement {
      const i = init === ";" ? ";" : init.trim();
      return pre + `for (${i} ${cond || ""}; ${update || ""}) ${body}`;
  }

WhileStmt
  = pre:_ "while" _ "(" _ cond:Expression _ ")" _ body:Statement { 
      return pre + `while (${cond}) ${body}`; 
  }

DoWhileStmt
  = pre:_ "do" _ body:Statement _ "while" _ "(" _ cond:Expression _ ")" _ ";" { 
      return pre + `do ${body} while (${cond});`; 
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
  = cond:LogicalOr _ "?" _ t:Expression _ ":" _ f:Expression { return `${cond} ? ${t} : ${f}`; } 
  / LogicalOr

LogicalOr
  = head:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((a, t) => `${a} || ${t[3]}`, head); }

LogicalAnd
  = head:Equality tail:(_ "&&" _ Equality)* { return tail.reduce((a, t) => `${a} && ${t[3]}`, head); }

Equality
  = head:Relational tail:(_ ("=="/"!=") _ Relational)* { return tail.reduce((a, t) => `${a} ${t[1]==="=="?"===":"!=="} ${t[3]}`, head); }

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
      // Safely strips C/GLSL float suffixes and guarantees valid TS decimals
      let txt = text().replace(/[fFuU]$/i, '');
      if (txt.startsWith('.')) txt = '0' + txt;
      if (txt.endsWith('.')) txt = txt + '0';
      return txt;
  }
