{
  function getDefault(smtType) {
      if (smtType === "Bool") return "false";
      if (smtType === "Int") return "0";
      if (smtType === "Real") return "0.0";
      if (smtType === "()") return "()";
      
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
  = comments:_ items:(TopLevel)* trailing:_ { 
      return comments + items.join("\n\n") + (trailing ? "\n" + trailing : ""); 
    }

TopLevel
  = comments:_ decl:(StructDecl / FunctionDecl / TypelessGlobalConst / GlobalVarDecl) {
      return comments + decl;
    }

/* ---------------------------------------------------- */
/* Structs & Globals                                    */
/* ---------------------------------------------------- */

StructDecl
  = "struct" __ name:Identifier _ "{" members:(StructMember)* trailing:_ "}" _ ";" {
      const memberList = members.join(" ") + trailing;
      return `(declare-datatypes ((compiled_${name} 0)) (((compiled_${name} ${memberList}))))`;
    }

StructMember
  = comments:_ type:Type __ id:Identifier isArray:(_ "[" _ Expression? _ "]")? _ ";" {
      let smtType = type;
      if (isArray) smtType = `(Array Int ${smtType})`;
      return `${comments}(compiled_${id} ${smtType})`;
    }

TypelessGlobalConst
  = "const" ws1:__ head:VarInit tail:(ws2:_ "," ws3:_ VarInit)* ws4:_ ";" {
      const vars = [head, ...tail.map(t => { t[3].ws = t[0]+t[2]; return t[3]; })];
      const smtType = "Real"; 
      return vars.map((v, i) => {
          let c = (i === 0 ? ws1 : v.ws) + ws4;
          if (v.val) return `${c}(declare-const ${v.id} ${smtType})\n(assert (= ${v.id} ${v.val}))`;
          return `${c}(declare-const ${v.id} ${smtType})`;
      }).join("\n");
    }

GlobalVarDecl
  = mods:(VarModifier)* type:Type ws1:__ head:VarInit tail:(ws2:_ "," ws3:_ VarInit)* ws4:_ ";" {
      const vars = [head, ...tail.map(t => { t[3].ws = t[0]+t[2]; return t[3]; })];
      return vars.map((v, i) => {
          const smtType = v.isArray ? `(Array Int ${type})` : type;
          let c = (i === 0 ? ws1 : v.ws) + ws4;
          if (v.val) return `${c}(declare-const ${v.id} ${smtType})\n(assert (= ${v.id} ${v.val}))`;
          return `${c}(declare-const ${v.id} ${smtType})`;
      }).join("\n");
    }

/* ---------------------------------------------------- */
/* Function Declarations & Scope Wrapping               */
/* ---------------------------------------------------- */

FunctionDecl
  = type:Type __ name:Identifier _ "(" _ params:ParamList? _ ")" _ "{" _ body:FunctionBody trailing:_ "}" {
      const pList = params ? params.join(" ") : "";
      
      let smtBody = body.returnExpr + trailing;
      if (body.locals.length > 0) {
          const bindings = body.locals.map(l => `${l.comment || ""}(${l.id} ${l.val})`).join("\n    ");
          smtBody = `(let (\n    ${bindings}\n  )\n    ${smtBody})`;
      }
      
      return `(define-fun compiled_${name} (${pList}) ${type}\n  ${smtBody}\n)`;
    }

ParamList
  = head:ParamDecl tail:(ws1:_ "," ws2:_ ParamDecl)* {
      return [head].concat(tail.map(t => t[0] + t[2] + t[3]));
    }

ParamDecl
  = mods:(VarModifier)* type:Type ws:__ id:Identifier {
      return `${ws}(compiled_${id} ${type})`;
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
              returnExpr = (stmt.comment || "") + stmt.expr;
          } else if (stmt.type === "If") {
              let tRet = stmt.trueBlock.returnExpr;
              let fRet = stmt.falseBlock ? stmt.falseBlock.returnExpr : returnExpr;
              if (tRet !== "()") returnExpr = (stmt.comment || "") + `(ite ${stmt.cond} ${tRet} ${fRet})`;
              if (stmt.trueBlock.locals) locals.push(...stmt.trueBlock.locals);
              if (stmt.falseBlock && stmt.falseBlock.locals) locals.push(...stmt.falseBlock.locals);
          } else if (stmt.type === "Switch") {
              if (stmt.returnExpr !== "()") returnExpr = (stmt.comment || "") + stmt.returnExpr;
              if (stmt.locals) locals.push(...stmt.locals);
          }
      });
      
      return { locals, returnExpr };
    }

