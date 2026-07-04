{
  const typeMap = {
    float: "Float",
    int: "Int",
    uint: "Int",
    bool: "Boolean",
    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",
    mat2: "Matrix2",
    mat3: "Matrix3",
    mat4: "Matrix4",
    void: "Unit"
  };

  const builtinMap = {
    abs: "math.abs",
    acos: "math.acos",
    asin: "math.asin",
    atan: "math.atan",
    ceil: "math.ceil",
    cos: "math.cos",
    exp: "math.exp",
    floor: "math.floor",
    log: "math.log",
    max: "math.max",
    min: "math.min",
    pow: "math.pow",
    sin: "math.sin",
    sqrt: "math.sqrt",
    tan: "math.tan",
    round: "math.round",
    // Assuming a standard VectorMath object for vector operations
    length: "VectorMath.length",
    normalize: "VectorMath.normalize",
    dot: "VectorMath.dot",
    cross: "VectorMath.cross",
    mix: "VectorMath.mix",
    clamp: "VectorMath.clamp",
    step: "VectorMath.step",
    smoothstep: "VectorMath.smoothstep"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  function mapFunc(f){
    return builtinMap[f] || f;
  }

  function emitComment(c){
    return c + "\n";
  }
}

/* ===================================================== */
/* entry                                                 */
/* ===================================================== */
Start
  = _ items:(TopLevel (_ TopLevel)*)? _
  {
    return items
      ? [items[0]].concat(items[1].map(x=>x[1])).join("\n")
      : "";
  }

/* ===================================================== */
/* top level                                             */
/* ===================================================== */
TopLevel
  = CommentStmt
  / StructDecl
  / GlobalDecl
  / FunctionDecl
  / Statement

Statement
  = CommentStmt
  / VarDecl
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / ExprStmt
  / Block

/* ===================================================== */
/* comments                                              */
/* ===================================================== */
CommentStmt
  = c:Comment { return emitComment(c); }

Comment
  = SingleLineComment
  / MultiLineComment

SingleLineComment
  = $("//" [^\r\n]*)

MultiLineComment
  = $("/*" (!"*/" .)* "*/")

/* ===================================================== */
/* structs                                               */
/* ===================================================== */
StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:(StructField (_ StructField)*)? _ "}" _ ";"?
  {
    const fs = fields
      ? [fields[0]].concat(fields[1].map(x=>x[1]))
      : [];
    return `class ${name} {\n  ${fs.join("\n  ")}\n}`;
  }

StructField
  = t:Type __ id:Identifier _ ";"
  {
    return `var ${id}: ${mapType(t)} = _`;
  }

/* ===================================================== */
/* globals                                               */
/* ===================================================== */
GlobalDecl
  = qual:StorageQualifier? _ t:Type __ id:Identifier arr:ArraySuffix? _ init:("=" _ e:Expression { return e; })? _ ";"
  {
    const ty = arr ? `Array[${mapType(t)}]` : mapType(t);
    return `var ${id}: ${ty}${init ? " = " + init : " = _"}`;
  }

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

/* ===================================================== */
/* variables                                             */
/* ===================================================== */
Declarator
  = id:Identifier arr:ArraySuffix? _ init:("=" _ e:Expression { return e; })?
  {
    return { id, arr, init };
  }

VarDecl
  = t:Type __ head:Declarator tail:(_ "," _ Declarator)* _ ";"
  {
    const decls = [head].concat(tail.map(x => x[3]));
    const ty = mapType(t);
    return decls.map(d => {
      const dtype = d.arr ? `Array[${ty}]` : ty;
      return `var ${d.id}: ${dtype}${d.init ? " = " + d.init : " = _"}`;
    }).join("\n");
  }

/* ===================================================== */
/* functions                                             */
/* ===================================================== */
FunctionDecl
  = ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block
  {
    return `def ${name}(${params ? params.join(", ") : ""}): ${mapType(ret)} = ${body}`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

Param
  = qual:(ParameterQualifier __)? t:Type __ id:Identifier
  {
    return `${id}: ${mapType(t)}`;
  }

ParameterQualifier
  = "inout" / "in" / "out"

/* ===================================================== */
/* blocks                                                */
/* ===================================================== */
Block
  = "{" _ stmts:(Statement (_ Statement)*)? _ "}"
  {
    const s = stmts
      ? [stmts[0]].concat(stmts[1].map(x=>x[1]))
      : [];
    return "{\n" + s.join("\n") + "\n}";
  }

/* ===================================================== */
/* control flow                                          */
/* ===================================================== */
IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ thenStmt:Statement elsePart:(_ "else" _ elseStmt:Statement { return elseStmt; })?
  {
    return `if (${cond}) ${thenStmt}${elsePart ? " else " + elsePart : ""}`;
  }

ElseClause
  = _ "else" _ x:Statement { return "else " + x; }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement
  {
    return `while (${cond}) ${body}`;
  }

DoWhileStmt
  = "do" _ body:Statement _ "while" _ "(" _ cond:Expression _ ")" _ ";"
  {
    return `do ${body} while (${cond})`;
  }

ForStmt
  = "for" _ "(" _ init:ForInit? _ ";" _ cond:Expression? _ ";" _ update:ForUpdate? _ ")" _ body:Statement
  {
    // Translates C-style for loops to block-scoped Scala while loops
    return `{\n  ${init || ""}\n  while (${cond || "true"}) {\n    ${body}\n    ${update || ""}\n  }\n}`;
  }

ForInit
  = VarDeclInline / AssignmentExpr / Expression

ForUpdate
  = AssignmentExpr / Postfix / Expression

VarDeclInline
  = t:Type __ head:Declarator tail:(_ "," _ Declarator)*
  {
    const decls = [head].concat(tail.map(x => x[3]));
    const ty = mapType(t);
    return decls.map(d => {
      const dtype = d.arr ? `Array[${ty}]` : ty;
      return `var ${d.id}: ${dtype}${d.init ? " = " + d.init : " = _"}`;
    }).join("\n");
  }

/* ===================================================== */
/* switch                                                */
/* ===================================================== */
SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ cases:(CaseClause _)* "}"
  {
    return `${expr} match {\n${cases.map(x => x[0]).join("")}\n}`;
  }

CaseClause
  = "case" __ v:Expression ":" _ body:((Statement _)+)?
  {
    return `  case ${v} =>\n    ${body ? body.map(x => x[0]).join("    ").replace(/break;/g, "") : ""}\n`;
  }
  / "default" ":" _ body:((Statement _)+)?
  {
    return `  case _ =>\n    ${body ? body.map(x => x[0]).join("    ").replace(/break;/g, "") : ""}\n`;
  }

/* ===================================================== */
/* return / assignment                                   */
/* ===================================================== */
ReturnStmt
  = "return" _ expr:Expression? _ ";"
  {
    return `return ${expr || ""}`;
  }

AssignmentStmt
  = e:AssignmentExpr _ ";"
  { return e; }

AssignmentExpr
  = lhs:Assignable _ op:AssignOp _ rhs:Expression
  {
    return `${lhs} ${op} ${rhs}`;
  }

AssignOp
  = "+=" / "-=" / "*=" / "/=" / "="

/* ===================================================== */
/* EXPRESSIONS                                           */
/* ===================================================== */
Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ ifTrue:Expression _ ":" _ ifFalse:Expression
  {
    return `if (${cond}) ${ifTrue} else ${ifFalse}`;
  }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(_ "||" _ LogicalAnd)*
  {
    return tail.reduce((a,t) => `${a} || ${t[3]}`, l);
  }

LogicalAnd
  = l:Comparison tail:(_ "&&" _ Comparison)*
  {
    return tail.reduce((a,t) => `${a} && ${t[3]}`, l);
  }

Comparison
  = l:AddSub tail:(_ CompOp _ AddSub)*
  {
    return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l);
  }

CompOp
  = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(_ ("+"/"-") _ MulDiv)*
  {
    return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l);
  }

