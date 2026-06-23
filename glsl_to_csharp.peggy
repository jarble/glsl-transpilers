{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "uint",
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

  // Generates raw C# expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} * (MathF.PI / 180f))`;
      case "degrees": return `(${a} * (180f / MathF.PI))`;
      case "sin": return `MathF.Sin(${ws2}${a}${ws3})`;
      case "cos": return `MathF.Cos(${ws2}${a}${ws3})`;
      case "tan": return `MathF.Tan(${ws2}${a}${ws3})`;
      case "asin": return `MathF.Asin(${ws2}${a}${ws3})`;
      case "acos": return `MathF.Acos(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `MathF.Atan2(${a}, ${b})` : `MathF.Atan(${a})`;

      // Exponential
      case "pow": return `MathF.Pow(${a}, ${b})`;
      case "exp": return `MathF.Exp(${a})`;
      case "log": return `MathF.Log(${a})`;
      case "exp2": return `MathF.Pow(2f, ${a})`;
      case "log2": return `MathF.Log2(${a})`;
      case "sqrt": return `MathF.Sqrt(${a})`;
      case "inversesqrt": return `(1f / MathF.Sqrt(${a}))`;

      // Common Math
      case "abs": return `MathF.Abs(${a})`;
      case "sign": return `MathF.Sign(${a})`;
      case "floor": return `MathF.Floor(${a})`;
      case "ceil": return `MathF.Ceiling(${a})`;
      case "fract": return `(${a} - MathF.Floor(${a}))`;
      case "mod": return `(${a} - ${b} * MathF.Floor(${a} / ${b}))`;
      case "min": return `MathF.Min(${a}, ${b})`;
      case "max": return `MathF.Max(${a}, ${b})`;
      case "clamp": return `MathF.Clamp(${a}, ${b}, ${c})`;
      case "mix": return `(${a} * (1f - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0f : 1f)`;
      case "smoothstep": 
        const t = `MathF.Clamp((${c} - ${a}) / (${b} - ${a}), 0f, 1f)`;
        return `(${t} * ${t} * (3f - 2f * ${t}))`;

      // Geometric 
      case "length": return `${a}.Length()`;
      case "distance": return `Vector3.Distance(${a}, ${b})`;
      case "dot": return `Vector3.Dot(${a}, ${b})`;
      case "cross": return `Vector3.Cross(${a}, ${b})`;
      case "normalize": return `Vector3.Normalize(${a})`;
      case "reflect": return `Vector3.Reflect(${a}, ${b})`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }

  // Generates C# Structs for GLSL Matrices AND Type Conversions
  function getBuiltInStructs() {
    return `
/* --- GLSL Built-in Matrix Types --- */
public struct mat2 {
    public Vector2 col0;
    public Vector2 col1;
    public mat2(Vector2 c0, Vector2 c1) { col0 = c0; col1 = c1; }
}

public struct mat3 {
    public Vector3 col0;
    public Vector3 col1;
    public Vector3 col2;
    public mat3(Vector3 c0, Vector3 c1, Vector3 c2) { col0 = c0; col1 = c1; col2 = c2; }
}

public struct mat4 {
    public Vector4 col0;
    public Vector4 col1;
    public Vector4 col2;
    public Vector4 col3;
    public mat4(Vector4 c0, Vector4 c1, Vector4 c2, Vector4 c3) { col0 = c0; col1 = c1; col2 = c2; col3 = c3; }
}

/* --- GLSL Type Conversions --- */
public static float _float(bool v) => v ? 1f : 0f;
public static float _float(int v) => (float)v;
public static float _float(uint v) => (float)v;
public static float _float(float v) => v;

public static int _int(bool v) => v ? 1 : 0;
public static int _int(int v) => v;
public static int _int(uint v) => (int)v;
public static int _int(float v) => (int)v;

public static uint _uint(bool v) => v ? 1u : 0u;
public static uint _uint(int v) => (uint)v;
public static uint _uint(uint v) => v;
public static uint _uint(float v) => (uint)v;

public static bool _bool(bool v) => v;
public static bool _bool(int v) => v != 0;
public static bool _bool(uint v) => v != 0u;
public static bool _bool(float v) => v != 0f;
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

    let result = "public struct " + structName + ws2 + "{" + items.join("") + wsEnd + "}";

    if (n1 && n2) {
      result += ws3 + "public " + structName + " " + n2 + ws4 + ";";
    }

    return result;
  }

StructField
  =
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    const typeStr = arr ? t + "[]" : t;
    return "public " + typeStr + ws1 + id + ws2 + (arr ? arr.str : "") + ws3 + ";";
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
    const dtype = arr ? ty + "[]" : ty;
    let initStr = init ? init : "";
    
    if (arr && arr.size && !init) {
      initStr = " = new " + ty + "[" + arr.size + "]";
    }

    const qStr = qual ? qual.ws : "";
    return qStr + dtype + ws1 + id + ws2 + ws3 + initStr + ws4 + ";";
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
      const dtype = d.arr ? ty + "[]" : ty;
      let initStr = d.init ? d.init : "";
      if (d.arr && d.arr.size && !d.init) {
         initStr = " = new " + ty + "[" + d.arr.size + "]";
      }
      
      if (i === 0) {
          return dtype + ws1 + d.id + d.ws1 + d.ws2 + initStr;
      } else {
          return d.wsA + ";" + d.wsB + dtype + " " + d.id + d.ws1 + d.ws2 + initStr;
      }
    }).join("") + ws2 + ";";
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    return ret + ws1 + name + ws2 + "(" + ws3 + (params||"") + ws4 + ")" + ws5 + body;
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
    const typeStr = arr ? t + "[]" : t;
    let qStr = "";
    if (qual && qual.pq) {
       qStr = qual.pq + qual.ws;
    } else if (qual) {
       qStr = qual.ws;
    }
    return qStr + typeStr + ws1 + id;
  }

