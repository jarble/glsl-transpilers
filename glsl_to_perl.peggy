{
  const builtinMap = {
    abs: "abs",
    acos: "POSIX::acos",
    asin: "POSIX::asin",
    atan: "atan2",
    ceil: "POSIX::ceil",
    cos: "cos",
    exp: "exp",
    floor: "POSIX::floor",
    log: "log",
    pow: "**",
    sin: "sin",
    sqrt: "sqrt",
    tan: "POSIX::tan"
  };

  // Intercepts built-in GLSL variables and prepends Perl sigils
  function mapVariable(name) {
    const builtinVars = new Set([
      "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing",
      "gl_PointSize", "gl_VertexID", "gl_InstanceID"
    ]);
    if (builtinVars.has(name)) return "$" + name;
    
    // Skip vector swizzling properties
    if (/^[xyzw]{2,4}$/.test(name)) return name;
    if (/^[rgba]{2,4}$/.test(name)) return name;
    if (/^[stpq]{2,4}$/.test(name)) return name;

    return "$compiled_" + name;
  }

  // Generates raw Perl expressions for built-in GLSL Math
  function mapFuncCall(name, args) {
    args = args || [];
    const a = args[0] || "";
    const b = args[1] || "";
    const c = args[2] || "";

    switch(name) {
      case "pow": return `(${a} ** ${b})`;
      case "mod": return `(${a} % ${b})`;
      case "fract": return `(${a} - POSIX::floor(${a}))`;
      case "mix": return `(${a} * (1.0 - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0.0 : 1.0)`;
      case "min": return `List::Util::min(${a}, ${b})`;
      case "max": return `List::Util::max(${a}, ${b})`;
      case "clamp": return `List::Util::max(${a}, List::Util::min(${b}, ${c}))`;
      default:
        if (builtinMap[name]) {
          return `${builtinMap[name]}(${args.join(", ")})`;
        }
        // Subroutine calls drop the $ prefix for the sub name itself
        return `compiled_${name}(${args.join(", ")})`;
    }
  }

  function emitComment(c) {
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
      ? "use strict;\nuse warnings;\nuse POSIX;\nuse List::Util;\n\n" + 
        [items[0]].concat(items[1].map(x=>x[1])).join("\n\n")
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
  = $("//" [^\r\n]*) { return "#" + text().substring(2); }

MultiLineComment
  = $("/*" (!"*/" .)* "*/") 

/* ===================================================== */
/* structs (Object Oriented Packages)                    */
/* ===================================================== */

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:(StructField (_ StructField)*)? _ "}" _ ";"?
  {
    const fs = fields ? [fields[0]].concat(fields[1].map(x=>x[1])) : [];
    const structName = "compiled_" + name;
    
    // Maps the struct to a Perl package with a bless constructor
    let pkg = `package ${structName};\n`;
    pkg += `sub new {\n    my $class = shift;\n    my $self = {\n`;
    pkg += fs.map(f => `        ${f} => shift`).join(",\n");
    pkg += `\n    };\n    return bless $self, $class;\n}\n1;`;
    return pkg;
  }

StructField
  = t:Type __ id:Identifier _ ";"
  {
    return id; 
  }

/* ===================================================== */
/* globals & variables                                   */
/* ===================================================== */

GlobalDecl
  = qual:StorageQualifier? _ t:Type __ id:Identifier arr:ArraySuffix? _ init:("=" _ e:Expression { return e; })? _ ";"
  {
    const mappedId = mapVariable(id);
    return "my " + mappedId + (init ? " = " + init : "") + ";";
  }

StorageQualifier
  = "uniform" / "attribute" / "varying" / "const"

Declarator
  = id:Identifier arr:ArraySuffix? _ init:("=" _ e:Expression { return e; })?
  {
    return { id: mapVariable(id), arr, init };
  }

VarDecl
  = t:Type __ head:Declarator tail:(_ "," _ Declarator)* _ ";"
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => {
      return "my " + d.id + (d.init ? " = " + d.init : "") + ";";
    }).join("\n");
  }

/* ===================================================== */
/* functions                                             */
/* ===================================================== */

FunctionDecl
  = ret:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block
  {
    const subName = "compiled_" + name;
    const paramStr = params ? `    my (${params.join(", ")}) = @_;\n` : "";
    
    // Inject param unpacking directly into the subroutine body
    const bodyContent = body.replace(/^{/, `{\n${paramStr}`);
    return `sub ${subName} ${bodyContent}`;
  }

ParamList
  = head:Param tail:(_ "," _ Param)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

Param
  = qual:(ParameterQualifier _)? t:Type __ id:Identifier
  {
    return mapVariable(id);
  }

ParameterQualifier = "inout" / "in" / "out"

/* ===================================================== */
/* blocks & control flow                                 */
/* ===================================================== */

Block
  = "{" _ stmts:(Statement (_ Statement)*)? _ "}"
  {
    const s = stmts ? [stmts[0]].concat(stmts[1].map(x=>x[1])) : [];
    return "{\n    " + s.join("\n    ") + "\n}";
  }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ thenStmt:Statement elsePart:(_ "elsif" _ ElseIfStmt / _ "else" _ Statement)?
  {
    return "if (" + cond + ") " + thenStmt + (elsePart ? " else" + (elsePart[1] === "elsif" ? "if " + elsePart[3] : " " + elsePart[3]) : "");
  }

ElseIfStmt
  = "(" _ cond:Expression _ ")" _ thenStmt:Statement elsePart:(_ "elsif" _ ElseIfStmt / _ "else" _ Statement)?
  {
     return "(" + cond + ") " + thenStmt + (elsePart ? " else" + (elsePart[1] === "elsif" ? "if " + elsePart[3] : " " + elsePart[3]) : "");
  }

WhileStmt
  = "while" _ "(" _ cond:Expression _ ")" _ body:Statement
  {
    return `while (${cond}) ${body}`;
  }

DoWhileStmt
  = "do" _ body:Statement _ "while" _ "(" _ cond:Expression _ ")" _ ";"
  {
    return `do ${body} while (${cond});`;
  }

ForStmt
  = "for" _ "(" _ init:ForInit? _ ";" _ cond:Expression? _ ";" _ update:ForUpdate? _ ")" _ body:Statement
  {
    // Refactors C-style loop into idiomatic Perl 'while' loop block
    const initStr = init ? init + "\n" : "";
    const condStr = cond ? cond : "1";
    const updateStr = update ? update + ";" : "";
    const bodyContent = body.replace(/}$/, `    ${updateStr}\n}`);
    
    return `{\n    ${initStr}while (${condStr}) ${bodyContent}\n}`;
  }

