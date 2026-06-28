{
  const typeMap = {
    "float": "float", 
    "int": "int", 
    "uint": "unsigned int",
    "bool": "bool", 
    "vec2": "vec2", 
    "vec3": "vec3",
    "vec4": "vec4", 
    "mat2": "mat2", 
    "mat3": "mat3",
    "mat4": "mat4", 
    "void": "void"
  };

  const builtins = new Set([
    "abs", "acos", "asin", "atan", "ceil", "cos", "exp", "floor",
    "log", "max", "min", "pow", "sin", "sqrt", "tan", "sign",
    "length", "normalize", "dot", "cross", "mix", "clamp", "reflect",
    "fract", "mod", "step", "smoothstep",
    "main", "gl_Position", "gl_FragColor", "gl_FragCoord"
  ]);

  function mapType(t) {
    return typeMap[t] || prefixId(t);
  }

  function prefixId(id) {
    if (builtins.has(id) || typeMap[id]) return id;
    return "compiled_" + id;
  }
}

/* ===================================================== 
// Top Level & Macros
===================================================== */

Start
  = items:(TopLevel)* { return items.join(""); }

TopLevel
  = Macro
  / StructDecl
  / FuncDecl
  / GlobalVarDecl
  / WS

Macro
  = ws:_ "#" mws:_ "define" reqWS:__ id:IdentifierName val:(![\r\n] .)* {
      return ws + "#" + mws + "define" + reqWS + prefixId(id) + val.map(c => c[1]).join("");
  }
  / ws:_ "#" val:(![\r\n] .)* {
      return ws + "#" + val.map(c => c[1]).join("");
  }

/* ===================================================== 
// Declarations (Structs, Functions, Variables)
===================================================== */

StructDecl
  = ws1:_ "struct" namePart:(ws2:__ id:IdentifierName { return ws2 + prefixId(id); })? ws3:_ "{" members:StructMember* ws4:_ "}" instPart:(ws5:_ inst:IdentifierName { return ws5 + prefixId(inst); })? ws6:_ ";" {
      // Conditionally maps both named structs and anonymous instance declarations
      return ws1 + "struct" + (namePart || "") + ws3 + "{" + members.join("") + ws4 + "}" + (instPart || "") + ws6 + ";";
  }

StructMember
  = ws1:_ type:TypeName ws2:__ id:IdentifierName arraySize:ArraySuffix? ws3:_ ";" {
      return ws1 + type + ws2 + prefixId(id) + (arraySize || "") + ws3 + ";";
  }

FuncDecl
  = ws1:_ type:TypeName ws2:__ id:IdentifierName ws3:_ "(" params:ParamList? ws4:_ ")" body:Block {
      return ws1 + type + ws2 + prefixId(id) + ws3 + "(" + (params || "") + ws4 + ")" + body;
  }

ParamList
  = ws1:_ param:ParamDecl tail:(ws2:_ "," ws3:_ p:ParamDecl { return ws2 + "," + ws3 + p; })* {
      return ws1 + param + tail.join("");
  }

ParamDecl
  = mod:(ParamModifier __)? type:TypeName ws1:__ id:IdentifierName arraySize:ArraySuffix? {
      return type + ws1 + prefixId(id) + (arraySize || "");
  }

ParamModifier
  = "inout" / "in" / "out"

GlobalVarDecl
  = ws1:_ mod:(VarModifier __)? type:TypeName ws2:__ id:IdentifierName arraySize:ArraySuffix? init:(ws3:_ "=" ws4:_ expr:Expression { return ws3 + "=" + ws4 + expr; })? ws5:_ ";" {
      return ws1 + type + ws2 + prefixId(id) + (arraySize || "") + (init || "") + ws5 + ";";
  }

VarModifier
  = "uniform" / "varying" / "attribute" / "const"

/* ===================================================== 
// Control Flow & Statements
===================================================== */

Block
  = ws1:_ "{" stmts:Statement* ws2:_ "}" {
      return ws1 + "{" + stmts.join("") + ws2 + "}";
  }

Statement
  = Block
  / IfStmt
  / ForStmt
  / WhileStmt
  / ReturnStmt
  / DeclStmt
  / ExprStmt
  / Macro
  / WS

IfStmt
  = ws1:_ "if" ws2:_ "(" cond:Expression ws3:_ ")" trueBody:Statement falseBody:(ws4:_ "else" falseStmt:Statement { return ws4 + "else" + falseStmt; })? {
      return ws1 + "if" + ws2 + "(" + cond + ws3 + ")" + trueBody + (falseBody || "");
  }

ForStmt
  = ws1:_ "for" ws2:_ "(" init:ForInit cond:ForCond update:ForUpdate ws3:_ ")" body:Statement {
      return ws1 + "for" + ws2 + "(" + init + cond + update + ws3 + ")" + body;
  }

ForInit = DeclStmt / ExprStmt / ws:_ ";" { return ws + ";"; }
ForCond = ws1:_ expr:Expression? ws2:_ ";" { return ws1 + (expr || "") + ws2 + ";"; }
ForUpdate = ws:_ expr:Expression? { return ws + (expr || ""); }

WhileStmt
  = ws1:_ "while" ws2:_ "(" cond:Expression ws3:_ ")" body:Statement {
      return ws1 + "while" + ws2 + "(" + cond + ws3 + ")" + body;
  }

ReturnStmt
  = ws1:_ "return" expr:(ws2:__ e:Expression { return ws2 + e; })? ws3:_ ";" {
      return ws1 + "return" + (expr || "") + ws3 + ";";
  }

