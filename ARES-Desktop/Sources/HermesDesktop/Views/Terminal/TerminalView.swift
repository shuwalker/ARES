import SwiftUI
import WebKit

// MARK: - Top-level view

struct TerminalView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.dashboardAPIAvailable, let port = appState.tunnelService.localPort {
            TerminalWebView(baseURL: URL(string: "http://localhost:\(port)")!)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if appState.activeConnection?.transportKind == .local,
                  let connection = appState.activeConnection {
            // Local transport: talk to the dashboard API at the connection's dashboard URL
            TerminalWebView(baseURL: connection.dashboardURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Terminal requires a connection",
                systemImage: "terminal",
                description: Text(
                    "Connect to a remote host (or start the local Hermes agent) to use the terminal."
                )
            )
        }
    }
}

// MARK: - NSViewRepresentable

struct TerminalWebView: NSViewRepresentable {
    let baseURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Allow the web content to make requests back to the same origin
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        // Transparent background so the macOS window background shows until the page loads
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator

        webView.loadHTMLString(terminalHTML(baseURL: baseURL), baseURL: baseURL)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Re-load only when baseURL changes (coordinator tracks this)
        if context.coordinator.lastBaseURL != baseURL {
            context.coordinator.lastBaseURL = baseURL
            webView.loadHTMLString(terminalHTML(baseURL: baseURL), baseURL: baseURL)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastBaseURL: URL

        init(baseURL: URL) {
            self.lastBaseURL = baseURL
        }
    }
}

// MARK: - HTML generation

