{
  const typeMap = {
    "int": "Int",
    "float": "Float",
    "bool": "Bool",
    "vec2": "Array Float",
    "vec3": "Array Float",
    "vec4": "Array Float",
    "ivec2": "Array Int",
    "ivec3": "Array Int",
    "ivec4": "Array Int",
    "bvec2": "Array Bool",
    "bvec3": "Array Bool",
    "bvec4": "Array Bool",
    "mat2": "Array (Array Float)",
    "mat3": "Array (Array Float)",
    "mat4": "Array (Array Float)"
  };

  function mapType(glslType) {
    if (!glslType || glslType === "void") return "Unit";
    return typeMap[glslType] || glslType;
  }

  // Generates Lean default values for types
  function getDefault(leanType) {
      if (leanType === "Bool") return "false";
      if (leanType === "Int") return "0";
      if (leanType === "Float") return "0.0";
      if (leanType.startsWith("Array")) return "#[]";
      return "0";
  }
}

/* ---------------------------------------------------- */
/* Entry Point                                          */
/* ---------------------------------------------------- */

Start
  = _ items:(TopLevel)* _ { 
      return items.join("\n\n"); 
    }

TopLevel
  = StructDecl
  / FunctionDecl
  / GlobalVarDecl

/* ---------------------------------------------------- */
/* Structs & Globals                                    */
/* ---------------------------------------------------- */

StructDecl
  = "struct" __ name:Identifier _ "{" _ members:(StructMember)* "}" _ ";" _ {
      const memberList = members.join("\n  ");
      return `structure ${name} where\n  ${memberList}`;
    }

StructMember
  = type:Type __ id:Identifier isArray:(_ "[" _ Expression? _ "]")? _ ";" _ {
      let leanType = mapType(type);
      if (isArray) leanType = `Array ${leanType}`;
      return `${id} : ${leanType}`;
    }

GlobalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseLeanType = mapType(type);
      return vars.map(v => {
          const leanType = v.isArray ? `Array ${baseLeanType}` : baseLeanType;
          if (v.val) return `def ${v.id} : ${leanType} := ${v.val}`;
          return `def ${v.id} : ${leanType} := ${getDefault(leanType)}`;
      }).join("\n");
    }

/* ---------------------------------------------------- */
/* Function Declarations & Scope Wrapping               */
/* ---------------------------------------------------- */

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:FunctionBody _ "}" {
      const pList = params ? params.join(" ") : "";
      const leanType = mapType(type);
      
      let leanBody = body.returnExpr;
      if (body.locals.length > 0) {
          const bindings = body.locals.map(l => `let ${l.id} := ${l.val};`).join("\n  ");
          leanBody = `${bindings}\n  ${leanBody}`;
      }
      
      return `def ${name} (${pList}) : ${leanType} :=\n  ${leanBody}`;
    }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return [head].concat(tail.map(t => t[3]));
    }

ParamDecl
  = mods:(VarModifier)* type:Type __ id:Identifier {
      return `${id} : ${mapType(type)}`;
    }

/* ---------------------------------------------------- */
/* Statements & Block Parsing                           */
/* ---------------------------------------------------- */

FunctionBody
  = stmts:(Statement)* {
      const locals = [];
      let returnExpr = "()"; 
      
      stmts.forEach(stmt => {
          if (!stmt) return;
          if (Array.isArray(stmt)) {
              stmt.forEach(s => locals.push(s));
          } else if (stmt.type === "LocalVar") {
              locals.push(stmt);
          } else if (stmt.type === "Return") {
              returnExpr = stmt.expr;
          } else if (stmt.type === "If") {
              let tRet = stmt.trueBlock.returnExpr;
              let fRet = stmt.falseBlock ? stmt.falseBlock.returnExpr : returnExpr;
              if (tRet !== "()") returnExpr = `if ${stmt.cond} then ${tRet} else ${fRet}`;
          }
      });
      
      return { locals, returnExpr };
    }

Statement
  = LocalVarDecl
  / AssignmentStmt
  / IfStmt
  / ReturnStmt