DeclStmt
  = ws1:_ type:TypeName ws2:__ id:IdentifierName arraySize:ArraySuffix? init:(ws3:_ "=" ws4:_ expr:Expression { return ws3 + "=" + ws4 + expr; })? ws5:_ ";" {
      return ws1 + type + ws2 + prefixId(id) + (arraySize || "") + (init || "") + ws5 + ";";
  }

ExprStmt
  = ws1:_ expr:Expression ws2:_ ";" {
      return ws1 + expr + ws2 + ";";
  }

/* ===================================================== 
// Expressions
===================================================== */

Expression
  = AssignmentExpr

AssignmentExpr
  = left:TernaryExpr right:(ws1:_ op:AssignOp ws2:_ expr:AssignmentExpr { return ws1 + op + ws2 + expr; })? {
      return left + (right || "");
  }

AssignOp = "=" / "+=" / "-=" / "*=" / "/="

TernaryExpr
  = cond:LogicalOrExpr tail:(ws1:_ "?" ws2:_ trueExpr:Expression ws3:_ ":" ws4:_ falseExpr:AssignmentExpr { return ws1 + "?" + ws2 + trueExpr + ws3 + ":" + ws4 + falseExpr; })? {
      return cond + (tail || "");
  }

LogicalOrExpr = head:LogicalAndExpr tail:(ws1:_ "||" ws2:_ expr:LogicalAndExpr { return ws1 + "||" + ws2 + expr; })* { return head + tail.join(""); }
LogicalAndExpr = head:EqualityExpr tail:(ws1:_ "&&" ws2:_ expr:EqualityExpr { return ws1 + "&&" + ws2 + expr; })* { return head + tail.join(""); }
EqualityExpr = head:RelationalExpr tail:(ws1:_ op:("==" / "!=") ws2:_ expr:RelationalExpr { return ws1 + op + ws2 + expr; })* { return head + tail.join(""); }
RelationalExpr = head:AdditiveExpr tail:(ws1:_ op:("<=" / ">=" / "<" / ">") ws2:_ expr:AdditiveExpr { return ws1 + op + ws2 + expr; })* { return head + tail.join(""); }
AdditiveExpr = head:MultiplicativeExpr tail:(ws1:_ op:("+" / "-") ws2:_ expr:MultiplicativeExpr { return ws1 + op + ws2 + expr; })* { return head + tail.join(""); }
MultiplicativeExpr = head:UnaryExpr tail:(ws1:_ op:("*" / "/" / "%") ws2:_ expr:UnaryExpr { return ws1 + op + ws2 + expr; })* { return head + tail.join(""); }

UnaryExpr
  = ws:_ op:("+" / "-" / "!") expr:UnaryExpr { return ws + op + expr; }
  / PostfixExpr

PostfixExpr
  = expr:PrimaryExpr tail:PostfixOp* { return expr + tail.join(""); }

PostfixOp
  = ws1:_ "[" ws2:_ index:Expression ws3:_ "]" { return ws1 + "[" + ws2 + index + ws3 + "]"; }
  / ws1:_ "." ws2:_ id:IdentifierName { return ws1 + "." + ws2 + id; } 
  / ws1:_ op:("++" / "--") { return ws1 + op; }

PrimaryExpr
  = ArrayConstructor
  / TypeConstructor
  / FuncCall
  / ws:_ num:Number { return ws + num; }
  / ws:_ id:IdentifierName { return ws + prefixId(id); }
  / ws1:_ "(" ws2:_ expr:Expression ws3:_ ")" { return ws1 + "(" + ws2 + expr + ws3 + ")"; }

/* ===================================================== 
// Arrays, Types, & Functions
===================================================== */

ArrayConstructor
  = ws1:_ id:IdentifierName ws2:_ "[" ws3:_ size:Expression? ws4:_ "]" ws5:_ "(" args:ArgList? ws6:_ ")" {
      let arrType = mapType(id) + "[" + (size ? size : "") + "]";
      let argStr = args ? args : "";
      return ws1 + "(" + arrType + ")" + ws2 + "{" + argStr + ws6 + "}";
  }

TypeConstructor
  = ws1:_ type:BuiltinType ws2:_ "(" args:ArgList? ws3:_ ")" {
      let argStr = args ? args : "";
      return ws1 + "(" + type + ")" + ws2 + "{" + argStr + ws3 + "}";
  }

FuncCall
  = ws1:_ id:IdentifierName ws2:_ "(" args:ArgList? ws3:_ ")" {
      let argStr = args ? args : "";
      return ws1 + prefixId(id) + ws2 + "(" + argStr + ws3 + ")";
  }

ArgList
  = ws1:_ arg:Expression tail:(ws2:_ "," ws3:_ a:Expression { return ws2 + "," + ws3 + a; })* {
      return ws1 + arg + tail.join("");
  }

ArraySuffix
  = ws1:_ "[" ws2:_ size:Expression? ws3:_ "]" { return ws1 + "[" + ws2 + (size || "") + ws3 + "]"; }

BuiltinType
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4"

TypeName
  = id:IdentifierName { return mapType(id); }

IdentifierName
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $( ([0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+) ([eE] [+-]? [0-9]+)? [fFuU]? )

/* ===================================================== 
// Whitespace & Comment Preservation
===================================================== */

WS
  = chars:([ \t\r\n] / Comment)+ { return chars.join(""); }

_ "optional whitespace"
  = chars:([ \t\r\n] / Comment)* { return chars.join(""); }

__ "mandatory whitespace"
  = chars:([ \t\r\n] / Comment)+ { return chars.join(""); }

Comment
  = MultiLineComment
  / SingleLineComment

SingleLineComment
  = "//" chars:(![\r\n] .)* { return "//" + chars.map(c=>c[1]).join(""); }

MultiLineComment
  = "/*" chars:(!("*/") .)* "*/" { return "/*" + chars.map(c=>c[1]).join("") + "*/"; }