MulDiv
  = l:Unary tail:(_ ("*" / "/" / "%") _ Unary)*
  {
    return tail.reduce((a,t) => `${a} ${t[1]} ${t[3]}`, l);
  }

Postfix
  = base:Primary op:("++" / "--")
  {
    return `${base} ${op.charAt(0)}= 1`; // Scala doesn't have ++/--, expanding to += 1
  }
  / Primary

Unary
  = op:("++" / "--") _ v:Unary
  { 
    return `${v} ${op.charAt(0)}= 1; ${v}`; // Approximate pre-increment for Scala
  }
  / "!" _ v:Unary { return `!${v}`; }
  / "-" _ v:Unary { return `-${v}`; }
  / Postfix

Primary
  = "true" { return "true"; }
  / "false" { return "false"; }
  / "(" _ e:Expression _ ")" { return `(${e})`; }
  / VectorConstructor
  / FuncCall
  / Assignable
  / Number

VectorConstructor
  = name:("vec2"/"vec3"/"vec4") _ "(" _ args:ArgList? _ ")"
  {
    return `${mapType(name)}(${args ? args.join(", ") : ""})`;
  }

FuncCall
  = name:Identifier _ "(" _ args:ArgList? _ ")"
  {
    return `${mapFunc(name)}(${args ? args.join(", ") : ""})`;
  }

ArgList
  = head:Expression tail:(_ "," _ Expression)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

/* ===================================================== */
/* assignables                                           */
/* ===================================================== */
Assignable
  = base:Identifier tail:(_ AccessPart)*
  {
    return tail.reduce((acc,t) => {
      const p = t[1];
      return p.type === "member"
        ? `${acc}.${p.name}`
        : `${acc}(${p.index})`; // Scala uses parentheses for array indexing
    }, base);
  }

AccessPart
  = "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

ExprStmt
  = expr:Expression _ ";"
  { return expr; }

/* ===================================================== */
/* types                                                 */
/* ===================================================== */
Type
  = BaseType

BaseType
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "void" / Identifier

ArraySuffix
  = "[" _ "]"

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $(
      (
        [0-9]+ "." [0-9]*
      / "." [0-9]+
      / [0-9]+
      )
      ([eE] [+\-]? [0-9]+)?
      [fFuU]?
    )

/* ===================================================== */
/* whitespace                                            */
/* ===================================================== */
_
  = ( [ \t\r\n] / Comment )*

__
  = ( [ \t\r\n] / Comment )+
