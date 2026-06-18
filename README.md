# GLSL Transpiler
 [A universal translator for GLSL](https://jarble.github.io/glsl-transpilers/glsl_transpilers.html)

Still a work-in-progress.
## GLSL input:
```
// Single line comment

/*
Multi-line comment
*/

struct Light {
    vec3 position;
    vec3 color;
    float intensity;
};

uniform vec3 cameraPosition;
attribute vec3 vertexPosition;
varying vec2 uv;

const float PI = 3.14159265;

float multiply(float x, float y) {
    return x * y;
}

int add(int a, int b) {
    return a + b;
}

vec3 normalizeColor(in vec3 c) {
    return normalize(c);
}

void modifyColor(
    in vec3 inputColor,
    out vec3 outputColor,
    inout float factor
) {
    factor = factor * 2.0;

    outputColor =
        normalize(
            inputColor *
            factor
        );
}

float complexMath(float x) {

    float a = sin(x);

    float b =
        cos(x) +
        sqrt(x);

    float c =
        pow(a,b) +
        abs(x);

    return c;
}

vec3 testVectors() {

    vec2 a =
        vec2(
            1.0,
            2.0
        );

    vec3 b =
        vec3(
            3.0,
            4.0,
            5.0
        );

    vec4 c =
        vec4(
            1.0,
            2.0,
            3.0,
            4.0
        );

    vec3 result =
        normalize(
            b +
            vec3(
                a.x,
                a.y,
                c.z
            )
        );

    return result;
}

float loopsAndConditions(int limit) {

    float total = 0.0;

    for(
        int i = 0;
        i < limit;
        i = i + 1
    ){

        if(
            i < 5 &&
            i != 2
        ){

            total =
                total +
                float(i);

        } else {

            total =
                total -
                1.0;

        }
    }

    while(
        total < 100.0
    ){

        total =
            total +
            10.0;
    }

    do {

        total =
            total -
            5.0;

    } while(
        total > 50.0
    );

    return total;
}

float switchExample(int mode){

    float result = 0.0;

    switch(mode){

        case 0:
            result = 10.0;

        case 1:
            result = 20.0;

        default:
            result = 99.0;
    }

    return result;
}

void arraysExample() {

    float values[];

    values[0] = 1.0;
    values[1] = 2.0;
    values[2] = 3.0;

    float sum =
        values[0] +
        values[1] +
        values[2];
}

void everything() {

    Light light;

    light.position =
        vec3(
            1.0,
            2.0,
            3.0
        );

    light.color =
        vec3(
            0.5,
            0.7,
            1.0
        );

    light.intensity =
        multiply(
            4.0,
            2.0
        );

    vec3 outputColor;

    float factor =
        1.5;

    modifyColor(
        light.color,
        outputColor,
        factor
    );

    vec3 finalColor =
        normalizeColor(
            outputColor
        );

    float result =
        complexMath(
            PI
        );

    result =
        result +
        loopsAndConditions(
            10
        );

    result =
        result +
        switchExample(
            1
        );
}
```