IfStmt
  = "if" _ "(" _ cond:Expression _ ")" _ "{" _ trueBlock:FunctionBody "}" _ falseBlock:("else" _ "{" _ FunctionBody "}")? _ {
      return {
         type: "If",
         cond: cond,
         trueBlock: trueBlock,
         // Fixed: The FunctionBody is at index 4, not 3
         falseBlock: falseBlock ? falseBlock[4] : null
      };
  }

LocalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseLeanType = mapType(type);
      return vars.map(v => {
          const leanType = v.isArray ? `Array ${baseLeanType}` : baseLeanType;
          let defaultVal = getDefault(leanType);
          return { type: "LocalVar", id: v.id, val: v.val || defaultVal };
      });
    }

VarInit
  = id:Identifier isArray:(_ "[" _ Expression? _ "]")? val:(_ "=" _ Expression)? {
      return { id: id, isArray: !!isArray, val: val ? val[3] : null };
    }

AssignmentStmt
  = target:LeftHandSide _ "=" _ expr:Expression _ ";" _ {
      return [{ type: "LocalVar", id: target, val: expr }];
    }

LeftHandSide
  = id:Identifier "." prop:Identifier { return `${id}_${prop}`; } 
  / Identifier

ReturnStmt
  = "return" __ expr:Expression _ ";" _ {
      return { type: "Return", expr: expr };
    }

/* ---------------------------------------------------- */
/* Expressions                                          */
/* ---------------------------------------------------- */

Expression
  = BinaryExpr

BinaryExpr
  = left:UnaryExpr tail:(_ ("&&" / "||" / "==" / "!=" / "<=" / ">=" / "<" / ">" / "+" / "-" / "*" / "/") _ UnaryExpr)* {
      return tail.reduce((result, element) => {
        let op = element[1];
        return `(${result} ${op} ${element[3]})`;
      }, left);
    }

UnaryExpr
  = "-" _ expr:PostfixExpr { return `(-${expr})`; }
  / "!" _ expr:PostfixExpr { return `(!${expr})`; }
  / PostfixExpr

PostfixExpr
  = head:PrimaryExpr tail:(
      _ "." _ prop:Identifier { return { type: "prop", val: prop }; }
    / _ "[" _ idx:Expression _ "]" { return { type: "index", val: idx }; }
  )* {
      return tail.reduce((result, element) => {
          if (element.type === "index") return `${result}[${element.val}]!`;
          if (element.type === "prop") {
              const p = element.val;
              // Map GLSL vector properties to array indices
              if (p === "x" || p === "r") return `${result}[0]!`;
              if (p === "y" || p === "g") return `${result}[1]!`;
              if (p === "z" || p === "b") return `${result}[2]!`;
              if (p === "w" || p === "a") return `${result}[3]!`;
              return `${result}.${p}`;
          }
      }, head);
  }

PrimaryExpr
  = ArrayConstructor
  / FunctionCall
  / "(" _ expr:Expression _ ")" { return `(${expr})`; }
  / Number
  / Identifier

// Parses float[3](...) or vec2[](...) into Lean Array literals
ArrayConstructor
  = type:Type _ "[" _ Expression? _ "]" _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(", ") : "";
      return `#[${argStr}]`;
  }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(" ") : "";
      if (name === "float") return `(${argStr}).toFloat`;
      if (name === "int") return `(${argStr}).toInt`;
      return `(${name} ${argStr})`;
    }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head].concat(tail.map(t => t[3]));
    }

/* ---------------------------------------------------- */
/* Lexical Tokens & Whitespace                          */
/* ---------------------------------------------------- */

Type
  = "void" / "float" / "int" / "bool" / "vec2" / "vec3" / "vec4" / "mat2" / "mat3" / "mat4" / Identifier

VarModifier
  = ("const" / "inout" / "in" / "out" / "uniform" / "varying" / "attribute") __

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $([0-9]+ "." [0-9]+ / "." [0-9]+ / [0-9]+ "." / [0-9]+)

_ "optional whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)*

__ "mandatory whitespace"
  = (WhiteSpace / MultiLineComment / SingleLineComment)+

WhiteSpace
  = [ \t\n\r]

SingleLineComment
  = "//" (![\n\r] .)*

MultiLineComment
  = "/*" (!"*/" .)* "*/"
