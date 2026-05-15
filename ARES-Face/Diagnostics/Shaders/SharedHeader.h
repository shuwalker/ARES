// SharedHeader.h — Bridge between Swift and Metal shader uniforms
// This header is included by both .metal files and accessible from Swift via bridging

#ifdef __METAL_VERSION__
#define TEXTURE_2D metal::texture2d<half>
#else
#define TEXTURE_2D uint64_t
#endif

typedef struct {
    float intensity;        // 0.0 - 1.0
    float expression;       // 0=neutral, 1=happy, 2=curious, 3=thinking, 4=surprised, 5=concerned, 6=excited, 7=sleepy
    float isSpeaking;       // 0.0 or 1.0
    float time;             // elapsed seconds
    // Cognition-driven uniforms — populated from CognitiveSnapshot via
    // CognitiveBindings. Trailing fields are non-breaking for shaders
    // that don't reference them yet.
    float noiseScale;       // 0.0 - 1.0, driven by urgency
    float emissivePulse;    // 0.0 - 1.0, driven by thought.confidence
    float vertexJitter;     // 0.0 - 1.0, driven by reasoning depth
    float glitchAmplitude;  // 0.0 - 1.0, driven by error count
} SurfaceCustomUniforms;

typedef struct {
    float vertexAnimationSpeed;
    float vertexAnimationAmplitude;
    float displacementScale;
    float normalInfluence;
    // Extended uniforms for new styles
    float cheekStripes;       // 0=off, 1=3-line pattern (synthMuse)
    float rimHue;              // 0=cyan, 0.5=magenta, 1=gold (rim light color)
    float eyeMode;             // 0=round, 1=slit, 2=glow, 3=hidden (eye rendering mode)
    float companionState;      // 0=ball, 1=revealed, 2=transformed (companion creature)
} GeometryCustomUniforms;