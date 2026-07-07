{
  // Maps GLSL math functions to standard Wolfram Language Headings
  const builtinMap = {
    abs: "Abs", acos: "ArcCos", asin: "ArcSin", atan: "ArcTan",
    ceil: "Ceiling", cos: "Cos", exp: "Exp", floor: "Floor",
    log: "Log", max: "Max", min: "Min", pow: "Power",
    sin: "Sin", sqrt: "Sqrt", tan: "Tan", round: "Round",
    clamp: "Clip", length: "Norm", normalize: "Normalize",
    dot: "Dot", cross: "Cross", mix: "Blend", step: "UnitStep"
  };

  function mapFunc(f) { 
    return builtinMap[f] || f; 
  }

  // Intercepts GLSL vectors and matrices, shifting them to Mathematica Lists
  function mapTypeConstruct(name, args) {
    if (name.match(/^[ib]?vec[234]$/) || name.match(/^mat[234]$/)) {
      return "{" + (args ? args.join(", ") : "") + "}";
    }
    return mapFunc(name) + "[" + (args ? args.join(", ") : "") + "]";
  }
}

/* ===================================================== */
/* Entry Point                                           */
/* ===================================================== */
Start 
  = _ items:(TopLevel (_ TopLevel)*)? _ {
    return items ? [items[0]].concat(items[1].map(x => x[1])).join("\n\n") : "";
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
  / ExprStmt 
  / Block

/* ===================================================== */
/* Structs & Associations                                */
/* ===================================================== */
StructDecl 
  = "struct" __ name:Identifier _ "{" _ fields:(StructField (_ StructField)*)? _ "}" _ ";"? {
    const fs = fields ? [fields[0]].concat(fields[1].map(x=>x[1])) : [];
    const args = fs.map(f => f.id + "_").join(", ");
    const assoc = fs.map(f => '"' + f.id + '" -> ' + f.id).join(", ");
    return name + "[" + args + "] := <|" + assoc + "|>;";
  }

StructField 
  = t:Type __ id:Identifier _ ";" { 
    return { id: id, type: t }; 
  }

/* ===================================================== */
/* Variables & Globals                                   */
/* ===================================================== */
GlobalDecl 
  = qual:StorageQualifier? _ t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
    return id + (init ? " = " + init[2] : "") + ";";
  }

StorageQualifier 
  = "uniform" / "attribute" / "varying" / "const"

VarDecl 
  = t:Type __ id:Identifier _ init:("=" _ Expression)? _ ";" {
    return id + (init ? " = " + init[2] : "") + ";";
  }

/* ===================================================== */
/* Functions                                             */
/* ===================================================== */
FunctionDecl 
  = ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block {
    const ps = params ? params.map(p => p + "_").join(", ") : "";
    return name + "[" + ps + "] := (\n" + body + "\n);";
  }

ParamList 
  = head:Param tail:(_ "," _ Param)* { 
    return [head].concat(tail.map(x=>x[3])); 
  }

Param 
  = qual:("inout" / "in" / "out" / __)? _ t:Type __ id:Identifier { 
    return id; 
  }

/* ===================================================== */
/* Control Flow & Blocks                                 */
/* ===================================================== */
Block 
  = "{" _ stmts:(Statement (_ Statement)*)? _ "}" {
    const s = stmts ? [stmts[0]].concat(stmts[1].map(x=>x[1])) : [];
    // Mathematica uses semi-colons for compound expressions
    return s.join("\n"); 
  }

IfStmt 
  = "if" _ "(" _ cond:Expression _ ")" _ thenStmt:Statement elsePart:(_ "else" _ Statement)? {
    return "If[" + cond + ", \n" + thenStmt + (elsePart ? ", \n" + elsePart[3] : "") + "\n];";
  }

WhileStmt 
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement {
    return "While[" + cond + ", \n" + body + "\n];";
  }

ForStmt 
  = "for" _ "(" _ init:(VarDecl / AssignmentExpr / Expression / "") _ ";" _ cond:Expression? _ ";" _ update:(AssignmentExpr / Postfix / Expression)? _ ")" _ body:Statement {
    return "For[" + (init||"") + ", " + (cond||"True") + ", " + (update||"") + ", \n" + body + "\n];";
  }

