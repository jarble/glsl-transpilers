{
  // CLIPS is dynamically typed, so type mapping is mostly ignored during translation
  // but kept here to interpret GLSL constructors properly.
  const typeMap = {
    float: "float",
    int: "integer",
    uint: "integer",
    bool: "symbol",
    vec2: "multifield",
    vec3: "multifield",
    vec4: "multifield",
    mat2: "multifield",
    mat3: "multifield",
    mat4: "multifield",
    void: "void"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Intercepts GLSL functions and maps them to CLIPS prefix expressions
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `(* ${a} (/ (pi) 180.0))`;
      case "degrees": return `(* ${a} (/ 180.0 (pi)))`;
      case "sin": return `(sin ${a})`;
      case "cos": return `(cos ${a})`;
      case "tan": return `(tan ${a})`;

      // Exponential
      case "pow": return `(** ${a} ${b})`;
      case "exp": return `(exp ${a})`;
      case "log": return `(log ${a})`;
      case "sqrt": return `(sqrt ${a})`;

      // Common Math
      case "abs": return `(abs ${a})`;
      case "mod": return `(mod ${a} ${b})`;
      case "min": return `(min ${a} ${b})`;
      case "max": return `(max ${a} ${b})`;
      case "step": return `(if (< ${a} ${b}) then 0.0 else 1.0)`;

      // Unmapped functions fallback to basic LISP prefix calls
      default: return `(${name} ${args.join(" ")})`;
    }
  }

  // Converts C-style comments to CLIPS semicolon comments
  function emitComment(c){
    return ";" + c.replace(/\/\//g, "").replace(/\/\*/g, "").replace(/\*\//g, "") + "\n";
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  =
  _
  items:(TopLevel (_ TopLevel)*)?
  _
  {
    return items
    ? [items[0]].concat(items[1].map(x=>x[1])).join("\n\n")
    : "";
  }

/* ===================================================== */
/* top level */
/* ===================================================== */

TopLevel
  =
  CommentStmt
  /
  StructDecl
  /
  GlobalDecl
  /
  FunctionDecl
  /
  Statement

Statement
  =
  CommentStmt
  /
  VarDecl
  /
  AssignmentStmt
  /
  ReturnStmt
  /
  IfStmt
  /
  ForStmt
  /
  WhileStmt
  /
  DoWhileStmt
  /
  SwitchStmt
  /
  ExprStmt
  /
  Block

/* ===================================================== */
/* comments */
/* ===================================================== */

CommentStmt
  =
  c:Comment
  { return emitComment(c); }

Comment
  =
  SingleLineComment
  /
  MultiLineComment

SingleLineComment
  =
  $("//" [^\r\n]*)

MultiLineComment
  =
  $("/*" (!"*/" .)* "*/")

/* ===================================================== */
/* structs -> deftemplates */
/* ===================================================== */

StructDecl
  =
  "struct"
  headName:(__ Identifier)?
  _
  "{"
  _
  fields:(StructField (_ StructField)*)?
  _
  "}"
  _
  tailName:(Identifier)?
  _
  ";"?
  {
    const n1 = headName ? headName[1] : null;
    const n2 = tailName;
    const structName = n1 || n2 || "AnonymousStruct";

    const fs = fields
      ? [fields[0]].concat(fields[1].map(x=>x[1]))
      : [];

    let result = `(deftemplate ${structName}\n  ${fs.join("\n  ")}\n)`;

    if (n1 && n2) {
      result += `\n(defglobal ?*${n2}* = (assert (${structName})))`;
    }

    return result;
  }

StructField
  =
  t:Type
  __
  id:Identifier
  _
  ";"
  {
    return `(slot ${id})`;
  }

/* ===================================================== */
/* globals -> defglobals */
/* ===================================================== */

GlobalDecl
  =
  qual:StorageQualifier?
  _
  t:Type
  __
  id:Identifier
  arr:ArraySuffix?
  _
  init:("=" _ e:Expression { return e; })?
  _
  ";"
  {
    return `(defglobal ?*${id}* = ${init ? init : "nil"})`;
  }

StorageQualifier
  =
  "uniform"
  / "attribute"
  / "varying"
  / "const"

/* ===================================================== */
/* variables */
/* ===================================================== */

Declarator
  =
  id:Identifier
  arr:ArraySuffix?
  _
  init:(
    "="
    _
    e:Expression
    { return e; }
  )?
  {
    return {
      id,
      arr,
      init
    };
  }

VarDecl
  =
  t:Type
  __
  head:Declarator
  tail:(_ "," _ Declarator)*
  _
  ";"
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => `(bind ?${d.id} ${d.init ? d.init : "nil"})`).join("\n");
  }

