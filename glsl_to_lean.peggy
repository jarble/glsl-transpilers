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

  const builtinVars = {
    "gl_Position": true, "gl_FragColor": true, "gl_FragCoord": true,
    "gl_FrontFacing": true, "gl_PointSize": true, "gl_VertexID": true,
    "gl_InstanceID": true
  };

  function mapType(glslType) {
    if (!glslType || glslType === "void") return "Unit";
    return typeMap[glslType] || mapVariable(glslType);
  }

  // Prepends "compiled_" to user-defined functions/variables while ignoring built-ins
  function mapVariable(name) {
    if (!name) return name;
    if (builtinVars[name] || typeMap[name] || name === "Unit") return name;
    return "compiled_" + name;
  }

  function getDefault(leanType) {
      if (leanType === "Bool") return "false";
      if (leanType === "Int") return "0";
      if (leanType === "Float") return "0.0";
      if (leanType.startsWith("Array")) return "#[]";
      if (leanType === "Unit") return "()";
      return `default`; 
  }

  // Translates GLSL built-in functions to Lean equivalents
  function mapFuncCall(name, args) {
      args = args || [];
      const a = args[0] || "";
      const b = args[1] || "";
      const argStr = args.join(" ");

      switch(name) {
          case "sin": return `Float.sin ${a}`;
          case "cos": return `Float.cos ${a}`;
          case "tan": return `Float.tan ${a}`;
          case "asin": return `Float.asin ${a}`;
          case "acos": return `Float.acos ${a}`;
          case "atan": return args.length === 2 ? `Float.atan2 ${a} ${b}` : `Float.atan ${a}`;
          case "pow": return `Float.pow ${a} ${b}`;
          case "exp": return `Float.exp ${a}`;
          case "log": return `Float.log ${a}`;
          case "sqrt": return `Float.sqrt ${a}`;
          case "abs": return `Float.abs ${a}`;
          case "floor": return `Float.floor ${a}`;
          case "ceil": return `Float.ceil ${a}`;
          case "min": return `min ${a} ${b}`;
          case "max": return `max ${a} ${b}`;
          case "float": return `(${a}).toFloat`;
          case "int": return `(${a}).toInt`;
          case "length": return `VectorMath.length ${a}`;
          case "normalize": return `VectorMath.normalize ${a}`;
          case "dot": return `VectorMath.dot ${a} ${b}`;
          case "cross": return `VectorMath.cross ${a} ${b}`;
          case "mix": return `VectorMath.lerp ${a} ${b} ${args[2]}`;
          case "step": return `VectorMath.step ${a} ${b}`;
          case "smoothstep": return `VectorMath.smoothStep ${a} ${b} ${args[2]}`;
          default: return `(${mapVariable(name)} ${argStr})`;
      }
  }
}

/* ---------------------------------------------------- */
/* Entry Point & Comment Preserving                     */
/* ---------------------------------------------------- */

Start
  = pre:_ items:(TopLevel)* post:_ { 
      return pre + items.join("") + post; 
    }

TopLevel
  = StructDecl
  / FunctionDecl
  / GlobalVarDecl

/* ---------------------------------------------------- */
/* Structs (Anonymous Support) & Globals                */
/* ---------------------------------------------------- */

StructDecl
  = pre:_ "struct" headName:(__ Identifier)? _ "{" _ members:(StructMember)* "}" _ tailName:(Identifier)? _ ";" post:_ {
      const n1 = headName ? headName[1] : null;
      const n2 = tailName;
      const rawName = n1 || n2 || "AnonymousStruct";
      const structName = mapVariable(rawName);
      const memberList = members.join("");

      let result = `${pre}structure ${structName} where\n${memberList}`;

      // If the GLSL code provided BOTH a struct name and a trailing instance variable,
      // or just an anonymous struct with an instance, emit the variable declaration too.
      if (n2) {
          const varName = mapVariable(n2);
          result += `\ndef ${varName} : ${structName} := default`;
      }

      return result + post;
    }

StructMember
  = pre:_ type:Type __ id:Identifier isArray:(_ "[" _ Expression? _ "]")? _ ";" post:_ {
      let leanType = mapType(type);
      if (isArray) leanType = `Array ${leanType}`;
      return `${pre}  ${mapVariable(id)} : ${leanType}${post}\n`;
    }

GlobalVarDecl
  = pre:_ mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" post:_ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseLeanType = mapType(type);
      return pre + vars.map(v => {
          const leanType = v.isArray ? `Array ${baseLeanType}` : baseLeanType;
          if (v.val) return `def ${mapVariable(v.id)} : ${leanType} := ${v.val}`;
          return `def ${mapVariable(v.id)} : ${leanType} := ${getDefault(leanType)}`;
      }).join("\n") + post;
    }

/* ---------------------------------------------------- */
/* Function Declarations & Scope Wrapping               */
/* ---------------------------------------------------- */