Statement
  = comments:_ stmt:(TypelessConstDecl / LocalVarDecl / AssignmentStmt / IfStmt / SwitchStmt / ReturnStmt / BreakStmt) {
      if (Array.isArray(stmt)) {
          if (stmt.length > 0) stmt[0].comment = comments + (stmt[0].comment || "");
      } else {
          stmt.comment = comments + (stmt.comment || "");
      }
      return stmt;
  }

SwitchStmt
  = "switch" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ "{" ws5:_ cases:SwitchCase* defaultCase:SwitchDefault? trailing:_ "}" {
      let result = defaultCase ? defaultCase.body.returnExpr : "()";
      let locals = [];
      if (defaultCase && defaultCase.body.locals) locals.push(...defaultCase.body.locals);
      
      for (let i = cases.length - 1; i >= 0; i--) {
          let c = cases[i];
          result = `(ite (= ${cond} ${c.val}) ${c.body.returnExpr} ${result})`;
          if (c.body.locals) locals.push(...c.body.locals);
      }
      
      return {
          type: "Switch",
          comment: ws1 + ws2 + ws3 + ws4 + ws5,
          returnExpr: result,
          locals: locals
      };
  }

SwitchCase
  = "case" ws1:__ val:Expression ws2:_ ":" ws3:_ body:FunctionBody {
      return { val: val, body: body, comment: ws1 + ws2 + ws3 };
  }

SwitchDefault
  = "default" ws1:_ ":" ws2:_ body:FunctionBody {
      return { body: body, comment: ws1 + ws2 };
  }

IfStmt
  = "if" ws1:_ "(" ws2:_ cond:Expression ws3:_ ")" ws4:_ "{" _ trueBlock:FunctionBody trailing1:_ "}" falseBlock:(ws5:_ "else" ws6:_ "{" _ FunctionBody trailing2:_ "}")? {
      if (trailing1) trueBlock.returnExpr += trailing1;
      if (falseBlock && falseBlock[7]) falseBlock[6].returnExpr += falseBlock[7];
      
      return {
         type: "If",
         comment: ws1 + ws2 + ws3 + ws4,
         cond: cond,
         trueBlock: trueBlock,
         falseBlock: falseBlock ? falseBlock[6] : null
      };
  }

BreakStmt
  = "break" ws1:_ ";" ws2:_ {
      return { type: "Break", comment: ws1 + ws2 };
  }

TypelessConstDecl
  = "const" ws1:__ head:VarInit tail:(ws2:_ "," ws3:_ VarInit)* ws4:_ ";" {
      const vars = [head, ...tail.map(t => { t[3].ws = t[0]+t[2]; return t[3]; })];
      const smtType = "Real";
      return vars.map((v, i) => {
          let defaultVal = getDefault(smtType);
          return { type: "LocalVar", id: v.id, val: v.val || defaultVal, comment: (i===0?ws1:v.ws) + ws4 };
      });
    }

LocalVarDecl
  = mods:(VarModifier)* type:Type ws1:__ head:VarInit tail:(ws2:_ "," ws3:_ VarInit)* ws4:_ ";" {
      const vars = [head, ...tail.map(t => { t[3].ws = t[0]+t[2]; return t[3]; })];
      return vars.map((v, i) => {
          const smtType = v.isArray ? `(Array Int ${type})` : type;
          let defaultVal = getDefault(smtType);
          return { type: "LocalVar", id: v.id, val: v.val || defaultVal, comment: (i===0?ws1:v.ws) + ws4 };
      });
    }

VarInit
  = id:Identifier isArray:(_ "[" _ Expression? _ "]")? val:(_ "=" _ Expression)? {
      return { id: "compiled_" + id, isArray: !!isArray, val: val ? val[3] : null };
    }

AssignmentStmt
  = target:LeftHandSide ws1:_ "=" ws2:_ expr:Expression ws3:_ ";" {
      return [{ type: "LocalVar", id: target, val: ws1 + ws2 + ws3 + expr }];
    }

LeftHandSide
  = id:Identifier "." prop:Identifier { return `compiled_${id}_${prop}`; } 
  / id:Identifier { return `compiled_${id}`; }

ReturnStmt
  = "return" ws1:__ expr:Expression ws2:_ ";" {
      return { type: "Return", expr: ws1 + ws2 + expr };
    }

