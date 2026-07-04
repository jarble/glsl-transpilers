{
  const typeMap = {
    float: "f32",
    int: "i32",
    uint: "u32",
    bool: "bool",
    vec2: "vec2<f32>",
    vec3: "vec3<f32>",
    vec4: "vec4<f32>",
    mat2: "mat2x2<f32>",
    mat3: "mat3x3<f32>",
    mat4: "mat4x4<f32>",
    void: "void"
  };

  function mapType(t) {
    return typeMap[t] || t;
  }
  
  const builtinVars = new Set([
      "gl_Position", "gl_FragCoord", "gl_VertexIndex", "gl_InstanceIndex", "gl_FrontFacing"
  ]);

  function mapIdentifier(name) {
      if (builtinVars.has(name)) return name;
      return "compiled_" + name;
  }
}

/* ===================================================== 
  Entry & Top Level 
===================================================== */

Start
  = _ items:(TopLevel (_ TopLevel)*)? _ {
      if (!items) return "";
      return [items[0]].concat(items[1].map(t => t[1])).join("\n\n");
    }

TopLevel
  = FunctionDecl
  / StructDecl
  / VarDeclStatement

/* ===================================================== 
  Structs & Functions 
===================================================== */

StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:StructField* _ "}" _ ";" {
      return "struct " + mapIdentifier(name) + " {\n" + fields.join("\n") + "\n}";
    }

StructField
  = _ type:BaseType __ name:Identifier _ ";" {
      return "  " + name + ": " + mapType(type) + ",";
    }

FunctionDecl
  = type:BaseType __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
      const mappedType = mapType(type);
      const retStr = mappedType !== "void" ? " -> " + mappedType : "";
      const paramStr = params ? params.join(", ") : "";
      
      return "fn " + mapIdentifier(name) + "(" + paramStr + ")" + retStr + " {\n" + body + "\n}";
    }

ParamList
  = head:Param tail:(_ "," _ Param)* {
      return [head].concat(tail.map(t => t[3]));
    }

Param
  = type:BaseType __ name:Identifier {
      return mapIdentifier(name) + ": " + mapType(type);
    }

/* ===================================================== 
  Statements & Control Flow 
===================================================== */

Statements
  = stmts:(Statement _)* {
      return stmts.map(s => s[0]).join("\n");
    }

Statement
  = Block
  / IfStmt
  / ForStmt
  / SwitchStmt
  / VarDeclStatement
  / ReturnStmt
  / ExprStmt

Block
  = "{" _ stmts:Statements _ "}" { return "{\n" + stmts + "\n}"; }

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ trueBranch:Statement falseBranch:(_ "else" _ Statement)? {
      let elseStr = falseBranch ? " else " + falseBranch[3] : "";
      return "if " + cond + " " + trueBranch + elseStr;
    }

ForStmt
  = "for" _ "(" _ init:(VarDeclStatement / ExprStmt / ";") _ cond:(Expression)? _ ";" _ step:(Expression)? _ ")" _ body:Statement {
      const initStr = init === ";" ? "" : init;
      const condStr = cond ? cond : "true";
      const stepStr = step ? step + ";" : "";
      // WGSL requires 'for' to use basic block structures, or mapping to loop {}
      return initStr + "\nloop {\n  if !(" + condStr + ") { break; }\n  " + body + "\n  " + stepStr + "\n}";
    }

SwitchStmt
  = "switch" _ "(" _ expr:Expression _ ")" _ "{" _ clauses:SwitchClause* _ "}" {
    return "switch " + expr + " {\n" + clauses.join("\n") + "\n}";
  }

SwitchClause
  = pre:_ "case" __ val:Expression _ ":" _ stmts:CaseStmts {
    return pre + "case " + val + ": {\n" + stmts + pre + "}";
  }
  / pre:_ "default" _ ":" _ stmts:CaseStmts {
    return pre + "default: {\n" + stmts + pre + "}";
  }

CaseStmts
  = items:( !("case" __ / "default" _ ":" / "}") item:(Statement / _) { return item; } )* {
    function flatten(arr) {
      return Array.isArray(arr) ? arr.map(flatten).join("") : arr;
    }
    let body = flatten(items);
    return body.replace(/\bbreak\s*;/g, "");
  }

