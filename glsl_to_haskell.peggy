{
  const typeMap = {
    "int": "Int",
    "float": "Float",
    "bool": "Bool",
    "vec2": "[Float]",
    "vec3": "[Float]",
    "vec4": "[Float]",
    "ivec2": "[Int]",
    "ivec3": "[Int]",
    "ivec4": "[Int]",
    "bvec2": "[Bool]",
    "bvec3": "[Bool]",
    "bvec4": "[Bool]",
    "mat2": "[[Float]]",
    "mat3": "[[Float]]",
    "mat4": "[[Float]]"
  };

  function mapType(glslType) {
    if (!glslType || glslType === "void") return "()";
    return typeMap[glslType] || glslType;
  }

  // Generates Haskell default values for types
  function getDefault(hsType) {
      if (hsType === "Bool") return "False";
      if (hsType === "Int") return "0";
      if (hsType === "Float") return "0.0";
      
      if (hsType.startsWith("[")) {
          return "[]";
      }
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
      const memberList = members.join(", ");
      return `data ${name} = ${name} { ${memberList} } deriving (Show, Eq)`;
    }

StructMember
  = type:Type __ id:Identifier isArray:(_ "[" _ Expression? _ "]")? _ ";" _ {
      let hsType = mapType(type);
      if (isArray) hsType = `[${hsType}]`;
      return `${id} :: ${hsType}`;
    }

GlobalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseHsType = mapType(type);
      return vars.map(v => {
          const hsType = v.isArray ? `[${baseHsType}]` : baseHsType;
          let decl = `${v.id} :: ${hsType}`;
          if (v.val) decl += `\n${v.id} = ${v.val}`;
          return decl;
      }).join("\n");
    }

/* ---------------------------------------------------- */
/* Function Declarations & Scope Wrapping               */
/* ---------------------------------------------------- */

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:FunctionBody _ "}" {
      const pTypes = params ? params.map(p => p.type).join(" -> ") : "";
      const pNames = params ? params.map(p => p.id).join(" ") : "";
      const retType = mapType(type);
      
      const sig = params && params.length > 0 
          ? `${name} :: ${pTypes} -> ${retType}` 
          : `${name} :: ${retType}`;
      
      let hsBody = body.returnExpr;
      if (body.locals.length > 0) {
          const bindings = body.locals.map(l => `${l.id} = ${l.val}`).join("\n    ");
          hsBody = `let ${bindings}\n  in ${hsBody}`;
      }
      
      return `${sig}\n${name} ${pNames} =\n  ${hsBody}`;
    }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return [head].concat(tail.map(t => t[3]));
    }

ParamDecl
  = mods:(VarModifier)* type:Type __ id:Identifier {
      return { id: id, type: mapType(type) };
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
              if (tRet !== "()") returnExpr = `(if ${stmt.cond} then ${tRet} else ${fRet})`;
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
         falseBlock: falseBlock ? falseBlock[3] : null
      };
  }

LocalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseHsType = mapType(type);
      return vars.map(v => {
          const hsType = v.isArray ? `[${baseHsType}]` : baseHsType;
          let defaultVal = getDefault(hsType);
          return { type: "LocalVar", id: v.id, val: v.val || defaultVal };
      });
    }

// Handles optional array brackets: points[] or values[3]
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
        if (op === "!=") op = "/="; 
        return `(${result} ${op} ${element[3]})`;
      }, left);
    }

UnaryExpr
  = "-" _ expr:PostfixExpr { return `(- ${expr})`; }
  / "!" _ expr:PostfixExpr { return `(not ${expr})`; }
  / PostfixExpr

PostfixExpr
  = head:PrimaryExpr tail:(
      _ "." _ prop:Identifier { return { type: "prop", val: prop }; }
    / _ "[" _ idx:Expression _ "]" { return { type: "index", val: idx }; }
  )* {
      return tail.reduce((result, element) => {
          if (element.type === "index") return `(${result} !! ${element.val})`;
          if (element.type === "prop") {
              const p = element.val;
              if (p === "x" || p === "r") return `(${result} !! 0)`;
              if (p === "y" || p === "g") return `(${result} !! 1)`;
              if (p === "z" || p === "b") return `(${result} !! 2)`;
              if (p === "w" || p === "a") return `(${result} !! 3)`;
              return `${p} ${result}`; // Haskell record syntax assumes prop is a function
          }
      }, head);
  }

PrimaryExpr
  = ArrayConstructor
  / FunctionCall
  / "(" _ expr:Expression _ ")" { return expr; }
  / Number
  / Boolean
  / Identifier

// Parses float[3](...) or vec2[](...) into Haskell Lists
ArrayConstructor
  = type:Type _ "[" _ Expression? _ "]" _ "(" _ args:ArgList? _ ")" {
      if (args) {
          return `[${args.join(", ")}]`;
      }
      return `[]`;
  }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(" ") : "";
      if (name === "float") return `(fromIntegral ${argStr} :: Float)`;
      if (name === "int") return `(round ${argStr} :: Int)`;
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

// Consumes standard GLSL memory/access modifiers to prevent syntax crashes
VarModifier
  = ("const" / "inout" / "in" / "out" / "uniform" / "varying" / "attribute") __

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $([0-9]+ "." [0-9]+ / "." [0-9]+ / [0-9]+ "." / [0-9]+)

Boolean
  = b:("true" / "false") { return b === "true" ? "True" : "False"; }

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
