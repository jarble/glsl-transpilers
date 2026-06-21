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

    void: "None"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Helper to manage Python's semantic indentation
  function indent(text) {
    if (!text) return "";
    return text.split("\n").map(line => line.trim() === "" ? "" : "    " + line).join("\n");
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

  // Intercepts the function name and its arguments to generate Python expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `math.radians(${a})`;
      case "degrees": return `math.degrees(${a})`;
      case "sin": return `math.sin(${a})`;
      case "cos": return `math.cos(${a})`;
      case "tan": return `math.tan(${a})`;
      case "asin": return `math.asin(${a})`;
      case "acos": return `math.acos(${a})`;
      case "atan": return args.length === 2 ? `math.atan2(${a}, ${b})` : `math.atan(${a})`;

      // Exponential
      case "pow": return `math.pow(${a}, ${b})`;
      case "exp": return `math.exp(${a})`;
      case "log": return `math.log(${a})`;
      case "exp2": return `math.pow(2.0, ${a})`;
      case "log2": return `math.log2(${a})`;
      case "sqrt": return `math.sqrt(${a})`;
      case "inversesqrt": return `(1.0 / math.sqrt(${a}))`;

      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `(1 if ${a} > 0 else -1 if ${a} < 0 else 0)`;
      case "floor": return `math.floor(${a})`;
      case "ceil": return `math.ceil(${a})`;
      case "fract": return `(${a} - math.floor(${a}))`;
      case "mod": return `(${a} - ${b} * math.floor(${a} / ${b}))`;
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `max(${b}, min(${c}, ${a}))`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(0.0 if ${b} < ${a} else 1.0)`;
      case "smoothstep": 
        const t = `max(0.0, min(1.0, (${c} - ${a}) / (${b} - ${a})))`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;

      // Geometric (Assuming a vector math library is used in the Python environment)
      case "length": return `${a}.length()`;
      case "distance": return `Vector3.distance(${a}, ${b})`;
      case "dot": return `Vector3.dot(${a}, ${b})`;
      case "cross": return `Vector3.cross(${a}, ${b})`;
      case "normalize": return `Vector3.normalize(${a})`;
      case "reflect": return `Vector3.reflect(${a}, ${b})`;

      // Unmapped functions pass through naturally
      default: return `${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c){
    return c + "\n";
  }

  // Generates the Python Classes for GLSL Matrices
  function getBuiltInStructs() {
    return `
class mat2:
    def __init__(self, c0, c1):
        self.col0 = c0
        self.col1 = c1

class mat3:
    def __init__(self, c0, c1, c2):
        self.col0 = c0
        self.col1 = c1
        self.col2 = c2

class mat4:
    def __init__(self, c0, c1, c2, c3):
        self.col0 = c0
        self.col1 = c1
        self.col2 = c2
        self.col3 = c3
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
    
    // Append the Matrix implementations and math import
    return "import math\n\n" + program + "\n\n# --- GLSL Built-in Matrix Types ---\n" + getBuiltInStructs();
  }

/* ===================================================== */
/* top level */
/* ===================================================== */

TopLevel
  =
  CommentStmt
  / StructDecl
  / GlobalDecl
  / FunctionDecl
  / Statement

Statement
  =
  CommentStmt
  / VarDecl
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / ExprStmt
  / Block

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
  / MultiLineComment

SingleLineComment
  =
  c:$("//" [^\r\n]*)
  { return "#" + c.substring(2); }

MultiLineComment
  =
  c:$("/*" (!"*/" .)* "*/")
  { return '"""\n' + c.substring(2, c.length - 2).trim() + '\n"""'; }

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

    const initArgs = fs.map(f => f.id).join(", ");
    const initAssigns = fs.length > 0 
      ? fs.map(f => `self.${f.id} = ${f.id}`).join("\n        ")
      : "pass";

    let result = `class ${structName}:\n    def __init__(self${initArgs ? ', ' + initArgs : ''}):\n        ${initAssigns}`;

    if (n1 && n2) {
      result += `\n${n2} = ${structName}()`;
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
    return { id: id, type: mapType(t) };
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
    return id + " = " + (init ? init : "None");
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
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => d.id + " = " + (d.init ? d.init : "None")).join("\n");
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
    return `def ${name}(${params ? params.join(", ") : ""}):\n${indent(body)}`;
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
    // Provide basic Python type hints
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
    : ["pass"];

    return s.join("\n");
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
    return `if ${cond}:\n${indent(thenStmt)}` + (elsePart ? `\nelse:\n${indent(elsePart)}` : "");
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
    return `while ${cond}:\n${indent(body)}`;
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
    return `while True:\n${indent(body)}\n    if not (${cond}):\n        break`;
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
    let res = init ? init + "\n" : "";
    let loopBody = body;
    if (update) loopBody += "\n" + update;
    res += `while ${cond || "True"}:\n${indent(loopBody)}`;
    return res;
  }

ForInit
  =
  VarDeclInline
  / AssignmentExpr
  / Expression

ForUpdate
  =
  AssignmentExpr
  / Postfix
  / Expression

VarDeclInline
  =
  t:Type
  __
  head:Declarator
  tail:(_ "," _ Declarator)*
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => `${d.id} = ${d.init ? d.init : "None"}`).join("\n");
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
    return `match ${expr}:\n${indent(cases.map(x => x[0]).join("\n"))}`;
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
    const b = body ? body.map(x => x[0]).join("\n") : "pass";
    return `case ${v}:\n${indent(b)}`;
  }
  /
  "default"
  ":"
  _
  body:((Statement _)+)?
  {
    const b = body ? body.map(x => x[0]).join("\n") : "pass";
    return `case _:\n${indent(b)}`;
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
    return "return" + (expr ? " " + expr : "");
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
    return `${ifTrue} if ${cond} else ${ifFalse}`;
  }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd
  tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t)=>a+" or "+t[3], l);
  }

LogicalAnd
  =
  l:Comparison
  tail:(_ "&&" _ Comparison)*
  {
    return tail.reduce((a,t)=>a+" and "+t[3], l);
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
    // Python does not have a postfix increment/decrement
    return base + (op === "++" ? " += 1" : " -= 1");
  }
  / Primary

Unary
  =
  "++" _ v:Unary { return v + " += 1"; }
  / "--" _ v:Unary { return v + " -= 1"; }
  / "!" _ v:Unary { return "not " + v; }
  / "-" _ v:Unary { return "-" + v; }
  / Postfix

Primary
  =
  base:(
      "true" { return "True"; }
    / "false" { return "False"; }
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
    // Stripping f/F/u/U suffixes because standard Python doesn't utilize them
    return num;
  }

/* ===================================================== */
/* whitespace */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
