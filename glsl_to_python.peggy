{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "int",
    bool: "bool",

    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",
    uvec2: "Vector2",
    uvec3: "Vector3",
    uvec4: "Vector4",

    mat2: "mat2",
    mat3: "mat3",
    mat4: "mat4",

    void: "None"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Appends/prepends 'compiled_' to user-defined variables
  function mapVariable(name) {
    const builtinVars = new Set([
      "gl_Position", "gl_FragColor", "gl_FragCoord",
      "gl_FrontFacing", "gl_PointSize", "gl_VertexID", "gl_InstanceID",
      "true", "false",
      "x", "y", "z", "w", "r", "g", "b", "a", "s", "t", "p", "q"
    ]);
    
    // Skip vector swizzling (e.g., .xyz, .rgba)
    if (/^[xyzw]{2,4}$/.test(name) || /^[rgba]{2,4}$/.test(name) || /^[stpq]{2,4}$/.test(name)) {
      return name;
    }
    
    return builtinVars.has(name) ? name : "compiled_" + name;
  }

  // Appends/prepends 'compiled_' to user-defined functions and structs
  function mapName(name) {
    return name.startsWith("compiled_") ? name : "compiled_" + name;
  }

  // Helper to manage Python's semantic indentation
  function indent(text) {
    if (!text) return "";
    return text.split("\n").map(line => line.trim() === "" ? "" : "    " + line).join("\n");
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

      // Unmapped functions get prefixed
      default: return `${mapName(name)}(${args.join(", ")})`;
    }
  }

  // Generates the Python Classes for GLSL Matrices
  function getBuiltInStructs() {
    return `class mat2:
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
        self.col3 = c3`;
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  =
  ws1:_ items:(TopLevel)* ws2:_
  {
    const program = items.join("\n\n");
    return "import math\n\n" + ws1 + program + ws2 + "\n\n# --- GLSL Built-in Matrix Types ---\n" + getBuiltInStructs();
  }

/* ===================================================== */
/* top level */
/* ===================================================== */

TopLevel
  =
  c:_ item:(StructDecl / GlobalDecl / FunctionDecl / Statement)
  { return c + item; }

Statement
  =
  c:_ stmt:(VarDecl / AssignmentStmt / ReturnStmt / IfStmt / ForStmt / WhileStmt / DoWhileStmt / SwitchStmt / ExprStmt / Block)
  { return c + stmt; }

/* ===================================================== */
/* comments */
/* ===================================================== */

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
  "struct" ws1:__ headName:Identifier? ws2:_ "{" ws3:_ fields:(StructField)* ws4:_ "}" ws5:__ tailName:Identifier? ws6:_ ";"?
  {
    const n1 = headName ? mapName(headName) : null;
    const n2 = tailName ? mapVariable(tailName) : null;
    const structName = n1 || n2 || mapName("AnonymousStruct");

    const initArgs = fields.map(f => f.id).join(", ");
    const initAssigns = fields.length > 0 
      ? fields.map(f => f.comments + `self.${f.id} = ${f.id}`).join("\n        ")
      : "pass";

    let result = `class ${structName}:\n    def __init__(self${initArgs ? ', ' + initArgs : ''}):\n        ${initAssigns}`;

    if (n1 && n2) {
      result += `\n${n2} = ${structName}()`;
    }

    return ws1 + ws2 + ws3 + ws4 + ws5 + ws6 + result;
  }

StructField
  =
  w:_ t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    return { id: mapVariable(id), type: mapType(t), comments: w + ws1 + ws2 + ws3 };
  }

/* ===================================================== */
/* globals */
/* ===================================================== */

