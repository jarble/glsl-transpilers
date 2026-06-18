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

  function mapType(t){
    return typeMap[t] || t;
  }

  // Intercepts built-in GLSL variables and maps to WGSL equivalents
  function mapVariable(name) {
    const builtinVars = {
      "gl_Position": "position", // Requires @builtin(position) in WGSL
      "gl_FragColor": "color",
      "gl_FragCoord": "frag_coord",
      "gl_FrontFacing": "front_facing",
      "gl_VertexIndex": "vertex_index",
      "gl_InstanceIndex": "instance_index"
    };
    return builtinVars[name] || name;
  }

  // Intercepts the function name and its arguments to generate raw WGSL expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `radians(${a})`;
      case "degrees": return `degrees(${a})`;
      case "sin": return `sin(${a})`;
      case "cos": return `cos(${a})`;
      case "tan": return `tan(${a})`;
      case "asin": return `asin(${a})`;
      case "acos": return `acos(${a})`;
      case "atan": return args.length === 2 ? `atan2(${a}, ${b})` : `atan(${a})`;

      // Exponential
      case "pow": return `pow(${a}, ${b})`;
      case "exp": return `exp(${a})`;
      case "log": return `log(${a})`;
      case "exp2": return `exp2(${a})`;
      case "log2": return `log2(${a})`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `inverseSqrt(${a})`;

      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `sign(${a})`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `fract(${a})`;
      case "mod": return `(${a} - ${b} * floor(${a} / ${b}))`; // WGSL uses % operator but behavior differs slightly for floats
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `clamp(${a}, ${b}, ${c})`;
      case "mix": return `mix(${a}, ${b}, ${c})`;
      case "step": return `step(${a}, ${b})`;
      case "smoothstep": return `smoothstep(${a}, ${b}, ${c})`;

      // Geometric 
      case "length": return `length(${a})`;
      case "distance": return `distance(${a}, ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      // Unmapped functions pass through natively
      default: return `${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c){
    return c + "\n";
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
    return items
    ? [items[0]].concat(items[1].map(x=>x[1])).join("\n")
    : "";
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
    
    const structName = n1 || n2 || "AnonymousStruct";

    const fs = fields
      ? [fields[0]].concat(fields[1].map(x=>x[1]))
      : [];

    let result = `struct ${structName} {\n${fs.join("\n")}\n}`;

    if (n1 && n2) {
      result += `\nvar ${n2}: ${structName};`;
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
    return `  ${id}: ${mapType(t)},`;
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
    const ty = arr ? `array<${mapType(t)}>` : mapType(t);
    // Generic translation for globals. Decorators like @group / @binding usually apply in WGSL
    return `var<private> ${id}: ${ty}${init ? " = " + init : ""};`;
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
      id,
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
    const decls =
      [head].concat(
        tail.map(x => x[3])
      );

    const ty = mapType(t);

    return decls.map(d => {
      const dtype = d.arr ? `array<${ty}>` : ty;
      return `var ${d.id}: ${dtype}${d.init ? " = " + d.init : ""};`;
    }).join("\n");
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
    const retType = mapType(ret);
    const returnClause = retType === "void" ? "" : ` -> ${retType}`;
    return `fn ${name}(${params ? params.join(", ") : ""})${returnClause} ${body}`;
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
    return `${id}: ${mapType(t)}`;
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

    return "{\n" + s.join("\n") + "\n}";
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
    // WGSL strictly requires {} for ifs, but the Statement capture usually outputs it cleanly
    return "if(" + cond + ") " +
           thenStmt +
           (elsePart ? " else " + elsePart : "");
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
    return `while(${cond}) ${body}`;
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
    return `loop {\n  ${body}\n  if (!(${cond})) { break; }\n}`;
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
    return "for(" + (init||"") + "; " + (cond||"") + "; " + (update||"") + ") " + body;
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
    const ty = mapType(t);

    return decls.map(d => {
      const dtype = d.arr ? `array<${ty}>` : ty;
      return `var ${d.id}: ${dtype}${d.init ? " = " + d.init : ""}`;
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
    return "switch(" + expr + "){\n" + cases.map(x => x[0]).join("") + "\n}";
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
    return "case " + v + ":\n" + (body ? body.map(x => x[0]).join("") : "");
  }
  /
  "default"
  ":"
  _
  body:((Statement _)+)?
  {
    return "default:\n" + (body ? body.map(x => x[0]).join("") : "");
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
    return "return " + (expr||"") + ";";
  }

AssignmentStmt
  =
  e:AssignmentExpr
  _
  ";"
  { return e + ";"; }

AssignmentExpr
  =
  lhs:Assignable
  _
  op:AssignOp
  _
  rhs:Expression
  {
    return lhs + " " + op + " " + rhs;
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
    // WGSL doesn't have a native ternary, it uses select() function: select(false_val, true_val, cond)
    return `select(${ifFalse}, ${ifTrue}, ${cond})`;
  }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd
  tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t)=>a+" || "+t[3], l);
  }

LogicalAnd
  =
  l:Comparison
  tail:(_ "&&" _ Comparison)*
  {
    return tail.reduce((a,t)=>a+" && "+t[3], l);
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
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

Postfix
  =
  base:Primary
  op:("++" / "--")
  {
    return base + op;
  }
  / Primary

Unary
  =
  "++" _ v:Unary { return "++"+v; }
  / "--" _ v:Unary { return "--"+v; }
  / "!" _ v:Unary { return "!"+v; }
  / "-" _ v:Unary { return "-"+v; }
  / Postfix

Primary
  =
  base:(
      "true" { return "true"; }
    / "false" { return "false"; }
    / "(" _ e:Expression _ ")" { return "(" + e + ")"; }
    / ArrayConstructor
    / TypeConstructor
    / FuncCall
    / Number
    / id:Identifier { return mapVariable(id); }
  )
  tail:(_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const p = t[1];
      return p.type === "member"
        ? acc + "." + p.name
        : acc + "[" + p.index + "]";
    }, base);
  }

ArrayConstructor
  =
  t:BaseType
  _
  "[" _ "]"
  _
  "("
  _
  args:ArgList?
  _
  ")"
  {
    return `array<${mapType(t)}>(${args ? args.join(", ") : ""})`;
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
    const mappedBase = mapVariable(base);
    return tail.reduce((acc,t)=>{
      const p = t[1];
      return p.type === "member"
        ? acc + "." + p.name
        : acc + "[" + p.index + "]";
    }, mappedBase);
  }

AccessPart
  =
  "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

ExprStmt
  =
  expr:Expression _
  ";"
  { return expr + ";"; }

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
  num:$(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+\-]? [0-9]+)?
  )
  suffix:([fFuU])?
  {
    // Auto-append 'f' to decimals without a suffix to prevent implicit type inference issues in WGSL
    const isFloat = num.includes('.') || num.includes('e') || num.includes('E');
    if (isFloat && !suffix) {
      return num + "f";
    }
    return num + (suffix ? suffix : "");
  }

/* ===================================================== */
/* whitespace */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
