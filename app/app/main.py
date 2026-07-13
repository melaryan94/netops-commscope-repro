import os
import time
import socket
import urllib.request

import jwt
from fastapi import Depends, FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

# --- Config (all via env so behavior can be flipped without code changes) ---
JWT_SECRET = os.getenv("JWT_SECRET", "dev-only-change-me")
JWT_ALG = "HS256"
JWT_TTL_SECONDS = int(os.getenv("JWT_TTL_SECONDS", "3600"))
# Comma-separated allowed origins. Empty = no CORS middleware (reproduces the
# two-origin failure). When single-origin behind App Gateway, CORS is unneeded.
ALLOWED_ORIGINS = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "").split(",") if o.strip()]
SERVE_STATIC = os.getenv("SERVE_STATIC", "true").lower() == "true"


def _database_url() -> str:
    # Prefer an explicit DATABASE_URL; otherwise compose from parts (DB_PASSWORD
    # typically arrives as a Key Vault reference resolved by App Service).
    explicit = os.getenv("DATABASE_URL", "")
    if explicit:
        return explicit
    host = os.getenv("DB_HOST", "")
    if not host:
        return ""
    user = os.getenv("DB_USER", "")
    pwd = os.getenv("DB_PASSWORD", "")
    name = os.getenv("DB_NAME", "postgres")
    return f"postgresql://{user}:{pwd}@{host}:5432/{name}?sslmode=require"


DATABASE_URL = _database_url()  # optional; enables /api/v1/dbcheck

# Dummy credentials — NOT for production
DEMO_USER = os.getenv("DEMO_USER", "netops")
DEMO_PASS = os.getenv("DEMO_PASS", "P@ssw0rd!")

app = FastAPI(title="NetOps Command Center (dummy)", version="0.1.0")

if ALLOWED_ORIGINS:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

bearer = HTTPBearer(auto_error=True)


class LoginRequest(BaseModel):
    username: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


def _make_token(sub: str) -> str:
    now = int(time.time())
    payload = {"sub": sub, "iat": now, "exp": now + JWT_TTL_SECONDS, "roles": ["noc"]}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALG)


def current_user(creds: HTTPAuthorizationCredentials = Depends(bearer)) -> dict:
    try:
        return jwt.decode(creds.credentials, JWT_SECRET, algorithms=[JWT_ALG])
    except jwt.PyJWTError:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid or expired token")


# --- Unauthenticated ---
@app.get("/api/v1/health")
def health():
    return {"status": "ok", "service": "netops-dummy", "host": socket.gethostname()}


@app.post("/api/v1/auth/login", response_model=TokenResponse)
def login(body: LoginRequest):
    if body.username != DEMO_USER or body.password != DEMO_PASS:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Bad credentials")
    return TokenResponse(access_token=_make_token(body.username))


# --- Authenticated ---
@app.get("/api/v1/me")
def me(user: dict = Depends(current_user)):
    return {"user": user["sub"], "roles": user.get("roles", [])}


@app.get("/api/v1/devices")
def devices(user: dict = Depends(current_user)):
    # Stand-in for the SD-WAN / device inventory
    return {
        "devices": [
            {"id": "rdc-director-sdwan01", "vendor": "versa", "status": "up"},
            {"id": "ruckus-ap-2201", "vendor": "ruckus", "status": "up"},
            {"id": "core-sw-07", "vendor": "cisco", "status": "degraded"},
        ]
    }


@app.get("/api/v1/vendors/{vendor}/status")
def vendor_status(vendor: str, user: dict = Depends(current_user)):
    known = {"versa", "ruckus", "cisco", "paloalto", "panorama", "logicmonitor", "infoblox", "freshservice"}
    if vendor.lower() not in known:
        raise HTTPException(status.HTTP_404_NOT_FOUND, f"Unknown vendor '{vendor}'")
    return {"vendor": vendor.lower(), "reachable": True, "latency_ms": 42}


@app.get("/api/v1/egress-ip")
def egress_ip(user: dict = Depends(current_user)):
    # Proves outbound traffic leaves via the NAT Gateway's stable public IP.
    try:
        with urllib.request.urlopen("https://api.ipify.org", timeout=5) as r:
            return {"egress_ip": r.read().decode().strip()}
    except Exception as e:  # noqa: BLE001 - surface the failure to the caller
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"egress check failed: {e}")


@app.get("/api/v1/dbcheck")
def dbcheck(user: dict = Depends(current_user)):
    # Proves the App Service can reach PostgreSQL over the private path.
    if not DATABASE_URL:
        raise HTTPException(status.HTTP_501_NOT_IMPLEMENTED, "DATABASE_URL not configured")
    try:
        import psycopg  # imported lazily so the app runs without the DB

        with psycopg.connect(DATABASE_URL, connect_timeout=5) as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT version();")
                ver = cur.fetchone()[0]
        return {"connected": True, "server": ver}
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"db check failed: {e}")


# Serve the SPA from the same origin (the "fixed" single-origin end state).
if SERVE_STATIC:
    app.mount("/", StaticFiles(directory="static", html=True), name="static")
