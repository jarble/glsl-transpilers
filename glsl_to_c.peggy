{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "unsigned int",
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

  // Intercepts built-in GLSL variables and constants
  function mapVariable(name) {
    const builtinVars = {
      "gl_Position": "gl_Position",
      "gl_FragColor": "gl_FragColor",
      "gl_FragCoord": "gl_FragCoord",
      "gl_FrontFacing": "gl_FrontFacing",
      "gl_PointSize": "gl_PointSize",
      "gl_VertexID": "gl_VertexID",
      "gl_InstanceID": "gl_InstanceID"
    };
    return builtinVars[name] || name;
  }

  // Intercepts the function name and its arguments to generate raw C expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} * (3.14159265358979323846f / 180.0f))`;
      case "degrees": return `(${a} * (180.0f / 3.14159265358979323846f))`;
      case "sin": return `sinf(${a})`;
      case "cos": return `cosf(${a})`;
      case "tan": return `tanf(${a})`;
      case "asin": return `asinf(${a})`;
      case "acos": return `acosf(${a})`;
      case "atan": return args.length === 2 ? `atan2f(${a}, ${b})` : `atanf(${a})`;

      // Exponential
      case "pow": return `powf(${a}, ${b})`;
      case "exp": return `expf(${a})`;
      case "log": return `logf(${a})`;
      case "exp2": return `exp2f(${a})`;
      case "log2": return `log2f(${a})`;
      case "sqrt": return `sqrtf(${a})`;
      case "inversesqrt": return `(1.0f / sqrtf(${a}))`;

      // Common Math
      case "abs": return `fabsf(${a})`;
      case "sign": return `((${a} > 0.0f) - (${a} < 0.0f))`;
      case "floor": return `floorf(${a})`;
      case "ceil": return `ceilf(${a})`;
      case "fract": return `(${a} - floorf(${a}))`;
      case "mod": return `fmodf(${a}, ${b})`;
      case "min": return `fminf(${a}, ${b})`;
      case "max": return `fmaxf(${a}, ${b})`;
      case "clamp": return `clamp(${a}, ${b}, ${c})`;
      case "mix": return `mix(${a}, ${b}, ${c})`;
      case "step": return `(${b} < ${a} ? 0.0f : 1.0f)`;
      case "smoothstep": 
        const t = `clamp((${c} - ${a}) / (${b} - ${a}), 0.0f, 1.0f)`;
        return `(${t} * ${t} * (3.0f - 2.0f * ${t}))`;

      // Geometric (Assuming standard C macro/function mappings in user code)
      case "length": return `length(${a})`;
      case "distance": return `distance(${a}, ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      // Unmapped functions pass through naturally
      default: return `${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c){
    return c + "\n";
  }

  // Generates the C Structs for GLSL Matrices
  function getBuiltInStructs() {
    return `
typedef struct {
    vec2 col0;
    vec2 col1;
} mat2;

typedef struct {
    vec3 col0;
    vec3 col1;
    vec3 col2;
} mat3;

typedef struct {
    vec4 col0;
    vec4 col1;
    vec4 col2;
    vec4 col3;
} mat4;
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
    ? [items[0]].concat(items[1].map(x=>x[1])).join("\n")
    : "";
    
    // Append the Matrix implementations to the final output
    return program + "\n\n/* --- GLSL Built-in Matrix Types --- */\n" + getBuiltInStructs();
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

    let result = `struct ${structName} {\n${fs.join("\n")}\n};`;

    if (n1 && n2) {
      result += `\nstruct ${structName} ${n2};`;
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
    return `${mapType(t)} ${id};`;
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
    const ty = mapType(t);
    return ty + " " + id + (arr ? "[]" : "") + (init ? " = " + init : "") + ";";
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
      return ty + " " + d.id + (d.arr ? "[]" : "") + (d.init ? " = " + d.init : "") + ";";
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
    return `${mapType(ret)} ${name}(${params ? params.join(", ") : ""})\n${body}`;
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
    return `${mapType(t)} ${id}`;
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
    return `do ${body} while(${cond});`;
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
      return ty + " " + d.id + (d.arr ? "[]" : "") + (d.init ? " = " + d.init : "");
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
    return cond + " ? " + ifTrue + " : " + ifFalse;
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
    return "(" + mapType(t) + "[]){ " + (args ? args.join(", ") : "") + " }";
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
    return "(" + mapType(name) + "){ " + (args ? args.join(", ") : "") + " }";
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
