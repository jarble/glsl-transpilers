{
  const typeMap = {
    float: "number", int: "number", uint: "number", bool: "boolean",
    vec2: "Vector2", vec3: "Vector3", vec4: "Vector4", 
    mat2: "Matrix2", mat3: "Matrix3", mat4: "Matrix4", void: "void"
  };

  function mapType(t) { return typeMap[t] || t; }

  // Intercepts identifiers to safely append 'compiled_' to user-defined names
  function mapVariable(name) {
    const builtIns = new Set([
        // Types
        "float", "int", "uint", "bool", "void",
        "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
        // Functions
        "radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan",
        "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt",
        "abs", "sign", "floor", "ceil", "round", "fract", "mod", "min", "max", "clamp", "mix", "step", "smoothstep",
        "length", "distance", "dot", "cross", "normalize", "reflect",
        // Built-in vars
        "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing", "gl_PointSize", "gl_VertexID", "gl_InstanceID",
        // Keywords/Booleans
        "true", "false",
        // Single letter swizzles
        "x", "y", "z", "w", "r", "g", "b", "a", "s", "t", "p", "q"
    ]);

    if (builtIns.has(name)) return name;

    // Skip vector swizzling properties (e.g., .xyz, .rgba, .stpq)
    if (/^[xyzw]{2,4}$/.test(name)) return name;
    if (/^[rgba]{2,4}$/.test(name)) return name;
    if (/^[stpq]{2,4}$/.test(name)) return name;

    if (name.startsWith("compiled_")) return name;
    return "compiled_" + name;
  }

  // Generates raw TypeScript expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    let rawName = name.replace("compiled_", "");

    switch(rawName) {
      // Inline Math Expressions
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "clamp": return `Math.min(Math.max(${a}, ${b}), ${c})`;
      case "fract": return `(${a} - Math.floor(${a}))`;
      case "step": return `(${b} < ${a} ? 0.0 : 1.0)`;
      case "smoothstep":
        const t = `Math.min(Math.max((${c} - ${a}) / (${b} - ${a}), 0.0), 1.0)`;
        return `(${t} * ${t} * (3.0 - 2.0 * ${t}))`;
      case "mod": return `(${a} - ${b} * Math.floor(${a} / ${b}))`;
      
      // Standard Library Math
      case "sin": return `Math.sin(${ws2}${a}${ws3})`;
      case "cos": return `Math.cos(${ws2}${a}${ws3})`;
      case "tan": return `Math.tan(${ws2}${a}${ws3})`;
      case "asin": return `Math.asin(${ws2}${a}${ws3})`;
      case "acos": return `Math.acos(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `Math.atan2(${a}, ${b})` : `Math.atan(${a})`;
      case "pow": return `Math.pow(${a}, ${b})`;
      case "exp": return `Math.exp(${a})`;
      case "log": return `Math.log(${a})`;
      case "exp2": return `Math.pow(2.0, ${a})`;
      case "log2": return `Math.log2(${a})`;
      case "abs": return `Math.abs(${a})`;
      case "sign": return `Math.sign(${a})`;
      case "max": return `Math.max(${a}, ${b})`;
      case "min": return `Math.min(${a}, ${b})`;
      case "floor": return `Math.floor(${a})`;
      case "ceil": return `Math.ceil(${a})`;
      case "round": return `Math.round(${a})`;
      case "sqrt": return `Math.sqrt(${a})`;
      case "inversesqrt": return `(1.0 / Math.sqrt(${a}))`;

      // Geometric functions (Assuming standard TS Vector standalone functions)
      case "length": return `length(${a})`;
      case "distance": return `distance(${a}, ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }
}

/* ===================================================== */
/* Entry */
/* ===================================================== */

Start
  = items:(ws:_ t:TopLevel { return ws + t; })* wsEnd:_
  { return items.join("") + wsEnd; }

TopLevel
  = StructDecl
  / GlobalDecl
  / FunctionDecl
  / MacroDecl
  / Statement

Statement
  = VarDecl
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
  / StatementBlock

/* ===================================================== */
/* Structs */
/* ===================================================== */

StructDecl
  = pre:_ "struct" ws1:__ headName:(Identifier)? ws2:_ "{" items:(ws:_ sf:StructField { return ws + sf; })* wsEnd:_ "}" ws3:_ tailName:(Identifier)? arr:ArraySuffix? ws4:_ init:("=" ws5:_ e:Expression { return "=" + ws5 + e; })? ws6:_ ";"
  {
    const structName = headName || tailName || "AnonymousStruct";
    let result = pre + "interface " + structName + ws2 + "{" + items.join("") + wsEnd + "}";
    
    // Instantiate trailing variable if present
    if (tailName) {
      const typeStr = structName + (arr ? "[]" : "");
      const valStr = init ? init : "";
      result += "\n" + pre + "let " + tailName + ": " + typeStr + ws4 + valStr + ws6 + ";";
    }
    return result;
  }

StructField
  = t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  { return id + ": " + mapType(t) + (arr ? "[]" : "") + ws3 + ";"; }

/* ===================================================== */
/* Globals & Variables */
/* ===================================================== */

GlobalDecl
  = pre:_ qual:(sq:StorageQualifier ws:__ { return {sq, ws}; })? t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)* ws2:_ ";"
  {
    const ty = mapType(t);
    const kw = qual && qual.sq === "const" ? "const" : "let";
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    
    return pre + kw + " " + decls.map((d, i) => {
      const dtype = d.arr ? ty + "[]" : ty;
      const initStr = d.init ? d.init : "";
      if (i === 0) return d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
      return d.wsA + "," + d.wsB + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
    }).join("") + ws2 + ";";
  }

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