GlobalDecl
  =
  qual:StorageQualifier? ws1:_ t:Type ws2:__ id:Identifier arr:ArraySuffix? ws3:_ init:("=" ws4:_ e:Expression { return ws4+e; })? ws5:_ ";"
  {
    return ws1 + ws2 + ws3 + ws5 + mapVariable(id) + " = " + (init ? init : "None");
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
  id:Identifier arr:ArraySuffix? ws1:_ init:("=" ws2:_ e:Expression { return ws2+e; })?
  {
    return {
      id: mapVariable(id),
      arr,
      init
    };
  }

VarDecl
  =
  t:Type ws1:__ head:Declarator tail:(w1:_ "," w2:_ Declarator { return {decl: w2, ws: w1+w2}; })* ws4:_ ";"
  {
    const decls = [head].concat(tail.map(x => x.decl));
    const tailComments = tail.map(x => x.ws).join("");
    return ws1 + tailComments + ws4 + decls.map(d => d.id + " = " + (d.init ? d.init : "None")).join("\n");
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    return ws1 + ws2 + ws3 + ws4 + ws5 + `def ${mapName(name)}(${params ? params.join(", ") : ""}):\n${indent(body)}`;
  }

ParamList
  =
  head:Param tail:(ws1:_ "," ws2:_ Param { return ws1+ws2+Param; })*
  {
    return [head].concat(tail.map(x => x[3]));
  }

Param
  =
  qual:(ParameterQualifier __)? t:Type ws1:__ id:Identifier
  {
    return ws1 + `${mapVariable(id)}: ${mapType(t)}`;
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
  "{" ws1:_ stmts:(Statement)* ws2:_ "}"
  {
    const body = ws1 + stmts.join("\n") + ws2;
    return body.trim() ? body : "pass";
  }

/* ===================================================== */
/* control flow */
/* ===================================================== */

IfStmt
  =
  "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else:\n" + indent(ws6 + elseStmt); })?
  {
    return ws1 + ws2 + ws3 + ws4 + `if ${cond}:\n${indent(thenStmt)}` + (elsePart ? "\n" + elsePart : "");
  }

WhileStmt
  =
  "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  {
    return ws1 + ws2 + ws3 + ws4 + `while ${cond}:\n${indent(body)}`;
  }

DoWhileStmt
  =
  "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  {
    return ws1 + ws2 + ws3 + ws4 + ws5 + ws6 + `while True:\n${indent(body)}\n    if not (${cond}):\n        break`;
  }

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    let res = ws1 + ws2 + ws3 + ws4 + ws5 + ws6 + ws7 + ws8;
    if (init) res += init + "\n";
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
  t:Type ws1:__ head:Declarator tail:(w1:_ "," w2:_ Declarator {return {decl: w2, ws: w1+w2}; })*
  {
    const decls = [head].concat(tail.map(x => x.decl));
    const comments = ws1 + tail.map(x => x.ws).join("");
    return comments + decls.map(d => `${d.id} = ${d.init ? d.init : "None"}`).join("\n");
  }

/* ===================================================== */
/* switch */
/* ===================================================== */

SwitchStmt
  =
  "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" ws5:_ cases:(CaseClause)* ws6:_ "}"
  {
    return ws1 + ws2 + ws3 + ws4 + ws5 + ws6 + `match ${expr}:\n${indent(cases.join("\n"))}`;
  }

CaseClause
  =
  "case" ws1:__ v:Expression ws2:_ ":" ws3:_ body:(Statement)* ("break" _ ";")?
  {
    const b = body.length > 0 ? ws3 + body.join("\n") : ws3 + "pass";
    return ws1 + ws2 + `case ${v}:\n${indent(b)}`;
  }
  /
  "default" ws1:_ ":" ws2:_ body:(Statement)* ("break" _ ";")?
  {
    const b = body.length > 0 ? ws2 + body.join("\n") : ws2 + "pass";
    return ws1 + `case _:\n${indent(b)}`;
  }

/* ===================================================== */
/* return / assignment */
/* ===================================================== */

ReturnStmt
  =
  "return" ws1:_ expr:Expression? ws2:_ ";"
  {
    return ws1 + "return" + (expr ? " " + expr : "") + ws2;
  }

