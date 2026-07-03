{
  const typeMap = { 
    "int": "int", 
    "float": "float", 
    "bool": "bool",
    "vec2": "array[1..2] of float",
    "vec3": "array[1..3] of float",
    "vec4": "array[1..4] of float",
    "ivec2": "array[1..2] of int",
    "ivec3": "array[1..3] of int",
    "ivec4": "array[1..4] of int",
    "bvec2": "array[1..2] of bool",
    "bvec3": "array[1..3] of bool",
    "bvec4": "array[1..4] of bool",
    "mat2": "array[1..2, 1..2] of float",
    "mat3": "array[1..3, 1..3] of float",
    "mat4": "array[1..4, 1..4] of float"
  };

  function mapType(glslType){
    if(!glslType) return "float";
    if(glslType.endsWith("[]")){
      const base = mapType(glslType.slice(0,-2));
      return "array[int] of " + base;
    }
    return typeMap[glslType] || glslType;
  }

  function formatNumber(n){ return n.indexOf(".") >= 0 ? n : n + ".0"; }

  function translateBuiltin(callee, args){
    if(typeof callee !== "string") callee = String(callee);
    if(callee.match(/^[ib]?vec[234]$/) || callee.match(/^mat[234]$/)) {
      return "[" + (args ? args.join(", ") : "") + "]";
    }
    return callee + "(" + (args ? args.join(", ") : "") + ")";
  }
}

/* ---------------- Entry ---------------- */
Start
  = pre:_ items:(TopLevelItem _)* { 
      return pre + items.map(i => i[0]).join(""); 
    }

/* ---------------- Top-level items ---------------- */
TopLevelItem
  = PrecisionDecl
  / StructDecl
  / FunctionDecl
  / FunctionDeclOnly
  / TopLevelVarDecl
  / TopLevelAssignmentStmt
  / TopLevelIfStmt
  / ExprStmt

/* ---------------- Precision (Ignored in MiniZinc) ---------------- */
PrecisionDecl
  = pre:_ "precision" __ ("highp"/"mediump"/"lowp") __ t:Type _ ";" {
      return pre + "% precision " + t + " ignored;\n";
    }

/* ---------------- Structs ---------------- */
StructDecl
  = pre:_ "struct" ws:__ id:Identifier _ "{" _ members:StructMember* _ "}" _ ";" {
      const fields = members.filter(m => m).map(m => mapType(m.type) + ": " + m.name).join(", ");
      return pre + "record" + ws + id + " = { " + fields + " };\n";
    }

StructMember
  = _ t:Type __ id:Identifier _ ";" _ { 
      return { name: id, type: t }; 
    }

/* ---------------- Top-level vars/assignments ---------------- */
TopLevelVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" {
      return pre + mapType(t) + ": " + id + pre2 + " = " + expr + ";\n";
    }
  / pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier _ ";" {
      return pre + mapType(t) + ": " + id + ";\n";
    }

VarQualifier = "uniform" / "attribute" / "varying" / "inout" / "in" / "out" / "const" / "highp" / "mediump" / "lowp"

TopLevelAssignmentStmt
  = pre:_ lhs:Assignable pre2:_ "=" _ rhs:Expression _ ";" {
      return pre + "constraint " + lhs + pre2 + " = " + rhs + ";\n";
    }

/* ---------------- Top-level if / else if / else ---------------- */
TopLevelIfStmt
  = pre:_ "if" pre2:_ "(" _ cond:Expression _ ")" pre3:_ then:InnerBlock _ elseifClauses:TopLevelElseIfClause* _ elsePart:TopLevelElseClause? {
      let code = pre + "constraint if" + pre2 + cond + pre3 + " then\n" + then;
      for (let e of elseifClauses) code += "\nelseif " + e.cond + " then\n" + e.block;
      if (elsePart) code += "\nelse\n" + elsePart;
      code += "\nendif;\n";
      return code;
    }