Declarator
  = id:Identifier ws1:_ arr:ArraySuffix? ws2:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })?
  { return { id, ws1, arr, ws2, init }; }

VarDecl
  = pre:_ t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)* ws2:_ ";"
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    
    return pre + "let " + decls.map((d, i) => {
      const dtype = d.arr ? ty + "[]" : ty;
      const initStr = d.init ? d.init : "";
      if (i === 0) return d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
      return d.wsA + "," + d.wsB + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
    }).join("") + ws2 + ";";
  }

VarDeclInline
  = t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)*
  {
    const ty = mapType(t);
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    
    return "let " + decls.map((d, i) => {
      const dtype = d.arr ? ty + "[]" : ty;
      const initStr = d.init ? d.init : "";
      if (i === 0) return d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
      return d.wsA + "," + d.wsB + d.id + ": " + dtype + d.ws1 + d.ws2 + initStr;
    }).join("");
  }

/* ===================================================== */
/* Functions & Macros */
/* ===================================================== */

FunctionDecl
  = pre:_ ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:StatementBlock
  {
    return pre + "function " + name + ws2 + "(" + ws3 + (params||"") + ws4 + "): " + mapType(ret) + ws5 + body;
  }

ParamList
  = head:Param tail:(ws1:_ "," ws2:_ Param)*
  { return head + tail.map(x => x[0] + "," + x[2] + x[3]).join(""); }

Param
  = qual:(pq:ParameterQualifier ws:__ { return {pq, ws}; })? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  { return id + ": " + mapType(t) + (arr ? "[]" : ""); }

ParameterQualifier
  = "inout" / "in" / "out"

MacroDecl
  = pre:_ "#" _ "define" __ name:Identifier _ "(" _ head:Identifier tail:(_ "," _ Identifier)* _ ")" _ body:$([^\r\n]*)
  {
      const params = [head, ...tail.map(t => t[3])].join(", ");
      return pre + `function ${name}(${params}) {\n    return ${body.trim()};\n}`;
  }
  / pre:_ "#" _ "define" __ name:Identifier __ body:$([^\r\n]*)
  {
      return pre + `const ${name} = ${body.trim()};`;
  }

/* ===================================================== */
/* Blocks & Control Flow */
/* ===================================================== */

StatementBlock
  = "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  { return "{" + items.join("") + wsEnd + "}"; }

IfStmt
  = pre:_ "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  { return pre + "if" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + thenStmt + (elsePart || ""); }

WhileStmt
  = pre:_ "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { return pre + "while" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + body; }

DoWhileStmt
  = pre:_ "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { return pre + "do" + ws1 + body + ws2 + "while" + ws3 + "(" + ws4 + cond + ws5 + ")" + ws6 + ";"; }

ForStmt
  = pre:_ "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  { return pre + "for" + ws1 + "(" + ws2 + (init||"") + ws3 + ";" + ws4 + (cond||"") + ws5 + ";" + ws6 + (update||"") + ws7 + ")" + ws8 + body; }

ForInit = VarDeclInline / AssignmentExpr / Expression
ForUpdate = AssignmentExpr / Postfix / Expression

/* ===================================================== */
/* Switch */
/* ===================================================== */

SwitchStmt
  = pre:_ "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  { return pre + "switch" + ws1 + "(" + ws2 + expr + ws3 + ")" + ws4 + "{" + cases.join("") + wsEnd + "}"; }

CaseClause
  = "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "case" + ws1 + v + ws2 + ":" + items.join(""); }
  / "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { return "default" + ws1 + ":" + items.join(""); }

/* ===================================================== */
/* Return & Assignments */
/* ===================================================== */

