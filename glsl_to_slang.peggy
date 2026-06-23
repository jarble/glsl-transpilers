{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "uint",
    bool: "bool",
    vec2: "float2",
    vec3: "float3",
    vec4: "float4",
    mat4: "float4x4",
    void: "void"
  };

  const glslBuiltins = new Set([
    "sin", "cos", "tan", "asin", "acos", "atan", "pow", "exp", "log", 
    "sqrt", "abs", "sign", "floor", "ceil", "fract", "mod", "min", "max", 
    "clamp", "mix", "step", "smoothstep", "length", "distance", "dot", 
    "cross", "normalize", "reflect", "refract"
  ]);

  function mapType(t) {
    return typeMap[t] || mapIdentifier(t);
  }

  function mapIdentifier(id) {
    // Do not prefix standard types, main, or GLSL built-ins
    if (glslBuiltins.has(id)) return id;
    if (id === "main" || id.startsWith("gl_") || typeMap[id]) return id;
    
    return "compiled_" + id;
  }

  function mapFuncCall(name, args) {
    const argStr = args ? args.join("") : "";
    
    // Translate specific GLSL built-ins to target language equivalents
    if (name === "mix") return `lerp(${argStr})`;
    if (name === "fract") return `frac(${argStr})`;
    if (name === "mod") return `fmod(${argStr})`;
    if (name === "inversesqrt") return `rsqrt(${argStr})`;
    
    if (glslBuiltins.has(name)) return `${name}(${argStr})`;
    
    return `${mapIdentifier(name)}(${argStr})`;
  }
}

/* ===================================================== */
/* Entry */
/* ===================================================== */

Start
  = ws:_ items:(TopLevel*)
  {
    return ws + items.join("");
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
  / ExprStmt

/* ===================================================== */
/* Structs */
/* ===================================================== */

StructDecl
  = "struct" ws1:__? headName:Identifier? ws2:_ "{" ws3:_ fields:(StructField*) "}" ws4:_ tailName:Identifier? ws5:_ ";" ws6:_
  {
    let structName = "AnonymousStruct";
    let instanceDecl = "";

    if (headName) {
      structName = mapIdentifier(headName);
    } else if (tailName) {
      // Generate a type name if anonymous struct has an instance variable
      structName = mapIdentifier(tailName) + "_Type"; 
    }

    let out = `struct ${structName}` + (ws1 || " ") + `{` + ws3 + fields.join("") + `}`;
    
    if (tailName) {
      out += `;\n${structName} ${mapIdentifier(tailName)}`;
    }
    
    return out + ";" + ws6;
  }

StructField
  = t:Type ws1:__ id:Identifier arr:ArraySuffix? ws2:_ ";" ws3:_
  {
    return mapType(t) + ws1 + mapIdentifier(id) + (arr || "") + ws2 + ";" + ws3;
  }

/* ===================================================== */
/* Globals & Variables */
/* ===================================================== */

GlobalDecl
  = t:Type ws1:__ id:Identifier arr:ArraySuffix? ws2:_ init:("=" _ Expression)? ws3:_ ";" ws4:_
  {
    const initStr = init ? init[0] + init[1] + init[2] : "";
    return mapType(t) + ws1 + mapIdentifier(id) + (arr || "") + ws2 + initStr + ws3 + ";" + ws4;
  }

VarDecl
  = t:Type ws1:__ id:Identifier arr:ArraySuffix? ws2:_ init:("=" _ Expression)? ws3:_ ";" ws4:_
  {
    const initStr = init ? init[0] + init[1] + init[2] : "";
    return mapType(t) + ws1 + mapIdentifier(id) + (arr || "") + ws2 + initStr + ws3 + ";" + ws4;
  }

/* ===================================================== */
/* Functions */
/* ===================================================== */

FunctionDecl
  = ret:Type ws1:__ name:Identifier ws2:_ "(" ws3:_ params:ParamList? ws4:_ ")" ws5:_ body:Block ws6:_
  {
    return mapType(ret) + ws1 + mapIdentifier(name) + ws2 + "(" + ws3 + (params || "") + ws4 + ")" + ws5 + body + ws6;
  }

ParamList
  = head:Param tail:(_ "," _ Param)*
  {
    return head + tail.map(t => t[0] + t[1] + t[2] + t[3]).join("");
  }

Param
  = t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    return mapType(t) + ws1 + mapIdentifier(id) + (arr || "");
  }

/* ===================================================== */
/* Blocks & Control Flow */
/* ===================================================== */

Block
  = "{" ws1:_ stmts:(Statement*) "}"
  {
    return "{" + ws1 + stmts.join("") + "}";
  }

ReturnStmt
  = "return" ws1:__ expr:Expression ws2:_ ";" ws3:_
  {
    return "return" + ws1 + expr + ws2 + ";" + ws3;
  }

AssignmentStmt
  = lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression ws3:_ ";" ws4:_
  {
    return lhs + ws1 + op + ws2 + rhs + ws3 + ";" + ws4;
  }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  = expr:Expression ws:_ ";" ws2:_
  { 
    return expr + ws + ";" + ws2; 
  }

/* ===================================================== */
/* Expressions */
/* ===================================================== */

Expression = FuncCall / Assignable / Number

FuncCall
  = name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    // Reconstruct arguments with their internal whitespace
    const argStr = args ? args : [];
    return mapFuncCall(name, argStr);
  }

ArgList
  = head:Expression tail:(ws1:_ "," ws2:_ Expression)*
  {
    return [head].concat(tail.map(t => t[0] + "," + t[2] + t[3]));
  }

Assignable
  = base:Identifier tail:(_ AccessPart)*
  {
    let out = mapIdentifier(base);
    for (let t of tail) {
      out += t[0] + t[1];
    }
    return out;
  }

AccessPart
  = "." name:Identifier { return "." + name; }
  / "[" ws1:_ idx:Expression ws2:_ "]" { return "[" + ws1 + idx + ws2 + "]"; }

/* ===================================================== */
/* Lexical Rules */
/* ===================================================== */

Type = Identifier
ArraySuffix = "[" _ Expression? _ "]" { return text(); }
Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $( ( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ ) ([eE] [+\-]? [0-9]+)? [fFuU]? )

/* ===================================================== */
/* Whitespace & Comments (The Magic Sauce) */
/* ===================================================== */

_ "optional whitespace"
  = ([ \t\r\n] / Comment)* { return text(); }

__ "mandatory whitespace"
  = ([ \t\r\n] / Comment)+ { return text(); }

Comment
  = SingleLineComment
  / MultiLineComment

SingleLineComment
  = "//" [^\r\n]*

MultiLineComment
  = "/*" (!"*/" .)* "*/"