TopLevelElseIfClause
  = _ "else" _ "if" pre:_ "(" _ cond:Expression _ ")" pre2:_ block:InnerBlock { return {cond, block}; }

TopLevelElseClause
  = _ "else" pre:_ block:InnerBlock { return block; }

/* ---------------- Inner statements and blocks ---------------- */
Statement
  = InnerVarDecl
  / InnerAssignment
  / ReturnStmt
  / IfStmt
  / SwitchStmt
  / BreakStmt
  / ExprStmt

InnerVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" { 
      return pre + "let { " + mapType(t) + ": " + id + pre2 + " = " + expr + "; } in"; 
    }
  / pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier _ ";" { 
      return pre + "let { " + mapType(t) + ": " + id + "; } in"; 
    }

InnerAssignment
  = pre:_ lhs:Assignable pre2:_ "=" _ rhs:Expression _ ";" { 
      return pre + lhs + pre2 + " = " + rhs + ";"; 
    }

ReturnStmt
  = pre:_ "return" _ expr:Expression? _ ";" { 
      return pre + (expr ? expr : "") + ";"; 
    }

BreakStmt
  = pre:_ "break" _ ";" { return pre + "break;"; }

ExprStmt
  = pre:_ expr:Expression _ ";" { return pre + expr + ";"; }

IfStmt
  = pre:_ "if" pre2:_ "(" _ cond:Expression _ ")" pre3:_ then:InnerBlock _ elsePart:ElseClause? {
      return pre + "(if " + cond + " then\n" + then + (elsePart ? "\nelse\n" + elsePart : "") + "\nendif)";
    }

ElseClause
  = _ "else" pre:_ stmt:(IfStmt / InnerBlock) { return stmt; }

/* ---------------- Switch Statements ---------------- */
SwitchStmt
  = pre:_ "switch" pre2:_ "(" _ expr:Expression _ ")" pre3:_ "{" _ cases:SwitchCase* _ defaultCase:DefaultCase? _ "}" {
      if (cases.length === 0) return pre + (defaultCase ? defaultCase : "");
      let code = pre + "(if " + expr + " == " + cases[0].val + " then " + cases[0].block;
      for (let i = 1; i < cases.length; i++) {
          code += "\nelseif " + expr + " == " + cases[i].val + " then " + cases[i].block;
      }
      if (defaultCase) {
          code += "\nelse " + defaultCase;
      }
      code += "\nendif)";
      return code;
    }

SwitchCase
  = _ "case" __ val:Expression _ ":" _ stmts:(Statement _)* {
      let block = stmts.map(s => s[0]).join(" ");
      // Strip 'return', 'break', and trailing semicolons inside the pure expression
      block = block.replace(/\breturn\b\s*/g, "").replace(/\bbreak\b\s*;/g, "").replace(/;/g, "").trim();
      return { val: val, block: block };
    }

DefaultCase
  = _ "default" _ ":" _ stmts:(Statement _)* {
      let block = stmts.map(s => s[0]).join(" ");
      block = block.replace(/\breturn\b\s*/g, "").replace(/\bbreak\b\s*;/g, "").replace(/;/g, "").trim();
      return block;
    }

InnerBlock
  = "{" pre:_ stmts:(Statement _)* "}" { 
      return stmts.map(s => s[0]).join("\n"); 
    }

/* ---------------- Functions ---------------- */
FunctionDecl
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ body:InnerBlock {
      const ps = params ? params.join(", ") : "";
      if (ret === "void") {
        return pre + "predicate " + id + "(" + ps + ") = \n" + body + "\n";
      }
      return pre + "function " + mapType(ret) + ": " + id + "(" + ps + ") = \n" + body + "\n";
    }

FunctionDeclOnly
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ ";" {
      const ps = params ? params.join(", ") : "";
      if (ret === "void") {
        return pre + "% predicate prototype: " + id + "(" + ps + ");\n";
      }
      return pre + "% function prototype: " + mapType(ret) + ": " + id + "(" + ps + ");\n";
    }

