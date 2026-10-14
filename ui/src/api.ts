export type PipelineStats = {
  clickhouse: { raw_logs: number };
  lake: { raw_logs: number };
};

export async function apiGet<T>(path: string, token: string): Promise<T> {
  const res = await fetch(`/api${path}`, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}
