{
  const typeMap = {
    float: "float",
    int: "int",
    uint: "uint",
    bool: "bool",

    vec2: "float2",
    vec3: "float3",
    vec4: "float4",
    uvec2: "uint2",
    uvec3: "uint3",
    uvec4: "uint4",
    ivec2: "int2",
    ivec3: "int3",
    ivec4: "int4",
    bvec2: "bool2",
    bvec3: "bool3",
    bvec4: "bool4",

    mat2: "float2x2",
    mat3: "float3x3",
    mat4: "float4x4",

    void: "void"
  };

  const glslBuiltins = new Set([
    "sin", "cos", "tan", "asin", "acos", "atan", "pow", "exp", "log", 
    "exp2", "log2", "sqrt", "inversesqrt", "abs", "sign", "floor", "ceil", 
    "fract", "mod", "min", "max", "clamp", "mix", "step", "smoothstep", 
    "length", "distance", "dot", "cross", "normalize", "reflect", "refract"
  ]);

  function mapType(t) {
    return typeMap[t] || mapIdentifier(t);
  }

  function mapIdentifier(id) {
    if (glslBuiltins.has(id)) return id;
    if (id === "main" || id.startsWith("gl_") || id.startsWith("SV_") || typeMap[id]) return id;
    
    return "compiled_" + id;
  }

  function mapFuncName(name) {
    // Translate specific GLSL built-ins to Slang equivalents
    if (name === "mix") return "lerp";
    if (name === "fract") return "frac";
    if (name === "mod") return "fmod";
    if (name === "inversesqrt") return "rsqrt";
    
    if (glslBuiltins.has(name)) return name;
    return mapIdentifier(name);
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
  = PreprocessorDirective
  / StructDecl
  / VarDecl
  / FunctionDecl
  / Statement

Statement
  = PreprocessorDirective
  / VarDecl
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
/* Preprocessor */
/* ===================================================== */

PreprocessorDirective
  = directive:$([ \t]* "#" ( "\\" . / [^\r\n] )*) ws:_
  { return directive + ws; }

/* ===================================================== */
/* Structs */
/* ===================================================== */

StructDecl
  = "struct" ws1:__? headName:Identifier? ws2:_ "{" ws3:_ fields:(StructField*) "}" ws4:_ tailName:Identifier? ws5:_ ";" ws6:_
  {
    let structName = "AnonymousStruct";

    if (headName) {
      structName = mapIdentifier(headName);
    } else if (tailName) {
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
    return mapType(t) + ws1 + id + (arr || "") + ws2 + ";" + ws3;
  }

/* ===================================================== */
/* Variables & Declarators */
/* ===================================================== */

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

Declarator
  = id:Identifier arr:ArraySuffix? ws1:_ init:("=" ws2:_ Expression)?
  {
    const initStr = init ? init[0] + init[1] + init[2] : "";
    return mapIdentifier(id) + (arr || "") + ws1 + initStr;
  }

VarDecl
  = qual:(StorageQualifier __)? t:Type ws1:__ head:Declarator tail:(ws2:_ "," ws3:_ Declarator)* ws4:_ ";" ws5:_
  {
    const prefix = qual ? qual[0] + qual[1] : "";
    let out = prefix + mapType(t) + ws1 + head;
    for (let t of tail) { out += t[0] + "," + t[2] + t[3]; }
    return out + ws4 + ";" + ws5;
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
  = head:Param tail:(ws1:_ "," ws2:_ Param)*
  {
    return head + tail.map(t => t[0] + "," + t[2] + t[3]).join("");
  }

Param
  = qual:(ParameterQualifier __)? t:Type ws1:__ id:Identifier arr:ArraySuffix?
  {
    const prefix = qual ? qual[0] + qual[1] : "";
    return prefix + mapType(t) + ws1 + mapIdentifier(id) + (arr || "");
  }

ParameterQualifier
  = "inout" / "in" / "out"

/* ===================================================== */
/* Blocks & Control Flow */
/* ===================================================== */

Block
  = "{" ws1:_ stmts:(Statement*) "}"
  {
    return "{" + ws1 + stmts.join("") + "}";
  }

IfStmt
  = "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ thenStmt:Statement elsePart:(ws5:_ "else" ws6:_ elseStmt:Statement { return ws5 + "else" + ws6 + elseStmt; })?
  {
    return "if" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + thenStmt + (elsePart || "");
  }

WhileStmt
  = "while" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ body:Statement
  {
    return "while" + ws1 + "(" + ws2 + cond + ws3 + ")" + ws4 + body;
  }

DoWhileStmt
  = "do" ws1:_ body:Statement ws2:_ "while" ws3:_ "(" ws4:_ cond:Expression ws5:_ ")" ws6:_ ";" ws7:_
  {
    return "do" + ws1 + body + ws2 + "while" + ws3 + "(" + ws4 + cond + ws5 + ")" + ws6 + ";" + ws7;
  }

ForStmt
  = "for" ws1:_ "(" ws2:_ init:ForInit? ws3:_ ";" ws4:_ cond:Expression? ws5:_ ";" ws6:_ update:ForUpdate? ws7:_ ")" ws8:_ body:Statement
  {
    return "for" + ws1 + "(" + ws2 + (init||"") + ws3 + ";" + ws4 + (cond||"") + ws5 + ";" + ws6 + (update||"") + ws7 + ")" + ws8 + body;
  }

ForInit = VarDeclInline / AssignmentExpr / Expression
ForUpdate = AssignmentExpr / Expression

VarDeclInline
  = t:Type ws1:__ head:Declarator tail:(ws2:_ "," ws3:_ Declarator)*
  {
    let out = mapType(t) + ws1 + head;
    for (let t of tail) { out += t[0] + "," + t[2] + t[3]; }
    return out;
  }

SwitchStmt
  = "switch" ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" ws4:_ "{" ws5:_ cases:(CaseClause)* "}" ws6:_
  {
    return "switch" + ws1 + "(" + ws2 + expr + ws3 + ")" + ws4 + "{" + ws5 + cases.join("") + "}" + ws6;
  }

CaseClause
  = "case" ws1:__ v:Expression ws2:_ ":" ws3:_ stmts:(Statement)*
  { return "case" + ws1 + v + ws2 + ":" + ws3 + stmts.join(""); }
  / "default" ws1:_ ":" ws2:_ stmts:(Statement)*
  { return "default" + ws1 + ":" + ws2 + stmts.join(""); }

/* ===================================================== */
/* Single Statements */
/* ===================================================== */

ReturnStmt
  = "return" ws1:__ expr:Expression ws2:_ ";" ws3:_
  { return "return" + ws1 + expr + ws2 + ";" + ws3; }
  / "return" ws1:_ ";" ws2:_
  { return "return" + ws1 + ";" + ws2; }

BreakStmt
  = "break" ws1:_ ";" ws2:_ { return "break" + ws1 + ";" + ws2; }

ContinueStmt
  = "continue" ws1:_ ";" ws2:_ { return "continue" + ws1 + ";" + ws2; }

AssignmentStmt
  = e:AssignmentExpr ws1:_ ";" ws2:_
  { return e + ws1 + ";" + ws2; }

ExprStmt
  = expr:Expression ws1:_ ";" ws2:_
  { return expr + ws1 + ";" + ws2; }

/* ===================================================== */
/* Expressions & Operators */
/* ===================================================== */

Expression = Ternary

Ternary
  = cond:LogicalOr ws1:_ "?" ws2:_ ifTrue:Expression ws3:_ ":" ws4:_ ifFalse:Expression
  { return cond + ws1 + "?" + ws2 + ifTrue + ws3 + ":" + ws4 + ifFalse; }
  / LogicalOr

LogicalOr  = l:LogicalAnd tail:(ws1:_ "||" ws2:_ LogicalAnd)* { return tail.reduce((a,t)=>a+t[0]+"||"+t[2]+t[3], l); }
LogicalAnd = l:BitwiseOr tail:(ws1:_ "&&" ws2:_ BitwiseOr)* { return tail.reduce((a,t)=>a+t[0]+"&&"+t[2]+t[3], l); }
BitwiseOr  = l:BitwiseXor tail:(ws1:_ "|" ws2:_ BitwiseXor)* { return tail.reduce((a,t)=>a+t[0]+"|"+t[2]+t[3], l); }
BitwiseXor = l:BitwiseAnd tail:(ws1:_ "^" ws2:_ BitwiseAnd)* { return tail.reduce((a,t)=>a+t[0]+"^"+t[2]+t[3], l); }
BitwiseAnd = l:Equality tail:(ws1:_ "&" ws2:_ Equality)* { return tail.reduce((a,t)=>a+t[0]+"&"+t[2]+t[3], l); }

Equality   = l:Comparison tail:(ws1:_ op:("=="/"!=") ws2:_ Comparison)* { return tail.reduce((a,t)=>a+t[0]+t[1]+t[2]+t[3], l); }
Comparison = l:Shift tail:(ws1:_ op:("<="/">="/"<"/">") ws2:_ Shift)* { return tail.reduce((a,t)=>a+t[0]+t[1]+t[2]+t[3], l); }
Shift      = l:AddSub tail:(ws1:_ op:("<<"/">>") ws2:_ AddSub)* { return tail.reduce((a,t)=>a+t[0]+t[1]+t[2]+t[3], l); }
AddSub     = l:MulDiv tail:(ws1:_ op:("+"/"-") ws2:_ MulDiv)* { return tail.reduce((a,t)=>a+t[0]+t[1]+t[2]+t[3], l); }
MulDiv     = l:Unary tail:(ws1:_ op:("*" / "/" / "%") ws2:_ Unary)* { return tail.reduce((a,t)=>a+t[0]+t[1]+t[2]+t[3], l); }

Unary
  = op:("++" / "--" / "!" / "-" / "~" / "+") ws1:_ v:Unary { return op + ws1 + v; }
  / Postfix

Postfix
  = base:Primary tail:(ws1:_ part:(AccessPart / "++" / "--") { return ws1 + part; })*
  {
    return base + tail.join("");
  }

Primary
  = "true" { return "true"; }
  / "false" { return "false"; }
  / "(" ws1:_ e:Expression ws2:_ ")" { return "(" + ws1 + e + ws2 + ")"; }
  / ArrayConstructor
  / TypeConstructor
  / FuncCall
  / Number
  / id:Identifier { return mapIdentifier(id); }

FuncCall
  = name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    return mapFuncName(name) + ws1 + "(" + ws2 + (args || "") + ws3 + ")";
  }

ArgList
  = head:Expression tail:(ws1:_ "," ws2:_ Expression)*
  {
    return head + tail.map(t => t[0] + "," + t[2] + t[3]).join("");
  }

ArrayConstructor
  = t:BaseType ws1:_ "[" ws2:_ size:Expression? ws3:_ "]" ws4:_ "(" ws5:_ args:ArgList? ws6:_ ")"
  {
    return "{" + ws5 + (args || "") + ws6 + "}";
  }

TypeConstructor
  = name:("uvec2"/"uvec3"/"uvec4"/"ivec2"/"ivec3"/"ivec4"/"bvec2"/"bvec3"/"bvec4"/"vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4") ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")"
  {
    return mapType(name) + ws1 + "(" + ws2 + (args || "") + ws3 + ")";
  }

AssignmentExpr
  = lhs:Assignable ws1:_ op:AssignOp ws2:_ rhs:Expression
  {
    return lhs + ws1 + op + ws2 + rhs;
  }

AssignOp = "+=" / "-=" / "*=" / "/=" / "%=" / "<<=" / ">>=" / "&=" / "^=" / "|=" / "="

/* ===================================================== */
/* Assignables & Accessors */
/* ===================================================== */

Assignable
  = base:Identifier tail:(ws1:_ part:AccessPart { return ws1 + part; })*
  {
    return mapIdentifier(base) + tail.join("");
  }

AccessPart
  = "." ws1:_ name:Identifier { return "." + ws1 + name; }
  / "[" ws1:_ idx:Expression ws2:_ "]" { return "[" + ws1 + idx + ws2 + "]"; }

/* ===================================================== */
/* Lexical Rules */
/* ===================================================== */

Type = BaseType

BaseType
  = "float" / "int" / "uint" / "bool" / "void"
  / "vec2" / "vec3" / "vec4"
  / "uvec2" / "uvec3" / "uvec4"
  / "ivec2" / "ivec3" / "ivec4"
  / "bvec2" / "bvec3" / "bvec4"
  / "mat2" / "mat3" / "mat4"
  / Identifier

ArraySuffix = "[" ws1:_ e:Expression? ws2:_ "]" { return "[" + ws1 + (e ? e : "") + ws2 + "]"; }

Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $( ( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ ) ([eE] [+\-]? [0-9]+)? [fFuU]? )

/* ===================================================== */
/* Whitespace & Comments */
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
