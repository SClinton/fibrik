"""Bearer-token authentication against the OIDC issuer (Dex)."""

from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, Request, status

from fibrik.settings import Settings


class TokenVerifier:
    def __init__(self, s: Settings):
        self.issuer = s.oidc_issuer
        self.audience = s.oidc_audience
        self.jwks = jwt.PyJWKClient(s.oidc_jwks_url, cache_keys=True, lifespan=300)

    def verify(self, token: str) -> dict:
        key = self.jwks.get_signing_key_from_jwt(token).key
        return jwt.decode(
            token,
            key,
            algorithms=["RS256", "ES256"],
            audience=self.audience,
            issuer=self.issuer,
            options={"require": ["exp", "iat", "sub"]},
        )


def current_user(request: Request) -> dict:
    """FastAPI dependency: the verified token claims, or 401."""
    verifier: TokenVerifier | None = request.app.state.verifier
    if verifier is None:  # auth disabled (no identity provider configured)
        return {"sub": "anonymous"}
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "missing bearer token")
    try:
        return verifier.verify(token)
    except jwt.PyJWTError as e:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, f"invalid token: {e}") from None


User = Annotated[dict, Depends(current_user)]
