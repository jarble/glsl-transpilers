{
  const typeMap = {
    float: "f32",
    int: "i32",
    uint: "u32",
    bool: "bool",

    vec2: "Vec2",
    vec3: "Vec3",
    vec4: "Vec4",

    mat2: "Mat2",
    mat3: "Mat3",
    mat4: "Mat4",

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

  // Generates raw Zig expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} * (std.math.pi / 180.0))`;
      case "degrees": return `(${a} * (180.0 / std.math.pi))`;
      case "sin": return `std.math.sin(${ws2}${a}${ws3})`;
      case "cos": return `std.math.cos(${ws2}${a}${ws3})`;
      case "tan": return `std.math.tan(${ws2}${a}${ws3})`;
      case "asin": return `std.math.asin(${ws2}${a}${ws3})`;
      case "acos": return `std.math.acos(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `std.math.atan2(f32, ${a}, ${b})` : `std.math.atan(${a})`;
      
      // Exponential
      case "pow": return `std.math.pow(f32, ${a}, ${b})`;
      case "exp": return `std.math.exp(${a})`;
      case "log": return `std.math.log(f32, std.math.e, ${a})`;
      case "exp2": return `std.math.pow(f32, 2.0, ${a})`;
      case "log2": return `std.math.log2(${a})`;
      case "sqrt": return `std.math.sqrt(${a})`;
      case "inversesqrt": return `(1.0 / std.math.sqrt(${a}))`;

      // Common Math
      case "abs": return `@abs(${a})`;
      case "sign": return `std.math.sign(${a})`;
      case "floor": return `@floor(${a})`;
      case "ceil": return `@ceil(${a})`;
      case "fract": return `(${a} - @floor(${a}))`;
      case "mod": return `@mod(${a}, ${b})`;
      case "min": return `@min(${a}, ${b})`;
      case "max": return `@max(${a}, ${b})`;
      case "clamp": return `std.math.clamp(${a}, ${b}, ${c})`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(if (${b} < ${a}) @as(f32, 0.0) else @as(f32, 1.0))`;
      case "smoothstep": 
        const t = `std.math.clamp((${c} - ${a}) / (${b} - ${a}), 0.0, 1.0)`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
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
    return "const std = @import(\"std\");\n\n" + program;
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
  / SwitchStmt
  / ExprStmt
  / Block

/* ===================================================== */
/* structs */
/* ===================================================== */

StructDecl
  =
  "struct" ws1:__ headName:(Identifier)?
  ws2:_ "{" items:(ws:_ sf:StructField { return ws + sf; })* wsEnd:_ "}" ws3:_ tailName:(Identifier)? ws4:_ ";"?
  {
    const n1 = headName;
    const n2 = tailName;
    const structName = n1 || n2 || "AnonymousStruct";

    let result = "const " + structName + " = struct " + ws2 + "{" + items.join("") + wsEnd + "};";

    if (n1 && n2) {
      result += ws3 + "var " + n2 + ": " + structName + " = undefined" + ws4 + ";";
    }

    return result;
  }

StructField
  =
  t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    const typeStr = arr ? "[" + (arr.size || "0") + "]" + t : t;
    return id + ws1 + ":" + ws2 + typeStr + "," + ws3;
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
    const dtype = arr ? "[" + (arr.size || "_") + "]" + ty : ty;
    let initStr = init ? init : " = undefined";
    
    // In Zig, global variables must be declared as `var` or `const`. We default to `var`.
    return "var " + id + ws1 + ": " + dtype + ws2 + ws3 + initStr + ws4 + ";";
  }

StorageQualifier = "uniform" / "attribute" / "varying" / "const"

/* ===================================================== */
/* variables */
/* ===================================================== */

Declarator
  =
  id:Identifier ws1:_ arr:ArraySuffix?
  ws2:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })?
  {
    return { id, ws1, arr, ws2, init };
  }

VarDecl
  =
  qual:("const" __)? t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)* ws2:_ ";"
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    const keyword = qual ? "const " : "var ";

    return decls.map((d, i) => {
      const dtype = d.arr ? "[" + (d.arr.size || "_") + "]" + ty : ty;
      let initStr = d.init ? d.init : " = undefined";
      
      if (i === 0) {
          return keyword + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
      } else {
          return d.wsA + ";" + d.wsB + keyword + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
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
    return "fn " + name + ws2 + "(" + ws3 + (params||"") + ws4 + ") " + ret + ws5 + body;
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
    const typeStr = arr ? "[]" + t : t;
    let isPtr = "";
    
    if (qual && (qual.pq === "inout" || qual.pq === "out")) {
       isPtr = "*";
    }
    
    return id + ": " + isPtr + typeStr;
  }

ParameterQualifier = "inout" / "in" / "out"

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

ForStmt
  =
  "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Block
  {
    // Zig lacks C-style for loops. Restructure into a block with a while loop and a continue expression.
    const initStr = init ? init + ";" : "";
    const condStr = cond ? cond : "true";
    const updateStr = update ? " : (" + update + ")" : "";
    
    return "{" + ws1 + initStr + ws2 + "while (" + condStr + ")" + updateStr + ws8 + body + "}";
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
        const dtype = d.arr ? "[" + (d.arr.size || "_") + "]" + ty : ty;
        let initStr = d.init ? d.init : " = undefined";
        
        if (i === 0) {
            return "var " + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
        } else {
            return d.wsA + ";" + d.wsB + "var " + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
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
  { 
    // Strip trailing breaks for Zig compliance
    const filteredItems = items.join("").replace(/\bbreak\s*;/g, "");
    return v + ws2 + " => {" + filteredItems + "},"; 
  }
  /
  "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { 
    const filteredItems = items.join("").replace(/\bbreak\s*;/g, "");
    return "else" + ws1 + " => {" + filteredItems + "},"; 
  }

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
  cond:LogicalOr ws1:_ "?"
  ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return "if (" + cond + ")" + ws1 + ws2 + ifTrue + ws3 + " else " + ws4 + ifFalse; }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd tail:(ws1:_ "||" ws2:_ LogicalAnd)*
  { return tail.reduce((a,t) => a + t[0] + "or" + t[2] + t[3], l); }

LogicalAnd
  =
  l:Comparison tail:(ws1:_ "&&" ws2:_ Comparison)*
  { return tail.reduce((a,t) => a + t[0] + "and" + t[2] + t[3], l); }

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
  op:("!"/"-") ws1:_ v:Unary { return (op === "!" ? "!" : "-") + ws1 + v; }
  / Postfix

Postfix
  =
  base:Primary op:("++" / "--")
  { return base + " " + (op === "++" ? "+= 1" : "-= 1"); }
  / Primary

Primary
  =
  base:(
      "true" { return "true"; }
    / "false" { return "false"; }
    / "(" ws1:_ e:Expression ws2:_ ")" { return "(" + ws1 + e + ws2 + ")"; }
    / ArrayConstructor
    / TypeConstructor
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
    return "[_]" + t + ws4 + "{" + ws5 + argsStr + ws6 + "}";
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return mapType(name) + ws1 + "{" + ws2 + argsStr + ws3 + "}";
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
      return num;
    }
    return num;
  }

/* ===================================================== */
/* formatting & whitespace matching */
/* ===================================================== */

Comment = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"

_  = ws:$( ( [ \t\r\n] / Comment )* ) { return ws; }
__ = ws:$( ( [ \t\r\n] / Comment )+ ) { return ws; }
