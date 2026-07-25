import path from "node:path";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig(({ mode }) => ({
  plugins: [react(), tailwindcss()],
  build: {
    minify: "esbuild",
    sourcemap: mode !== "production",
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes("node_modules/@monaco-editor") || id.includes("node_modules/monaco-editor")) return "monaco";
          if (id.includes("node_modules/@xterm")) return "xterm";
          if (id.includes("node_modules/lucide-react")) return "lucide";
          if (id.includes("node_modules/framer-motion")) return "motion";
          if (id.includes("node_modules/@radix-ui") || id.includes("node_modules/embla-carousel")) return "ui-vendor";
          if (id.includes("node_modules/recharts") || id.includes("node_modules/d3")) return "charts";
        },
      },
    },
  },
  esbuild:
    mode === "production"
      ? {
          drop: ["console", "debugger"],
          legalComments: "none",
        }
      : undefined,
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    proxy: {
      "/api": {
        target: "http://127.0.0.1:8787",
        ws: true,
      },
    },
  },
}));