/* ---------------------------------------------------- */
/* Expressions                                          */
/* ---------------------------------------------------- */

Expression
  = TernaryExpr

TernaryExpr
  = cond:BinaryExpr ws1:_ "?" ws2:_ trueExpr:TernaryExpr ws3:_ ":" ws4:_ falseExpr:TernaryExpr {
      return `${ws1}${ws2}${ws3}${ws4}(ite ${cond} ${trueExpr} ${falseExpr})`;
  }
  / BinaryExpr

BinaryExpr
  = left:UnaryExpr tail:(ws1:_ op:("&&" / "||" / "==" / "!=" / "<=" / ">=" / "<" / ">" / "+" / "-" / "*" / "/") ws2:_ right:UnaryExpr { return {op, right, ws: ws1+ws2}; })* {
      return tail.reduce((result, element) => {
        let op = element.op;
        if (op === "==") op = "="; 
        if (op === "!=") return `${element.ws}(not (= ${result} ${element.right}))`;
        if (op === "&&") op = "and";
        if (op === "||") op = "or";
        return `${element.ws}(${op} ${result} ${element.right})`;
      }, left);
    }

UnaryExpr
  = "-" ws:_ expr:PostfixExpr { return `${ws}(- ${expr})`; }
  / "!" ws:_ expr:PostfixExpr { return `${ws}(not ${expr})`; }
  / PostfixExpr

PostfixExpr
  = head:PrimaryExpr tail:(
      ws1:_ "." ws2:_ prop:Identifier { return { type: "prop", val: prop, ws: ws1+ws2 }; }
    / ws1:_ "[" ws2:_ idx:Expression ws3:_ "]" { return { type: "index", val: idx, ws: ws1+ws2+ws3 }; }
  )* {
      return tail.reduce((result, element) => {
          if (element.type === "index") return `${element.ws}(select ${result} ${element.val})`;
          if (element.type === "prop") {
              const p = element.val;
              if (p === "x" || p === "r") return `${element.ws}(select ${result} 0)`;
              if (p === "y" || p === "g") return `${element.ws}(select ${result} 1)`;
              if (p === "z" || p === "b") return `${element.ws}(select ${result} 2)`;
              if (p === "w" || p === "a") return `${element.ws}(select ${result} 3)`;
              return `${element.ws}${result}_${p}`;
          }
      }, head);
  }

PrimaryExpr
  = ArrayConstructor
  / FunctionCall
  / "(" ws1:_ expr:Expression ws2:_ ")" { return ws1 + expr + ws2; }
  / Number
  / id:Identifier { return "compiled_" + id; }

ArrayConstructor
  = type:Type ws1:_ "[" ws2:_ Expression? ws3:_ "]" ws4:_ "(" ws5:_ args:ArgList? ws6:_ ")" {
      const arrayType = `(Array Int ${type})`;
      const comments = ws1 + ws2 + ws3 + ws4 + ws5 + ws6;
      let result = `${comments}((as const ${arrayType}) ${getDefault(type)})`;
      
      if (args) {
          args.forEach((arg, i) => {
              result = `(store ${result} ${i} ${arg})`;
          });
      }
      return result;
  }