ParamList = head:Param tail:(_ "," _ Param)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

Param = qual:(ParamQualifier __)* t:Type __ id:Identifier { 
    return mapType(t) + ": " + id; 
}

ParamQualifier = "inout" / "in" / "out" / "const"

/* ---------------- Expressions ---------------- */
Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ thenExpr:Expression _ ":" _ elseExpr:Expression {
      return "(if " + cond + " then " + thenExpr + " else " + elseExpr + " endif)";
    }
  / LogicalOr

LogicalOr = left:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((acc,t)=>acc + " \\/ " + t[3], left); }
LogicalAnd = left:Equality tail:(_ "&&" _ Equality)* { return tail.reduce((acc,t)=>acc + " /\\ " + t[3], left); }
Equality = left:Relational tail:(_ ("==" / "!=") _ Relational)* { return tail.reduce((acc,t)=>acc + " " + t[1] + " " + t[3], left); }
Relational = left:Additive tail:(_ ("<=" / ">=" / "<" / ">") _ Additive)* { return tail.reduce((acc,t)=>acc + " " + t[1] + " " + t[3], left); }

Additive = left:Multiplicative tail:(_ ("+" / "-") _ Multiplicative)* { return tail.reduce((acc,t)=>acc + " " + t[1] + " " + t[3], left); }
Multiplicative = left:Exponent tail:(_ ("*" / "/" / "%") _ Exponent)* { 
    return tail.reduce((acc,t)=> t[1] === "%" ? acc + " mod " + t[3] : acc + " " + t[1] + " " + t[3], left); 
}
Exponent = left:Unary tail:(_ "**" _ Unary)* { return tail.reduce((acc,t)=> acc + " ^ " + t[3], left); }

Unary
  = "-" _ v:Unary { return "-" + v; }
  / "!" _ v:Unary { return "not " + v; }
  / Postfix

Postfix
  = base:Primary tail:PostfixPart* { return tail.reduce((acc, part) => part(acc), base); }

PostfixPart
  = "(" _ args:ArgList? _ ")" { return function(callee){ return translateBuiltin(callee,args||[]); } }
  / "[" _ idx:Expression _ "]" { return function(a){ return a + "[" + idx + "]"; }; }
  / "." name:Identifier { return function(o){ return o + "." + name; }; }

ArgList = head:Expression tail:(_ "," _ Expression)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

/* ---------------- Primary ---------------- */
Primary
  = Number
  / Boolean
  / ArrayLiteral
  / Identifier
  / "(" _ e:Expression _ ")" { return "(" + e + ")"; }

/* ---------------- Arrays ---------------- */
ArrayLiteral = "[" _ elems:ExprList? _ "]" { const arr = elems ? elems : []; return "[" + arr.join(", ") + "]"; }
ExprList = head:Expression tail:(_ "," _ Expression)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

/* ---------------- Assignable ---------------- */
Assignable = Postfix

/* ---------------- Tokens ---------------- */
Number = n:$([0-9]+ ("." [0-9]+)?) { return formatNumber(text()); }
Boolean = b:("true" / "false") { return b; }
Identifier = id:$([a-zA-Z_$][a-zA-Z0-9_$]*) { return id; }

/* ---------------- Types ---------------- */
Type = base:BaseType arr:("[]")* { return base + arr.join(""); }
BaseType = "float" / "int" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "ivec2" / "ivec3" / "ivec4" / "bvec2" / "bvec3" / "bvec4" / "mat2" / "mat3" / "mat4" / Identifier

/* ---------------- Whitespace & comments ---------------- */
_ = ws:([ \t\r\n]+ / Comment)* { return ws.map(c=>c).join(""); }
__ = ws:([ \t\r\n]+ / Comment)+ { return ws.map(c=>c).join(""); }

Comment
  = SingleLineComment / MultiLineComment
SingleLineComment = c:$("//" [^\r\n]*) { return c + "\n"; }
MultiLineComment = c:$("/*" (!"*/" .)* "*/") { return c + "\n"; }
