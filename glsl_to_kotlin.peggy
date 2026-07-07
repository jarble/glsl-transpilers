{
  const typeMap = {
    float: "Float",
    int: "Int",
    uint: "UInt",
    bool: "Boolean",
    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",
    mat2: "Matrix2",
    mat3: "Matrix3",
    mat4: "Matrix4",
    void: "Unit"
  };

  function mapType(t) {
    return typeMap[t] || t;
  }

  // Intercepts and formats Kotlin-safe identifiers
  function mapIdentifier(name) {
    return name; // Add prefixing if necessary for scope management
  }
}

Start = _ items:TopLevel* _ { return items.join("\n"); }

TopLevel = FunctionDecl / StructDecl / VariableDecl

// Example: fun add(a: Float, b: Float): Float { ... }
FunctionDecl
  = ret:Type _ name:Identifier _ "(" _ params:ParamList? _ ")" _ body:Block
  { return `fun ${name}(${params || ""}): ${ret} ${body}`; }

// Example: data class Light(val position: Vector3, val intensity: Float)
StructDecl
  = "struct" __ name:Identifier _ "{" _ fields:StructFieldList _ "}"
  { return `data class ${name}(${fields})`; }

StructFieldList = head:StructField tail:(_ StructField)* { return [head, ...tail.map(t => t[1])].join(", "); }
StructField = type:Type __ name:Identifier { return `val ${name}: ${type}`; }

ParamList = head:Param tail:(_ "," _ Param)* { return [head, ...tail.map(t => t[3])].join(", "); }
Param = type:Type __ name:Identifier { return `${name}: ${type}`; }

Block = "{" _ stmts:StatementList _ "}" { return `{\n${stmts}\n}`; }
StatementList = head:Statement tail:(_ Statement)* { return [head, ...tail.map(t => t[1])].join("\n"); }

Statement
  = VariableDecl / ReturnStmt / ExprStmt

VariableDecl
  = type:Type __ name:Identifier _ "=" _ expr:Expression _ ";"
  { return `var ${name}: ${type} = ${expr}`; }

ReturnStmt
  = "return" _ expr:Expression _ ";" { return `return ${expr}`; }

ExprStmt = expr:Expression _ ";" { return expr; }

Type = t:([a-zA-Z]+) { return mapType(t.join("")); }

Identifier = name:$([a-zA-Z_][a-zA-Z0-9_]*) { return mapIdentifier(name); }

Expression = Number / Identifier / BinaryExpr

BinaryExpr = left:Identifier _ op:("+"/"-"/"*"/"/") _ right:Expression { return `${left} ${op} ${right}`; }

Number = num:$([0-9]+ ("." [0-9]*)?) { return num; }

_ = [ \t\r\n]*
__ = [ \t\r\n]+
