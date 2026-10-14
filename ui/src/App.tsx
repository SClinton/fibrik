import { Database, LogIn, LogOut, RefreshCw, Waves } from "lucide-react";
import type { User, UserManager } from "oidc-client-ts";
import { useCallback, useEffect, useState } from "react";
import { apiGet, type PipelineStats } from "./api";
import { displayName } from "./auth";

type Props = { users: UserManager };

export default function App({ users }: Props) {
  const [user, setUser] = useState<User | null>(null);
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    (async () => {
      try {
        if (window.location.pathname === "/auth/callback") {
          setUser(await users.signinRedirectCallback());
          window.history.replaceState({}, "", "/");
        } else {
          const u = await users.getUser();
          setUser(u && !u.expired ? u : null);
        }
      } catch (e) {
        setError(String(e));
      } finally {
        setReady(true);
      }
    })();
  }, [users]);

  if (!ready) return null;

  return (
    <div className="min-h-screen bg-slate-50 text-slate-900">
      <header className="flex items-center justify-between border-b bg-white px-6 py-3">
        <div className="flex items-center gap-2 font-semibold">
          <Waves className="h-5 w-5 text-teal-700" aria-hidden />
          Fibrik
        </div>
        {user ? (
          <div className="flex items-center gap-3 text-sm">
            <span data-testid="user-name">{displayName(user)}</span>
            <button
              className="inline-flex items-center gap-1 rounded-md border px-3 py-1.5 hover:bg-slate-100"
              onClick={() => users.signoutRedirect()}
            >
              <LogOut className="h-4 w-4" aria-hidden /> Sign out
            </button>
          </div>
        ) : null}
      </header>
      <main className="mx-auto max-w-4xl p-6">
        {error ? <p className="mb-4 rounded-md bg-red-50 p-3 text-sm text-red-800">{error}</p> : null}
        {user ? <Overview token={user.access_token} /> : <SignIn onSignIn={() => users.signinRedirect()} />}
      </main>
    </div>
  );
}

function SignIn({ onSignIn }: { onSignIn: () => void }) {
  return (
    <section className="mx-auto mt-24 max-w-sm rounded-lg border bg-white p-8 text-center shadow-sm">
      <h1 className="text-xl font-semibold">Sign in to Fibrik</h1>
      <p className="mt-2 text-sm text-slate-600">Keep the signal, cut the SIEM cost.</p>
      <button
        className="mt-6 inline-flex items-center gap-2 rounded-md bg-teal-700 px-4 py-2 text-white hover:bg-teal-800"
        onClick={onSignIn}
      >
        <LogIn className="h-4 w-4" aria-hidden /> Sign in
      </button>
    </section>
  );
}

function Overview({ token }: { token: string }) {
  const [stats, setStats] = useState<PipelineStats | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      setStats(await apiGet<PipelineStats>("/v1/pipeline/stats", token));
      setError(null);
    } catch (e) {
      setError(String(e));
    }
  }, [token]);

  useEffect(() => {
    refresh();
    const id = window.setInterval(refresh, 10_000);
    return () => window.clearInterval(id);
  }, [refresh]);

  return (
    <section>
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">Pipeline</h1>
        <button
          className="inline-flex items-center gap-1 rounded-md border bg-white px-3 py-1.5 text-sm hover:bg-slate-100"
          onClick={refresh}
        >
          <RefreshCw className="h-4 w-4" aria-hidden /> Refresh
        </button>
      </div>
      {error ? <p className="mt-4 rounded-md bg-red-50 p-3 text-sm text-red-800">{error}</p> : null}
      <div className="mt-4 grid gap-4 sm:grid-cols-2">
        <Stat label="Events in hot store (ClickHouse)" value={stats?.clickhouse.raw_logs} testId="stat-hot" />
        <Stat label="Events in lake (Iceberg)" value={stats?.lake.raw_logs} testId="stat-lake" />
      </div>
      <p className="mt-6 text-sm text-slate-600">
        Send syslog (RFC 5424, TCP 5140) or OTLP (4317/4318) to the fibrik-otelcol service. Cost
        overview and sources arrive in week 2.
      </p>
    </section>
  );
}

function Stat({ label, value, testId }: { label: string; value?: number; testId: string }) {
  return (
    <div className="rounded-lg border bg-white p-5 shadow-sm">
      <div className="flex items-center gap-2 text-sm text-slate-600">
        <Database className="h-4 w-4" aria-hidden /> {label}
      </div>
      <div className="mt-2 text-3xl font-semibold tabular-nums" data-testid={testId}>
        {value ?? "–"}
      </div>
    </div>
  );
}
