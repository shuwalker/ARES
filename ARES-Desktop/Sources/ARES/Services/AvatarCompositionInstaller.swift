import Foundation

enum AvatarCompositionInstaller {
    static let avatarDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ares/avatar")
    static let indexFile = avatarDir.appendingPathComponent("index.html")

    static func installIfNeeded() {
        guard !FileManager.default.fileExists(atPath: indexFile.path) else { return }
        try? FileManager.default.createDirectory(at: avatarDir, withIntermediateDirectories: true)
        try? htmlComposition.write(to: indexFile, atomically: true, encoding: .utf8)
        print("✅ [AVATAR] Installed composition to \(indexFile.path)")
    }

    static let htmlComposition: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>ARES Avatar</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                display: flex;
                align-items: center;
                justify-content: center;
                min-height: 100vh;
                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            }

            .container {
                position: relative;
                width: 300px;
                height: 300px;
            }

            .head {
                position: absolute;
                width: 240px;
                height: 240px;
                left: 30px;
                top: 30px;
                border-radius: 50%;
                background: radial-gradient(circle at 35% 35%, #ffd700, #ffed4e);
                box-shadow: 0 0 60px var(--glow-color, rgba(100, 150, 255, 0.3));
                transition: box-shadow 200ms ease;
            }

            .eyes {
                position: absolute;
                width: 100%;
                height: 50%;
                top: 40%;
                display: flex;
                justify-content: space-around;
                align-items: center;
                padding: 0 40px;
            }

            .eye {
                width: 40px;
                height: 40px;
                border-radius: 50%;
                background: white;
                position: relative;
                box-shadow: 0 2px 8px rgba(0, 0, 0, 0.3);
                transition: all 200ms ease;
            }

            .pupil {
                position: absolute;
                width: 20px;
                height: 20px;
                border-radius: 50%;
                background: #333;
                top: 10px;
                left: 10px;
                transition: all 200ms ease;
            }

            .mouth {
                position: absolute;
                width: 120px;
                height: 60px;
                left: 60px;
                bottom: 20px;
            }

            .mouth svg {
                width: 100%;
                height: 100%;
            }

            .mouth path {
                fill: none;
                stroke: #333;
                stroke-width: 3;
                stroke-linecap: round;
                transition: d 200ms ease;
            }

            /* Emotion states */
            .neutral .mouth path {
                d: path('M 20 40 Q 60 45 100 40');
            }

            .happy .mouth path {
                d: path('M 20 50 Q 60 65 100 50');
            }

            .curious .mouth path {
                d: path('M 20 40 Q 60 35 100 40');
            }

            .thinking .mouth path {
                d: path('M 20 45 Q 60 40 100 45');
            }

            /* State indicators */
            .head.idle {
                --glow-color: rgba(100, 150, 255, 0.5);
            }

            .head.listening {
                --glow-color: rgba(100, 255, 150, 0.8);
                animation: pulse-green 1s ease-in-out infinite;
            }

            .head.thinking {
                --glow-color: rgba(255, 200, 100, 0.6);
            }

            .head.speaking {
                --glow-color: rgba(255, 255, 255, 0.8);
                animation: pulse-white 0.8s ease-in-out infinite;
            }

            @keyframes pulse-green {
                0%, 100% { box-shadow: 0 0 40px rgba(100, 255, 150, 0.5); }
                50% { box-shadow: 0 0 80px rgba(100, 255, 150, 0.9); }
            }

            @keyframes pulse-white {
                0%, 100% { box-shadow: 0 0 40px rgba(255, 255, 255, 0.6); }
                50% { box-shadow: 0 0 80px rgba(255, 255, 255, 1); }
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="head neutral idle" id="head">
                <div class="eyes">
                    <div class="eye">
                        <div class="pupil"></div>
                    </div>
                    <div class="eye">
                        <div class="pupil"></div>
                    </div>
                </div>
                <div class="mouth">
                    <svg viewBox="0 0 120 60">
                        <path d="M 20 40 Q 60 45 100 40"></path>
                    </svg>
                </div>
            </div>
        </div>

        <script>
            window.setEmotion = function(emotion, intensity, state) {
                const head = document.getElementById('head');

                // Remove old emotion class
                ['neutral', 'happy', 'curious', 'thinking'].forEach(e => {
                    head.classList.remove(e);
                });

                // Add new emotion class
                if (['neutral', 'happy', 'curious', 'thinking'].includes(emotion)) {
                    head.classList.add(emotion);
                }

                // Remove old state class
                ['idle', 'listening', 'thinking', 'speaking'].forEach(s => {
                    head.classList.remove(s);
                });

                // Add new state class
                if (['idle', 'listening', 'thinking', 'speaking'].includes(state)) {
                    head.classList.add(state);
                }

                // Optional: adjust eye size based on intensity
                const eyeSize = 40 + (intensity * 10);
                document.querySelectorAll('.eye').forEach(eye => {
                    eye.style.width = eyeSize + 'px';
                    eye.style.height = eyeSize + 'px';
                });
            };

            // Test: cycle through emotions on load
            let emotions = ['neutral', 'happy', 'curious', 'thinking'];
            let idx = 0;
            setInterval(() => {
                window.setEmotion(emotions[idx], 0.5 + Math.random() * 0.5, 'idle');
                idx = (idx + 1) % emotions.length;
            }, 3000);
        </script>
    </body>
    </html>
    """
}