AssignmentStmt
  =
  e:AssignmentExpr ws1:_ ";"
  { return e + ws1; }

AssignmentExpr
  =
  lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  {
    return ws1 + ws2 + lhs + " " + op + " " + rhs;
  }

AssignOp
  =
  "+=" / "-=" / "*=" / "/=" / "%=" / "<<=" / ">>=" / "&=" / "^=" / "|=" / "="

/* ===================================================== */
/* EXPRESSIONS */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  {
    return `(${ifTrue} if ${cond} else ${ifFalse})`;
  }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t)=>a+" or "+t[3], l);
  }

LogicalAnd
  =
  l:BitwiseOr tail:(_ "&&" _ BitwiseOr)*
  {
    return tail.reduce((a,t)=>a+" and "+t[3], l);
  }

BitwiseOr
  =
  l:BitwiseXor tail:(_ "|" _ BitwiseXor)*
  {
    return tail.reduce((a,t)=>a+" | "+t[3], l);
  }

BitwiseXor
  =
  l:BitwiseAnd tail:(_ "^" _ BitwiseAnd)*
  {
    return tail.reduce((a,t)=>a+" ^ "+t[3], l);
  }

BitwiseAnd
  =
  l:Equality tail:(_ "&" _ Equality)*
  {
    return tail.reduce((a,t)=>a+" & "+t[3], l);
  }

Equality
  =
  l:Relational tail:(_ ("=="/"!=") _ Relational)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

Relational
  =
  l:Shift tail:(_ ("<="/">="/"<"/">") _ Shift)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

Shift
  =
  l:AddSub tail:(_ ("<<"/">>") _ AddSub)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

AddSub
  =
  l:MulDiv tail:(_ ("+"/"-") _ MulDiv)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

MulDiv
  =
  l:Unary tail:(_ ("*" / "/" / "%") _ Unary)*
  {
    return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
  }

Postfix
  =
  base:Primary op:("++" / "--")
  {
    return base + (op === "++" ? " += 1" : " -= 1");
  }
  / Primary

Unary
  =
  "++" _ v:Unary { return v + " += 1"; }
  / "--" _ v:Unary { return v + " -= 1"; }
  / "!" _ v:Unary { return "not " + v; }
  / "-" _ v:Unary { return "-" + v; }
  / "~" _ v:Unary { return "~" + v; }
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
  t:BaseType _ "[" _ "]" _ "(" _ args:ArgList? _ ")"
  {
    return "[" + (args ? args.join(", ") : "") + "]";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"uvec2"/"uvec3"/"uvec4"/"mat2"/"mat3"/"mat4") _ "(" _ args:ArgList? _ ")"
  {
    return mapType(name) + "(" + (args ? args.join(", ") : "") + ")";
  }

FuncCall
  =
  name:Identifier _ "(" _ args:ArgList? _ ")"
  {
    return mapFuncCall(name, args);
  }

ArgList
  =
  head:Expression tail:(_ "," _ Expression)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

/* ===================================================== */
/* assignables */
/* ===================================================== */

Assignable
  =
  base:Identifier tail:(_ AccessPart)*
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
  expr:Expression ws1:_ ";"
  { return expr + ws1; }

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
  / "uvec2"
  / "uvec3"
  / "uvec4"
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
  suffix:([fFuU]+)?
  {
    // Stripping f/F/u/U suffixes because standard Python doesn't utilize them.
    // Handles 1., .3, and standard forms.
    return num;
  }

/* ===================================================== */
/* whitespace & comments capture mechanism */
/* ===================================================== */

_ 
  = ws:( [ \t\r\n]+ { return ""; } / c:Comment { return c; } )* { 
    let res = ws.filter(x => x !== "").join("\n");
    return res ? res + "\n" : ""; 
  }

__ 
  = ws:( [ \t\r\n]+ { return ""; } / c:Comment { return c; } )+ 
  { 
    let res = ws.filter(x => x !== "").join("\n");
    return res ? res + "\n" : ""; 
  }