ReturnStmt
  = pre:_ "return" ws1:__ expr:Expression? ws2:_ ";"
  { return pre + "return" + ws1 + (expr||"") + ws2 + ";"; }
  / pre:_ "return" ws1:_ ";"
  { return pre + "return" + ws1 + ";"; }

BreakStmt = pre:_ "break" ws1:_ ";" { return pre + "break" + ws1 + ";"; }
ContinueStmt = pre:_ "continue" ws1:_ ";" { return pre + "continue" + ws1 + ";"; }

AssignmentStmt
  = pre:_ e:AssignmentExpr ws1:_ ";"
  { return pre + e + ws1 + ";"; }

AssignmentExpr
  = lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { return lhs + ws1 + op + ws2 + rhs; }
  / Ternary

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  = pre:_ expr:Expression ws1:_ ";"
  { return pre + expr + ws1 + ";"; }

/* ===================================================== */
/* Expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  = cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return cond + ws1 + "?" + ws2 + ifTrue + ws3 + ":" + ws4 + ifFalse; }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(ws1:_ "||" ws2:_ LogicalAnd)*
  { return tail.reduce((a,t) => a + t[0] + "||" + t[2] + t[3], l); }

LogicalAnd
  = l:Comparison tail:(ws1:_ "&&" ws2:_ Comparison)*
  { return tail.reduce((a,t) => a + t[0] + "&&" + t[2] + t[3], l); }

Comparison
  = l:AddSub tail:(ws1:_ op:CompOp ws2:_ AddSub)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(ws1:_ op:("+"/"-") ws2:_ MulDiv)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

MulDiv
  = l:Unary tail:(ws1:_ op:("*" / "/" / "%") ws2:_ Unary)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

Unary
  = op:("++"/"--"/"!"/"-") ws1:_ v:Unary
  { return op + ws1 + v; }
  / Postfix

Postfix
  = base:Primary tail:PostfixPart*
  { return tail.reduce((acc, t) => t(acc), base); }

PostfixPart
  = ws1:_ "[" ws2:_ idx:Expression ws3:_ "]" { return (b) => b + ws1 + "[" + ws2 + idx + ws3 + "]"; }
  / ws1:_ "." ws2:_ name:Identifier { return (b) => b + ws1 + "." + ws2 + name; }
  / ws1:_ op:("++"/"--") { return (b) => b + ws1 + op; }

Primary
  = "true" { return "true"; }
  / "false" { return "false"; }
  / "(" ws1:_ e:Expression ws2:_ ")" { return "(" + ws1 + e + ws2 + ")"; }
  / ArrayConstructor
  / TypeConstructor
  / FuncCall
  / Number
  / id:Identifier { return id; }

ArrayConstructor
  = t:BaseType ws1:_ "[" ws2:_ size:Expression? ws3:_ "]" ws4:_ "(" ws5:_ args:ArgList? ws6:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "[" + ws5 + argsStr + ws6 + "]";
  }

TypeConstructor
  = name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    return "new " + mapType(name) + ws1 + "(" + ws2 + argsStr + ws3 + ")";
  }

FuncCall
  = name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  { return mapFuncCall(name, args, ws1, ws2, ws3); }

ArgList
  = head:Expression tail:(ws1:_ "," ws2:_ Expression)*
  {
    return {
      str: head + tail.map(x => x[0] + "," + x[2] + x[3]).join(""),
      list: [head].concat(tail.map(x => x[3]))
    };
  }

/* ===================================================== */
/* Assignables */
/* ===================================================== */

Assignable
  = base:Identifier tail:PostfixPart*
  { return tail.reduce((acc, t) => t(acc), base); }

/* ===================================================== */
/* Types & Tokens */
/* ===================================================== */

Type = BaseType

BaseType
  = t:(
    "float" / "int" / "uint" / "bool" / "void"
  / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4"
  ) { return mapType(t); }
  / Identifier

ArraySuffix = "[" ws1:_ size:Expression? ws2:_ "]" { return { size, str: "[" + ws1 + (size||"") + ws2 + "]" }; }

Identifier = name:$([a-zA-Z_][a-zA-Z0-9_]*) { return mapVariable(name); }

Number
  = num:$(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+-]? [0-9]+)?
  )
  suffix:([fFuU])?
  {
    let txt = num;
    if (txt.startsWith('.')) txt = '0' + txt;
    if (txt.endsWith('.')) txt = txt + '0';
    return txt;
  }

/* ===================================================== */
/* Formatting & Whitespace Matching */
/* ===================================================== */

Comment
  = "//" [^\r\n]* { return text(); }
  / "/*" (!"*/" .)* "*/" { return text(); }

_  = ws: ( ( [ \t\r\n] / Comment )* ) { return ws.join(""); }
__ = ws: ( ( [ \t\r\n] / Comment )+ ) { return ws.join(""); }
