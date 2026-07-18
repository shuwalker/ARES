import React, { StrictMode } from "react";
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
  render() {
    if (this.state.error) {
      return (
        <div style={{ padding: "2rem", color: "red", fontFamily: "monospace" }}>
          <h2>Something went wrong.</h2>
          <pre style={{ whiteSpace: "pre-wrap" }}>{this.state.error.toString()}\n{this.state.error.stack}</pre>
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