/* ===================================================== */
/* functions -> deffunctions */
/* ===================================================== */

FunctionDecl
  =
  ret:Type
  __
  name:Identifier
  _
  "("
  _
  params:ParamList?
  _
  ")"
  _
  body:Block
  {
    return `(deffunction ${name} (${params ? params.join(" ") : ""})\n  ${body}\n)`;
  }

ParamList
  =
  head:Param
  tail:(_ "," _ Param)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

Param
  =
  qual:(ParameterQualifier __)?
  t:Type
  __
  id:Identifier
  {
    return `?${id}`;
  }

ParameterQualifier
  =
  "inout"
  / "in"
  / "out"

/* ===================================================== */
/* blocks */
/* ===================================================== */

Block
  =
  "{"
  _
  stmts:(Statement (_ Statement)*)?
  _
  "}"
  {
    const s = stmts
    ? [stmts[0]].concat(stmts[1].map(x=>x[1]))
    : [];

    if (s.length === 0) return "";
    if (s.length === 1) return s[0];
    return "(progn\n  " + s.join("\n  ") + "\n)";
  }

/* ===================================================== */
/* control flow */
/* ===================================================== */

IfStmt
  =
  "if"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  thenStmt:Statement
  elsePart:(_ "else" _ elseStmt:Statement { return elseStmt; })?
  {
    return `(if ${cond} then\n  ${thenStmt}\n` + (elsePart ? ` else\n  ${elsePart}` : "") + `)`;
  }

WhileStmt
  =
  "while"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  body:Statement
  {
    return `(while ${cond} do\n  ${body}\n)`;
  }

DoWhileStmt
  =
  "do"
  _
  body:Statement
  _
  "while"
  _
  "("
  _
  cond:Expression
  _
  ")"
  _
  ";"
  {
    // Emulated by ensuring the loop fires at least once
    return `(progn\n  ${body}\n  (while ${cond} do\n    ${body}\n  )\n)`;
  }

ForStmt
  =
  "for"
  _
  "("
  _
  init:ForInit?
  _
  ";"
  _
  cond:Expression?
  _
  ";"
  _
  update:ForUpdate?
  _
  ")"
  _
  body:Statement
  {
    return `(progn\n  ${init||""}\n  (while ${cond||"TRUE"} do\n    ${body}\n    ${update||""}\n  )\n)`;
  }

ForInit
  =
  VarDeclInline
  /
  AssignmentExpr
  /
  Expression

ForUpdate
  =
  AssignmentExpr
  /
  Postfix
  /
  Expression

VarDeclInline
  =
  t:Type
  __
  head:Declarator
  tail:(_ "," _ Declarator)*
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => `(bind ?${d.id} ${d.init ? d.init : "nil"})`).join("\n");
  }

/* ===================================================== */
/* switch -> mapped to nested ifs in CLIPS */
/* ===================================================== */

SwitchStmt
  =
  "switch"
  _
  "("
  _
  expr:Expression
  _
  ")"
  _
  "{"
  _
  cases:(CaseClause _)*
  "}"
  {
    // A simplified conversion using nested if statements
    let result = "";
    cases.reverse().forEach((x, i) => {
        let cc = x[0];
        if (cc.isDefault) {
            result = cc.body;
        } else {
            result = `(if (eq ${expr} ${cc.val}) then\n  ${cc.body}\n` + (result ? ` else\n  ${result}` : "") + `)`;
        }
    });
    return result || "()";
  }

CaseClause
  =
  "case"
  __
  v:Expression
  ":"
  _
  body:((Statement _)+)?
  {
    return { isDefault: false, val: v, body: (body ? body.map(x => x[0]).join("\n") : "()") };
  }
  /
  "default"
  ":"
  _
  body:((Statement _)+)?
  {
    return { isDefault: true, body: (body ? body.map(x => x[0]).join("\n") : "()") };
  }

/* ===================================================== */
/* return / assignment */
/* ===================================================== */

ReturnStmt
  =
  "return"
  _
  expr:Expression?
  _
  ";"
  {
    return "(return " + (expr||"") + ")";
  }

AssignmentStmt
  =
  e:AssignmentExpr
  _
  ";"
  { return e; }

AssignmentExpr
  =
  lhs:Assignable
  _
  op:AssignOp
  _
  rhs:Expression
  {
    if (op === "=") return `(bind ${lhs} ${rhs})`;
    // Handle +=, -=, *=, /=
    const mathOp = op.charAt(0);
    return `(bind ${lhs} (${mathOp} ${lhs} ${rhs}))`;
  }