ParameterQualifier = "inout" { return "ref"; } / "in" { return ""; } / "out" { return "out"; }

/* ===================================================== */
/* blocks & control flow */
/* ===================================================== */

Block
  =
  "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  {
    return "{" + items.join("") + wsEnd + "}";
  }

IfStmt
  =
  "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement
  elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  {
    return "if" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + thenStmt + (elsePart || "");
  }

WhileStmt
  =
  "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { return "while" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + body; }

DoWhileStmt
  =
  "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { return "do" + ws1 + body + ws2 + "while" + ws3 + "(" + ws4 + cond + ws5 + ")" + ws6 + ";"; }

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    return "for" + ws1 + "(" + ws2 + (init||"") + ws3 + ";" + ws4 + (cond||"") + ws5 + ";" + ws6 + (update||"") + ws7 + ")" + ws8 + body;
  }

ForInit = VarDeclInline / AssignmentExpr / Expression

ForUpdate = AssignmentExpr / Postfix / Expression

VarDeclInline
  =
  t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)*
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    const firstDtype = head.arr ? ty + "[]" : ty;
    
    return firstDtype + ws1 + decls.map((d, i) => {
        let initStr = d.init ? d.init : "";
        if (d.arr && d.arr.size && !d.init) {
           initStr = " = new " + ty + "[" + d.arr.size + "]";
        }
        if (i === 0) {
            return d.id + d.ws1 + d.ws2 + initStr;
        } else {
            return d.wsA + "," + d.wsB + d.id + d.ws1 + d.ws2 + initStr;
        }
    }).join("");
  }

SwitchStmt
  =
  "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  {
    return "switch" + ws1 + "(" + ws2 + expr + ws3 + ")" + ws4 + "{" + cases.join("") + wsEnd + "}";
  }

CaseClause
  =
  "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "case" + ws1 + v + ws2 + ":" + items.join(""); }
  /
  "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "default" + ws1 + ":" + items.join(""); }

/* ===================================================== */
/* return & assignments */
/* ===================================================== */

ReturnStmt
  =
  "return" ws1:__ expr:Expression? ws2:_ ";"
  { return "return" + ws1 + (expr||"") + ws2 + ";"; }
  /
  "return" ws1:_ ";"
  { return "return" + ws1 + ";"; }

AssignmentStmt
  =
  e:AssignmentExpr ws1:_ ";"
  { return e + ws1 + ";"; }

AssignmentExpr
  =
  lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { return lhs + ws1 + op + ws2 + rhs; }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  =
  expr:Expression ws1:_ ";"
  { return expr + ws1 + ";"; }

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
    return "new " + t + "[]" + ws4 + "{" + ws5 + argsStr + ws6 + "}";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "new " + mapType(name) + ws1 + "(" + ws2 + argsStr + ws3 + ")";
  }

ScalarConstructor
  =
  name:("float" / "int" / "uint" / "bool") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    // Intercepts casting and pipes it to the generated C# helper methods
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
      return num + "f";
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
