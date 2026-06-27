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
}

/* ===================================================== 
  Entry & Top Level 
===================================================== 
*/

Start
  = _ items:(TopLevel (_ TopLevel)*)? _ {
      if (!items) return "";
      return [items[0]].concat(items[1].map(t => t[1])).join("\n\n");
    }

TopLevel
  = FunctionDecl
  / VarDeclStatement

/* ===================================================== 
  Functions 
===================================================== 
*/

FunctionDecl
  = type:BaseType __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:Statements _ "}" {
      const mappedType = mapType(type);
      const retStr = mappedType !== "void" ? " -> " + mappedType : "";
      const paramStr = params ? params.join(", ") : "";
      
      // WGSL uses: fn name(param: type) -> return_type { ... }
      return "fn compiled_" + name + "(" + paramStr + ")" + retStr + " {\n" + body + "\n}";
    }

ParamList
  = head:Param tail:(_ "," _ Param)* {
      return [head].concat(tail.map(t => t[3]));
    }

Param
  = type:BaseType __ name:Identifier {
      return "compiled_" + name + ": " + mapType(type);
    }

/* ===================================================== 
  Statements & Declarations 
===================================================== 
*/

Statements
  = stmts:(Statement _)* {
      return stmts.map(s => s[0]).join("\n");
    }

Statement
  = VarDeclStatement
  / ExprStmt
  / ReturnStmt

VarDeclStatement
  = type:BaseType __ head:SingleVarDecl tail:(_ "," _ SingleVarDecl)* _ ";" {
      const mappedType = mapType(type);
      let decls = [head];
      
      if (tail && tail.length > 0) {
        decls = decls.concat(tail.map(t => t[3]));
      }

      return decls.map(decl => {
        let finalType = mappedType;
        
        // If an array size was found, wrap the mapped WGSL type
        if (decl.size) {
            finalType = "array<" + mappedType + ", " + decl.size + ">";
        }
        
        // Injects the compiled_ prefix and formats the WGSL variable declaration
        return "var compiled_" + decl.name + ": " + finalType + " = " + decl.init + ";";
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

ExprStmt
  = expr:Expression _ ";" { return expr + ";"; }

ReturnStmt
  = "return" __ expr:Expression _ ";" { return "return " + expr + ";"; }

/* ===================================================== 
  Expressions & Operations 
===================================================== 
*/

Expression
  = ConditionalExpression

ConditionalExpression
  = cond:LogicalOrExpression _ "?" _ trueExpr:Expression _ ":" _ falseExpr:ConditionalExpression {
      // Maps (cond ? true : false) -> select(false, true, cond)
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
  = head:PrimaryExpression tail:(_ ("*" / "/") _ PrimaryExpression)* {
      return tail.reduce((result, element) => result + " " + element[1] + " " + element[3], head);
    }

PrimaryExpression
  = ArrayConstructor
  / FunctionCall
  / FloatLiteral
  / Number
  / Identifier { return "compiled_" + text(); }
  / "(" _ expr:Expression _ ")" { return "(" + expr + ")"; }

/* ===================================================== 
  Constructors & Calls
===================================================== 
*/

ArrayConstructor
  = type:BaseType _ "[" _ size:Number _ "]" _ "(" _ args:ArgList? _ ")" {
      const mappedType = mapType(type);
      const argStr = args ? args.join(", ") : "";
      
      // Formats as array<f32, 3>(1.0f, 2.0f, 3.0f)
      return "array<" + mappedType + ", " + size + ">(" + argStr + ")";
    }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(", ") : "";
      
      // Prevent double prefixing on WGSL built-ins we map directly
      if (name === "select" || name === "array") {
          return name + "(" + argStr + ")"; 
      }
      return "compiled_" + name + "(" + argStr + ")";
    }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head].concat(tail.map(t => t[3]));
    }

/* ===================================================== 
  Lexical Rules 
===================================================== 
*/

BaseType
  = "float" / "int" / "uint" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / "void"

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

FloatLiteral
  = num:$( ( [0-9]+ "." [0-9]* / "." [0-9]+ ) ([eE] [+-]? [0-9]+)? ) suffix:[fF]? {
      // WGSL requires trailing 'f' for f32 literals
      return num + "f";
    }

Number
  = $([0-9]+)

_ "optional whitespace"
  = [ \t\n\r]*

__ "mandatory whitespace"
  = [ \t\n\r]+
