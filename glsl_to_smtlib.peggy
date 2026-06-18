{
  const typeMap = {
    "int": "Int",
    "float": "Real",
    "bool": "Bool",
    "vec2": "(Array Int Real)",
    "vec3": "(Array Int Real)",
    "vec4": "(Array Int Real)",
    "ivec2": "(Array Int Int)",
    "ivec3": "(Array Int Int)",
    "ivec4": "(Array Int Int)",
    "bvec2": "(Array Int Bool)",
    "bvec3": "(Array Int Bool)",
    "bvec4": "(Array Int Bool)",
    "mat2": "(Array Int (Array Int Real))",
    "mat3": "(Array Int (Array Int Real))",
    "mat4": "(Array Int (Array Int Real))"
  };

  function mapType(glslType) {
    if (!glslType || glslType === "void") return "()";
    return typeMap[glslType] || glslType;
  }

  function getDefault(smtType) {
      if (smtType === "Bool") return "false";
      if (smtType === "Int") return "0";
      if (smtType === "Real") return "0.0";
      
      const prefix = "(Array Int ";
      if (smtType.startsWith(prefix)) {
          const innerType = smtType.slice(prefix.length, -1);
          return `((as const ${smtType}) ${getDefault(innerType)})`;
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
  / TypelessGlobalConst
  / GlobalVarDecl

/* ---------------------------------------------------- */
/* Structs & Globals                                    */
/* ---------------------------------------------------- */

StructDecl
  = "struct" __ name:Identifier _ "{" _ members:(StructMember)* "}" _ ";" _ {
      const memberList = members.join(" ");
      return `(declare-datatypes ((${name} 0)) (((${name} ${memberList}))))`;
    }

StructMember
  = type:Type __ id:Identifier isArray:(_ "[" _ Expression? _ "]")? _ ";" _ {
      let smtType = mapType(type);
      if (isArray) smtType = `(Array Int ${smtType})`;
      return `(${id} ${smtType})`;
    }

TypelessGlobalConst
  = "const" __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const smtType = "Real"; 
      return vars.map(v => {
          if (v.val) return `(declare-const ${v.id} ${smtType})\n(assert (= ${v.id} ${v.val}))`;
          return `(declare-const ${v.id} ${smtType})`;
      }).join("\n");
    }

GlobalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseSmtType = mapType(type);
      return vars.map(v => {
          const smtType = v.isArray ? `(Array Int ${baseSmtType})` : baseSmtType;
          if (v.val) return `(declare-const ${v.id} ${smtType})\n(assert (= ${v.id} ${v.val}))`;
          return `(declare-const ${v.id} ${smtType})`;
      }).join("\n");
    }

/* ---------------------------------------------------- */
/* Function Declarations & Scope Wrapping               */
/* ---------------------------------------------------- */

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:FunctionBody _ "}" {
      const pList = params ? params.join(" ") : "";
      const smtType = mapType(type);
      
      let smtBody = body.returnExpr;
      if (body.locals.length > 0) {
          const bindings = body.locals.map(l => `(${l.id} ${l.val})`).join(" ");
          smtBody = `(let (${bindings})\n    ${smtBody})`;
      }
      
      return `(define-fun ${name} (${pList}) ${smtType}\n  ${smtBody}\n)`;
    }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return [head].concat(tail.map(t => t[3]));
    }

ParamDecl
  = mods:(VarModifier)* type:Type __ id:Identifier {
      return `(${id} ${mapType(type)})`;
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
              if (tRet !== "()") returnExpr = `(ite ${stmt.cond} ${tRet} ${fRet})`;
          }
      });
      
      return { locals, returnExpr };
    }

Statement
  = TypelessConstDecl
  / LocalVarDecl
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

TypelessConstDecl
  = "const" __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const smtType = "Real";
      return vars.map(v => {
          let defaultVal = getDefault(smtType);
          return { type: "LocalVar", id: v.id, val: v.val || defaultVal };
      });
    }

