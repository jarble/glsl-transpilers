{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "int", // Mercury handles unsigned internally or via custom libs; falling back to int
    bool: "bool",

    vec2: "vec2",
    vec3: "vec3",
    vec4: "vec4",

    mat2: "mat2",
    mat3: "mat3",
    mat4: "mat4",

    void: "void"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Capitalizes identifiers to satisfy Mercury's Variable naming rules
  function cap(str) {
    if (!str) return str;
    return str.charAt(0).toUpperCase() + str.slice(1);
  }

  // Intercepts the function name and its arguments to generate raw Mercury expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} * (math.pi / 180.0))`;
      case "degrees": return `(${a} * (180.0 / math.pi))`;
      case "sin": return `math.sin(${a})`;
      case "cos": return `math.cos(${a})`;
      case "tan": return `math.tan(${a})`;
      case "asin": return `math.asin(${a})`;
      case "acos": return `math.acos(${a})`;
      case "atan": return args.length === 2 ? `math.atan2(${a}, ${b})` : `math.atan(${a})`;

      // Exponential
      case "pow": return `math.pow(${a}, ${b})`;
      case "exp": return `math.exp(${a})`;
      case "log": return `math.ln(${a})`;
      case "exp2": return `math.pow(2.0, ${a})`;
      case "log2": return `math.log2(${a})`;
      case "sqrt": return `math.sqrt(${a})`;
      case "inversesqrt": return `(1.0 / math.sqrt(${a}))`;

      // Common Math
      case "abs": return `math.abs(${a})`;
      case "sign": return `math.sign(${a})`;
      case "floor": return `math.floor(${a})`;
      case "ceil": return `math.ceiling(${a})`;
      case "fract": return `(${a} - math.floor(${a}))`;
      case "mod": return `(${a} - ${b} * math.floor(${a} / ${b}))`;
      case "min": return `math.min(${a}, ${b})`;
      case "max": return `math.max(${a}, ${b})`;
      case "clamp": return `math.clamp(${a}, ${b}, ${c})`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(if ${b} < ${a} then 0.0 else 1.0)`;
      case "smoothstep": 
        const t = `math.clamp((${c} - ${a}) / (${b} - ${a}), 0.0, 1.0)`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;

      // Geometric (Assuming a custom vec module in Mercury)
      case "length": return `vec.length(${a})`;
      case "distance": return `vec.distance(${a}, ${b})`;
      case "dot": return `vec.dot(${a}, ${b})`;
      case "cross": return `vec.cross(${a}, ${b})`;
      case "normalize": return `vec.normalize(${a})`;

      // Unmapped functions pass through naturally
      default: return `${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c){
    return c + "\n";
  }

  // Generates the Mercury Algebraic Data Types for GLSL Matrices
  function getBuiltInStructs() {
    return `
:- type mat2
    ---> mat2(
        col0 :: vec2,
        col1 :: vec2
    ).

:- type mat3
    ---> mat3(
        col0 :: vec3,
        col1 :: vec3,
        col2 :: vec3
    ).

:- type mat4
    ---> mat4(
        col0 :: vec4,
        col1 :: vec4,
        col2 :: vec4,
        col3 :: vec4
    ).
`;
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  =
  _
  items:(TopLevel (_ TopLevel)*)?
  _
  {
    const program = items
    ? [items[0]].concat(items[1].map(x=>x[1])).join("\n\n")
    : "";
    
    return program + "\n\n% --- GLSL Built-in Matrix Types --- %\n" + getBuiltInStructs();
  }

/* ===================================================== */
/* top level */
/* ===================================================== */

TopLevel
  =
  CommentStmt
  /
  StructDecl
  /
  GlobalDecl
  /
  FunctionDecl
  /
  Statement

Statement
  =
  CommentStmt
  /
  VarDecl
  /
  AssignmentStmt
  /
  ReturnStmt
  /
  IfStmt
  /
  ForStmt
  /
  WhileStmt
  /
  DoWhileStmt
  /
  SwitchStmt
  /
  ExprStmt
  /
  Block

/* ===================================================== */
/* comments */
/* ===================================================== */

CommentStmt
  =
  c:Comment
  { return emitComment(c); }

Comment
  =
  SingleLineComment
  /
  MultiLineComment

SingleLineComment
  =
  $("//" [^\r\n]*)

MultiLineComment
  =
  $("/*" (!"*/" .)* "*/")

/* ===================================================== */
/* structs */
/* ===================================================== */

StructDecl
  =
  "struct"
  headName:(__ Identifier)?
  _
  "{"
  _
  fields:(StructField (_ StructField)*)?
  _
  "}"
  _
  tailName:(Identifier)?
  _
  ";"?
  {
    const n1 = headName ? headName[1] : null;
    const n2 = tailName;
    const structName = n1 || n2 || "anonymous_struct";

    const fs = fields
      ? [fields[0]].concat(fields[1].map(x=>x[1]))
      : [];

    let result = `:- type ${structName}\n    ---> ${structName}(\n        ${fs.join(",\n        ")}\n    ).`;

    if (n1 && n2) {
      result += `\n:- func ${n2} = ${structName}.`;
    }

    return result;
  }

StructField
  =
  t:Type
  __
  id:Identifier
  _
  ";"
  {
    return `${id} :: ${mapType(t)}`;
  }

/* ===================================================== */
/* globals */
/* ===================================================== */

GlobalDecl
  =
  qual:StorageQualifier?
  _
  t:Type
  __
  id:Identifier
  arr:ArraySuffix?
  _
  init:("=" _ e:Expression { return e; })?
  _
  ";"
  {
    const ty = arr ? "list(" + mapType(t) + ")" : mapType(t);
    return `:- func ${id} = ${ty}.\n${id} = ` + (init ? init : "default") + ".";
  }

StorageQualifier
  =
  "uniform"
  / "attribute"
  / "varying"
  / "const"

/* ===================================================== */
/* variables */
/* ===================================================== */

Declarator
  =
  id:Identifier
  arr:ArraySuffix?
  _
  init:(
    "="
    _
    e:Expression
    { return e; }
  )?
  {
    return {
      id: cap(id),
      arr,
      init
    };
  }

VarDecl
  =
  t:Type
  __
  head:Declarator
  tail:(_ "," _ Declarator)*
  _
  ";"
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => {
      return d.id + " = " + (d.init ? d.init : "Default");
    }).join(", ");
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type
  __
  name:Identifier
  _
  "("
  _
  params:ParamList?
  _
  ")"
  _
  body:Block
  {
    const paramTypes = params ? params.map(p => p.type).join(", ") : "";
    const paramVars = params ? params.map(p => p.id).join(", ") : "";
    const retType = mapType(ret);
    
    let decl = `:- func ${name}(${paramTypes}) = ${retType}.\n`;
    decl += `${name}(${paramVars}) = ReturnValue :-\n${body}.`;
    return decl;
  }

ParamList
  =
  head:Param
  tail:(_ "," _ Param)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

Param
  =
  qual:(ParameterQualifier __)?
  t:Type
  __
  id:Identifier
  {
    return { type: mapType(t), id: cap(id) };
  }

ParameterQualifier
  =
  "inout"
  / "in"
  / "out"

/* ===================================================== */
/* blocks */
/* ===================================================== */

Block
  =
  "{"
  _
  stmts:(Statement (_ Statement)*)?
  _
  "}"
  {
    const s = stmts
    ? [stmts[0]].concat(stmts[1].map(x=>x[1]))
    : [];

    return "    (\n        " + s.join(",\n        ") + "\n    )";
  }

/* ===================================================== */
/* control flow */
/* ===================================================== */

IfStmt
  =
  "if"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  thenStmt:Statement
  elsePart:(_ "else" _ elseStmt:Statement { return elseStmt; })?
  {
    return "( if " + cond + " then\n        " + thenStmt + "\n    else\n        " + (elsePart ? elsePart : "true") + "\n    )";
  }

WhileStmt
  =
  "while"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  body:Statement
  {
    return `while_loop(${cond}, ${body})`; // Pseudo-syntax for Mercury
  }

DoWhileStmt
  =
  "do"
  _
  body:Statement
  _
  "while"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  ";"
  {
    return `do_while_loop(${body}, ${cond})`;
  }

ForStmt
  =
  "for"
  _
  "("
  _
  init:ForInit?
  _
  ";"
  _
  cond:Expression?
  _
  ";"
  _
  update:ForUpdate?
  _
  ")"
  _
  body:Statement
  {
    return "for_loop(" + (init||"true") + ", " + (cond||"true") + ", " + (update||"true") + ", " + body + ")";
  }

ForInit
  =
  VarDeclInline
  /
  AssignmentExpr
  /
  Expression

ForUpdate
  =
  AssignmentExpr
  /
  Postfix
  /
  Expression

VarDeclInline
  =
  t:Type
  __
  head:Declarator
  tail:(_ "," _ Declarator)*
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => {
      return d.id + " = " + (d.init ? d.init : "Default");
    }).join(", ");
  }

