{
const typeMap = {
 float:"number",
 int:"number",
 uint:"number",
 bool:"boolean",

 vec2:"[number, number]",
 vec3:"[number, number, number]",
 vec4:"[number, number, number, number]"
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
 sign:"Math.sign",
 round:"Math.round",
 trunc:"Math.trunc",

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
 return c+"\n";
}
}

/* ===================================================== */

Start
=
_
items:(TopLevel (_ TopLevel)*)?
_
{
 const all =
 items
 ? [items[0]].concat(
     items[1].map(x=>x[1])
   )
 : [];

 return all.join("\n");
}

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
{
 return emitComment(c);
}

Comment
=
SingleLineComment
/
MultiLineComment

SingleLineComment
=
c:$("//" [^\r\n]*)
{
 return c;
}

MultiLineComment
=
c:$("/*" (!"*/" .)* "*/")
{
 return c;
}

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
 const fs =
 fields
 ? [fields[0]].concat(
     fields[1].map(x=>x[1])
   )
 : [];

 return (
`interface ${name} {
${fs.join("\n")}
}`
 );
}

StructField
=
t:Type
__
id:Identifier
_
";"
{
 return `${id}: ${mapType(t)};`;
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
init:(
 "="
 _
 e:Expression
 { return e; }
)?
_
";"
{
 const tsType =
 arr
 ? mapType(t)+"[]"
 : mapType(t);

 return (
   "let "+
   id+
   ": "+
   tsType+
   (init ? " = "+init : "")+
   ";"
 );
}

StorageQualifier
=
"uniform"
/
"attribute"
/
"varying"
/
"const"

/* ===================================================== */
/* vars */
/* ===================================================== */

VarDecl
=
t:Type
__
id:Identifier
arr:ArraySuffix?
_
init:(
 "="
 _
 e:Expression
 { return e; }
)?
_
";"
{
 const tsType =
 arr
 ? mapType(t)+"[]"
 : mapType(t);

 return (
 "let "+
 id+
 ": "+
 tsType+
 (init ? " = "+init : "")+
 ";"
 );
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
 return (
`function ${name}(
${params ? params.join(",\n") : ""}
): ${mapType(ret)}
${body}`
 );
}

ParamList
=
head:Param
tail:(_ "," _ Param)*
{
 return [head].concat(
 tail.map(x=>x[3])
 );
}

Param
=
qual:(ParameterQualifier __)?
t:Type
__
id:Identifier
{
 return `${id}: ${mapType(t)}`;
}

ParameterQualifier
=
"inout"
/
"in"
/
"out"

/* ===================================================== */

Block
=
"{"
_
stmts:(Statement (_ Statement)*)?
_
"}"
{
 const s =
 stmts
 ? [stmts[0]].concat(
     stmts[1].map(x=>x[1])
   )
 : [];

 return "{\n"+s.join("\n")+"\n}";
}

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
then:Block
elsePart:ElseClause?
{
 return (
 "if ("+
 cond+
 ") "+
 then+
 (elsePart?(" "+elsePart):"")
 );
}

ElseClause
=
_
"else"
_
x:(IfStmt / Block)
{
 return "else "+x;
}

/* ===================================================== */

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
body:Block
{
 return `while (${cond}) ${body}`;
}

DoWhileStmt
=
"do"
_
body:Block
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
 return `do ${body} while (${cond});`;
}

/* ===================================================== */
/* fixed for loops */
/* ===================================================== */

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
body:Block
{
 return (
 "for("+
 (init||"")+
 "; "+
 (cond||"")+
 "; "+
 (update||"")+
 ") "+
 body
 );
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
Expression

VarDeclInline
=
t:Type
__
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
 const tsType =
 arr
 ? mapType(t)+"[]"
 : mapType(t);

 return (
 "let "+
 id+
 ": "+
 tsType+
 (init ? " = "+init : "")
 );
}

