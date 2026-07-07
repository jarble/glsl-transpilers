{
  const builtIns = new Set([
    "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing",
    "gl_PointSize", "gl_VertexID", "gl_InstanceID",
    "float", "int", "uint", "bool", "void",
    "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
    "true", "false"
  ]);

  // Safely prefix user-defined variables to prevent Ruby keyword collisions
  function mapVariable(name) {
    if (builtIns.has(name)) return name;
    if (/^[xyzw]{2,4}$/.test(name)) return name;
    if (/^[rgba]{2,4}$/.test(name)) return name;
    if (/^[stpq]{2,4}$/.test(name)) return name;
    if (name.startsWith("compiled_")) return name;
    return "compiled_" + name;
  }

  // Maps GLSL math to Ruby Math module and native methods
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      case "radians": return `(${a} * (Math::PI / 180.0))`;
      case "degrees": return `(${a} * (180.0 / Math::PI))`;
      case "sin": return `Math.sin(${a})`;
      case "cos": return `Math.cos(${a})`;
      case "tan": return `Math.tan(${a})`;
      case "asin": return `Math.asin(${a})`;
      case "acos": return `Math.acos(${a})`;
      case "atan": return args.length === 2 ? `Math.atan2(${a}, ${b})` : `Math.atan(${a})`;
      case "pow": return `(${a} ** ${b})`;
      case "exp": return `Math.exp(${a})`;
      case "log": return `Math.log(${a})`;
      case "sqrt": return `Math.sqrt(${a})`;
      case "abs": return `${a}.abs`;
      case "floor": return `${a}.floor`;
      case "ceil": return `${a}.ceil`;
      case "round": return `${a}.round`;
      case "min": return `[${a}, ${b}].min`;
      case "max": return `[${a}, ${b}].max`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0.0 : 1.0)`;
      default: return `${mapVariable(name)}(${args.join(", ")})`;
    }
  }

  function emitComment(c) {
    // Translates C-style comments to Ruby comments
    return c.replace(/\/\//g, '#').replace(/\/\*/g, '=begin\n').replace(/\*\//g, '\n=end') + "\n";
  }
}

/* ===================================================== */
/* Entry Point                                           */
/* ===================================================== */

Start
  = _ items:(TopLevel (_ TopLevel)*)? _
  {
    return items ? [items[0]].concat(items[1].map(x => x[1])).join("\n\n") : "";
  }

TopLevel
  = CommentStmt
  / StructDecl
  / GlobalDecl
  / FunctionDecl

Statement
  = CommentStmt
  / VarDecl
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / SwitchStmt
  / ExprStmt
  / Block
  / BreakStmt

/* ===================================================== */
/* Comments & Whitespace                                 */
/* ===================================================== */

CommentStmt
  = c:Comment { return emitComment(c); }

Comment
  = SingleLineComment / MultiLineComment

SingleLineComment
  = $ ("//" [^\r\n]*)

MultiLineComment
  = $ ("/*" (!"*/" .)* "*/")

_  = ws:([ \t\r\n] / Comment)* { return ws.join(""); }
__ = ws:([ \t\r\n] / Comment)+ { return ws.join(""); }

/* ===================================================== */
/* Structs (Ruby Struct.new)                             */
/* ===================================================== */

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:(StructField (_ StructField)*)? _ "}" _ tailName:Identifier? _ ";"
  {
    const structName = mapVariable(name || tailName || "AnonymousStruct");
    const fs = fields ? [fields[0]].concat(fields[1].map(x => x[1])) : [];
    const syms = fs.map(f => `:${f}`).join(", ");
    
    let result = `${structName} = Struct.new(${syms})`;
    if (tailName && name) {
      result += `\n${mapVariable(tailName)} = ${structName}.new`;
    }
    return result;
  }

StructField
  = t:Type __ id:Identifier _ ";" { return mapVariable(id); }

/* ===================================================== */
/* Variables & Globals                                   */
/* ===================================================== */

GlobalDecl
  = qual:StorageQualifier? _ t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";"
  {
    const val = init ? ` = ${init[2]}` : " = nil";
    return `${mapVariable(id)}${val}`;
  }

StorageQualifier = "uniform" / "attribute" / "varying" / "const"

VarDecl
  = t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";"
  {
    const val = init ? ` = ${init[2]}` : " = nil";
    return `${mapVariable(id)}${val}`;
  }

/* ===================================================== */
/* Functions                                             */
/* ===================================================== */

FunctionDecl
  = ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block
  {
    const pStr = params ? params.join(", ") : "";
    return `def ${mapVariable(name)}(${pStr})\n${body}\nend`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)*
  { return [head].concat(tail.map(x => x[3])); }

Param
  = qual:(ParamQualifier __)? t:Type __ id:Identifier
  { return mapVariable(id); }

ParamQualifier = "inout" / "in" / "out"

/* ===================================================== */
/* Blocks & Control Flow                                 */
/* ===================================================== */

Block
  = "{" _ stmts:(Statement (_ Statement)*)? _ "}"
  {
    const s = stmts ? [stmts[0]].concat(stmts[1].map(x => x[1])) : [];
    // Indent for readability
    return s.map(line => "  " + line).join("\n");
  }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ thenStmt:Statement elsePart:(_ "else" _ Statement)?
  {
    const el = elsePart ? `\nelse\n  ${elsePart[3]}` : "";
    return `if ${cond}\n  ${thenStmt}${el}\nend`;
  }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement
  {
    return `while ${cond}\n  ${body}\nend`;
  }

ForStmt
  = "for" _ "(" _ init:(VarDecl / ExprStmt / ";") _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Statement
  {
    const i = init === ";" ? "" : init + "\n";
    const c = cond || "true";
    const u = update ? `\n  ${update}` : "";
    return `${i}while ${c}\n  ${body}${u}\nend`;
  }

SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ cases:(CaseClause _)* "}"
  {
    const cStr = cases.map(x => x[0]).join("\n");
    return `case ${expr}\n${cStr}\nend`;
  }

CaseClause
  = "case" __ v:Expression _ ":" _ body:((Statement _)+)?
  {
    const bStr = body ? body.map(x => "  " + x[0]).filter(x => !x.includes("break")).join("\n") : "";
    return `when ${v}\n${bStr}`;
  }
  / "default" _ ":" _ body:((Statement _)+)?
  {
    const bStr = body ? body.map(x => "  " + x[0]).filter(x => !x.includes("break")).join("\n") : "";
    return `else\n${bStr}`;
  }

BreakStmt
  = "break" _ ";" { return "break"; }

ReturnStmt
  = "return" _ expr:Expression? _ ";"
  { return "return" + (expr ? " " + expr : ""); }

AssignmentStmt
  = e:AssignmentExpr _ ";" { return e; }

ExprStmt
  = expr:Expression _ ";" { return expr; }

/* ===================================================== */
/* Expressions                                           */
/* ===================================================== */

Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ ifTrue:Expression _ ":" _ ifFalse:Expression
  { return `${cond} ? ${ifTrue} : ${ifFalse}`; }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(_ "||" _ LogicalAnd)*
  { return tail.reduce((a, t) => `${a} || ${t[3]}`, l); }

LogicalAnd
  = l:Comparison tail:(_ "&&" _ Comparison)*
  { return tail.reduce((a, t) => `${a} && ${t[3]}`, l); }

Comparison
  = l:AddSub tail:(_ CompOp _ AddSub)*
  { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(_ ("+"/"-") _ MulDiv)*
  { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, l); }

MulDiv
  = l:Unary tail:(_ ("*" / "/" / "%") _ Unary)*
  { return tail.reduce((a, t) => `${a} ${t[1]} ${t[3]}`, l); }

Unary
  = op:("++"/"--"/"!"/"-") _ v:Unary
  {
    if (op === "!") return `!${v}`;
    if (op === "++") return `${v} += 1`;
    if (op === "--") return `${v} -= 1`;
    return `${op}${v}`;
  }
  / Postfix

Postfix
  = base:Primary tail:PostfixPart*
  { return tail.reduce((acc, part) => part(acc), base); }

PostfixPart
  = _ "[" _ idx:Expression _ "]" { return (b) => `${b}[${idx}]`; }
  / _ "." _ prop:Identifier { return (b) => `${b}.${prop}`; }
  / _ op:("++"/"--") { return (b) => (op === "++" ? `${b} += 1` : `${b} -= 1`); }

Primary
  = "true" { return "true"; }
  / "false" { return "false"; }
  / "(" _ e:Expression _ ")" { return `(${e})`; }
  / ArrayConstructor
  / FuncCall
  / Number
  / Identifier

ArrayConstructor
  = type:Type _ "[" _ size:Expression? _ "]" _ "(" _ args:ArgList? _ ")"
  {
    const argStr = args ? args.join(", ") : "";
    return `[${argStr}]`;
  }
  / type:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") _ "(" _ args:ArgList? _ ")"
  {
    // Vectors/Matrices rendered as native Ruby arrays for duck-typing
    const argStr = args ? args.join(", ") : "";
    return `[${argStr}]`;
  }

FuncCall
  = name:Identifier _ "(" _ args:ArgList? _ ")"
  { return mapFuncCall(name, args); }

ArgList
  = head:Expression tail:(_ "," _ Expression)*
  { return [head].concat(tail.map(x => x[3])); }

/* ===================================================== */
/* Assignables                                           */
/* ===================================================== */

AssignmentExpr
  = lhs:Assignable _ op:AssignOp _ rhs:Expression
  { return `${lhs} ${op} ${rhs}`; }

Assignable
  = base:Identifier tail:PostfixPart*
  { return tail.reduce((acc, part) => part(acc), mapVariable(base)); }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

/* ===================================================== */
/* Types and Core Tokens                                 */
/* ===================================================== */

Type
  = "float" / "int" / "uint" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / Identifier

Identifier
  = name:$([a-zA-Z_][a-zA-Z0-9_]*) { return mapVariable(name); }

Number
  = num:$(
      ([0-9]+ "." [0-9]*)
    / ("." [0-9]+)
    / ([0-9]+)
    )
    exp:$([eE] [+\-]? [0-9]+)?
    suffix:([fFuU])?
  {
    // Strip 'f' and 'u' suffixes since Ruby dynamically assigns Floats and Integers
    let val = num + (exp || "");
    if (val.startsWith(".")) val = "0" + val;
    if (val.endsWith(".")) val = val + "0";
    if (!val.includes(".") && !exp) val += ".0"; // default scalar to float to mimic GLSL
    return val;
  }