/* ===================================================== */
/* switch */
/* ===================================================== */

SwitchStmt
  =
  "switch"
  _
  "("
  _
  expr:Expression
  _
  ")"
  _
  "{"
  _
  cases:(CaseClause _)*
  "}"
  {
    return "( % switch " + expr + "\n" + cases.map(x => x[0]).join("\n; ") + "\n)";
  }

CaseClause
  =
  "case"
  __
  v:Expression
  ":"
  _
  body:((Statement _)+)?
  {
    return "    ( " + v + " -> " + (body ? body.map(x => x[0]).join(", ") : "true") + " )";
  }
  /
  "default"
  ":"
  _
  body:((Statement _)+)?
  {
    return "    ( _ -> " + (body ? body.map(x => x[0]).join(", ") : "true") + " )";
  }

/* ===================================================== */
/* return / assignment */
/* ===================================================== */

ReturnStmt
  =
  "return"
  _
  expr:Expression?
  _
  ";"
  {
    return "ReturnValue = " + (expr || "true");
  }

AssignmentStmt
  =
  e:AssignmentExpr
  _
  ";"
  { return e; }

AssignmentExpr
  =
  lhs:Assignable
  _
  op:AssignOp
  _
  rhs:Expression
  {
    if (op === "=") return lhs + " = " + rhs;
    return lhs + " = " + lhs + " " + op.charAt(0) + " " + rhs;
  }

