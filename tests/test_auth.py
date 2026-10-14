import time
from types import SimpleNamespace

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from fibrik.api.app import create_app
from fibrik.settings import Settings

ISSUER = "http://localhost:8080/dex"


@pytest.fixture
def client_and_key():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    s = Settings(oidc_issuer=ISSUER, oidc_audience="fibrik-ui", lake_writer_enabled=False)
    app = create_app(s)
    # Skip the JWKS fetch: hand the verifier the test public key.
    app.state.verifier.jwks = SimpleNamespace(
        get_signing_key_from_jwt=lambda _t: SimpleNamespace(key=key.public_key())
    )
    return TestClient(app), key


def _token(key, **over):
    now = int(time.time())
    claims = {
        "iss": ISSUER,
        "aud": "fibrik-ui",
        "sub": "u1",
        "email": "a@example.com",
        "iat": now,
        "exp": now + 300,
    } | over
    return jwt.encode(claims, key, algorithm="RS256")


def test_info_is_public(client_and_key):
    client, _ = client_and_key
    assert client.get("/v1/info").json()["name"] == "fibrik"


def test_me_requires_a_token(client_and_key):
    client, _ = client_and_key
    assert client.get("/v1/me").status_code == 401


def test_me_with_valid_token(client_and_key):
    client, key = client_and_key
    r = client.get("/v1/me", headers={"Authorization": f"Bearer {_token(key)}"})
    assert r.status_code == 200
    assert r.json() == {"sub": "u1", "email": "a@example.com"}


@pytest.mark.parametrize("over", [{"aud": "other"}, {"iss": "http://evil/dex"}, {"exp": 1}])
def test_bad_tokens_are_rejected(client_and_key, over):
    client, key = client_and_key
    r = client.get("/v1/me", headers={"Authorization": f"Bearer {_token(key, **over)}"})
    assert r.status_code == 401
