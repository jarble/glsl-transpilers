{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "int",
    bool: "bool",

    vec2: "vec2",
    vec3: "vec3",
    vec4: "vec4",

    mat2: "mat2",
    mat3: "mat3",
    mat4: "mat4",

    void: "unit"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Intercepts identifiers to safely append 'compiled_' to user-defined names
  function mapIdentifier(name) {
    const builtIns = new Set([
        // Types
        "float", "int", "uint", "bool", "void",
        "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
        // Functions
        "radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan",
        "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt",
        "abs", "sign", "floor", "ceil", "fract", "mod", "min", "max", "clamp", "mix", "step", "smoothstep",
        "length", "distance", "dot", "cross", "normalize", "reflect",
        // Built-in vars
        "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing", "gl_PointSize", "gl_VertexID", "gl_InstanceID",
        // Keywords/Booleans
        "true", "false",
        // Single letter swizzles
        "x", "y", "z", "w", "r", "g", "b", "a", "s", "t", "p", "q"
    ]);
    
    // Skip recognized built-in GLSL identifiers
    if (builtIns.has(name)) return name;
    
    // Skip vector swizzling properties (e.g., .xyz, .rgba, .stpq)
    if (/^[xyzw]{2,4}$/.test(name)) return name;
    if (/^[rgba]{2,4}$/.test(name)) return name;
    if (/^[stpq]{2,4}$/.test(name)) return name;

    // Prevent double-prefixing just in case
    if (name.startsWith("compiled_")) return name;

    return "compiled_" + name;
  }

  // Generates raw OCaml expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} *. (Float.pi /. 180.0))`;
      case "degrees": return `(${a} *. (180.0 /. Float.pi))`;
      case "sin": return `sin (${ws2}${a}${ws3})`;
      case "cos": return `cos (${ws2}${a}${ws3})`;
      case "tan": return `tan (${ws2}${a}${ws3})`;
      case "asin": return `asin (${ws2}${a}${ws3})`;
      case "acos": return `acos (${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `atan2 ${a} ${b}` : `atan(${a})`;

      // Exponential
      case "pow": return `(${a} ** ${b})`;
      case "exp": return `exp(${a})`;
      case "log": return `log(${a})`;
      case "exp2": return `(2.0 ** ${a})`;
      case "log2": return `(log(${a}) /. log(2.0))`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `(1.0 /. sqrt(${a}))`;

      // Common Math
      case "abs": return `abs_float(${a})`;
      case "sign": return `(if ${a} > 0.0 then 1.0 else if ${a} < 0.0 then -1.0 else 0.0)`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `(${a} -. floor(${a}))`;
      case "mod": return `mod_float ${a} ${b}`;
      case "min": return `min ${a} ${b}`;
      case "max": return `max ${a} ${b}`;
      case "clamp": return `max ${a} (min ${b} ${c})`;
      case "mix": return `(${a} *. (1.0 -. ${c}) +. ${b} *. ${c})`;
      case "step": return `(if ${b} < ${a} then 0.0 else 1.0)`;
      case "smoothstep": 
        const t = `(max 0.0 (min 1.0 ((${c} -. ${a}) /. (${b} -. ${a}))))`;
        return `(${t} *. ${t} *. (3.0 -. 2.0 *. ${t}))`;

      // Geometric 
      case "length": return `Vec.length ${a}`;
      case "distance": return `Vec.distance ${a} ${b}`;
      case "dot": return `Vec.dot ${a} ${b}`;
      case "cross": return `Vec.cross ${a} ${b}`;
      case "normalize": return `Vec.normalize ${a}`;
      case "reflect": return `Vec.reflect ${a} ${b}`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1} ${ws2}${argsStr}${ws3}`;
    }
  }

  // Generates OCaml Structs for GLSL Matrices AND Type Conversions
  function getBuiltInStructs() {
    return `
(* --- GLSL Built-in Matrix Types --- *)
type mat2 = { mutable col0: vec2; mutable col1: vec2 }
let make_mat2 c0 c1 = { col0 = c0; col1 = c1 }

type mat3 = { mutable col0: vec3; mutable col1: vec3; mutable col2: vec3 }
let make_mat3 c0 c1 c2 = { col0 = c0; col1 = c1; col2 = c2 }

type mat4 = { mutable col0: vec4; mutable col1: vec4; mutable col2: vec4; mutable col3: vec4 }
let make_mat4 c0 c1 c2 c3 = { col0 = c0; col1 = c1; col2 = c2; col3 = c3 }

(* --- GLSL Type Conversions --- *)
let _float_of_bool v = if v then 1.0 else 0.0
let _float_of_int v = float_of_int v
let _int_of_bool v = if v then 1 else 0
let _int_of_float v = int_of_float v
let _bool_of_int v = v <> 0
let _bool_of_float v = v <> 0.0
`;
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  =
  items:(ws:_ t:TopLevel { return ws + t; })*
  wsEnd:_
  {
    const program = items.join("\n") + wsEnd;
    return program + "\n\n" + getBuiltInStructs();
  }

TopLevel
  =
  StructDecl
  / GlobalDecl
  / FunctionDecl
  / Statement

Statement
  =
  VarDecl
  / AssignmentStmt
  / ReturnStmt
  / BreakStmt
  / ContinueStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / ExprStmt
  / Block

/* ===================================================== */
/* structs */
/* ===================================================== */

StructDecl
  =
  "struct" ws1:__ headName:(Identifier)? ws2:_ "{" items:(ws:_ sf:StructField { return ws + sf; })* wsEnd:_ "}" ws3:_ tailName:(Identifier)? ws4:_ ";"?
  {
    const n1 = headName;
    const n2 = tailName;
    const structName = n1 || n2 || "anonymous_struct";

    let result = "type " + structName + ws2 + "={" + items.join(";") + wsEnd + "}";

    if (n1 && n2) {
      result += ws3 + "let " + n2 + " = ref " + "(make_" + structName + " ());";
    }

    return result;
  }

StructField
  =
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    const typeStr = arr ? t + " array" : t;
    return "mutable " + id + ws2 + " : " + typeStr;
  }

