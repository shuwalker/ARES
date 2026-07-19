import React, { StrictMode, type ErrorInfo } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";

import App from "@/App";
import { ThemeProvider } from "@/context/ThemeContext";
import { AresProvider } from "@/shared/ares-context";
import { LocalProfileProvider } from "@/shared/local-profile";
import "@/index.css";

const root = document.getElementById("root");

if (!root) throw new Error("ARES root element was not found");

class ErrorBoundary extends React.Component<{children: React.ReactNode}, {error: Error | null}> {
  constructor(props: {children: React.ReactNode}) {
    super(props);
    this.state = { error: null };
  }
  static getDerivedStateFromError(error: Error) {
    return { error };
  }
  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("ARES render failed", error, info.componentStack);
  }
  render() {
    if (this.state.error) {
      return (
        <div role="alert" style={{ maxWidth: 640, margin: "10vh auto", padding: "2rem", fontFamily: "system-ui, sans-serif" }}>
          <h1 style={{ fontSize: "1.25rem", fontWeight: 600 }}>ARES hit an unexpected error</h1>
          <p style={{ opacity: 0.75 }}>
            Your local data is unchanged. Retry this view or return to the main screen.
          </p>
          <div style={{ display: "flex", gap: "0.5rem", marginTop: "1rem" }}>
            <button type="button" onClick={() => this.setState({ error: null })}>Retry</button>
            <button type="button" onClick={() => window.location.assign("/today")}>Go to Today</button>
            <button type="button" onClick={() => window.location.reload()}>Reload</button>
          </div>
        </div>
      );
    }
    return this.props.children;
  }
}

createRoot(root).render(
  <StrictMode>
    <ErrorBoundary>
      <BrowserRouter>
        <ThemeProvider>
          <LocalProfileProvider>
            <AresProvider>
              <App />
            </AresProvider>
          </LocalProfileProvider>
        </ThemeProvider>
      </BrowserRouter>
    </ErrorBoundary>
  </StrictMode>,
);
