{
  const typeMap = { 
    "int": "Z", 
    "float": "R", 
    "bool": "bool",
    "vec2": "vec R 2",
    "vec3": "vec R 3",
    "vec4": "vec R 4",
    "ivec2": "vec Z 2",
    "ivec3": "vec Z 3",
    "ivec4": "vec Z 4",
    "bvec2": "vec bool 2",
    "bvec3": "vec bool 3",
    "bvec4": "vec bool 4",
    "mat2": "mat R 2 2",
    "mat3": "mat R 3 3",
    "mat4": "mat R 4 4"
  };

  // Maps GLSL math to Coq's standard Reals library
  const builtinFuncMap = {
    "abs": "Rabs",
    "acos": "acos",
    "asin": "asin",
    "atan": "atan",
    "cos": "cos",
    "sin": "sin",
    "tan": "tan",
    "exp": "exp",
    "log": "ln",
    "log2": "Rlog2",
    "pow": "Rpower",
    "sqrt": "sqrt",
    "min": "Rmin",
    "max": "Rmax",
    "floor": "Zfloor",
    "ceil": "Zceil",
    "fract": "Rfract",
    "mod": "Rmod",
    "mix": "Rmix",
    "clamp": "Rclamp",
    "sign": "Rsign",
    "step": "Rstep",
    "smoothstep": "Rsmoothstep",
    "length": "vlength",
    "distance": "vdistance",
    "dot": "vdot",
    "cross": "vcross",
    "normalize": "vnormalize",
    "reflect": "vreflect",
    "refract": "vrefract"
  };

  // Maps GLSL environment variables/constants
  const builtinConstMap = {
    "gl_Position": "gl_Position",
    "gl_FragColor": "gl_FragColor",
    "gl_FragCoord": "gl_FragCoord",
    "gl_FrontFacing": "gl_FrontFacing",
    "gl_PointCoord": "gl_PointCoord"
  };

  function mapType(glslType){
    if(!glslType) return "R";
    if(glslType.endsWith("[]")){
      const base = mapType(glslType.slice(0,-2));
      return "list " + base;
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
    
    // Translate GLSL vector/matrix constructors to Coq list literals
    if(callee.match(/^[ib]?vec[234]$/) || callee.match(/^mat[234]$/)) {
      return "[" + (args ? args.join("; ") : "") + "]";
    }

    // Map to Coq standard library function, or keep original name
    const coqFunc = builtinFuncMap[callee] || callee;

    // Wrap in parentheses to strictly define Coq application precedence
    return "(" + coqFunc + (args && args.length ? " " + args.join(" ") : "") + ")";
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

/* ---------------- Precision (Ignored in Coq) ---------------- */
PrecisionDecl
  = pre:_ "precision" __ ("highp"/"mediump"/"lowp") __ t:Type _ ";" {
      return pre + "(* precision " + t + " ignored *)\n";
    }

/* ---------------- Structs ---------------- */
StructDecl
  = pre:_ "struct" ws:__ id:Identifier _ "{" _ members:StructMember* _ "}" _ ";" {
      const fields = members.filter(m => m).map(m => m.name + " : " + mapType(m.type)).join("; ");
      return pre + "Record " + id + " : Type := mk_" + id + " { " + fields + " }.\n";
    }

StructMember
  = _ t:Type __ id:Identifier _ ";" _ { 
      return { name: id, type: t }; 
    }

/* ---------------- Top-level vars/assignments ---------------- */
TopLevelVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" {
      return pre + "Definition " + id + " : " + mapType(t) + " :=" + pre2 + expr + ".\n";
    }
  / pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier _ ";" {
      return pre + "Parameter " + id + " : " + mapType(t) + ".\n";
    }

VarQualifier = "uniform" / "attribute" / "varying" / "inout" / "in" / "out" / "const" / "highp" / "mediump" / "lowp"

TopLevelAssignmentStmt
  = pre:_ lhs:Assignable pre2:_ "=" _ rhs:Expression _ ";" {
      return pre + "Axiom " + lhs + "_eq : " + lhs + " =" + pre2 + rhs + ".\n";
    }

/* ---------------- Top-level if / else if / else ---------------- */
TopLevelIfStmt
  = pre:_ "if" pre2:_ "(" _ cond:Expression _ ")" pre3:_ then:InnerBlock _ elseifClauses:TopLevelElseIfClause* _ elsePart:TopLevelElseClause? {
      let code = pre + "Axiom if_stmt : if " + cond + " then\n" + then;
      for (let e of elseifClauses) code += "\nelse if " + e.cond + " then\n" + e.block;
      if (elsePart) code += "\nelse\n" + elsePart;
      code += ".\n";
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
  / ExprStmt

InnerVarDecl
  = pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier pre2:_ "=" _ expr:Expression _ ";" { 
      return pre + "let " + id + " : " + mapType(t) + " :=" + pre2 + expr + " in"; 
    }
  / pre:_ qual:(VarQualifier __)* t:Type __ id:Identifier _ ";" { 
      return pre + "let " + id + " : " + mapType(t) + " := 0 in"; // Default fake init
    }

InnerAssignment
  = pre:_ lhs:Assignable pre2:_ "=" _ rhs:Expression _ ";" { 
      return pre + "let " + lhs + " :=" + pre2 + rhs + " in"; 
    }

ReturnStmt
  = pre:_ "return" __ expr:Expression? _ ";" { 
      return pre + (expr ? expr : "tt"); 
    }

ExprStmt
  = pre:_ expr:Expression _ ";" { return pre + expr; }

IfStmt
  = pre:_ "if" pre2:_ "(" _ cond:Expression _ ")" pre3:_ then:InnerBlock _ elsePart:ElseClause? {
      return pre + "(if " + cond + " then\n" + then + (elsePart ? "\nelse\n" + elsePart : "\nelse tt") + ")";
    }

ElseClause
  = _ "else" pre:_ stmt:(IfStmt / InnerBlock) { return stmt; }

InnerBlock
  = "{" pre:_ stmts:(Statement _)* "}" { 
      return stmts.map(s => s[0]).join("\n"); 
    }

/* ---------------- Functions ---------------- */
FunctionDecl
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ body:InnerBlock {
      const ps = params ? params.join(" ") : "";
      if (ret === "void") {
        return pre + "Definition " + id + " " + ps + " : unit := \n" + body + ".\n";
      }
      return pre + "Definition " + id + " " + ps + " : " + mapType(ret) + " := \n" + body + ".\n";
    }

FunctionDeclOnly
  = pre:_ ret:Type __ id:Identifier _ "(" _ params:ParamList? _ ")" _ ";" {
      const ps = params ? "forall " + params.join(" ") + ", " : "";
      const mappedRet = ret === "void" ? "unit" : mapType(ret);
      return pre + "Parameter " + id + " : " + ps + mappedRet + ".\n";
    }

ParamList = head:Param tail:(_ "," _ Param)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

Param = qual:(ParamQualifier __)* t:Type __ id:Identifier { 
    return "(" + id + " : " + mapType(t) + ")"; 
}

ParamQualifier = "inout" / "in" / "out" / "const"

/* ---------------- Expressions ---------------- */
Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ thenExpr:Expression _ ":" _ elseExpr:Expression {
      return "(if " + cond + " then " + thenExpr + " else " + elseExpr + ")";
    }
  / LogicalOr

LogicalOr = left:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((acc,t)=>acc + " || " + t[3], left); }
LogicalAnd = left:Equality tail:(_ "&&" _ Equality)* { return tail.reduce((acc,t)=>acc + " && " + t[3], left); }
Equality = left:Relational tail:(_ ("==" / "!=") _ Relational)* { return tail.reduce((acc,t)=>acc + " " + (t[1]==="==" ? "=" : "<>") + " " + t[3], left); }
Relational = left:Additive tail:(_ ("<=" / ">=" / "<" / ">") _ Additive)* { return tail.reduce((acc,t)=>acc + " " + t[1] + " " + t[3], left); }

Additive = left:Multiplicative tail:(_ ("+" / "-") _ Multiplicative)* { return tail.reduce((acc,t)=>acc + " " + t[1] + " " + t[3], left); }
Multiplicative = left:Exponent tail:(_ ("*" / "/" / "%") _ Exponent)* { 
    return tail.reduce((acc,t)=> t[1] === "%" ? acc + " mod " + t[3] : acc + " " + t[1] + " " + t[3], left); 
}
Exponent = left:Unary tail:(_ "**" _ Unary)* { return tail.reduce((acc,t)=> acc + " ^ " + t[3], left); }

Unary
  = "-" _ v:Unary { return "-" + v; }
  / "!" _ v:Unary { return "negb " + v; }
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
ArrayLiteral = "[" _ elems:ExprList? _ "]" { const arr = elems ? elems : []; return "[" + arr.join("; ") + "]"; }
ExprList = head:Expression tail:(_ "," _ Expression)* { return [head].concat(tail.map(t=>t[3])).filter(m=>m); }

/* ---------------- Assignable ---------------- */
Assignable = Postfix

/* ---------------- Tokens ---------------- */
Number = n:$(( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ ) ([eE] [+-]? [0-9]+)? [fFuU]?) { return formatNumber(text()); }
Boolean = b:("true" / "false") { return b; }

// Checks if the identifier is a GLSL builtin constant, maps it if found, otherwise returns it raw.
Identifier = id:$([a-zA-Z_$][a-zA-Z0-9_$]*) { return builtinConstMap[id] || id; }

/* ---------------- Types ---------------- */
Type = base:BaseType arr:("[]")* { return base + arr.join(""); }
BaseType = "float" / "int" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "ivec2" / "ivec3" / "ivec4" / "bvec2" / "bvec3" / "bvec4" / "mat2" / "mat3" / "mat4" / Identifier

/* ---------------- Whitespace & comments ---------------- */
_ = ws:([ \t\r\n]+ / Comment)* { return ws.map(c=>c).join(""); }
__ = ws:([ \t\r\n]+ / Comment)+ { return ws.map(c=>c).join(""); }

Comment
  = SingleLineComment / MultiLineComment
SingleLineComment = c:$("//" [^\r\n]*) { return "(*" + c.slice(2) + " *)\n"; }
MultiLineComment = c:$("/*" (!"*/" .)* "*/") { return "(*" + c.slice(2, -2) + "*)\n"; }