/* ===================================================== */
/* globals */
/* ===================================================== */

GlobalDecl
  =
  qual:(sq:StorageQualifier ws:__ { return {sq, ws}; })? 
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })? ws4:_ ";"
  {
    const ty = mapType(t);
    const dtype = arr ? ty + " array" : ty;
    let initStr = init ? init : " = Obj.magic ()"; // fallback initialization
    
    if (arr && arr.size && !init) {
      initStr = " = Array.make " + arr.size + " (Obj.magic ())";
    }

    return "let " + id + ws2 + " : " + dtype + " ref" + ws3 + initStr + ws4;
  }

StorageQualifier = "uniform" / "attribute" / "varying" / "const"

/* ===================================================== */
/* variables */
/* ===================================================== */

Declarator
  =
  id:Identifier ws1:_ arr:ArraySuffix? ws2:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })?
  {
    return { id, ws1, arr, ws2, init };
  }

VarDecl
  =
  t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)* ws2:_ ";"
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));

    // Safely unroll multiple comma-separated declarations (float a, b;) to ensure arrays translate correctly
    return decls.map((d, i) => {
      const dtype = d.arr ? ty + " array" : ty;
      let initStr = d.init ? d.init : " = Obj.magic ()";
      if (d.arr && d.arr.size && !d.init) {
         initStr = " = Array.make " + d.arr.size + " (Obj.magic ())";
      }
      
      if (i === 0) {
          return "let " + d.id + d.ws1 + " : " + dtype + " ref " + d.ws2 + initStr + " in";
      } else {
          return d.wsA + "let " + d.wsB + d.id + d.ws1 + " : " + dtype + " ref " + d.ws2 + initStr + " in";
      }
    }).join("\n") + ws2;
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    return "let " + name + ws2 + " " + ws3 + (params||"()") + ws4 + " : " + mapType(ret) + ws5 + "=" + body;
  }

