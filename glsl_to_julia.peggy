{
  const typeMap = {
    float: "Float32",
    int: "Int32",
    uint: "UInt32",
    bool: "Bool",
    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",
    mat2: "mat2",
    mat3: "mat3",
    mat4: "mat4",
    void: "Nothing"
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

  // Generates raw Julia expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `deg2rad(${a})`;
      case "degrees": return `rad2deg(${a})`;
      case "sin": return `sin(${ws2}${a}${ws3})`;
      case "cos": return `cos(${ws2}${a}${ws3})`;
      case "tan": return `tan(${ws2}${a}${ws3})`;
      case "asin": return `asin(${ws2}${a}${ws3})`;
      case "acos": return `acos(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `atan(${a}, ${b})` : `atan(${a})`;

      // Exponential
      case "pow": return `(${a} ^ ${b})`;
      case "exp": return `exp(${a})`;
      case "log": return `log(${a})`;
      case "exp2": return `exp2(${a})`;
      case "log2": return `log2(${a})`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `(1.0f0 / sqrt(${a}))`;

      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `sign(${a})`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `(${a} - floor(${a}))`;
      case "mod": return `mod(${a}, ${b})`;
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `clamp(${a}, ${b}, ${c})`;
      case "mix": return `(${a} * (1.0f0 - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0.0f0 : 1.0f0)`;
      case "smoothstep": 
        const t = `clamp((${c} - ${a}) / (${b} - ${a}), 0.0f0, 1.0f0)`;
        return `((t) -> t * t * (3.0f0 - 2.0f0 * t))(${t})`;

      // Geometric 
      case "length": return `norm(${a})`;
      case "distance": return `norm(${a} - ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }

  // Generates Julia Structs for GLSL Matrices AND Type Conversions
  function getBuiltInStructs() {
    return `
# --- GLSL Built-in Matrix Types ---
mutable struct mat2
    col0::Vector2
    col1::Vector2
end

mutable struct mat3
    col0::Vector3
    col1::Vector3
    col2::Vector3
end

mutable struct mat4
    col0::Vector4
    col1::Vector4
    col2::Vector4
    col3::Vector4
end

# --- GLSL Type Conversions ---
_float(v::Bool) = v ? 1.0f0 : 0.0f0
_float(v::Int32) = Float32(v)
_float(v::UInt32) = Float32(v)
_float(v::Float32) = v

_int(v::Bool) = v ? Int32(1) : Int32(0)
_int(v::Int32) = v
_int(v::UInt32) = Int32(v)
_int(v::Float32) = Int32(trunc(v))

_uint(v::Bool) = v ? UInt32(1) : UInt32(0)
_uint(v::Int32) = UInt32(v)
_uint(v::UInt32) = v
_uint(v::Float32) = UInt32(trunc(v))

_bool(v::Bool) = v
_bool(v::Int32) = v != 0
_bool(v::UInt32) = v != 0
_bool(v::Float32) = v != 0.0f0
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
    return "using LinearAlgebra\n\n" + program + "\n\n" + getBuiltInStructs();
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

    let result = "mutable struct " + structName + ws2 + "\n" + items.join("") + wsEnd + "end\n";

    if (n1 && n2) {
      result += ws3 + n2 + "::" + structName + ws4 + "\n";
    }

    return result;
  }

StructField
  =
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    const typeStr = arr ? "Vector{" + t + "}" : t;
    return id + ws1 + "::" + typeStr + ws2 + ws3 + "\n";
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
    const dtype = arr ? "Vector{" + ty + "}" : ty;
    let initStr = init ? init : "";
    
    if (arr && arr.size && !init) {
      initStr = " = Vector{" + ty + "}(undef, " + arr.size + ")";
    }

    const qStr = qual ? qual.ws : "";
    return qStr + id + "::" + dtype + ws1 + ws2 + ws3 + initStr + ws4 + "\n";
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

    return decls.map((d, i) => {
      const dtype = d.arr ? "Vector{" + ty + "}" : ty;
      let initStr = d.init ? d.init : "";
      if (d.arr && d.arr.size && !d.init) {
         initStr = " = Vector{" + ty + "}(undef, " + d.arr.size + ")";
      }
      
      return d.id + d.ws1 + "::" + dtype + d.ws2 + initStr;
    }).join("\n") + ws2 + "\n";
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    return "function " + name + ws2 + "(" + ws3 + (params||"") + ws4 + ")::" + ret + ws5 + "\n" + body + "end\n";
  }

ParamList
  =
  head:Param tail:(ws1:_ "," ws2:_ Param)*
  {
    return head + tail.map(x => x[0] + "," + x[2] + x[3]).join("");
  }

Param
  =
  qual:(pq:ParameterQualifier ws:__ { return {pq, ws}; })? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    const typeStr = arr ? "Vector{" + t + "}" : t;
    return id + ws1 + "::" + typeStr;
  }

ParameterQualifier = "inout" { return "ref"; } / "in" { return ""; } / "out" { return "out"; }

/* ===================================================== */
/* blocks & control flow */
/* ===================================================== */

Block
  =
  "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  {
    return items.join("") + wsEnd;
  }

IfStmt
  =
  "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement
  elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  {
    return "if " + ws2 + cond + "\n" + ws4 + thenStmt + (elsePart || "") + "\nend\n";
  }

WhileStmt
  =
  "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { return "while " + ws2 + cond + "\n" + ws4 + body + "\nend\n"; }

DoWhileStmt
  =
  "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { return "while true\n" + ws1 + body + ws2 + "if !(" + ws4 + cond + ws5 + ") break end\n" + ws6 + "\nend\n"; }

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    return (init||"") + "\nwhile " + (cond||"true") + ws8 + "\n" + body + "\n" + (update||"") + "\nend\n";
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
        let initStr = d.init ? d.init : "";
        if (d.arr && d.arr.size && !d.init) {
           initStr = " = Vector{" + ty + "}(undef, " + d.arr.size + ")";
        }
        return d.id + d.ws1 + "::" + (d.arr ? "Vector{" + ty + "}" : ty) + d.ws2 + initStr;
    }).join("\n");
  }

SwitchStmt
  =
  "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  {
    return "begin # switch(" + expr + ")\n" + cases.join("") + wsEnd + "end\n";
  }

CaseClause
  =
  "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "/* case " + v + ": */\n" + items.join(""); }
  /
  "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "/* default: */\n" + items.join(""); }

/* ===================================================== */
/* return & assignments */
/* ===================================================== */

ReturnStmt
  =
  "return" ws1:__ expr:Expression? ws2:_ ";"
  { return "return" + ws1 + (expr||"") + ws2 + "\n"; }
  /
  "return" ws1:_ ";"
  { return "return" + ws1 + "\n"; }

AssignmentStmt
  =
  e:AssignmentExpr ws1:_ ";"
  { return e + ws1 + "\n"; }

AssignmentExpr
  =
  lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { return lhs + ws1 + op + ws2 + rhs; }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  =
  expr:Expression ws1:_ ";"
  { return expr + ws1 + "\n"; }

/* ===================================================== */
/* expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return cond + ws1 + "?" + ws2 + ifTrue + ws3 + ":" + ws4 + ifFalse; }
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
    return t + ws4 + "[" + ws5 + argsStr + ws6 + "]";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return mapType(name) + ws1 + "(" + ws2 + argsStr + ws3 + ")";
  }

ScalarConstructor
  =
  name:("float" / "int" / "uint" / "bool") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "_" + name + ws1 + "(" + ws2 + argsStr + ws3 + ")";
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
      str: head + tail.map(x => x[0] + "," + x[2] + x[3]).join(""),
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
      return num + "f0";
    }
    if (suffix && suffix[0].toLowerCase() === 'f') {
      return num + "f0";
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
