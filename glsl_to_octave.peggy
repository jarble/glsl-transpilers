{
  const typeMap = {
    float: "float", int: "int", uint: "uint", bool: "bool",
    vec2: "vec2", vec3: "vec3", vec4: "vec4",
    mat2: "mat2", mat3: "mat3", mat4: "mat4", void: "void"
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

  // Generates raw Octave expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(${a} .* (pi / 180.0))`;
      case "degrees": return `(${a} .* (180.0 / pi))`;
      case "sin": case "cos": case "tan": case "asin": case "acos":
        return `${name}(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `atan2(${a}, ${b})` : `atan(${a})`;
      // Exponential
      case "pow": return `power(${a}, ${b})`;
      case "exp": return `exp(${a})`;
      case "log": return `log(${a})`;
      case "exp2": return `power(2.0, ${a})`;
      case "log2": return `log2(${a})`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `(1.0 ./ sqrt(${a}))`;
      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `sign(${a})`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `(${a} - floor(${a}))`;
      case "mod": return `mod(${a}, ${b})`;
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `max(min(${a}, ${c}), ${b})`;
      case "mix": return `(${a} .* (1.0 - ${c}) + ${b} .* ${c})`;
      case "step": return `(${b} < ${a})`; 
      case "smoothstep": 
        const t = `max(min((${c} - ${a}) ./ (${b} - ${a}), 1.0), 0.0)`;
        return `(${t} .* ${t} .* (3.0 - 2.0 .* ${t}))`;
      // Geometric 
      case "length": return `norm(${a})`;
      case "distance": return `norm(${a} - ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `(${a} ./ norm(${a}))`;
      case "reflect": return `(${a} - 2.0 .* dot(${b}, ${a}) .* ${b})`;
      // Constructors
      case "vec2": case "vec3": case "vec4": case "mat2": case "mat3": case "mat4":
        return `[${argsStr}]`;
      // User functions
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  = items:(ws:_ t:TopLevel { return ws + t; })* wsEnd:_
  {
    return items.join("") + wsEnd;
  }

TopLevel
  = StructDecl
  / GlobalDecl
  / FunctionDecl
  / Statement

Statement
  = VarDecl
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / BreakStmt
  / ContinueStmt
  / ExprStmt
  / Block

/* ===================================================== */
/* structs (Mapped to Octave constructor functions) */
/* ===================================================== */

StructDecl
  = "struct" ws1:__ headName:(Identifier)? ws2:_ "{" items:(ws:_ sf:StructField { return sf; })* wsEnd:_ "}" ws3:_ tailName:(Identifier)? ws4:_ ";"?
  {
    const n1 = headName;
    const n2 = tailName;
    const structName = n1 || n2 || "AnonymousStruct";
    
    // Create an Octave function that acts as a constructor, returning a struct
    const args = items.map(i => i.id).join(", ");
    const fields = items.map(i => `'${i.id}', ${i.id}`).join(", ");
    let result = `function obj = ${structName}(${args})\n  obj = struct(${fields});\nendfunction`;
    
    if (n1 && n2) {
      result += ws3 + `${n2} = ${structName}();` + ws4;
    }
    return result;
  }

StructField
  = t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ ";"
  {
    return { id: id, type: t };
  }

/* ===================================================== */
/* globals */
/* ===================================================== */

GlobalDecl
  = qual:(sq:StorageQualifier ws:__ { return {sq, ws}; })? t:Type ws1:__ id:Identifier ws2:_ arr:ArraySuffix? ws3:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })? ws4:_ ";"
  {
    let initStr = init ? init : "";
    if (arr && arr.size && !init) {
      initStr = " = zeros(" + arr.size + ", 1)";
    }
    // Drop the type completely in Octave
    return id + ws2 + ws3 + initStr + ws4 + ";";
  }

StorageQualifier = "uniform" / "attribute" / "varying" / "const"

/* ===================================================== */
/* variables */
/* ===================================================== */

Declarator
  = id:Identifier ws1:_ arr:ArraySuffix? ws2:_ init:("=" ws:_ e:Expression { return "=" + ws + e; })?
  {
    return { id, ws1, arr, ws2, init };
  }

VarDecl
  = t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)* ws2:_ ";"
  {
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    return decls.map((d, i) => {
      let initStr = d.init ? d.init : "";
      if (d.arr && d.arr.size && !d.init) {
         initStr = " = zeros(" + d.arr.size + ", 1)";
      }
      
      if (i === 0) {
          return d.id + d.ws1 + d.ws2 + initStr;
      } else {
          return d.wsA + ";" + d.wsB + d.id + d.ws1 + d.ws2 + initStr;
      }
    }).join("") + ws2 + ";";
  }

/* ===================================================== */
/* functions */
/* ===================================================== */

