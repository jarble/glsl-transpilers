{
const typeMap = {
 float:"f32",
 int:"i32",
 uint:"u32",
 bool:"bool",

 vec2:"Vec2",
 vec3:"Vec3",
 vec4:"Vec4",

 void:"void"
};

const builtinMap = {
 abs:"@abs",
 acos:"std.math.acos",
 asin:"std.math.asin",
 atan:"std.math.atan",
 ceil:"std.math.ceil",
 cos:"std.math.cos",
 exp:"std.math.exp",
 floor:"std.math.floor",
 log:"std.math.log",
 max:"@max",
 min:"@min",
 pow:"std.math.pow",
 sin:"std.math.sin",
 sqrt:"std.math.sqrt",
 tan:"std.math.tan",
 round:"std.math.round",

 length:"length",
 normalize:"normalize",
 dot:"dot",
 cross:"cross",
 mix:"mix",
 clamp:"clamp",
 step:"step",
 smoothstep:"smoothstep"
};

const paramQualifiersByFunction = Object.create(null);

function mapType(t){
 return typeMap[t] || t;
}

function mapArrayType(t){
 return "[]" + mapType(t);
}

function mapFunc(f){
 return builtinMap[f] || f;
}

function isPointerQualifier(q){
 return q === "out" || q === "inout";
}

function mapNumber(n){
 return n.replace(/[fFuU]$/, "");
}

function appendBeforeClosingBrace(block, line){
 const idx = block.lastIndexOf(String.fromCharCode(125));
 return idx >= 0
   ? block.slice(0, idx) + line + "\n" + block.slice(idx)
   : block + "\n" + line;
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

 return "const " + name + " = struct {\n" +
        fs.join("\n") +
        "\n};";
}

StructField
=
t:Type
__
id:Identifier
_
";"
{
 return `${id}: ${mapType(t)},`;
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
 const ty = arr ? mapArrayType(t) : mapType(t);
 const kind = qual === "const" ? "const" : "var";

 return kind + " " + id + ": " + ty + " = " + (init || "undefined") + ";";
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

 return decls.map(d => {
   const dtype =
     d.arr
     ? mapArrayType(t)
     : mapType(t);

   return "var " + d.id + ": " + dtype + " = " + (d.init || "undefined") + ";";
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
 const ps = params || [];
 paramQualifiersByFunction[name] = ps.map(p => p.qualifier);

 return "fn " + name + "(\n" +
        ps.map(p => p.code).join(", ") +
        "\n) " + mapType(ret) + "\n" +
        body;
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
 const qualifier = qual ? qual[0] : "";
 const pointer = isPointerQualifier(qualifier);
 const ty = pointer ? "*" + mapType(t) : mapType(t);
 return {
  id,
  qualifier,
  pointer,
  code: id + ": " + ty
 };
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
 return "if (" + cond + ") " +
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
 return "while (" + cond + ") " + body;
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
 return "while (true) " + appendBeforeClosingBrace(body, "if (!(" + cond + ")) break;");
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
 const whileHead = update
   ? "while (" + (cond || "true") + ") : (" + update + ") "
   : "while (" + (cond || "true") + ") ";

 return init
   ? "{\n" + init + ";\n" + whileHead + body + "\n}"
   : whileHead + body;
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

 return decls.map(d => {
   const dtype =
     d.arr
     ? mapArrayType(t)
     : mapType(t);

   return "var " + d.id + ": " + dtype + " = " + (d.init || "undefined");
 }).join("; ");
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
 return "switch (" + expr + ") {\n" +
 cases.map(x => x[0]).join("") +
 "};";
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
 return v + " => {\n" +
 (body ? body.map(x => x[0]).join("") : "") +
 "},\n";
}

/
"default"
":"
_
body:((Statement _)+)?
{
 return "else => {\n" +
 (body ? body.map(x => x[0]).join("") : "") +
 "},\n";
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
 return expr ? "return " + expr + ";" : "return;";
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
 return "if (" + cond + ") " + ifTrue + " else " + ifFalse;
}

/ LogicalOr

LogicalOr
=
l:LogicalAnd
tail:(_ "||" _ LogicalAnd)*
{
 return tail.reduce((a,t)=>a+" or "+t[3], l);
}

LogicalAnd
=
l:Comparison
tail:(_ "&&" _ Comparison)*
{
 return tail.reduce((a,t)=>a+" and "+t[3], l);
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
 return op === "++" ? base + " += 1" : base + " -= 1";
}

/
Primary

Unary
=
"++"
_ v:Unary { return v + " += 1"; }

/
"--"
_ v:Unary { return v + " -= 1"; }

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
/ ScalarConstructor
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
 return mapType(name) + "{ " + (args ? args.join(", ") : "") + " }";
}

ScalarConstructor
=
name:("float"/"int"/"uint"/"bool")
_
"("
_
args:ArgList?
_
")"
{
 const callArgs = args || [];
 return callArgs.length === 1
   ? "@as(" + mapType(name) + ", " + callArgs[0] + ")"
   : mapType(name) + "(" + callArgs.join(", ") + ")";
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
 const callArgs = args || [];
 const qualifiers = paramQualifiersByFunction[name] || [];
 const mappedArgs = callArgs.map((arg, i) => isPointerQualifier(qualifiers[i]) ? "&" + arg : arg);

 return mapFunc(name) + "(" + mappedArgs.join(", ") + ")";
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
n:$(
    (
      [0-9]+ "." [0-9]*
    / "." [0-9]+
    / [0-9]+
    )
    ([eE] [+\-]? [0-9]+)?
    [fFuU]?
)
{ return mapNumber(n); }

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