private func terminalHTML(baseURL: URL) -> String {
    let base = baseURL.absoluteString.hasSuffix("/")
        ? String(baseURL.absoluteString.dropLast())
        : baseURL.absoluteString

    // NOTE: backtick characters inside a Swift multiline string literal are fine;
    // only \( must be escaped as \( for Swift interpolation. JavaScript template
    // literals that reference Swift-level variables use string concatenation instead.
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <title>ARES Terminal</title>
      <link
        rel="stylesheet"
        href="https://cdn.jsdelivr.net/npm/xterm@5.3.0/css/xterm.css"
      />
      <script src="https://cdn.jsdelivr.net/npm/xterm@5.3.0/lib/xterm.js"></script>
      <script src="https://cdn.jsdelivr.net/npm/@xterm/addon-fit@0.10.0/lib/addon-fit.js"></script>
      <style>
        *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { width: 100%; height: 100%; overflow: hidden; background: #1e1e1e; }
        #app { display: flex; flex-direction: column; width: 100%; height: 100%; }
        #terminal-container { flex: 1 1 0; overflow: hidden; padding: 4px 4px 0 4px; }
        #bottom-bar {
          display: flex;
          align-items: center;
          justify-content: flex-end;
          padding: 4px 10px;
          background: #2a2a2a;
          border-top: 1px solid #3a3a3a;
          min-height: 32px;
        }
        #ai-debug-btn {
          background: #3a3a3a;
          color: #d4d4d4;
          border: 1px solid #555;
          border-radius: 6px;
          padding: 3px 12px;
          font-size: 12px;
          cursor: pointer;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          transition: background 0.15s;
        }
        #ai-debug-btn:hover { background: #4a4a4a; }
        #ai-debug-btn:disabled { opacity: 0.45; cursor: default; }
        /* AI overlay panel */
        #debug-overlay {
          display: none;
          position: absolute;
          bottom: 40px;
          right: 12px;
          width: 420px;
          max-height: 55%;
          background: #252526;
          border: 1px solid #555;
          border-radius: 10px;
          padding: 14px;
          color: #d4d4d4;
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
          font-size: 13px;
          overflow-y: auto;
          z-index: 100;
          box-shadow: 0 8px 32px rgba(0,0,0,0.6);
        }
        #debug-overlay.visible { display: block; }
        #debug-overlay-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          margin-bottom: 10px;
        }
        #debug-overlay-title { font-weight: 600; font-size: 13px; color: #9cdcfe; }
        #debug-overlay-close {
          background: none;
          border: none;
          color: #888;
          cursor: pointer;
          font-size: 16px;
          line-height: 1;
          padding: 0 2px;
        }
        #debug-overlay-close:hover { color: #ccc; }
        #debug-overlay-body { white-space: pre-wrap; word-break: break-word; line-height: 1.5; }
        #debug-overlay-spinner { color: #888; font-style: italic; }
      </style>
    </head>
    <body>
      <div id="app">
        <div id="terminal-container"></div>
        <div id="bottom-bar">
          <button id="ai-debug-btn" title="Analyze recent output with AI">AI Debug</button>
        </div>
      </div>

      <!-- AI debug overlay -->
      <div id="debug-overlay" role="dialog" aria-label="AI Debug Suggestion">
        <div id="debug-overlay-header">
          <span id="debug-overlay-title">AI Debug Suggestion</span>
          <button id="debug-overlay-close" aria-label="Dismiss">&times;</button>
        </div>
        <div id="debug-overlay-body"></div>
      </div>

      <script>
        (function () {
          'use strict';

          var BASE_URL = '\(base)';
          var sessionId = null;
          var term = null;
          var fitAddon = null;
          var lineBuffer = [];
          var MAX_BUFFER_LINES = 500;

          // ─── Terminal init ────────────────────────────────────────────────
          function initTerminal() {
            term = new Terminal({
              theme: {
                background: '#1e1e1e',
                foreground: '#d4d4d4',
                cursor: '#d4d4d4',
                selectionBackground: 'rgba(255,255,255,0.2)',
                black:   '#000000', red:     '#cd3131',
                green:   '#0dbc79', yellow:  '#e5e510',
                blue:    '#2472c8', magenta: '#bc3fbc',
                cyan:    '#11a8cd', white:   '#e5e5e5',
                brightBlack:   '#666666', brightRed:     '#f14c4c',
                brightGreen:   '#23d18b', brightYellow:  '#f5f543',
                brightBlue:    '#3b8eea', brightMagenta: '#d670d6',
                brightCyan:    '#29b8db', brightWhite:   '#e5e5e5'
              },
              fontFamily: 'Menlo, Consolas, "Courier New", monospace',
              fontSize: 13,
              cursorBlink: true,
              scrollback: 2000,
              allowProposedApi: true
            });

            fitAddon = new FitAddon.FitAddon();
            term.loadAddon(fitAddon);
            term.open(document.getElementById('terminal-container'));
            fitAddon.fit();

            // Keystroke input
            term.onData(function (data) {
              if (!sessionId) return;
              fetch(BASE_URL + '/api/terminal-input', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ sessionId: sessionId, data: data })
              }).catch(function (err) {
                console.warn('terminal-input error:', err);
              });
            });

            // Capture output lines for AI debug
            term.onLineFeed(function () {
              var line = term.buffer.active.getLine(
                term.buffer.active.length - 2
              );
              if (line) {
                lineBuffer.push(line.translateToString(true));
                if (lineBuffer.length > MAX_BUFFER_LINES) {
                  lineBuffer.shift();
                }
              }
            });

            // Resize observer
            var resizeObserver = new ResizeObserver(function () {
              fitAddon.fit();
              if (sessionId) {
                fetch(BASE_URL + '/api/terminal-resize', {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    sessionId: sessionId,
                    cols: term.cols,
                    rows: term.rows
                  })
                }).catch(function (err) {
                  console.warn('terminal-resize error:', err);
                });
              }
            });
            resizeObserver.observe(document.getElementById('terminal-container'));

            connectStream();
          }

          // ─── SSE stream ──────────────────────────────────────────────────
          function connectStream() {
            term.write('\\x1b[33mConnecting to terminal…\\x1b[0m\\r\\n');

            fetch(BASE_URL + '/api/terminal-stream', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ cols: term.cols, rows: term.rows })
            }).then(function (response) {
              if (!response.ok || !response.body) {
                throw new Error('HTTP ' + response.status);
              }
              var reader = response.body.getReader();
              var decoder = new TextDecoder();
              var partial = '';

              function read() {
                reader.read().then(function (chunk) {
                  if (chunk.done) {
                    term.write('\\r\\n\\x1b[31m[stream closed]\\x1b[0m\\r\\n');
                    return;
                  }
                  partial += decoder.decode(chunk.value, { stream: true });
                  var lines = partial.split('\\n');
                  partial = lines.pop();
                  lines.forEach(function (line) {
                    line = line.trim();
                    if (line.startsWith('data:')) {
                      var json = line.slice(5).trim();
                      if (!json || json === '[DONE]') return;
                      try {
                        var data = JSON.parse(json);
                        if (data.sessionId && !sessionId) {
                          sessionId = data.sessionId;
                        }
                        if (typeof data.output === 'string') {
                          term.write(data.output);
                        }
                      } catch (e) {
                        // non-JSON data line — ignore
                      }
                    }
                  });
                  read();
                }).catch(function (err) {
                  term.write('\\r\\n\\x1b[31m[read error: ' + err.message + ']\\x1b[0m\\r\\n');
                });
              }
              read();
            }).catch(function (err) {
              term.write('\\r\\n\\x1b[31m[connection failed: ' + err.message + ']\\x1b[0m\\r\\n');
            });
          }

          // ─── AI Debug ────────────────────────────────────────────────────
          var overlay = document.getElementById('debug-overlay');
          var overlayBody = document.getElementById('debug-overlay-body');
          var debugBtn = document.getElementById('ai-debug-btn');
          var closeBtn = document.getElementById('debug-overlay-close');

          closeBtn.addEventListener('click', function () {
            overlay.classList.remove('visible');
          });

          debugBtn.addEventListener('click', function () {
            var recentLines = lineBuffer.slice(-50).join('\\n');
            overlayBody.innerHTML = '<span id="debug-overlay-spinner">Analyzing…</span>';
            overlay.classList.add('visible');
            debugBtn.disabled = true;

            fetch(BASE_URL + '/api/debug-analyze', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ output: recentLines })
            }).then(function (response) {
              if (!response.ok) throw new Error('HTTP ' + response.status);
              return response.json();
            }).then(function (data) {
              var suggestion = (data && data.suggestion) ? data.suggestion : '(no suggestion returned)';
              overlayBody.textContent = suggestion;
            }).catch(function (err) {
              overlayBody.textContent = 'Error: ' + err.message;
            }).finally(function () {
              debugBtn.disabled = false;
            });
          });

          // ─── Window close: terminate session ─────────────────────────────
          window.addEventListener('beforeunload', function () {
            if (sessionId) {
              navigator.sendBeacon(
                BASE_URL + '/api/terminal-close',
                JSON.stringify({ sessionId: sessionId })
              );
            }
          });

          // ─── Boot ─────────────────────────────────────────────────────────
          function boot() {
            if (typeof window.Terminal === 'undefined' || typeof window.FitAddon === 'undefined') {
              // xterm.js CDN scripts did not load — show a user-facing banner
              document.body.innerHTML = '';
              var banner = document.createElement('div');
              banner.style.cssText = [
                'display:flex', 'flex-direction:column', 'align-items:center',
                'justify-content:center', 'height:100vh', 'background:#1e1e1e',
                'color:#d4d4d4', 'font-family:-apple-system,BlinkMacSystemFont,sans-serif',
                'font-size:14px', 'gap:12px', 'padding:24px', 'text-align:center'
              ].join(';');
              banner.innerHTML = '<svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="#888" stroke-width="1.5"><path d="M12 9v4m0 4h.01M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/></svg>' +
                '<strong style="color:#fff">Terminal requires internet connection to load.</strong>' +
                '<span style="color:#888">Check your connection and reload.</span>';
              document.body.appendChild(banner);
              return;
            }
            initTerminal();
          }

          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', boot);
          } else {
            boot();
          }
        }());
      </script>
    </body>
    </html>
    """
}