FunctionDecl
  = ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block
  {
    // Octave requires named return variables. We inject '_ret' automatically.
    const retDeclaration = ret !== "void" ? "_ret = " : "";
    // Cleanly unwrap the Block rule which wraps code in "end" instead of brackets
    return `function ${retDeclaration}${name}(${params || ""})\n${ws5}${body}`;
  }

ParamList
  = head:Param tail:(ws1:_ "," ws2:_ Param)*
  {
    return head + tail.map(x => ", " + x[3]).join("");
  }

Param
  = qual:(pq:ParameterQualifier ws:__ { return {pq, ws}; })? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    return id; // Erase type in Octave
  }

ParameterQualifier = "inout" / "in" / "out"

/* ===================================================== */
/* blocks & control flow */
/* ===================================================== */

Block
  = "{" items:(ws:_ s:Statement { return ws + s; })* wsEnd:_ "}"
  {
    return items.join("") + wsEnd + "end";
  }

IfStmt
  = "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement
  elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else\n" + ws6 + elseStmt; })?
  {
    // Only append `end` if the thenStmt isn't a block (which provides its own 'end')
    const needsEnd = !thenStmt.endsWith("end");
    return "if " + cond + "\n" + ws4 + thenStmt + "\n" + (elsePart || "") + (needsEnd ? "\nend" : "");
  }

WhileStmt
  = "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  { 
    const needsEnd = !body.endsWith("end");
    return "while " + cond + "\n" + ws4 + body + (needsEnd ? "\nend" : "");
  }

DoWhileStmt
  = "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";"
  { 
    return "while true\n" + ws1 + body + "\n" + ws2 + "if ~(" + cond + ")\nbreak;\nend\nend;";
  }

ForStmt
  = "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    // Transpose C-style for-loop into an Octave block-scoped while loop
    const initStr = init ? init + (init.endsWith(";") ? "" : ";\n") : "";
    const updateStr = update ? update + (update.endsWith(";") ? "" : ";\n") : "";
    const needsEnd = !body.endsWith("end");
    
    return initStr + "while " + (cond || "true") + "\n" + ws8 + body + "\n" + updateStr + (needsEnd ? "end" : "");
  }

BreakStmt = "break" ws:_ ";" { return "break;"; }
ContinueStmt = "continue" ws:_ ";" { return "continue;"; }

ForInit = VarDeclInline / AssignmentExpr / Expression
ForUpdate = AssignmentExpr / Postfix / Expression

VarDeclInline
  = t:Type ws1:__ head:Declarator tail:(wsA:_ "," wsB:_ Declarator)*
  {
    const decls = [head].concat(tail.map(x => ({ wsA: x[0], wsB: x[2], ...x[3] })));
    return decls.map((d, i) => {
        let initStr = d.init ? d.init : "";
        if (d.arr && d.arr.size && !d.init) {
           initStr = " = zeros(" + d.arr.size + ", 1)";
        }
        if (i === 0) {
            return d.id + d.ws1 + d.ws2 + initStr;
        } else {
            return d.wsA + ";" + d.wsB + d.id + d.ws1 + d.ws2 + initStr;
        }
    }).join("");
  }

SwitchStmt
  = "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" cases:(ws:_ c:CaseClause { return ws + c; })* wsEnd:_ "}"
  {
    return "switch " + expr + "\n" + cases.join("") + wsEnd + "end";
  }

CaseClause
  = "case" ws1:__ v:Expression ws2:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { 
    // Strip "break;" since Octave switch statements don't fall through
    const cleanedItems = items.join("").replace(/break\s*;/g, "");
    return "case " + v + "\n" + cleanedItems;
  }
  / "default" ws1:_ ":" items:(ws:_ s:Statement { return ws + s; })*
  { 
    const cleanedItems = items.join("").replace(/break\s*;/g, "");
    return "otherwise\n" + cleanedItems;
  }

/* ===================================================== */
/* return & assignments */
/* ===================================================== */

ReturnStmt
  = "return" ws1:__ expr:Expression? ws2:_ ";"
  { 
    if (expr) {
        return "_ret = " + expr + ";" + ws1 + "return;";
    }
    return "return;";
  }

AssignmentStmt
  = e:AssignmentExpr ws1:_ ";"
  { return e + ws1 + ";"; }

AssignmentExpr
  = lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  { 
    if (op === "+=" || op === "-=" || op === "*=" || op === "/=") {
        const baseOp = op.charAt(0);
        // Expand compound assignment since Octave natively lacks them: a += 1 -> a = a + 1
        return lhs + ws1 + "=" + ws2 + lhs + " " + (baseOp === '*' || baseOp === '/' ? '.' + baseOp : baseOp) + " " + rhs;
    }
    return lhs + ws1 + op + ws2 + rhs;
  }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  = expr:Expression ws1:_ ";"
  { return expr + ws1 + ";"; }