FunctionCall
  = name:Identifier ws1:_ "(" ws2:_ args:ArgList? ws3:_ ")" {
      const argStr = args ? args.join(" ") : "";
      const comments = ws1 + ws2 + ws3;
      
      if (name === "float") return `${comments}(to_real ${argStr})`;
      if (name === "int") return `${comments}(to_int ${argStr})`;
      
      const builtIns = new Set([
          "abs", "sign", "min", "max", "clamp", "floor", "ceil", "trunc",
          "fract", "mod", "mix", "step", "smoothstep", "fma"
      ]);
      
      let smtName = builtIns.has(name) ? name : `compiled_${name}`;
      
      if (args) {
          if (name === "abs" && args.length === 1) return `${comments}(abs ${args[0]})`;
          if (name === "sign" && args.length === 1) return `${comments}(ite (> ${args[0]} 0.0) 1.0 (ite (< ${args[0]} 0.0) -1.0 0.0))`;
          if (name === "min" && args.length === 2) return `${comments}(ite (< ${args[0]} ${args[1]}) ${args[0]} ${args[1]})`;
          if (name === "max" && args.length === 2) return `${comments}(ite (> ${args[0]} ${args[1]}) ${args[0]} ${args[1]})`;
          if (name === "clamp" && args.length === 3) return `${comments}(ite (< ${args[0]} ${args[1]}) ${args[1]} (ite (> ${args[0]} ${args[2]}) ${args[2]} ${args[0]}))`;
          if (name === "floor" && args.length === 1) return `${comments}(to_real (to_int ${args[0]}))`;
          if (name === "ceil" && args.length === 1) return `${comments}(- (to_real (to_int (- ${args[0]}))))`;
          if (name === "trunc" && args.length === 1) return `${comments}(ite (< ${args[0]} 0.0) (- (to_real (to_int (- ${args[0]})))) (to_real (to_int ${args[0]})))`;
          if (name === "fract" && args.length === 1) return `${comments}(- ${args[0]} (to_real (to_int ${args[0]})))`;
          if (name === "mod" && args.length === 2) return `${comments}(- ${args[0]} (* ${args[1]} (to_real (to_int (/ ${args[0]} ${args[1]})))))`;
          if (name === "mix" && args.length === 3) return `${comments}(+ (* ${args[0]} (- 1.0 ${args[2]})) (* ${args[1]} ${args[2]}))`;
          if (name === "step" && args.length === 2) return `${comments}(ite (< ${args[1]} ${args[0]}) 0.0 1.0)`;
          if (name === "smoothstep" && args.length === 3) {
              const tRaw = `(/ (- ${args[2]} ${args[0]}) (- ${args[1]} ${args[0]}))`;
              const t = `(ite (< ${tRaw} 0.0) 0.0 (ite (> ${tRaw} 1.0) 1.0 ${tRaw}))`;
              return `${comments}(* (* ${t} ${t}) (- 3.0 (* 2.0 ${t})))`;
          }
          if (name === "fma" && args.length === 3) return `${comments}(+ (* ${args[0]} ${args[1]}) ${args[2]})`;
      }
      
      return `${comments}(${smtName} ${argStr})`;
    }

ArgList
  = head:Expression tail:(ws1:_ "," ws2:_ Expression)* {
      return [head].concat(tail.map(t => t[0] + t[2] + t[3]));
    }

/* ---------------------------------------------------- */
/* Lexical Tokens & Comment Capturing                   */
/* ---------------------------------------------------- */

Type
  = "void" { return "()"; }
  / "float" { return "Real"; }
  / "int" { return "Int"; }
  / "bool" { return "Bool"; }
  / "vec2" { return "(Array Int Real)"; }
  / "vec3" { return "(Array Int Real)"; }
  / "vec4" { return "(Array Int Real)"; }
  / "ivec2" { return "(Array Int Int)"; }
  / "ivec3" { return "(Array Int Int)"; }
  / "ivec4" { return "(Array Int Int)"; }
  / "bvec2" { return "(Array Int Bool)"; }
  / "bvec3" { return "(Array Int Bool)"; }
  / "bvec4" { return "(Array Int Bool)"; }
  / "mat2" { return "(Array Int (Array Int Real))"; }
  / "mat3" { return "(Array Int (Array Int Real))"; }
  / "mat4" { return "(Array Int (Array Int Real))"; }
  / id:Identifier { return "compiled_" + id; }

VarModifier
  = ("const" / "inout" / "in" / "out" / "uniform" / "varying" / "attribute") __

Identifier
  = $([a-zA-Z_][a-zA-Z0-9_]*)

Number
  = $([0-9]+ "." [0-9]+ / "." [0-9]+ / [0-9]+ "." / [0-9]+)

_ "optional whitespace"
  = tokens:(WhiteSpace / MultiLineComment / SingleLineComment)* {
      const comments = tokens.filter(t => typeof t === "string" && t.startsWith(";"));
      return comments.length > 0 ? comments.join("\n") + "\n" : "";
  }

__ "mandatory whitespace"
  = tokens:(WhiteSpace / MultiLineComment / SingleLineComment)+ {
      const comments = tokens.filter(t => typeof t === "string" && t.startsWith(";"));
      return comments.length > 0 ? comments.join("\n") + "\n" : "";
  }

WhiteSpace
  = [ \t\n\r] { return null; }

SingleLineComment
  = "//" text:(![\n\r] .)* { 
      return ";" + text.map(t => t[1]).join(""); 
    }

MultiLineComment
  = "/*" text:(!"*/" .)* "*/" { 
      const content = text.map(t => t[1]).join("");
      return content.split("\n").map(line => ";" + line).join("\n");
    }
