{{
  // Helper to handle Nim's indentation-based blocking
  function indent(str, spaces = 2) {
    if (!str) return ' '.repeat(spaces) + 'discard';
    return str.split('\n').map(line => ' '.repeat(spaces) + line).join('\n');
  }

  // Maps GLSL type primitives to standard Nim types
  function mapType(glslType) {
    const types = {
      'float': 'float32',
      'int': 'int32',
      'bool': 'bool',
      'void': '', // Void return types are omitted in Nim procs
      'vec2': 'Vec2',
      'vec3': 'Vec3',
      'vec4': 'Vec4',
      'mat4': 'Mat4'
    };
    return types[glslType] || glslType;
  }
}}

Start
  = elements:SourceElement* { return elements.join('\n\n').trim(); }

SourceElement
  = FunctionDefinition
  / GlobalDeclaration

// --- Declarations ---

GlobalDeclaration
  = qual:Qualifier? _ type:Type _ id:Identifier _ ";" {
      const pragma = qual ? ` {.${qual}.}` : '';
      return `var ${id}${pragma}: ${mapType(type)}`;
    }
  / qual:Qualifier? _ type:Type _ id:Identifier _ "=" _ expr:Expression _ ";" {
      const pragma = qual ? ` {.${qual}.}` : '';
      return `var ${id}${pragma}: ${mapType(type)} = ${expr}`;
    }

LocalDeclaration
  = type:Type _ id:Identifier _ ";" { 
      return `var ${id}: ${mapType(type)}`; 
    }
  / type:Type _ id:Identifier _ "=" _ expr:Expression _ ";" { 
      // Infers type cleanly using Nim's var initialization
      return `var ${id} = ${expr}`; 
    }

// --- Functions ---

FunctionDefinition
  = retType:Type _ id:Identifier _ "(" _ params:ParameterList? _ ")" _ "{" _ body:StatementList _ "}" {
      const nimType = mapType(retType);
      const typeStr = nimType ? `: ${nimType}` : '';
      const paramStr = params ? params : '';
      const bodyStr = body.trim() ? indent(body) : '  discard';
      return `proc ${id}(${paramStr})${typeStr} =\n${bodyStr}`;
    }

ParameterList
  = head:Parameter tail:(_ "," _ Parameter)* {
      return [head, ...tail.map(t => t[3])].join(', ');
    }

Parameter
  = qual:ParameterQualifier? _ type:Type _ id:Identifier { 
      // Maps 'out/inout' parameters to Nim 'var' parameters
      const isVar = (qual === 'out' || qual === 'inout') ? 'var ' : '';
      return `${id}: ${isVar}${mapType(type)}`; 
    }

// --- Statements ---

StatementList
  = stmts:Statement* { return stmts.filter(s => s).join('\n'); }

Statement
  = _ stmt:(LocalDeclaration / Assignment / ReturnStatement / IfStatement) _ { return stmt; }

Assignment
  = id:Identifier _ "=" _ expr:Expression _ ";" { return `${id} = ${expr}`; }

ReturnStatement
  = "return" _ expr:Expression? _ ";" { return expr ? `return ${expr}` : `return`; }

IfStatement
  = "if" _ "(" _ cond:Expression _ ")" _ "{" _ body:StatementList _ "}" {
      return `if ${cond}:\n${indent(body)}`;
    }

// --- Expressions ---

Expression
  = BinaryExpression
  / PrimaryExpression

BinaryExpression
  = left:PrimaryExpression _ op:[+\-*/=<>!]+ _ right:Expression {
      return `${left} ${op.join('')} ${right}`;
    }

PrimaryExpression
  = FunctionCall
  / FloatLiteral
  / IntLiteral
  / Identifier
  / "(" _ expr:Expression _ ")" { return `(${expr})`; }

FunctionCall
  = id:Identifier _ "(" _ args:ArgumentList? _ ")" {
      return `${id}(${args || ''})`;
    }

ArgumentList
  = head:Expression tail:(_ "," _ Expression)* {
      return [head, ...tail.map(t => t[3])].join(', ');
    }

// --- Lexical Tokens ---

Qualifier
  = "uniform" / "attribute" / "varying" / "in" / "out"

ParameterQualifier
  = "inout" / "in" / "out"

Type
  = "float" / "int" / "bool" / "void" / "vec2" / "vec3" / "vec4" / "mat4"

Identifier
  = head:[a-zA-Z_] tail:[a-zA-Z0-9_]* { return head + tail.join(''); }

FloatLiteral
  = digits:[0-9]+ "." fraction:[0-9]* { return digits.join('') + '.' + fraction.join(''); }

IntLiteral
  = digits:[0-9]+ { return digits.join(''); }

_ "whitespace"
  = [ \t\n\r]*
