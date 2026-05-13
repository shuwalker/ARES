// SharedHeader.h — Bridge between Swift and Metal shader uniforms
// This header is included by both .metal files and accessible from Swift via bridging

#ifdef __METAL_VERSION__
#define TEXTURE_2D metal::texture2d<half>
#else
#define TEXTURE_2D uint64_t
#endif

typedef struct {
    float intensity;       // 0.0 - 1.0
    float expression;      // 0=neutral, 1=happy, 2=curious, 3=thinking, 4=surprised, 5=concerned, 6=excited, 7=sleepy
    float isSpeaking;      // 0.0 or 1.0
    float time;            // elapsed seconds
} SurfaceCustomUniforms;

typedef struct {
    float vertexAnimationSpeed;
    float vertexAnimationAmplitude;
    float displacementScale;
    float normalInfluence;
} GeometryCustomUniforms;