AssignOp
  =
  "+=" / "-=" / "*=" / "/=" / "="

/* ===================================================== */
/* EXPRESSIONS */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr
  _
  "?"
  _
  ifTrue:Expression
  _
  ":"
  _
  ifFalse:Expression
  {
    return "( if " + cond + " then " + ifTrue + " else " + ifFalse + " )";
  }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd
  tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t)=>a+" ; "+t[3], l); // Mercury uses ; for logical OR
  }

LogicalAnd
  =
  l:Comparison
  tail:(_ "&&" _ Comparison)*
  {
    return tail.reduce((a,t)=>a+", "+t[3], l); // Mercury uses , for logical AND
  }

Comparison
  =
  l:AddSub
  tail:(_ CompOp _ AddSub)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

CompOp
  =
  "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  =
  l:MulDiv
  tail:(_ ("+"/"-") _ MulDiv)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

MulDiv
  =
  l:Unary
  tail:(_ ("*" / "/" / "%") _ Unary)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l); // Note: mod in Mercury usually uses 'mod' instead of '%'
  }

Postfix
  =
  base:Primary
  op:("++" / "--")
  {
    return base + " = " + base + " " + op.charAt(0) + " 1";
  }
  / Primary

Unary
  =
  "++" _ v:Unary { return v + " = " + v + " + 1"; }
  / "--" _ v:Unary { return v + " = " + v + " - 1"; }
  / "!" _ v:Unary { return "not(" + v + ")"; }
  / "-" _ v:Unary { return "-" + v; }
  / Postfix

Primary
  =
  base:(
      "true" { return "true"; }
    / "false" { return "false"; }
    / "(" _ e:Expression _ ")" { return "(" + e + ")"; }
    / TypeConstructor
    / FuncCall
    / Number
    / Identifier
  )
  tail:(_ AccessPart)*
  {
    let computedBase = typeof base === "string" && base.match(/^[a-zA-Z]/) && base !== "true" && base !== "false" && !base.includes("(") ? cap(base) : base;
    return tail.reduce((acc, t) => {
      const p = t[1];
      return p.type === "member"
        ? acc + "^" + p.name // Record field access in Mercury
        : "list.det_index0(" + acc + ", " + p.index + ")";
    }, computedBase);
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4")
  _
  "("
  _
  args:ArgList?
  _
  ")"
  {
    return mapType(name) + "(" + (args ? args.join(", ") : "") + ")";
  }

FuncCall
  =
  name:Identifier
  _
  "("
  _
  args:ArgList?
  _
  ")"
  {
    return mapFuncCall(name, args);
  }

ArgList
  =
  head:Expression
  tail:(_ "," _ Expression)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

/* ===================================================== */
/* assignables */
/* ===================================================== */

Assignable
  =
  base:Identifier
  tail:(_ AccessPart)*
  {
    return tail.reduce((acc,t)=>{
      const p = t[1];
      return p.type === "member"
        ? acc + "^" + p.name
        : acc + "[" + p.index + "]"; // Left-hand side lists are tricky in pure Logic, abstracting here
    }, cap(base));
  }

AccessPart
  =
  "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

ExprStmt
  =
  expr:Expression _
  ";"
  { return expr; }

/* ===================================================== */
/* types */
/* ===================================================== */

Type = BaseType

BaseType
  =
  "float"
  / "int"
  / "uint"
  / "bool"
  / "vec2"
  / "vec3"
  / "vec4"
  / "mat2"
  / "mat3"
  / "mat4"
  / "void"
  / Identifier

ArraySuffix = "[" _ "]"

Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  =
  $(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+\-]? [0-9]+)?
      [fFuU]?
  )

/* ===================================================== */
/* whitespace */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
