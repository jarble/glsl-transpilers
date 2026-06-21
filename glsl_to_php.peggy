{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "int",
    bool: "bool",

    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",

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
    // PHP variables require the $ prefix
    return "$" + (builtinVars[name] || name);
  }

  // Intercepts the function name and its arguments to generate raw PHP expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `deg2rad(${a})`;
      case "degrees": return `rad2deg(${a})`;
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
      case "exp2": return `pow(2, ${a})`;
      case "log2": return `log(${a}, 2)`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `(1.0 / sqrt(${a}))`;

      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `(${a} > 0 ? 1 : (${a} < 0 ? -1 : 0))`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `(${a} - floor(${a}))`;
      case "mod": return `fmod(${a}, ${b})`;
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `max(${a}, min(${b}, ${c}))`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0.0 : 1.0)`;
      case "smoothstep": 
        const t = `max(0.0, min(1.0, (${c} - ${a}) / (${b} - ${a})))`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;

      // Geometric (Assuming PHP Vector classes with these methods)
      case "length": return `${a}->length()`;
      case "distance": return `Vector3::distance(${a}, ${b})`;
      case "dot": return `Vector3::dot(${a}, ${b})`;
      case "cross": return `Vector3::cross(${a}, ${b})`;
      case "normalize": return `${a}->normalize()`;
      case "reflect": return `Vector3::reflect(${a}, ${b})`;

      // Unmapped functions pass through naturally
      default: return `${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c){
    return c + "\n";
  }

  // Generates the PHP Classes for GLSL Matrices
  function getBuiltInStructs() {
    return `
class mat2 {
    public Vector2 $col0;
    public Vector2 $col1;
    public function __construct(Vector2 $c0, Vector2 $c1) { $this->col0 = $c0; $this->col1 = $c1; }
}

class mat3 {
    public Vector3 $col0;
    public Vector3 $col1;
    public Vector3 $col2;
    public function __construct(Vector3 $c0, Vector3 $c1, Vector3 $c2) { $this->col0 = $c0; $this->col1 = $c1; $this->col2 = $c2; }
}

class mat4 {
    public Vector4 $col0;
    public Vector4 $col1;
    public Vector4 $col2;
    public Vector4 $col3;
    public function __construct(Vector4 $c0, Vector4 $c1, Vector4 $c2, Vector4 $c3) { $this->col0 = $c0; $this->col1 = $c1; $this->col2 = $c2; $this->col3 = $c3; }
}
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

    let result = `class ${structName} {\n${fs.join("\n")}\n}`;

    if (n1 && n2) {
      result += `\n$${n2} = new ${structName}();`;
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
    return `public ${mapType(t)} $${id};`;
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
    // PHP doesn't use static type hints for standard variables, just the $ assignment
    return "$" + id + (init ? " = " + init : " = null") + ";";
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

    return decls.map(d => {
      return "$" + d.id + (d.init ? " = " + d.init : " = null") + ";";
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
    return `function ${name}(${params ? params.join(", ") : ""}) : ${mapType(ret)}\n${body}`;
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
    const isRef = (qual && qual[0] !== "in") ? "&" : "";
    return `${mapType(t)} ${isRef}$${id}`;
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

    return decls.map(d => {
      return "$" + d.id + (d.init ? " = " + d.init : " = null");
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
        ? acc + "->" + p.name
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
    return "[" + (args ? args.join(", ") : "") + "]";
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
    return "new " + mapType(name) + "(" + (args ? args.join(", ") : "") + ")";
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
        ? acc + "->" + p.name
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
    // Drop the suffix cleanly as PHP utilizes standard implicit numeric notation
    return num;
  }

/* ===================================================== */
/* whitespace */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
