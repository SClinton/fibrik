import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// `npm run dev` proxies the API, Dex and runtime config to a running
// deployment (make k3d-up deploy, then port 8080).
const target = process.env.FIBRIK_URL ?? "http://localhost:8080";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    proxy: {
      "/api": target,
      "/dex": target,
      "/config.json": target,
    },
  },
});