FunctionDecl
  = pre:_ type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:FunctionBody _ "}" post:_ {
      const pList = params ? params.join(" ") : "";
      const leanType = mapType(type);
      const funcName = mapVariable(name);
      
      let leanBody = body.returnExpr;
      if (body.locals.length > 0) {
          // Bubbles up interior pre/post whitespace directly into the Let sequences
          const bindings = body.locals.map(l => `${l.pre}let ${l.id} := ${l.val};${l.post}`).join("\n  ");
          leanBody = `${bindings}\n  ${leanBody}`;
      }
      
      return `${pre}def ${funcName} (${pList}) : ${leanType} :=\n  ${leanBody}${post}`;
    }

ParamList
  = head:ParamDecl tail:(_ "," _ ParamDecl)* {
      return [head].concat(tail.map(t => t[3]));
    }

ParamDecl
  = pre:_ mods:(VarModifier)* type:Type __ id:Identifier post:_ {
      return `${pre}(${mapVariable(id)} : ${mapType(type)})${post}`;
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
              returnExpr = stmt.pre + stmt.expr + stmt.post;
          } else if (stmt.type === "If") {
              let tRet = stmt.trueBlock.returnExpr;
              let fRet = stmt.falseBlock ? stmt.falseBlock.returnExpr : returnExpr;
              if (tRet !== "()") returnExpr = `${stmt.pre}if ${stmt.cond} then ${tRet} else ${fRet}${stmt.post}`;
          }
      });
      
      return { locals, returnExpr };
    }

Statement
  = LocalVarDecl
  / AssignmentStmt
  / IfStmt
  / ReturnStmt
  / ExprStmt

ExprStmt
  = pre:_ expr:Expression _ ";" post:_ {
      return { type: "Expr", val: expr, pre: pre, post: post };
  }

IfStmt
  = pre:_ "if" _ "(" _ cond:Expression _ ")" _ "{" _ trueBlock:FunctionBody "}" _ falseBlock:("else" _ "{" _ FunctionBody "}")? post:_ {
      return {
         type: "If",
         cond: cond,
         trueBlock: trueBlock,
         falseBlock: falseBlock ? falseBlock[4] : null,
         pre: pre,
         post: post
      };
  }

LocalVarDecl
  = pre:_ mods:(VarModifier)* type:Type __ head:VarInit tail:(_ "," _ VarInit)* _ ";" post:_ {
      const vars = [head, ...tail.map(t => t[3])];
      const baseLeanType = mapType(type);
      return vars.map((v, i) => {
          const leanType = v.isArray ? `Array ${baseLeanType}` : baseLeanType;
          let defaultVal = getDefault(leanType);
          // Attach pre to the first var, post to the last, empty string to others for formatting stability
          return { type: "LocalVar", id: mapVariable(v.id), val: v.val || defaultVal, pre: i === 0 ? pre : "", post: i === vars.length -1 ? post : "" };
      });
    }

VarInit
  = id:Identifier isArray:(_ "[" _ Expression? _ "]")? val:(_ "=" _ Expression)? {
      return { id: id, isArray: !!isArray, val: val ? val[3] : null };
    }

AssignmentStmt
  = pre:_ target:LeftHandSide _ "=" _ expr:Expression _ ";" post:_ {
      return [{ type: "LocalVar", id: target, val: expr, pre: pre, post: post }];
    }

LeftHandSide
  = id:Identifier "." prop:Identifier { return `${mapVariable(id)}_${prop}`; } 
  / id:Identifier { return mapVariable(id); }

ReturnStmt
  = pre:_ "return" __ expr:Expression? _ ";" post:_ {
      return { type: "Return", expr: expr || "()", pre: pre, post: post };
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
  / id:Identifier { return mapVariable(id); }

// Parses float[3](...) or vec2[](...) into Lean Array literals
ArrayConstructor
  = type:Type _ "[" _ Expression? _ "]" _ "(" _ args:ArgList? _ ")" {
      const argStr = args ? args.join(", ") : "";
      return `#[${argStr}]`;
  }

FunctionCall
  = name:Identifier _ "(" _ args:ArgList? _ ")" {
      return mapFuncCall(name, args);
    }

ArgList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head].concat(tail.map(t => t[3]));
    }

/* ---------------------------------------------------- */
/* Lexical Tokens, Whitespace & Comment Extraction      */
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
  = ws:(WhiteSpace / MultiLineComment / SingleLineComment)* { return ws.join(""); }

__ "mandatory whitespace"
  = ws:(WhiteSpace / MultiLineComment / SingleLineComment)+ { return ws.join(""); }

WhiteSpace
  = ws:[ \t\n\r] { return ws; }

SingleLineComment
  = c:$("//" (![\n\r] .)*) { return c; }

MultiLineComment
  = c:$("/*" (!"*/" .)* "*/") { return c; }