AssignOp
  =
  "+=" / "-=" / "*=" / "/=" / "="

/* ===================================================== */
/* EXPRESSIONS - Converted to LISP Prefix */
/* ===================================================== */

Expression = Ternary

Ternary
  =
  cond:LogicalOr
  _
  "?"
  _
  ifTrue:Expression
  _
  ":"
  _
  ifFalse:Expression
  {
    return `(if ${cond} then ${ifTrue} else ${ifFalse})`;
  }
  / LogicalOr

LogicalOr
  =
  l:LogicalAnd
  tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t)=> `(or ${a} ${t[3]})`, l);
  }

LogicalAnd
  =
  l:Comparison
  tail:(_ "&&" _ Comparison)*
  {
    return tail.reduce((a,t)=> `(and ${a} ${t[3]})`, l);
  }

Comparison
  =
  l:AddSub
  tail:(_ CompOp _ AddSub)*
  {
    return tail.reduce((a,t)=> {
      let op = t[1];
      if (op === "==") op = "eq";
      if (op === "!=") op = "neq";
      return `(${op} ${a} ${t[3]})`;
    }, l);
  }

CompOp
  =
  "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  =
  l:MulDiv
  tail:(_ ("+"/"-") _ MulDiv)*
  {
    return tail.reduce((a,t)=> `(${t[1]} ${a} ${t[3]})`, l);
  }

MulDiv
  =
  l:Unary
  tail:(_ ("*" / "/" / "%") _ Unary)*
  {
    return tail.reduce((a,t)=> {
      let op = t[1] === "%" ? "mod" : t[1];
      return `(${op} ${a} ${t[3]})`;
    }, l);
  }

Postfix
  =
  base:Primary
  op:("++" / "--")
  {
    const mathOp = op === "++" ? "+" : "-";
    return `(bind ${base} (${mathOp} ${base} 1))`;
  }
  / Primary

Unary
  =
  "++" _ v:Unary { return `(bind ${v} (+ ${v} 1))`; }
  / "--" _ v:Unary { return `(bind ${v} (- ${v} 1))`; }
  / "!" _ v:Unary { return `(not ${v})`; }
  / "-" _ v:Unary { return `(- 0 ${v})`; }
  / Postfix

Primary
  =
  base:(
      "true" { return "TRUE"; }
    / "false" { return "FALSE"; }
    / "(" _ e:Expression _ ")" { return e; }
    / TypeConstructor
    / FuncCall
    / Number
    / id:Identifier { return "?" + id; }
  )
  tail:(_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const p = t[1];
      if (p.type === "member") {
         return `(send ${acc} get-${p.name})`; // Approximate slot retrieval
      }
      return `(nth$ (+ ${p.index} 1) ${acc})`; // 1-based index in CLIPS multifields
    }, base);
  }

TypeConstructor
  =
  name:("vec2"/"vec3"/"vec4"/"mat2"/"mat3"/"mat4")
  _
  "("
  _
  args:ArgList?
  _
  ")"
  {
    // GLSL Vector initializations map to CLIPS multifield arrays
    return "(create$ " + (args ? args.join(" ") : "") + ")";
  }

FuncCall
  =
  name:Identifier
  _
  "("
  _
  args:ArgList?
  _
  ")"
  {
    return mapFuncCall(name, args);
  }

ArgList
  =
  head:Expression
  tail:(_ "," _ Expression)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

/* ===================================================== */
/* assignables */
/* ===================================================== */

Assignable
  =
  base:Identifier
  tail:(_ AccessPart)*
  {
    return tail.reduce((acc,t)=>{
      const p = t[1];
      if (p.type === "member") {
         return `(send ${acc} get-${p.name})`; // Pseudo object-oriented access
      }
      return `(nth$ (+ ${p.index} 1) ${acc})`;
    }, "?" + base);
  }

AccessPart
  =
  "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

ExprStmt
  =
  expr:Expression _
  ";"
  { return expr; }

/* ===================================================== */
/* types */
/* ===================================================== */

Type = BaseType

BaseType
  =
  "float"
  / "int"
  / "uint"
  / "bool"
  / "vec2"
  / "vec3"
  / "vec4"
  / "mat2"
  / "mat3"
  / "mat4"
  / "void"
  / Identifier

ArraySuffix = "[" _ "]"

Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  =
  $(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+\-]? [0-9]+)?
      [fFuU]?
  )

/* ===================================================== */
/* whitespace */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