AssignmentExpr
=
lhs:Assignable
_
op:AssignOp
_
rhs:Expression
{
 return lhs+" "+op+" "+rhs;
}

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
 return (
 "switch("+expr+"){\n"+
 cases.map(x=>x[0]).join("")+
 "\n}"
 );
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
 return (
 "case "+
 v+
 ":\n"+
 (body
 ? body.map(x=>x[0]).join("")
 : "")
 );
}

/
"default"
":"
_
body:((Statement _)+)?
{
 return (
 "default:\n"+
 (body
 ? body.map(x=>x[0]).join("")
 : "")
 );
}

/* ===================================================== */

ReturnStmt
=
"return"
_
expr:Expression?
_
";"
{
 return "return "+(expr||"")+";";
}

AssignmentStmt
=
e:AssignmentExpr
_
";"
{
 return e+";";
}

AssignOp
=
"+="
/
"-="
/
"*="
/
"/="
/
"="
/
"&="
/
"|="
/
"^="
/
"<<="
/
">>="

/* ===================================================== */
/* expressions */
/* ===================================================== */

Expression = LogicalOr

LogicalOr
=
l:LogicalAnd
tail:(_ "||" _ LogicalAnd)*
{
 return tail.reduce(
 (a,t)=>a+" || "+t[3],
 l
 );
}

LogicalAnd
=
l:Comparison
tail:(_ "&&" _ Comparison)*
{
 return tail.reduce(
 (a,t)=>a+" && "+t[3],
 l
 );
}

Comparison
=
l:AddSub
tail:(_ CompOp _ AddSub)*
{
 return tail.reduce(
 (a,t)=>a+" "+t[1]+" "+t[3],
 l
 );
}

CompOp
=
"=="
/
"!="
/
"<="
/
">="
/
"<"
/
">"

AddSub
=
l:MulDiv
tail:(_ ("+"/"-") _ MulDiv)*
{
 return tail.reduce(
 (a,t)=>a+" "+t[1]+" "+t[3],
 l
 );
}

MulDiv
=
l:Unary
tail:(_ ("*" / "/" / "%") _ Unary)*
{
 return tail.reduce(
 (a,t)=>a+" "+t[1]+" "+t[3],
 l
 );
}

Unary
=
"!"
_ v:Unary { return "!"+v; }

/
"-"
_ v:Unary { return "-"+v; }

/
Primary

/* ===================================================== */

Primary
=
"true" { return "true"; }

/
"false" { return "false"; }

/
"("
_
e:Expression
_
")"
{
 return "("+e+")";
}

/
VectorConstructor

/
FuncCall

/
Assignable

/
Number

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
 return "["+
 (args ? args.join(", ") : "")+
 "]";
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
 return (
 mapFunc(name)+
 "("+
 (args ? args.join(", ") : "")+
 ")"
 );
}

ArgList
=
head:Expression
tail:(_ "," _ Expression)*
{
 return [head].concat(
 tail.map(x=>x[3])
 );
}

/* ===================================================== */

Assignable
=
base:Identifier
tail:(_ AccessPart)*
{
 return tail.reduce(
 (acc,t)=>{
 const p=t[1];

 if(p.type==="member")
 return acc+"."+p.name;

 return acc+"["+p.index+"]";
 }, base);
}

AccessPart
=
"."
name:Identifier
{
 return {
 type:"member",
 name
 };
}

/
"["
_
idx:Expression
_
"]"
{
 return {
 type:"index",
 index:idx
 };
}

/* ===================================================== */

ExprStmt
=
expr:Expression
_
";"
{
 return expr+";";
}

/* ===================================================== */

Type
=
base:BaseType
{
 return base;
}

BaseType
=
"float"
/
"int"
/
"uint"
/
"bool"
/
"vec2"
/
"vec3"
/
"vec4"
/
"void"
/
Identifier

ArraySuffix
=
"["
_
"]"

Identifier
=
$([a-zA-Z_][a-zA-Z0-9_]*)

Number
=
$([0-9]+ ("." [0-9]+)?)

_=[ \t\r\n]*
__=[ \t\r\n]+
