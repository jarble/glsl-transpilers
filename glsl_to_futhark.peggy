{
  const typeMap = {
    float: "f32",
    int: "i32",
    uint: "u32",
    bool: "bool",

    vec2: "[2]f32",
    vec3: "[3]f32",
    vec4: "[4]f32",

    mat2: "[2][2]f32",
    mat3: "[3][3]f32",
    mat4: "[4][4]f32",

    void: ""
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

  // Generates raw Futhark expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} * (f32.pi / 180.0))`;
      case "degrees": return `(${a} * (180.0 / f32.pi))`;
      case "sin": return `(f32.sin ${ws2}${a}${ws3})`;
      case "cos": return `(f32.cos ${ws2}${a}${ws3})`;
      case "tan": return `(f32.tan ${ws2}${a}${ws3})`;
      case "asin": return `(f32.asin ${ws2}${a}${ws3})`;
      case "acos": return `(f32.acos ${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `(f32.atan2 ${a} ${b})` : `(f32.atan ${a})`;

      // Exponential
      case "pow": return `(${a} ** ${b})`;
      case "exp": return `(f32.exp ${a})`;
      case "log": return `(f32.log ${a})`;
      case "exp2": return `(2.0 ** ${a})`;
      case "log2": return `(f32.log2 ${a})`;
      case "sqrt": return `(f32.sqrt ${a})`;
      case "inversesqrt": return `(1.0 / f32.sqrt ${a})`;

      // Common Math
      case "abs": return `(f32.abs ${a})`;
      case "sign": return `(f32.sgn ${a})`;
      case "floor": return `(f32.floor ${a})`;
      case "ceil": return `(f32.ceil ${a})`;
      case "fract": return `(${a} - f32.floor ${a})`;
      case "mod": return `(${a} % ${b})`;
      case "min": return `(f32.min ${a} ${b})`;
      case "max": return `(f32.max ${a} ${b})`;
      case "clamp": return `(f32.max ${a} (f32.min ${b} ${c}))`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(if ${b} < ${a} then 0.0 else 1.0)`;
      case "smoothstep": 
        const t = `(f32.max 0.0 (f32.min 1.0 ((${c} - ${a}) / (${b} - ${a}))))`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;

      // Geometric (Relying on standard 1D array math in Futhark)
      case "length": return `(f32.sqrt (f32.sum (map (\\x -> x * x) ${a})))`;
      case "distance": return `(f32.sqrt (f32.sum (map2 (\\x y -> (x - y) ** 2.0) ${a} ${b})))`;
      case "dot": return `(f32.sum (map2 (*) ${a} ${b}))`;
      case "cross": return `[${a}[1]*${b}[2] - ${a}[2]*${b}[1], ${a}[2]*${b}[0] - ${a}[0]*${b}[2], ${a}[0]*${b}[1] - ${a}[1]*${b}[0]]`;
      case "normalize": return `(let l = f32.sqrt (f32.sum (map (\\x -> x * x) ${a})) in map (/ l) ${a})`;
      case "reflect": return `(let d = f32.sum (map2 (*) ${a} ${b}) in map2 (\\i n -> i - 2.0 * d * n) ${a} ${b})`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }

  // Generates Polyfills for Matrix Types (Futhark handles arrays natively, returning empty)
  function getBuiltInStructs() {
    return `
-- Futhark natively treats GLSL vectors and matrices as multi-dimensional arrays.
-- The compiled outputs rely on standard [N]f32 and [N][M]f32 representations.
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
    const program = items.join("") + wsEnd;
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
    const structName = n1 || n2 || "AnonymousStruct";

    let result = "type " + structName + ws2 + " = {" + items.join(",") + wsEnd + "}";

    if (n1 && n2) {
      result += ws3 + "let " + n2 + " : " + structName + " = empty_" + structName;
    }

    return result;
  }

StructField
  =
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    const typeStr = arr ? "[" + arr.size + "]" + t : t;
    return id + ws1 + ": " + typeStr;
  }

/* ===================================================== */
/* globals */
/* ===================================================== */

GlobalDecl
  =
  qual:(sq:StorageQualifier ws:__ { return {sq, ws}; })? 
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ init:("=" ws:_ e:Expression { return ws + "=" + ws + e; })? ws4:_ ";"
  {
    const ty = mapType(t);
    const dtype = arr && arr.size ? "[" + arr.size + "]" + ty : ty;
    let initStr = init ? init : "";
    
    if (arr && arr.size && !init) {
      initStr = " = replicate " + arr.size + " 0.0f32";
    }

    const qStr = qual ? qual.ws : "";
    return qStr + "let " + id + ws1 + ": " + dtype + ws2 + ws3 + initStr;
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

    // Shadowing multiple comma-separated variables into sequential let bindings
    return decls.map((d, i) => {
      const dtype = d.arr && d.arr.size ? "[" + d.arr.size + "]" + ty : ty;
      let initStr = d.init ? d.init : " = 0"; // Fallback init for Futhark
      if (d.arr && d.arr.size && !d.init) {
         initStr = " = replicate " + d.arr.size + " 0";
      }
      
      if (i === 0) {
          return "let " + d.id + " : " + dtype + d.ws1 + d.ws2 + initStr;
      } else {
          return d.wsA + d.wsB + "let " + d.id + " : " + dtype + d.ws1 + d.ws2 + initStr;
      }
    }).join("\n");
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    const retType = ret ? " : " + ret : "";
    return "def " + name + ws2 + "(" + ws3 + (params||"") + ws4 + ")" + retType + ws5 + "=\n" + body;
  }

ParamList
  =
  head:Param tail:(ws1:_ "," ws2:_ Param)*
  {
    return head + tail.map(x => ", " + x[3]).join("");
  }

Param
  =
  qual:(pq:ParameterQualifier ws:__ { return {pq, ws}; })? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    const typeStr = arr && arr.size ? "[" + arr.size + "]" + t : t;
    return id + " : " + typeStr;
  }

ParameterQualifier = "inout" { return "ref"; } / "in" { return ""; } / "out" { return "out"; }

/* ===================================================== */
/* blocks & control flow */
/* ===================================================== */

Block
  =
  "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  {
    return "(\n" + items.join("\n") + wsEnd + ")";
  }

IfStmt
  =
  "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement
  elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  {
    return "if" + ws1 + cond + ws3 + "then\n" + ws4 + thenStmt + "\n" + (elsePart ? elsePart : "else ()");
  }

WhileStmt
  =
  "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { return "loop () = () while " + cond + ws3 + "do\n" + ws4 + body; }

DoWhileStmt
  =
  "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { return "loop () = () while " + cond + ws5 + "do\n" + ws1 + body; }

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    return "(let _ = " + (init||"()") + " in loop () = () while " + (cond||"true") + " do (\n" + body + "\nlet _ = " + (update||"()") + " in ()))";
  }

ForInit = VarDeclInline / AssignmentExpr / Expression

ForUpdate = AssignmentExpr / Postfix / Expression

VarDeclInline
  =
  t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)*
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    const firstDtype = head.arr && head.arr.size ? "[" + head.arr.size + "]" + ty : ty;
    
    return decls.map((d, i) => {
        let initStr = d.init ? d.init : "";
        if (d.arr && d.arr.size && !d.init) {
           initStr = " = replicate " + d.arr.size + " 0";
        }
        return "let " + d.id + " : " + firstDtype + d.ws1 + d.ws2 + initStr;
    }).join("\n");
  }

SwitchStmt
  =
  "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  {
    return "match " + expr + ws4 + "\n" + cases.join("\n") + wsEnd;
  }

CaseClause
  =
  "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "case " + v + ws2 + "->" + items.join(""); }
  /
  "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "case _ " + ws1 + "->" + items.join(""); }

/* ===================================================== */
/* return & assignments */
/* ===================================================== */

ReturnStmt
  =
  "return" ws1:__ expr:Expression? ws2:_ ";"
  { return (expr||"()"); }
  /
  "return" ws1:_ ";"
  { return "()"; }

AssignmentStmt
  =
  e:AssignmentExpr ws1:_ ";"
  { return "let " + e; }

AssignmentExpr
  =
  lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { return lhs + ws1 + op + ws2 + rhs; }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  =
  expr:Expression ws1:_ ";"
  { return expr; }

/* ===================================================== */
/* expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return "(if " + cond + ws1 + "then " + ws2 + ifTrue + ws3 + "else " + ws4 + ifFalse + ")"; }
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
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  =
  l:MulDiv tail:(ws1:_ op:("+"/"-") ws2:_ MulDiv)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

MulDiv
  =
  l:Unary tail:(ws1:_ op:("*" / "/" / "%") ws2:_ Unary)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

Unary
  =
  op:("++"/"--"/"!"/"-") ws1:_ v:Unary { return op + ws1 + v; }
  / Postfix

Postfix
  =
  base:Primary op:("++" / "--")
  { return base + op; }
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
        : acc + ws + "[" + p.ws1 + p.index + p.ws2 + "]";
    }, base);
  }

ArrayConstructor
  =
  t:BaseType ws1:_ "[" ws2:_ size:Expression? ws3:_ "]" ws4:_ "(" ws5:_ args:ArgList? ws6:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "[" + ws5 + argsStr + ws6 + "]";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "[" + ws2 + argsStr + ws3 + "]";
  }

ScalarConstructor
  =
  name:("float" / "int" / "uint" / "bool") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    // Intercepts casting and translates it to standard f32/i32/u32 Futhark conversions
    return mapType(name) + "." + name + ws1 + "(" + ws2 + argsStr + ws3 + ")";
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
      str: head + tail.map(x => ", " + x[3]).join(""),
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
        : acc + ws + "[" + p.ws1 + p.index + p.ws2 + "]";
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
      return num + "f32";
    }
    return num + (suffix ? suffix[0] : "");
  }

/* ===================================================== */
/* formatting & whitespace matching */
/* ===================================================== */

Comment = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"

// Extracts the exact matched string of whitespace/comments to pass through the AST
_  = ws:$( ( [ \t\r\n] / Comment )* ) { return ws; }
__ = ws:$( ( [ \t\r\n] / Comment )+ ) { return ws; }
