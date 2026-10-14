// Runtime configuration, served by Caddy from the chart's values, so one UI
// build works on every host.
export type RuntimeConfig = {
  issuer: string;
  clientId: string;
};

export async function loadConfig(): Promise<RuntimeConfig> {
  const res = await fetch("/config.json", { cache: "no-store" });
  if (!res.ok) throw new Error(`config.json: ${res.status}`);
  return res.json();
}
