{
  const typeMap = {
    float: "float", int: "int", uint: "uint", bool: "bool",
    vec2: "vec2", vec3: "vec3", vec4: "vec4",
    mat2: "mat2", mat3: "mat3", mat4: "mat4", void: "void"
  };

  function mapType(t) {
    return typeMap[t] || t;
  }

  // Forces variables to start with an uppercase letter for Picat logic variables
  function mapVariable(name) {
    const builtIns = new Set([
      "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing",
      "gl_PointSize", "gl_VertexID", "gl_InstanceID"
    ]);
    if (builtIns.has(name)) {
      // Capitalize built-ins to maintain Picat variable rules
      return "Gl_" + name.substring(3);
    }
    // Prepend V_ to safely capitalize and prevent keyword collisions
    return "V_" + name;
  }

  // Maps GLSL math to Picat built-ins and structures arrays
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Intrinsic Math
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "clamp": return `max(${a}, min(${b}, ${c}))`;
      case "step": return `cond(${b} < ${a}, 0.0, 1.0)`;
      case "smoothstep": 
        return `cond(${a} >= ${b}, 0.0, ((${c}-${a})/(${b}-${a})) * ((${c}-${a})/(${b}-${a})) * (3.0 - 2.0 * ((${c}-${a})/(${b}-${a}))))`;
      case "mod": return `(${a} mod ${b})`;
      case "pow": return `(${a} ** ${b})`;
      case "inversesqrt": return `(1.0 / sqrt(${a}))`;

      // Array/Vector Constructors -> Picat Array Literals
      case "vec2": case "vec3": case "vec4":
      case "mat2": case "mat3": case "mat4":
      case "ivec2": case "ivec3": case "ivec4":
        return `{${args.join(", ")}}`;

      // Standard Math 
      case "sin": case "cos": case "tan": case "asin": case "acos": case "atan":
      case "exp": case "log": case "sqrt": case "abs": case "sign":
      case "floor": case "ceil": case "max": case "min":
        return `${name}(${args.join(", ")})`;

      default:
        return `${mapVariable(name)}(${args.join(", ")})`;
    }
  }

  function emitComment(c) {
    return c + "\n";
  }
}

/* ===================================================== */
/* Entry */
/* ===================================================== */

Start
  = _ items:(TopLevel (_ TopLevel)*)? _
  {
    return items ? [items[0]].concat(items[1].map(x => x[1])).join("\n\n") : "";
  }

TopLevel
  = CommentStmt
  / StructDecl
  / GlobalDecl
  / FunctionDecl

/* ===================================================== */
/* Comments & Whitespace */
/* ===================================================== */

CommentStmt
  = c:Comment { return emitComment(c); }

Comment
  = SingleLineComment / MultiLineComment

SingleLineComment
  = c:$("//" [^\r\n]*) { return "%" + c.substring(2); } // Picat uses % for single-line comments

MultiLineComment
  = $("/" "*" (!"*/" .)* "*" "/")

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+

/* ===================================================== */
/* Structs */
/* ===================================================== */

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:(StructField (_ StructField)*)? _ "}" _ tailName:(Identifier)? _ ";"
  {
    const structName = mapVariable(name);
    let result = `% Struct mapped to a Map factory\nnew_${structName}() = V_Map => V_Map = new_map().`;
    if (tailName) {
      result += `\n${mapVariable(tailName)} = new_${structName}().`;
    }
    return result;
  }

StructField
  = t:Type __ id:Identifier _ ";"
  { return ""; } // Erased in Picat, handled purely dynamically

/* ===================================================== */
/* Globals & Variables */
/* ===================================================== */

GlobalDecl
  = qual:StorageQualifier? _ t:Type __ id:Identifier arr:ArraySuffix? _ init:("=" _ Expression)? _ ";"
  {
    const val = init ? init[2] : "0";
    return `${mapVariable(id)} = ${val}.`;
  }

StorageQualifier = "uniform" / "attribute" / "varying" / "const"

VarDecl
  = t:Type __ id:Identifier arr:ArraySuffix? _ init:("=" _ Expression)?
  {
    const val = init ? init[2] : "0";
    // Using unification '=' for initial declarations
    return `${mapVariable(id)} = ${val}`;
  }

/* ===================================================== */
/* Functions */
/* ===================================================== */

FunctionDecl
  = ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block
  {
    const pList = params ? params.join(", ") : "";
    // Picat function syntax mapping
    return `${mapVariable(name)}(${pList}) = V_Return =>\n${body}\n.`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)*
  {
    return [head].concat(tail.map(x => x[3]));
  }

Param
  = qual:(ParameterQualifier _)? t:Type __ id:Identifier
  {
    return mapVariable(id);
  }

ParameterQualifier = "inout" / "in" / "out"

/* ===================================================== */
/* Blocks & Control Flow */
/* ===================================================== */

Block
  = "{" _ stmts:(Statement (_ Statement)*)? _ "}"
  {
    // Picat chains subgoals/statements with commas
    const s = stmts ? [stmts[0]].concat(stmts[1].map(x => x[1])).filter(x => x !== "") : [];
    return s.join(",\n");
  }