ReturnStmt 
  = "return" _ expr:Expression? _ ";" { 
    return "Return[" + (expr||"") + "];"; 
  }

/* ===================================================== */
/* Assignments                                           */
/* ===================================================== */
AssignmentStmt 
  = e:AssignmentExpr _ ";" { return e + ";"; }

AssignmentExpr 
  = lhs:Assignable _ op:AssignOp _ rhs:Expression { 
    return lhs + " " + op + " " + rhs; 
  }

AssignOp 
  = "+=" / "-=" / "*=" / "/=" / "="

/* ===================================================== */
/* Expressions                                           */
/* ===================================================== */
Expression = Ternary

Ternary 
  = cond:LogicalOr _ "?" _ t:Expression _ ":" _ f:Expression { 
    return "If[" + cond + ", " + t + ", " + f + "]"; 
  } 
  / LogicalOr

LogicalOr 
  = l:LogicalAnd tail:(_ "||" _ LogicalAnd)* { return tail.reduce((a,t)=> a + " || " + t[3], l); }

LogicalAnd 
  = l:Comparison tail:(_ "&&" _ Comparison)* { return tail.reduce((a,t)=> a + " && " + t[3], l); }

Comparison 
  = l:AddSub tail:(_ CompOp _ AddSub)* { return tail.reduce((a,t)=> a + " " + t[1] + " " + t[3], l); }

CompOp 
  = "==" { return "=="; } / "!=" { return "!="; } / "<=" / ">=" / "<" / ">"

AddSub 
  = l:MulDiv tail:(_ ("+"/"-") _ MulDiv)* { return tail.reduce((a,t)=> a + " " + t[1] + " " + t[3], l); }

MulDiv 
  = l:Unary tail:(_ ("*"/"/"/"%") _ Unary)* {
    return tail.reduce((a,t) => t[1] === "%" ? "Mod[" + a + ", " + t[3] + "]" : a + " " + t[1] + " " + t[3], l);
  }

Postfix 
  = base:Primary op:("++" / "--") { 
    return base + (op === "++" ? " += 1" : " -= 1"); 
  } 
  / Primary

Unary 
  = op:("++"/"--"/"!"/"-") _ v:Unary {
    if(op === "!") return "Not[" + v + "]";
    if(op === "++") return v + " += 1";
    if(op === "--") return v + " -= 1";
    return op + v;
  } 
  / Postfix

Primary 
  = "true" { return "True"; }
  / "false" { return "False"; }
  / "(" _ e:Expression _ ")" { return "(" + e + ")"; }
  / FuncCall
  / Assignable
  / Number

FuncCall 
  = name:Identifier _ "(" _ args:ArgList? _ ")" { 
    return mapTypeConstruct(name, args); 
  }

ArgList 
  = head:Expression tail:(_ "," _ Expression)* { 
    return [head].concat(tail.map(x=>x[3])); 
  }

Assignable 
  = base:Identifier tail:(_ AccessPart)* {
    return tail.reduce((acc, t) => {
      const p = t[1];
      // Note: Mathematica lists are 1-indexed, so we add 1 to GLSL array bounds
      return p.type === "member" ? acc + '["' + p.name + '"]' : acc + "[[" + p.index + " + 1]]";
    }, base);
  }

AccessPart 
  = "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

ExprStmt 
  = expr:Expression _ ";" { return expr + ";"; }

/* ===================================================== */
/* Types & Tokens                                        */
/* ===================================================== */
Type 
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / "void" / Identifier

Identifier 
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number 
  = num:$([0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+) suffix:[fFuU]? { 
    return num; // Strips GLSL suffixes so Mathematica reads it securely
  }

/* ===================================================== */
/* Whitespace & Comments                                 */
/* ===================================================== */
_  = ([ \t\r\n] / Comment)*
__ = ([ \t\r\n] / Comment)+

Comment 
  = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"
