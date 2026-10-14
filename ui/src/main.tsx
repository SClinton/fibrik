import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./App";
import { createUserManager } from "./auth";
import { loadConfig } from "./config";
import "./index.css";

const root = createRoot(document.getElementById("root")!);

loadConfig()
  .then((cfg) =>
    root.render(
      <StrictMode>
        <App users={createUserManager(cfg)} />
      </StrictMode>,
    ),
  )
  .catch((e) => root.render(<p style={{ padding: 24 }}>Fibrik failed to load: {String(e)}</p>));