Statement
  = CommentStmt
  / VarDecl _ ";" { return text().replace(/;$/, "").trim(); }
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / ExprStmt

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ thenStmt:InnerBlock _ elsePart:("else" _ InnerBlock)?
  {
    const ePart = elsePart ? `\nelse\n${elsePart[2]}` : "";
    return `if (${cond}) then\n${thenStmt}${ePart}\nend`;
  }

InnerBlock
  = Block / stmt:Statement { return stmt; }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:InnerBlock
  {
    return `while (${cond}) do\n${body}\nend`;
  }

DoWhileStmt
  = "do" _ body:InnerBlock _ "while" _ "(" _ cond:Expression _ ")" _ ";"
  {
    return `do\n${body}\nwhile (${cond})`;
  }

ForStmt
  = "for" _ "(" _ init:ForInit? _ ";" _ cond:Expression? _ ";" _ update:Expression? _ ")" _ body:Block
  {
    const c = cond || "true";
    const u = update ? `,\n${update}` : "";
    return `${init || "true"},\nwhile (${c}) do\n${body}${u}\nend`;
  }

ForInit = VarDecl / AssignmentExpr / Expression

/* ===================================================== */
/* Switch Statements */
/* ===================================================== */

SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ cases:(CaseClause _)* "}"
  {
    let result = "";
    cases.forEach((c, index) => {
      let clause = c[0];
      if (clause.isDefault) {
          result += `else\n${clause.body}\n`;
      } else {
          let kw = index === 0 ? "if" : "elseif";
          result += `${kw} (${expr} == ${clause.val}) then\n${clause.body}\n`;
      }
    });
    result += "end";
    return result;
  }

CaseClause
  = "case" __ v:Expression _ ":" _ body:((Statement _)+)?
  {
    // Filter out standard C-style breaks for pure Picat translation
    let b = body ? body.map(x => x[0]).filter(s => !s.startsWith("break")).join(",\n") : "true";
    return { isDefault: false, val: v, body: b };
  }
  / "default" _ ":" _ body:((Statement _)+)?
  {
    let b = body ? body.map(x => x[0]).filter(s => !s.startsWith("break")).join(",\n") : "true";
    return { isDefault: true, body: b };
  }

/* ===================================================== */
/* Assignments & Returns */
/* ===================================================== */

ReturnStmt
  = "return" _ expr:Expression? _ ";"
  {
    // Using Picat's explicit return functionality inside functions
    return `return ${expr || "true"}`;
  }

AssignmentStmt
  = e:AssignmentExpr _ ";"
  { return e; }

AssignmentExpr
  = lhs:Assignable _ op:AssignOp _ rhs:Expression
  { 
    // Destructive mutation mapping in Picat is :=
    const mappedOp = op === "=" ? ":=" : op;
    return `${lhs} ${mappedOp} ${rhs}`; 
  }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  = expr:Expression _ ";"
  { return expr; }

/* ===================================================== */
/* Expressions */
/* ===================================================== */

Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ ifTrue:Expression _ ":" _ ifFalse:Expression
  { return `cond(${cond}, ${ifTrue}, ${ifFalse})`; }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(_ "||" _ LogicalAnd)*
  { return tail.reduce((a,t) => `${a} || ${t[3]}`, l); }

LogicalAnd
  = l:Comparison tail:(_ "&&" _ Comparison)*
  { return tail.reduce((a,t) => `${a} && ${t[3]}`, l); }

Comparison
  = l:AddSub tail:(_ CompOp _ AddSub)*
  { return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(_ ("+"/"-") _ MulDiv)*
  { return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l); }

MulDiv
  = l:Unary tail:(_ ("*" / "/" / "%") _ Unary)*
  { return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l); }

Unary
  = op:("++"/"--"/"!"/"-") _ v:Unary 
  { 
    if(op === "!") return `not(${v})`;
    if(op === "++") return `${v} := ${v} + 1`;
    if(op === "--") return `${v} := ${v} - 1`;
    return `${op}${v}`; 
  }
  / Postfix

Postfix
  = base:Primary op:("++" / "--")
  { 
    if(op === "++") return `${base} := ${base} + 1`;
    if(op === "--") return `${base} := ${base} - 1`;
    return base;
  }
  / Primary

Primary
  = "true" { return "true"; }
  / "false" { return "false"; }
  / "(" _ e:Expression _ ")" { return `(${e})`; }
  / FuncCall
  / Assignable
  / Number

FuncCall
  = name:Identifier _ "(" _ args:ArgList? _ ")"
  { return mapFuncCall(name, args); }

ArgList
  = head:Expression tail:(_ "," _ Expression)*
  { return [head].concat(tail.map(x => x[3])); }

Assignable
  = base:Identifier tail:(_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const p = t[1];
      return p.type === "member" ? `${acc}.${p.name}` : `${acc}[${p.index}]`;
    }, mapVariable(base));
  }

AccessPart
  = "." name:Identifier { return {type: "member", name: mapVariable(name)}; }
  / "[" _ idx:Expression _ "]" { return {type: "index", index: idx}; }

/* ===================================================== */
/* Types & Tokens */
/* ===================================================== */

Type
  = BaseType

BaseType
  = "float" / "int" / "uint" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / Identifier

ArraySuffix = "[" _ "]"

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = num:$(
      ( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ )
      ([eE] [+-]? [0-9]+)?
    )
    suffix:([fFuU])?
  {
    // Strips type suffixes so Picat reads a clean numeric string
    return num;
  }
