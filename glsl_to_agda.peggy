{
  const typeMap = { 
    "int": "Int", 
    "uint": "Nat",
    "float": "Float", 
    "bool": "Bool",
    "void": "Unit",
    "vec2": "Vec Float 2",
    "vec3": "Vec Float 3",
    "vec4": "Vec Float 4",
    "ivec2": "Vec Int 2",
    "ivec3": "Vec Int 3",
    "ivec4": "Vec Int 4",
    "bvec2": "Vec Bool 2",
    "bvec3": "Vec Bool 3",
    "bvec4": "Vec Bool 4",
    "mat2": "Matrix Float 2 2",
    "mat3": "Matrix Float 3 3",
    "mat4": "Matrix Float 4 4"
  };

  function mapType(glslType){
    if(!glslType) return "Float";
    if(glslType.endsWith("[]")){
      const base = mapType(glslType.slice(0,-2));
      return "List " + base;
    }
    return typeMap[glslType] || glslType;
  }

  function formatNumber(n){
    let s = String(n).replace(/[fFuU]$/, "");
    if (s.toLowerCase().includes("e")) {
      let val = Number(s);
      let out = val.toString();
      if (!out.toLowerCase().includes("e")) {
        return out.includes(".") ? out : out + ".0";
      }
      let parts = s.toLowerCase().split("e");
      let base = parts[0];
      let exp = parts[1];
      if (!base.includes(".")) base += ".0";
      return "(" + base + " * 10^" + exp + ")";
    }
    if (s.startsWith(".")) s = "0" + s;
    if (s.endsWith(".")) s = s + "0";
    if (s.indexOf(".") === -1) s = s + ".0";
    return s;
  }

  function translateBuiltin(callee, args){
    if(typeof callee !== "string") callee = String(callee);
    
    // Arrays and Vector initialization in Agda uses brackets
    if(callee.match(/^[ib]?vec[234]$/) || callee.match(/^mat[234]$/)) {
      return "[" + (args ? args.join(", ") : "") + "]";
    }

    // Standard Agda application is space separated: (f a b)
    return "(" + callee + (args && args.length ? " " + args.join(" ") : "") + ")";
  }
}

/* ---------------- Entry ---------------- */
Start
  = pre:_ items:(TopLevelItem _)* { 
      return pre + items.map(i => i[0]).join("\n"); 
    }

/* ---------------- Top-level items ---------------- */
TopLevelItem
  = StructDecl
  / FunctionDecl
  / FunctionDeclOnly
  / TopLevelVarDecl
  / ExprStmt

/* ---------------- Structs to Agda Records ---------------- */
StructDecl
  = pre:_ "struct" ws:__ id:Identifier _ "{" _ members:StructMember* _ "}" _ ";" {
      const fields = members.filter(m => m).map(m => m.name + " : " + mapType(m.type)).join("\n    ");
      return pre + "record " + id + " : Set where\n  field\n    " + fields + "\n";
    }

StructMember
  = _ t:Type __ id:Identifier _ ";" _ { 
      return { name: id, type: t }; 
    }

/* ---------------- Top-level vars ---------------- */
TopLevelVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" {
      return pre + id + " : " + mapType(t) + "\n" + id + " =" + pre2 + expr + "\n";
    }
  / pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier _ ";" {
      return pre + "postulate " + id + " : " + mapType(t) + "\n";
    }

VarQualifier = "uniform" / "attribute" / "varying" / "inout" / "in" / "out" / "const" / "highp" / "mediump" / "lowp"

/* ---------------- Inner statements and blocks ---------------- */
Statement
  = SwitchStmt
  / InnerVarDecl
  / ReturnStmt
  / IfStmt
  / ExprStmt

InnerVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" { 
      return pre + "let " + id + " = " + expr + " in"; 
    }

ReturnStmt
  = pre:_ "return" __ expr:Expression? _ ";" { 
      return pre + (expr ? expr : "tt"); 
    }

ExprStmt
  = pre:_ expr:Expression _ ";" { return pre + expr; }

IfStmt
  = pre:_ "if" pre2:_ "(" _ cond:Expression _ ")" pre3:_ then:InnerBlock _ elsePart:ElseClause? {
      return pre + "(if " + cond + " then " + then + (elsePart ? " else " + elsePart : " else tt") + ")";
    }

ElseClause
  = _ "else" pre:_ stmt:(IfStmt / InnerBlock) { return stmt; }