ParamList
  =
  head:Param tail:(ws1:_ "," ws2:_ Param)*
  {
    return head + tail.map(x => ws1 + " " + ws2 + x[3]).join("");
  }

Param
  =
  qual:(pq:ParameterQualifier ws:__ { return {pq, ws}; })? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    const typeStr = arr ? t + " array" : t;
    return "(" + id + " : " + typeStr + ")";
  }

ParameterQualifier = "inout" { return "ref"; } / "in" { return ""; } / "out" { return "out"; }

/* ===================================================== */
/* blocks & control flow */
/* ===================================================== */

Block
  =
  "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  {
    return "begin\n" + items.join(";\n") + wsEnd + "end";
  }

IfStmt
  =
  "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement
  elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  {
    return "if" + ws1 + ws2 + cond + ws3 + " then\n" + ws4 + thenStmt + (elsePart || " else ()");
  }

WhileStmt
  =
  "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { return "while" + ws1 + ws2 + cond + ws3 + " do\n" + ws4 + body + "\ndone"; }

DoWhileStmt
  =
  "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { return "begin " + ws1 + body + ws2 + "; while" + ws3 + ws4 + cond + ws5 + " do\n" + body + "\ndone end" + ws6; }

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    return "begin " + ws1 + ws2 + (init||"()") + ws3 + "; while " + ws4 + (cond||"true") + ws5 + " do begin\n" + body + "; " + ws6 + (update||"()") + ws7 + " end done end";
  }

ForInit = VarDeclInline / AssignmentExpr / Expression

ForUpdate = AssignmentExpr / Postfix / Expression

VarDeclInline
  =
  t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)*
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    
    return decls.map((d, i) => {
        let initStr = d.init ? d.init : " = Obj.magic ()";
        if (d.arr && d.arr.size && !d.init) {
           initStr = " = Array.make " + d.arr.size + " (Obj.magic ())";
        }
        return "let " + d.id + d.ws1 + " = ref (" + d.ws2 + initStr.substring(1) + ") in ";
    }).join("");
  }

SwitchStmt
  =
  "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  {
    return "match" + ws1 + ws2 + expr + ws3 + " with\n" + cases.join("\n") + wsEnd;
  }

CaseClause
  =
  "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "| " + v + ws2 + " -> begin\n" + items.join(";\n") + "\nend"; }
  /
  "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "| _" + ws1 + " -> begin\n" + items.join(";\n") + "\nend"; }

/* ===================================================== */
/* return, break, continue & assignments */
/* ===================================================== */

ReturnStmt
  =
  "return" ws1:__ expr:Expression? ws2:_ ";"
  { return (expr||"()") + ws2; }
  /
  "return" ws1:_ ";"
  { return "()" + ws1; }

BreakStmt
  =
  "break" ws1:_ ";"
  { return "()" + ws1; }

ContinueStmt
  =
  "continue" ws1:_ ";"
  { return "()" + ws1; }

AssignmentStmt
  =
  e:AssignmentExpr ws1:_ ";"
  { return e + ws1; }

AssignmentExpr
  =
  lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { return lhs + ws1 + op + ws2 + rhs; }

// Assuming := for refs and <- for array/record properties
AssignOp = "+=" / "-=" / "*=" / "/=" / "=" { return ":="; }

ExprStmt
  =
  expr:Expression ws1:_ ";"
  { return expr + ws1; }

