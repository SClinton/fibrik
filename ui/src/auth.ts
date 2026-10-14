import { User, UserManager, WebStorageStateStore } from "oidc-client-ts";
import type { RuntimeConfig } from "./config";

// Authorization code flow with PKCE against Dex. Dex fronts the real
// identity provider (GitHub first), so the UI only ever speaks OIDC.
export function createUserManager(cfg: RuntimeConfig): UserManager {
  const origin = window.location.origin;
  return new UserManager({
    authority: cfg.issuer,
    client_id: cfg.clientId,
    redirect_uri: `${origin}/auth/callback`,
    post_logout_redirect_uri: `${origin}/`,
    response_type: "code",
    scope: "openid profile email",
    // Session-scoped: closing the tab ends the session.
    userStore: new WebStorageStateStore({ store: window.sessionStorage }),
  });
}

export function displayName(user: User): string {
  const p = user.profile;
  return (p.name as string) || (p.preferred_username as string) || (p.email as string) || p.sub;
}
