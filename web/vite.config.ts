import react from "@vitejs/plugin-react";
import { defineConfig } from "vitest/config";

// In development the API and the two Flutter apps come from the running cluster.
const cluster = process.env.JARDEM_CLUSTER ?? "http://localhost:8080";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      "/api": { target: cluster, ws: true, changeOrigin: true },
      "/app": { target: cluster, changeOrigin: true },
    },
  },
  build: { outDir: "dist", emptyOutDir: true, sourcemap: false },
  test: { environment: "jsdom", include: ["src/**/*.test.{ts,tsx}"], setupFiles: ["src/test-setup.ts"] },
});