/* ===================================================== */
/* expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return "if " + cond + ws1 + " then " + ws2 + ifTrue + ws3 + " else " + ws4 + ifFalse; }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd tail:(ws1:_ "||" ws2:_ LogicalAnd)*
  { return tail.reduce((a,t) => a + t[0] + "||" + t[2] + t[3], l); }

LogicalAnd
  =
  l:Comparison tail:(ws1:_ "&&" ws2:_ Comparison)*
  { return tail.reduce((a,t) => a + t[0] + "&&" + t[2] + t[3], l); }

Comparison
  =
  l:AddSub tail:(ws1:_ op:CompOp ws2:_ AddSub)*
  { return tail.reduce((a,t) => a + t[0] + (t[1] === "==" ? "=" : t[1] === "!=" ? "<>" : t[1]) + t[2] + t[3], l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  =
  l:MulDiv tail:(ws1:_ op:("+"/"-") ws2:_ MulDiv)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

MulDiv
  =
  l:Unary tail:(ws1:_ op:("*" / "/" / "%") ws2:_ Unary)*
  { return tail.reduce((a,t) => a + t[0] + (t[1] === "%" ? "mod" : t[1]) + t[2] + t[3], l); }

Unary
  =
  op:("++"/"--"/"!"/"-") ws1:_ v:Unary { return (op==="!" ? "not" : op) + ws1 + v; }
  / Postfix

Postfix
  =
  base:Primary op:("++" / "--")
  { return base + " := !" + base + " " + (op==="++" ? "+" : "-") + " 1"; }
  / Primary

Primary
  =
  base:(
      "true" { return "true"; }
    / "false" { return "false"; }
    / "(" ws1:_ e:Expression ws2:_ ")" { return "(" + ws1 + e + ws2 + ")"; }
    / ArrayConstructor
    / TypeConstructor
    / ScalarConstructor
    / FuncCall
    / Number
    / id:Identifier { return id; }
  )
  tail:(ws1:_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const ws = t[0];
      const p = t[1];
      return p.type === "member"
        ? acc + ws + "." + p.ws + p.name
        : acc + ws + ".(" + p.ws1 + p.index + p.ws2 + ")";
    }, base);
  }

ArrayConstructor
  =
  t:BaseType ws1:_ "[" ws2:_ size:Expression? ws3:_ "]" ws4:_ "(" ws5:_ args:ArgList? ws6:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "[|" + ws5 + argsStr + ws6 + "|]";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.list.join(" ") : "";
    return "make_" + mapType(name) + ws1 + "(" + ws2 + argsStr + ws3 + ")";
  }

ScalarConstructor
  =
  name:("float" / "int" / "uint" / "bool") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "_" + name + "_of_" + "unknown" /* Placeholder for dynamic cast resolution */ + ws1 + " " + ws2 + argsStr + ws3;
  }

FuncCall
  =
  name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    return mapFuncCall(name, args, ws1, ws2, ws3);
  }

ArgList
  =
  head:Expression tail:(ws1:_ "," ws2:_ Expression)*
  {
    return {
      str: head + tail.map(x => x[0] + " " + x[2] + x[3]).join(""), // mapped ',' to space for currying
      list: [head].concat(tail.map(x => x[3]))
    };
  }

/* ===================================================== */
/* assignables */
/* ===================================================== */

Assignable
  =
  base:Identifier tail:(ws1:_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const ws = t[0];
      const p = t[1];
      return p.type === "member"
        ? acc + ws + "." + p.ws + p.name
        : acc + ws + ".(" + p.ws1 + p.index + p.ws2 + ")";
    }, base);
  }

AccessPart
  =
  "." ws:_ name:Identifier { return {type:"member", name, ws}; }
  / "[" ws1:_ idx:Expression ws2:_ "]" { return {type:"index", index:idx, ws1, ws2}; }

/* ===================================================== */
/* types & tokens */
/* ===================================================== */

Type = BaseType

BaseType
  =
  t:(
    "float" / "int" / "uint" / "bool" / "void"
  / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4"
  )
  { return mapType(t); }
  / Identifier

ArraySuffix = "[" ws1:_ size:Expression? ws2:_ "]" { return { size, str: "[" + ws1 + (size||"") + ws2 + "]" }; }

// Uses the smart heuristic wrapper
Identifier = name:$([a-zA-Z_][a-zA-Z0-9_]*) { return mapIdentifier(name); }

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
      return num; // natively parsed as float in OCaml
    }
    return num;
  }

/* ===================================================== */
/* formatting & whitespace matching */
/* ===================================================== */

Comment = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"

// Extracts the exact matched string of whitespace/comments to pass through the AST
_  = ws:$( ( [ \t\r\n] / Comment )* ) { return ws; }
__ = ws:$( ( [ \t\r\n] / Comment )+ ) { return ws; }
