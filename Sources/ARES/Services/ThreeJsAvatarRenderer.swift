import SwiftUI
import WebKit
import os

@MainActor
final class ThreeJsAvatarRenderer: NSObject {
    let view: NSView
    private let webView: WKWebView
    private let logger = Logger(subsystem: "com.ares", category: "Renderer")

    override init() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        self.webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.layer?.backgroundColor = .clear
        self.view = webView
        super.init()
        webView.uiDelegate = self
        loadScene()
    }

    private func loadScene() {
        let bundle = Bundle.main
        let modelDir = FileManager.default.temporaryDirectory.appendingPathComponent("ares-avatar-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

        let files = [
            ("fmaEdward", "obj"), ("fmaEdward", "mtl"),
            ("Fma_EdwardGate_Albedo", "jpg"), ("Fma_EdwardGate_Normal", "png"),
            ("Fma_EdwardGate_Ao", "jpg"), ("Fma_EdwardGate_Metallic", "jpg"),
            ("Fma_EdwardGate_Roughness", "jpg")
        ]

        var allCopied = true
        for (name, ext) in files {
            if let srcPath = bundle.path(forResource: name, ofType: ext) {
                let dest = modelDir.appendingPathComponent("\(name).\(ext)")
                try? FileManager.default.copyItem(at: URL(fileURLWithPath: srcPath), to: dest)
            } else {
                allCopied = false
                logger.error("Missing: \(name).\(ext)")
            }
        }

        guard allCopied else {
            webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
            return
        }

        let html = Self.buildHTML()
        let htmlPath = modelDir.appendingPathComponent("index.html")
        try? html.write(to: htmlPath, atomically: true, encoding: .utf8)
        webView.loadFileURL(htmlPath, allowingReadAccessTo: modelDir)
    }

    func showFloatingText(_ text: String, role: String = "user") {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        callJS("window.showFloatingText('\(escaped)', '\(role)')")
    }

    func clearFloatingText() {
        callJS("window.clearFloatingText()")
    }

    @MainActor
    private func callJS(_ script: String) {
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error = error {
                self?.logger.error("JS: \(error.localizedDescription)")
            }
        }
    }

    static func buildHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
            *{margin:0;padding:0}
            body{background:#fff;overflow:hidden;width:100vw;height:100vh}
            canvas{display:block}
        </style>
        </head>
        <body>
        <script type="importmap">
        {
            "imports": {
                "three": "https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js",
                "three/addons/": "https://cdn.jsdelivr.net/npm/three@0.160.0/examples/jsm/"
            }
        }
        </script>
        <script type="module">
        import * as THREE from 'three';
        import { OBJLoader } from 'three/addons/loaders/OBJLoader.js';

        const scene = new THREE.Scene();
        scene.background = new THREE.Color(0xffffff);
        const camera = new THREE.PerspectiveCamera(40, 1, 0.1, 50);
        camera.position.set(0, 1.8, 5);
        camera.lookAt(0, 1.5, 0);
        const renderer = new THREE.WebGLRenderer({antialias:true,alpha:true,powerPreference:'high-performance'});
        renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        renderer.toneMapping = THREE.ACESFilmicToneMapping;
        renderer.toneMappingExposure = 1.0;
        renderer.outputColorSpace = THREE.SRGBColorSpace;
        document.body.appendChild(renderer.domElement);

        const ambient = new THREE.AmbientLight(0xffffff, 0.4);
        scene.add(ambient);
        const keyLight = new THREE.DirectionalLight(0xffffff, 1.2);
        keyLight.position.set(-4, 8, 6);
        scene.add(keyLight);
        const fillLight = new THREE.DirectionalLight(0xffffff, 0.5);
        fillLight.position.set(3, 2, 4);
        scene.add(fillLight);
        scene.fog = new THREE.Fog(0xffffff, 8, 18);

        const floor = new THREE.Mesh(
            new THREE.PlaneGeometry(10, 10),
            new THREE.MeshStandardMaterial({color:0xf5f5f5,roughness:0.9,metalness:0.0,transparent:true,opacity:0.3,side:THREE.DoubleSide})
        );
        floor.rotation.x = -Math.PI/2;
        floor.position.y = -0.1;
        scene.add(floor);

        const gateGroup = new THREE.Group();
        scene.add(gateGroup);

        const texLoader = new THREE.TextureLoader();
        const gateMat = new THREE.MeshStandardMaterial({
            map: texLoader.load('Fma_EdwardGate_Albedo.jpg'),
            normalMap: texLoader.load('Fma_EdwardGate_Normal.png'),
            aoMap: texLoader.load('Fma_EdwardGate_Ao.jpg'),
            metalnessMap: texLoader.load('Fma_EdwardGate_Metallic.jpg'),
            roughnessMap: texLoader.load('Fma_EdwardGate_Roughness.jpg'),
            roughness: 0.7, metalness: 0.3,
        });

        const objLoader = new OBJLoader();
        objLoader.load('fmaEdward.obj', (obj) => {
            obj.traverse(c => { if(c.isMesh){c.material=gateMat;c.castShadow=true;c.receiveShadow=true;} });
            obj.rotation.x = -Math.PI/2;
            const box = new THREE.Box3().setFromObject(obj);
            const size = box.getSize(new THREE.Vector3());
            const center = box.getCenter(new THREE.Vector3());
            const scale = 1.8 / Math.max(size.x, size.y, size.z);
            obj.scale.set(scale, scale, scale);
            obj.position.set(-center.x*scale, -center.y*scale+0.8, -center.z*scale);
            gateGroup.add(obj);
        });

        function animate() {
            requestAnimationFrame(animate);
            const w=window.innerWidth, h=window.innerHeight;
            if(camera.aspect!==w/h){camera.aspect=w/h;camera.updateProjectionMatrix();renderer.setSize(w,h);}
            renderer.render(scene, camera);
        }
        animate();

        const textContainer = document.createElement('div');
        textContainer.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);width:70%;max-width:700px;pointer-events:none;z-index:10';
        document.body.appendChild(textContainer);

        window.showFloatingText = (text, role) => {
            const el = document.createElement('div');
            const isUser = role === 'user';
            el.style.cssText = `font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;font-size:${isUser?'15px':'17px'};font-weight:${isUser?'400':'300'};color:${isUser?'rgba(0,0,0,0.5)':'rgba(0,0,0,0.8)'};text-align:${isUser?'right':'left'};padding:8px 16px;margin:4px 0;background:${isUser?'rgba(0,0,0,0.03)':'transparent'};border-radius:12px;opacity:0;transform:translateY(10px);transition:all 0.5s ease;line-height:1.5;letter-spacing:${isUser?'0.3px':'0.1px'};`;
            el.textContent = text;
            textContainer.appendChild(el);
            requestAnimationFrame(() => { el.style.opacity='1'; el.style.transform='translateY(0)'; });
            el.scrollIntoView({behavior:'smooth',block:'end'});
        };
        window.clearFloatingText = () => {
            while(textContainer.firstChild){const c=textContainer.firstChild;c.style.opacity='0';c.style.transform='translateY(-10px)';setTimeout(()=>c.remove(),500);}
        };
        console.log('ARES Sanctum loaded');
        </script>
        </body>
        </html>
        """
    }

    static let fallbackHTML = buildHTML()
}

extension ThreeJsAvatarRenderer: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        logger.info("JS: \(message)")
        completionHandler()
    }
}