VarDeclStatement
  = type:BaseType __ head:SingleVarDecl tail:(_ "," _ SingleVarDecl)* _ ";" {
      const mappedType = mapType(type);
      let decls = [head];
      
      if (tail && tail.length > 0) {
        decls = decls.concat(tail.map(t => t[3]));
      }

      return decls.map(decl => {
        let finalType = mappedType;
        if (decl.size) {
            finalType = "array<" + mappedType + ", " + decl.size + ">";
        }
        return "var " + mapIdentifier(decl.name) + ": " + finalType + " = " + decl.init + ";";
      }).join("\n");
    }

SingleVarDecl
  = name:Identifier _ isArray:("[" _ Number _ "]")? _ "=" _ init:Expression {
      return { 
        name: name, 
        size: isArray ? isArray[2] : null, 
        init: init 
      };
    }

ReturnStmt
  = "return" __ expr:Expression _ ";" { return "return " + expr + ";"; }
  / "return" _ ";" { return "return;"; }

ExprStmt
  = expr:Expression _ ";" { return expr + ";"; }

/* ===================================================== 
  Expressions & Operations 
===================================================== */

Expression
  = AssignmentExpression

AssignmentExpression
  = left:PrimaryExpression _ op:("=" / "+=" / "-=" / "*=" / "/=") _ right:Expression {
      return left + " " + op + " " + right;
    }
  / ConditionalExpression

ConditionalExpression
  = cond:LogicalOrExpression _ "?" _ trueExpr:Expression _ ":" _ falseExpr:ConditionalExpression {
      // WGSL mapping: (cond ? true : false) -> select(false, true, cond)
      return "select(" + falseExpr + ", " + trueExpr + ", " + cond + ")";
    }
  / LogicalOrExpression

LogicalOrExpression
  = head:LogicalAndExpression tail:(_ "||" _ LogicalAndExpression)* {
      return tail.reduce((result, element) => result + " || " + element[3], head);
    }

LogicalAndExpression
  = head:EqualityExpression tail:(_ "&&" _ EqualityExpression)* {
      return tail.reduce((result, element) => result + " && " + element[3], head);
    }

EqualityExpression
  = head:RelationalExpression tail:(_ ("==" / "!=") _ RelationalExpression)* {
      return tail.reduce((result, element) => result + " " + element[1] + " " + element[3], head);
    }

RelationalExpression
  = head:AdditiveExpression tail:(_ ("<=" / ">=" / "<" / ">") _ AdditiveExpression)* {
      return tail.reduce((result, element) => result + " " + element[1] + " " + element[3], head);
    }

AdditiveExpression
  = head:MultiplicativeExpression tail:(_ ("+" / "-") _ MultiplicativeExpression)* {
      return tail.reduce((result, element) => result + " " + element[1] + " " + element[3], head);
    }

MultiplicativeExpression
  = head:PostfixExpression tail:(_ ("*" / "/") _ PostfixExpression)* {
      return tail.reduce((result, element) => result + " " + element[1] + " " + element[3], head);
    }

PostfixExpression
  = expr:PrimaryExpression _ "++" { return expr + " = " + expr + " + 1"; }
  / expr:PrimaryExpression _ "--" { return expr + " = " + expr + " - 1"; }
  / PrimaryExpression

PrimaryExpression
  = ArrayConstructor
  / FunctionCall
  / FloatLiteral
  / Number
  / Identifier { return mapIdentifier(text()); }
  / "(" _ expr:Expression _ ")" { return "(" + expr + ")"; }

/* ===================================================== 
  Constructors & Calls
===================================================== */

ArrayConstructor
  = type:BaseType _ "[" _ size:Number _ "]" _ "(" _ args:ArgList? _ ")" {
      const mappedType = mapType(type);
      const argStr = args ? args.join(", ") : "";
      return "array<" + mappedType + ", " + size + ">(" + argStr + ")";
    }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(", ") : "";
      if (name === "select" || name === "array") {
          return name + "(" + argStr + ")"; 
      }
      return mapIdentifier(name) + "(" + argStr + ")";
    }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head].concat(tail.map(t => t[3]));
    }

/* ===================================================== 
  Lexical Rules 
===================================================== */

BaseType
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / "void"

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

FloatLiteral
  = num:$( ( [0-9]+ "." [0-9]* / "." [0-9]+ ) ([eE] [+-]? [0-9]+)? ) suffix:[fF]? {
      return num + "f";
    }

Number
  = $([0-9]+)

Comment
  = "//" [^\r\n]* / "/*" (!"*/" .)* "*/"

_ "optional whitespace"
  = ([ \t\n\r] / Comment)*

__ "mandatory whitespace"
  = ([ \t\n\r] / Comment)+