LocalVarDecl
  = mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" _ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseSmtType = mapType(type);
      return vars.map(v => {
          const smtType = v.isArray ? `(Array Int ${baseSmtType})` : baseSmtType;
          let defaultVal = getDefault(smtType);
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
  = TernaryExpr

TernaryExpr
  = cond:BinaryExpr _ "?" _ trueExpr:TernaryExpr _ ":" _ falseExpr:TernaryExpr {
      return `(ite ${cond} ${trueExpr} ${falseExpr})`;
  }
  / BinaryExpr

BinaryExpr
  = left:UnaryExpr tail:(_ ("&&" / "||" / "==" / "!=" / "<=" / ">=" / "<" / ">" / "+" / "-" / "*" / "/") _ UnaryExpr)* {
      return tail.reduce((result, element) => {
        let op = element[1];
        if (op === "==") op = "="; 
        if (op === "!=") return `(not (= ${result} ${element[3]}))`;
        if (op === "&&") op = "and";
        if (op === "||") op = "or";
        return `(${op} ${result} ${element[3]})`;
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
          if (element.type === "index") return `(select ${result} ${element.val})`;
          if (element.type === "prop") {
              const p = element.val;
              if (p === "x" || p === "r") return `(select ${result} 0)`;
              if (p === "y" || p === "g") return `(select ${result} 1)`;
              if (p === "z" || p === "b") return `(select ${result} 2)`;
              if (p === "w" || p === "a") return `(select ${result} 3)`;
              return `${result}_${p}`;
          }
      }, head);
  }

PrimaryExpr
  = ArrayConstructor
  / FunctionCall
  / "(" _ expr:Expression _ ")" { return expr; }
  / Number
  / Identifier

ArrayConstructor
  = type:Type _ "[" _ Expression? _ "]" _ "(" _ args:ArgList? _ ")" {
      const smtType = mapType(type);
      const arrayType = `(Array Int ${smtType})`;
      
      let result = `((as const ${arrayType}) ${getDefault(smtType)})`;
      
      if (args) {
          args.forEach((arg, i) => {
              result = `(store ${result} ${i} ${arg})`;
          });
      }
      return result;
  }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(" ") : "";
      if (name === "float") return `(to_real ${argStr})`;
      if (name === "int") return `(to_int ${argStr})`;
      
      if (args) {
          // Absolute Value & Sign
          if (name === "abs" && args.length === 1) {
              return `(abs ${args[0]})`;
          }
          if (name === "sign" && args.length === 1) {
              return `(ite (> ${args[0]} 0.0) 1.0 (ite (< ${args[0]} 0.0) -1.0 0.0))`;
          }

          // Min, Max, Clamp
          if (name === "min" && args.length === 2) {
              return `(ite (< ${args[0]} ${args[1]}) ${args[0]} ${args[1]})`;
          }
          if (name === "max" && args.length === 2) {
              return `(ite (> ${args[0]} ${args[1]}) ${args[0]} ${args[1]})`;
          }
          if (name === "clamp" && args.length === 3) {
              return `(ite (< ${args[0]} ${args[1]}) ${args[1]} (ite (> ${args[0]} ${args[2]}) ${args[2]} ${args[0]}))`;
          }

          // Rounding, Modulo, Fractionals
          if (name === "floor" && args.length === 1) {
              return `(to_real (to_int ${args[0]}))`;
          }
          if (name === "ceil" && args.length === 1) {
              return `(- (to_real (to_int (- ${args[0]}))))`;
          }
          if (name === "trunc" && args.length === 1) {
              return `(ite (< ${args[0]} 0.0) (- (to_real (to_int (- ${args[0]})))) (to_real (to_int ${args[0]})))`;
          }
          if (name === "fract" && args.length === 1) {
              return `(- ${args[0]} (to_real (to_int ${args[0]})))`;
          }
          if (name === "mod" && args.length === 2) {
              return `(- ${args[0]} (* ${args[1]} (to_real (to_int (/ ${args[0]} ${args[1]})))))`;
          }

          // Interpolation & Steps
          if (name === "mix" && args.length === 3) {
              return `(+ (* ${args[0]} (- 1.0 ${args[2]})) (* ${args[1]} ${args[2]}))`;
          }
          if (name === "step" && args.length === 2) {
              return `(ite (< ${args[1]} ${args[0]}) 0.0 1.0)`;
          }
          if (name === "smoothstep" && args.length === 3) {
              // t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
              const tRaw = `(/ (- ${args[2]} ${args[0]}) (- ${args[1]} ${args[0]}))`;
              const t = `(ite (< ${tRaw} 0.0) 0.0 (ite (> ${tRaw} 1.0) 1.0 ${tRaw}))`;
              // return t * t * (3.0 - 2.0 * t)
              return `(* (* ${t} ${t}) (- 3.0 (* 2.0 ${t})))`;
          }

          // Fused Multiply-Add
          if (name === "fma" && args.length === 3) {
              return `(+ (* ${args[0]} ${args[1]}) ${args[2]})`;
          }
      }
      
      // Fallback for native SMT-LIB supported math (e.g. sqrt) or undefined functions
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