/* ===================================================== */
/* expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  = cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { 
     // Octave has no ternary, simulate via inline functional logic if numeric, but here we emit standard if-else fallback or function logic. 
     // To keep it strictly expression-based, we can use cell arrays or inline logic if applicable, but a functional wrapper is safest:
     return `ifelse(${cond}, ${ifTrue}, ${ifFalse})`;
  }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(ws1:_ "||" ws2:_ LogicalAnd)*
  { return tail.reduce((a,t) => a + t[0] + "||" + t[2] + t[3], l); }

LogicalAnd
  = l:Comparison tail:(ws1:_ "&&" ws2:_ Comparison)*
  { return tail.reduce((a,t) => a + t[0] + "&&" + t[2] + t[3], l); }

Comparison
  = l:AddSub tail:(ws1:_ op:CompOp ws2:_ AddSub)*
  { return tail.reduce((a,t) => a + t[0] + (t[1] === "!=" ? "~=" : t[1]) + t[2] + t[3], l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(ws1:_ op:("+"/"-") ws2:_ MulDiv)*
  { return tail.reduce((a,t) => a + t[0] + t[1] + t[2] + t[3], l); }

MulDiv
  = l:Unary tail:(ws1:_ op:("*" / "/" / "%") ws2:_ Unary)*
  { return tail.reduce((a,t) => {
        if (t[1] === "%") return "mod(" + a + ", " + t[3] + ")";
        // Octave prefers dot-multiplication for array broadcasts
        return a + t[0] + "." + t[1] + t[2] + t[3];
    }, l);
  }

Unary
  = op:("++"/"--"/"!"/"-") ws1:_ v:Unary 
  { 
      if (op === "!") return "~" + ws1 + v; // Octave NOT
      // Pre-increment is problematic as an expression in Octave. 
      if (op === "++" || op === "--") return v + " = " + v + (op === "++" ? " + 1" : " - 1");
      return op + ws1 + v;
  }
  / Postfix

Postfix
  = base:Primary op:("++" / "--")
  { 
    // Post-increment
    return base + " = " + base + (op === "++" ? " + 1" : " - 1");
  }
  / Primary

Primary
  = base:(
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
        // Octave arrays are 1-indexed, and index syntax uses parentheses ()
        : acc + ws + "(" + p.ws1 + p.index + " + 1" + p.ws2 + ")";
    }, base);
  }

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
    return "[" + ws2 + argsStr + ws3 + "]";
  }

ScalarConstructor
  = name:("float" / "int" / "uint" / "bool") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    const argsStr = args ? args.str : "";
    if (name === "int" || name === "uint") return "round(" + argsStr + ")";
    return argsStr;
  }

FuncCall
  = name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    return mapFuncCall(name, args, ws1, ws2, ws3);
  }

ArgList
  = head:Expression tail:(ws1:_ "," ws2:_ Expression)*
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
  = base:Identifier tail:(ws1:_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const ws = t[0];
      const p = t[1];
      return p.type === "member"
        ? acc + ws + "." + p.ws + p.name
        : acc + ws + "(" + p.ws1 + p.index + " + 1" + p.ws2 + ")";
    }, base);
  }

AccessPart
  = "." ws:_ name:Identifier { return {type:"member", name, ws}; }
  / "[" ws1:_ idx:Expression ws2:_ "]" { return {type:"index", index:idx, ws1, ws2}; }

/* ===================================================== */
/* types & tokens */
/* ===================================================== */

Type = BaseType

BaseType
  = t:(
    "float" / "int" / "uint" / "bool" / "void"
  / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4"
  )
  { return mapType(t); }
  / Identifier

ArraySuffix = "[" ws1:_ size:Expression? ws2:_ "]" { return { size, str: "[" + ws1 + (size||"") + ws2 + "]" }; }

Identifier = name:$([a-zA-Z_][a-zA-Z0-9_]*) { return mapIdentifier(name); }

Number
  = num:$(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+\-]? [0-9]+)?
  )
  suffix:([fFuU])?
  {
    // Strip f, F, u, U suffixes as Octave evaluates naked numbers automatically
    let cleanNum = num;
    if (cleanNum.startsWith(".")) cleanNum = "0" + cleanNum;
    if (cleanNum.endsWith(".")) cleanNum = cleanNum + "0";
    return cleanNum;
  }

/* ===================================================== */
/* formatting & whitespace matching */
/* ===================================================== */

Comment = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"

_  = ws:$( ( [ \t\r\n] / Comment )* ) { return ws; }
__ = ws:$( ( [ \t\r\n] / Comment )+ ) { return ws; }
}