/* ---------------- Switch Statement translation ---------------- */
SwitchStmt
  = pre:_ "switch" pre2:_ "(" _ cond:Expression _ ")" pre3:_ "{" _ cases:SwitchCase* _ def:SwitchDefault? _ "}" {
      let result = def ? def : "unit";
      for (let i = cases.length - 1; i >= 0; i--) {
         result = "if " + cond + " ≡ " + cases[i].match + " then " + cases[i].body + " else " + result;
      }
      return pre + "(" + result + ")";
    }

SwitchCase
  = _ "case" __ match:Expression _ ":" _ stmts:(Statement _)* {
      // Strip out imperative constructs to form a pure expression
      let body = stmts.map(s => s[0]).join(" ")
                      .replace(/return /g, "")
                      .replace(/;/g, "")
                      .replace(/break/g, "")
                      .trim();
      return { match: match, body: body };
  }

SwitchDefault
  = _ "default" _ ":" _ stmts:(Statement _)* {
      let body = stmts.map(s => s[0]).join(" ")
                      .replace(/return /g, "")
                      .replace(/;/g, "")
                      .replace(/break/g, "")
                      .trim();
      return body;
  }

InnerBlock
  = "{" pre:_ stmts:(Statement _)* "}" { 
      return stmts.map(s => s[0].trim()).filter(s => s !== "break").join(" "); 
    }

/* ---------------- Functions ---------------- */
FunctionDecl
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ body:InnerBlock {
      const typeSig = params ? params.map(p => p.type).join(" -> ") + " -> " + mapType(ret) : mapType(ret);
      const varNames = params ? params.map(p => p.name).join(" ") : "";
      
      return pre + id + " : " + typeSig + "\n" + id + (varNames ? " " + varNames : "") + " = " + body + "\n";
    }

FunctionDeclOnly
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ ";" {
      const typeSig = params ? params.map(p => p.type).join(" -> ") + " -> " + mapType(ret) : mapType(ret);
      return pre + "postulate " + id + " : " + typeSig + "\n";
    }

ParamList = head:Param tail:(_ "," _ Param)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

Param = qual:(ParamQualifier __)* t:Type __ id:Identifier { 
    return { name: id, type: mapType(t) }; 
}

ParamQualifier = "inout" / "in" / "out" / "const"

/* ---------------- Expressions ---------------- */
Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ thenExpr:Expression _ ":" _ elseExpr:Expression {
      return "(if " + cond + " then " + thenExpr + " else " + elseExpr + ")";
    }
  / LogicalOr

LogicalOr = left:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((acc,t)=>acc + " ∨ " + t[3], left); }
LogicalAnd = left:Equality tail:(_ "&&" _ Equality)* { return tail.reduce((acc,t)=>acc + " ∧ " + t[3], left); }
Equality = left:Relational tail:(_ ("==" / "!=") _ Relational)* { return tail.reduce((acc,t)=>acc + " " + (t[1]==="==" ? "≡" : "≢") + " " + t[3], left); }
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
  / "[" _ idx:Expression _ "]" { return function(a){ return "(nth " + idx + " " + a + ")"; }; }
  / "." name:Identifier { return function(o){ return "(" + name + " " + o + ")"; }; }

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

/* ---------------- Tokens ---------------- */
Number = n:$(( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ ) ([eE] [+-]? [0-9]+)? [fFuU]?) { return formatNumber(text()); }
Boolean = b:("true" / "false") { return b; }
Identifier = id:$([a-zA-Z_$][a-zA-Z0-9_$]*) { return id; }

/* ---------------- Types ---------------- */
Type = base:BaseType arr:("[]")* { return base + arr.join(""); }
BaseType = "float" / "int" / "uint" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "ivec2" / "ivec3" / "ivec4" / "bvec2" / "bvec3" / "bvec4" / "mat2" / "mat3" / "mat4" / Identifier

/* ---------------- Whitespace & comments ---------------- */
_ = ws:([ \t\r\n]+ / Comment)* { return ws.map(c=>c).join(""); }
__ = ws:([ \t\r\n]+ / Comment)+ { return ws.map(c=>c).join(""); }

Comment
  = SingleLineComment / MultiLineComment
SingleLineComment = c:$("//" [^\r\n]*) { return "--" + c.slice(2) + "\n"; }
MultiLineComment = c:$("/*" (!"*/" .)* "*/") { return "{-" + c.slice(2, -2) + "-}\n"; }