ForInit
  = VarDeclInline / AssignmentExpr / Expression

ForUpdate
  = AssignmentExpr / Postfix / Expression

VarDeclInline
  = t:Type __ head:Declarator tail:(_ "," _ Declarator)*
  {
    const decls = [head].concat(tail.map(x => x[3]));
    return decls.map(d => "my " + d.id + (d.init ? " = " + d.init : "") + ";").join(" ");
  }

/* ===================================================== */
/* assignments & expressions                             */
/* ===================================================== */

ReturnStmt
  = "return" _ expr:Expression? _ ";"
  { return "return" + (expr ? " " + expr : "") + ";"; }

AssignmentStmt
  = e:AssignmentExpr _ ";"
  { return e + ";"; }

AssignmentExpr
  = lhs:Assignable _ op:AssignOp _ rhs:Expression
  { return lhs + " " + op + " " + rhs; }

AssignOp = "+=" / "-=" / "*=" / "/=" / "="

ExprStmt
  = expr:Expression _ ";"
  { return expr + ";"; }

Expression = Ternary

Ternary
  = cond:LogicalOr _ "?" _ ifTrue:Expression _ ":" _ ifFalse:Expression
  { return `(${cond} ? ${ifTrue} : ${ifFalse})`; }
  / LogicalOr

LogicalOr
  = l:LogicalAnd tail:(_ "||" _ LogicalAnd)*
  { return tail.reduce((a,t) => a + " || " + t[3], l); }

LogicalAnd
  = l:Comparison tail:(_ "&&" _ Comparison)*
  { return tail.reduce((a,t) => a + " && " + t[3], l); }

Comparison
  = l:AddSub tail:(_ CompOp _ AddSub)*
  { return tail.reduce((a,t) => a + " " + t[1] + " " + t[3], l); }

CompOp = "==" / "!=" / "<=" / ">=" / "<" / ">"

AddSub
  = l:MulDiv tail:(_ ("+"/"-") _ MulDiv)*
  { return tail.reduce((a,t) => a + " " + t[1] + " " + t[3], l); }

MulDiv
  = l:Unary tail:(_ ("*" / "/" / "%") _ Unary)*
  { return tail.reduce((a,t) => a + " " + t[1] + " " + t[3], l); }

Unary
  = op:("++" / "--" / "!" / "-") _ v:Unary { return op + v; }
  / Postfix

Postfix
  = base:Primary op:("++" / "--")
  { return base + op; }
  / Primary

Primary
  = base:(
      "true" { return "1"; }
    / "false" { return "0"; }
    / "(" _ e:Expression _ ")" { return "(" + e + ")"; }
    / FuncCall
    / Number
    / id:Identifier { return mapVariable(id); }
  )
  tail:(_ AccessPart)*
  {
    return tail.reduce((acc, t) => {
      const p = t[1];
      return p.type === "member"
        ? acc + "->{" + p.name + "}"
        : acc + "->[" + p.index + "]";
    }, base);
  }

FuncCall
  = name:Identifier _ "(" _ args:ArgList? _ ")"
  {
    return mapFuncCall(name, args);
  }

ArgList
  = head:Expression tail:(_ "," _ Expression)*
  {
    return [head].concat(tail.map(x=>x[3]));
  }

Assignable
  = base:Identifier tail:(_ AccessPart)*
  {
    const mappedBase = mapVariable(base);
    return tail.reduce((acc,t) => {
      const p = t[1];
      return p.type === "member"
        ? acc + "->{" + p.name + "}"
        : acc + "->[" + p.index + "]";
    }, mappedBase);
  }

AccessPart
  = "." name:Identifier { return {type:"member", name}; }
  / "[" _ idx:Expression _ "]" { return {type:"index", index:idx}; }

/* ===================================================== */
/* types & tokens                                        */
/* ===================================================== */

Type = BaseType

BaseType
  = "float" / "int" / "uint" / "bool" / "void"
  / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / Identifier

ArraySuffix = "[" _ size:Expression? _ "]"

Identifier = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = num:$(
      ( [0-9]+ "." [0-9]* / "." [0-9]+ / [0-9]+ )
      ([eE] [+\-]? [0-9]+)?
  )
  suffix:([fFuU])?
  {
    return num; 
  }

/* ===================================================== */
/* whitespace                                            */
/* ===================================================== */

_  = ( [ \t\r\n] / Comment )*
__ = ( [ \t\r\n] / Comment )+
