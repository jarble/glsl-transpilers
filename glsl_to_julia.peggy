{
  const typeMap = {
    float: "Float32",
    int: "Int32",
    uint: "UInt32",
    bool: "Bool",
    vec2: "Vector2",
    vec3: "Vector3",
    vec4: "Vector4",
    mat2: "mat2",
    mat3: "mat3",
    mat4: "mat4",
    void: "Nothing"
  };

  function mapType(t){
    return typeMap[t] || t;
  }

  // Intercepts identifiers to safely append 'compiled_' to user-defined names
  function mapIdentifier(name) {
    const builtIns = new Set([
        // Types
        "float", "int", "uint", "bool", "void",
        "vec2", "vec3", "vec4", "mat2", "mat3", "mat4",
        // Functions
        "radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan",
        "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt",
        "abs", "sign", "floor", "ceil", "fract", "mod", "min", "max", "clamp", "mix", "step", "smoothstep",
        "length", "distance", "dot", "cross", "normalize", "reflect",
        // Built-in vars
        "gl_Position", "gl_FragColor", "gl_FragCoord", "gl_FrontFacing", "gl_PointSize", "gl_VertexID", "gl_InstanceID",
        // Keywords/Booleans
        "true", "false",
        // Single letter swizzles
        "x", "y", "z", "w", "r", "g", "b", "a", "s", "t", "p", "q"
    ]);
    
    // Skip recognized built-in GLSL identifiers
    if (builtIns.has(name)) return name;
    
    // Skip vector swizzling properties (e.g., .xyz, .rgba, .stpq)
    if (/^[xyzw]{2,4}$/.test(name)) return name;
    if (/^[rgba]{2,4}$/.test(name)) return name;
    if (/^[stpq]{2,4}$/.test(name)) return name;

    // Prevent double-prefixing just in case
    if (name.startsWith("compiled_")) return name;

    return "compiled_" + name;
  }

  // Generates raw Julia expressions for built-in GLSL Math
  function mapFuncCall(name, args, ws1, ws2, ws3) {
    const argsStr = args ? args.str : "";
    const argsList = args ? args.list : [];
    const a = argsList[0] || "";
    const b = argsList[1] || "";
    const c = argsList[2] || "";

    switch(name) {
      // Trigonometry
      case "radians": return `deg2rad(${a})`;
      case "degrees": return `rad2deg(${a})`;
      case "sin": return `sin(${ws2}${a}${ws3})`;
      case "cos": return `cos(${ws2}${a}${ws3})`;
      case "tan": return `tan(${ws2}${a}${ws3})`;
      case "asin": return `asin(${ws2}${a}${ws3})`;
      case "acos": return `acos(${ws2}${a}${ws3})`;
      case "atan": return argsList.length === 2 ? `atan(${a}, ${b})` : `atan(${a})`;

      // Exponential
      case "pow": return `(${a} ^ ${b})`;
      case "exp": return `exp(${a})`;
      case "log": return `log(${a})`;
      case "exp2": return `exp2(${a})`;
      case "log2": return `log2(${a})`;
      case "sqrt": return `sqrt(${a})`;
      case "inversesqrt": return `(1.0f0 / sqrt(${a}))`;

      // Common Math
      case "abs": return `abs(${a})`;
      case "sign": return `sign(${a})`;
      case "floor": return `floor(${a})`;
      case "ceil": return `ceil(${a})`;
      case "fract": return `(${a} - floor(${a}))`;
      case "mod": return `mod(${a}, ${b})`;
      case "min": return `min(${a}, ${b})`;
      case "max": return `max(${a}, ${b})`;
      case "clamp": return `clamp(${a}, ${b}, ${c})`;
      case "mix": return `(${a} * (1.0f0 - ${c}) + ${b} * ${c})`;
      case "step": return `(${b} < ${a} ? 0.0f0 : 1.0f0)`;
      case "smoothstep": 
        const t = `clamp((${c} - ${a}) / (${b} - ${a}), 0.0f0, 1.0f0)`;
        return `((t) -> t * t * (3.0f0 - 2.0f0 * t))(${t})`;

      // Geometric 
      case "length": return `norm(${a})`;
      case "distance": return `norm(${a} - ${b})`;
      case "dot": return `dot(${a}, ${b})`;
      case "cross": return `cross(${a}, ${b})`;
      case "normalize": return `normalize(${a})`;
      case "reflect": return `reflect(${a}, ${b})`;

      // User functions and unmapped built-ins perfectly retain layout
      default: return `${name}${ws1}(${ws2}${argsStr}${ws3})`;
    }
  }

  // Generates Julia Structs for GLSL Matrices AND Type Conversions
  function getBuiltInStructs() {
    return `
# --- GLSL Built-in Matrix Types ---
mutable struct mat2
    col0::Vector2
    col1::Vector2
end

mutable struct mat3
    col0::Vector3
    col1::Vector3
    col2::Vector3
end

mutable struct mat4
    col0::Vector4
    col1::Vector4
    col2::Vector4
    col3::Vector4
end

# --- GLSL Type Conversions ---
_float(v::Bool) = v ? 1.0f0 : 0.0f0
_float(v::Int32) = Float32(v)
_float(v::UInt32) = Float32(v)
_float(v::Float32) = v

_int(v::Bool) = v ? Int32(1) : Int32(0)
_int(v::Int32) = v
_int(v::UInt32) = Int32(v)
_int(v::Float32) = Int32(trunc(v))

_uint(v::Bool) = v ? UInt32(1) : UInt32(0)
_uint(v::Int32) = UInt32(v)
_uint(v::UInt32) = v
_uint(v::Float32) = UInt32(trunc(v))

_bool(v::Bool) = v
_bool(v::Int32) = v != 0
_bool(v::UInt32) = v != 0
_bool(v::Float32) = v != 0.0f0
`;
  }
}

/* ===================================================== */
/* entry */
/* ===================================================== */

Start
  =
  items:(ws:_ t:TopLevel { return ws + t; })*
  wsEnd:_
  {
    const program = items.join("") + wsEnd;
    return "using LinearAlgebra\n\n" + program + "\n\n" + getBuiltInStructs();
  }

TopLevel
  =
  StructDecl
  / GlobalDecl
  / FunctionDecl
  / Statement

Statement
  =
  VarDecl
  / AssignmentStmt
  / ReturnStmt
  / IfStmt
  / ForStmt
  / WhileStmt
  / DoWhileStmt
  / SwitchStmt
  / ExprStmt
  / Block

/* ===================================================== */
/* structs */
/* ===================================================== */

StructDecl
