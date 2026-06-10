{
const typeMap = {
 float:"float",
 int:"int",
 uint:"int",
 bool:"boolean",

 vec2:"Vec2",
 vec3:"Vec3",
 vec4:"Vec4",

 void:"void"
};

const builtinMap = {
 abs:"Math.abs",
 acos:"Math.acos",
 asin:"Math.asin",
 atan:"Math.atan",
 ceil:"Math.ceil",
 cos:"Math.cos",
 exp:"Math.exp",
 floor:"Math.floor",
 log:"Math.log",
 max:"Math.max",
 min:"Math.min",
 pow:"Math.pow",
 sin:"Math.sin",
 sqrt:"Math.sqrt",
 tan:"Math.tan",
 round:"Math.round",

 length:"length",
 normalize:"normalize",
 dot:"dot",
 cross:"cross",
 mix:"mix",
 clamp:"clamp",
 step:"step",
 smoothstep:"smoothstep"
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
/* entry */
/* ===================================================== */

Start
=
_
items:(TopLevel (_ TopLevel)*)?
_
{
 return items
 ? [items[0]].concat(items[1].map(x=>x[1])).join("\n")
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
/* structs */
/* ===================================================== */

StructDecl
=
"struct"
__
name:Identifier
_
"{"
_
fields:(StructField (_ StructField)*)?
_
"}"
_
";"?
{
 const fs = fields
 ? [fields[0]].concat(fields[1].map(x=>x[1]))
 : [];

 return `class ${name} {
${fs.join("\n")}
}`;
}

StructField
=
t:Type
__
id:Identifier
_
";"
{
 return `${mapType(t)} ${id};`;
}

/* ===================================================== */
/* globals */
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
 const ty = arr ? mapType(t)+"[]" : mapType(t);

 return ty + " " + id + (init ? " = " + init : "") + ";";
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
 const decls =
  [head].concat(
   tail.map(x => x[3])
  );

 const ty = mapType(t);

 return decls.map(d => {
   const dtype =
     d.arr
     ? ty + "[]"
     : ty;

   return (
     dtype +
     " " +
     d.id +
     (d.init ? " = " + d.init : "") +
     ";"
   );
 }).join("\n");
}

/* ===================================================== */
/* functions */
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
 return `${mapType(ret)} ${name}(
${params ? params.join(", ") : ""}
)
${body}`;
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
 return `${mapType(t)} ${id}`;
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

 return "{\n" + s.join("\n") + "\n}";
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
 return "if(" + cond + ") " +
        thenStmt +
        (elsePart ? " else " + elsePart : "");
}

ElseClause
=
_
"else"
_
x:Statement
{
 return "else " + x;
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
 return `while(${cond}) ${body}`;
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
 return `do ${body} while(${cond});`;
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
 return "for(" + (init||"") + "; " + (cond||"") + "; " + (update||"") + ") " + body;
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
 const decls =
  [head].concat(
   tail.map(x => x[3])
  );

 const ty = mapType(t);

 return decls.map(d => {
   const dtype =
     d.arr
     ? ty + "[]"
     : ty;

   return (
     dtype +
     " " +
     d.id +
     (d.init ? " = " + d.init : "")
   );
 }).join(", ");
}

/* ===================================================== */
/* switch */
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
 return "switch(" + expr + "){\n" +
 cases.map(x => x[0]).join("") +
 "\n}";
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
 return "case " + v + ":\n" +
 (body ? body.map(x => x[0]).join("") : "");
}

/
"default"
":"
_
body:((Statement _)+)?
{
 return "default:\n" +
 (body ? body.map(x => x[0]).join("") : "");
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
 return "return " + (expr||"") + ";";
}

AssignmentStmt
=
e:AssignmentExpr
_
";"
{ return e + ";"; }

AssignmentExpr
=
lhs:Assignable
_
op:AssignOp
_
rhs:Expression
{
 return lhs + " " + op + " " + rhs;
}

AssignOp
=
"+="
/ "-="
/ "*="
/ "/="
/ "="

/* ===================================================== */
/* EXPRESSIONS */
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
 return cond + " ? " + ifTrue + " : " + ifFalse;
}

/ LogicalOr

LogicalOr
=
l:LogicalAnd
tail:(_ "||" _ LogicalAnd)*
{
 return tail.reduce((a,t)=>a+" || "+t[3], l);
}

LogicalAnd
=
l:Comparison
tail:(_ "&&" _ Comparison)*
{
 return tail.reduce((a,t)=>a+" && "+t[3], l);
}

Comparison
=
l:AddSub
tail:(_ CompOp _ AddSub)*
{
 return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
}

CompOp
=
"=="
/ "!="
/ "<="
/ ">="
/ "<"
/ ">"

AddSub
=
l:MulDiv
tail:(_ ("+"/"-") _ MulDiv)*
{
 return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
}

MulDiv
=
l:Unary
tail:(_ ("*" / "/" / "%") _ Unary)*
{
 return tail.reduce((a,t)=>a+" "+t[1]+" "+t[3], l);
}

Postfix
=
base:Primary
op:("++" / "--")
{
 return base + op;
}

/
Primary

Unary
=
"++"
_ v:Unary { return "++"+v; }

/
"--"
_ v:Unary { return "--"+v; }

/
"!"
_ v:Unary { return "!"+v; }

/
"-"
_ v:Unary { return "-"+v; }

/
Postfix

Primary
=
"true" { return "true"; }
/ "false" { return "false"; }
/ "(" _ e:Expression _ ")" { return "(" + e + ")"; }
/ VectorConstructor
/ FuncCall
/ Assignable
/ Number

VectorConstructor
=
name:("vec2"/"vec3"/"vec4")
_
"("
_
args:ArgList?
_
")"
{
 return "new " + mapType(name) + "(" + (args ? args.join(", ") : "") + ")";
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
 return mapFunc(name) + "(" + (args ? args.join(", ") : "") + ")";
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
  return p.type === "member"
   ? acc + "." + p.name
   : acc + "[" + p.index + "]";
 }, base);
}

AccessPart
=
"." name:Identifier { return {type:"member", name}; }

/
"[" _ idx:Expression _ "]"
{ return {type:"index", index:idx}; }

ExprStmt
=
expr:Expression _
";"
{ return expr + ";"; }

/* ===================================================== */
/* types */
/* ===================================================== */

Type
=
BaseType

BaseType
=
"float"
/ "int"
/ "uint"
/ "bool"
/ "vec2"
/ "vec3"
/ "vec4"
/ "void"
/ Identifier

ArraySuffix
=
"[" _ "]"

Identifier
=
$([a-zA-Z_][a-zA-Z0-9_]*)

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

_
=
(
    [ \t\r\n]
  / Comment
)*

__
=
(
    [ \t\r\n]
  / Comment
)+
