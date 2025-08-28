"""
FastAPI backend for authentication.
- POST /login accepts {"email","password"}
- Calls Firebase REST API signInWithPassword using FIREBASE_WEB_API_KEY
- On success returns a JWT (HS256) containing sub (firebase uid) and email

Notes:
- Set FIREBASE_WEB_API_KEY and JWT_SECRET in environment or .env
- This implementation is intentionally minimal for the checkpoint.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, EmailStr
import os
import httpx
import jwt
import secrets
import logging
from datetime import datetime, timedelta
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

load_dotenv()

WEB_API_KEY = os.getenv('FIREBASE_WEB_API_KEY')
JWT_SECRET = os.getenv('JWT_SECRET', 'change-me')

app = FastAPI(title='Points Auth Backend')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configure CORS to allow preflight requests from the Flutter client during development.
# You can set a comma-separated list of origins in the environment variable CORS_ORIGINS.
# Use '*' to allow all origins (development only).
origins_env = os.getenv('CORS_ORIGINS', '*')
if origins_env.strip() == '*':
    origins = ['*']
else:
    origins = [o.strip() for o in origins_env.split(',') if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

@app.post('/login')
async def login(req: LoginRequest):
    """Authenticate with Firebase REST API and return our own JWT on success."""
    if not WEB_API_KEY:
        logger.error('FIREBASE_WEB_API_KEY not configured')
        raise HTTPException(status_code=500, detail='FIREBASE_WEB_API_KEY not configured')

    firebase_url = f'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={WEB_API_KEY}'
    req_payload = {'email': req.email, 'password': req.password, 'returnSecureToken': True}

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(firebase_url, json=req_payload, timeout=10.0)
        except httpx.RequestError as e:
            logger.exception('Error contacting Firebase')
            raise HTTPException(status_code=502, detail=f'Error contacting Firebase: {e}')

    # Handle non-200 responses from Firebase
    if resp.status_code != 200:
        try:
            err = resp.json()
            msg = err.get('error', {}).get('message', '')
        except Exception:
            msg = resp.text
        logger.info('Authentication failed for %s: %s', req.email, msg)
        raise HTTPException(status_code=401, detail=f'Authentication failed: {msg}')

    try:
        data = resp.json()
    except Exception as e:
        logger.exception('Failed to parse Firebase response')
        raise HTTPException(status_code=500, detail='Failed to parse response from Firebase')

    uid = data.get('localId')
    email = data.get('email')
    if not uid or not email:
        logger.error('Missing uid/email in Firebase response: %s', data)
        raise HTTPException(status_code=500, detail='Invalid response from Firebase')

    now = datetime.utcnow()
    token_payload = {
        'sub': uid,
        'email': email,
        'iat': int(now.timestamp()),
        'exp': int((now + timedelta(hours=1)).timestamp())
    }

    try:
        token = jwt.encode(token_payload, JWT_SECRET, algorithm='HS256')
        if isinstance(token, bytes):
            token = token.decode('utf-8')
    except Exception as e:
        logger.exception('Failed to encode JWT')
        raise HTTPException(status_code=500, detail='Failed to create access token')

    # Issue a refresh token and store it
    refresh = _create_refresh_token(uid, email)

    return {
        'access_token': token,
        'token_type': 'bearer',
        'uid': uid,
        'email': email,
        'refresh_token': refresh,
    }


@app.get('/ping')
async def ping():
    return {'ok': True}


# Simple in-memory blacklist for revoked tokens (development only).
# In production use a persistent store (Redis, database) with TTL.
_revoked_tokens = set()

# In-memory store for refresh tokens: token -> {uid, email, expires}
_refresh_tokens = {}
# Blacklist for revoked refresh tokens
_revoked_refresh_tokens = set()


class LogoutRequest(BaseModel):
    refresh_token: str


@app.post('/auth/logout')
async def logout(req: LogoutRequest):
    """Validate the provided JWT and add it to the in-memory blacklist.

    Request body: {"refresh_token": "<token>"}
    """
    token = req.refresh_token
    if not token:
        raise HTTPException(status_code=400, detail='refresh_token is required')

    # If refresh token already revoked, treat as success
    if token in _revoked_refresh_tokens:
        return {'message': 'Logged out successfully'}

    # Check presence in refresh store
    entry = _refresh_tokens.get(token)
    if not entry:
        # token not recognized
        raise HTTPException(status_code=401, detail='Invalid refresh token')

    # Revoke: remove from store and add to revoked set
    try:
        del _refresh_tokens[token]
    except KeyError:
        pass
    _revoked_refresh_tokens.add(token)
    logger.info('Revoked refresh token for uid=%s', entry.get('uid'))

    return {'message': 'Logged out successfully'}


def _create_refresh_token(uid: str, email: str, days: int = 30):
    token = secrets.token_urlsafe(48)
    expires = int((datetime.utcnow() + timedelta(days=days)).timestamp())
    _refresh_tokens[token] = {'uid': uid, 'email': email, 'expires': expires}
    return token


@app.post('/refresh')
async def refresh_token(body: dict):
    """Exchange a valid refresh token for a new access token.

    Expected body: {"refresh_token": "..."}
    """
    token = body.get('refresh_token')
    if not token:
        raise HTTPException(status_code=400, detail='refresh_token is required')

    if token in _revoked_refresh_tokens:
        raise HTTPException(status_code=401, detail='Refresh token revoked')

    entry = _refresh_tokens.get(token)
    if not entry:
        raise HTTPException(status_code=401, detail='Invalid refresh token')

    if entry.get('expires', 0) < int(datetime.utcnow().timestamp()):
        # expired
        # ensure it's removed
        try:
            del _refresh_tokens[token]
        except KeyError:
            pass
        raise HTTPException(status_code=401, detail='Refresh token expired')

    # Create new access token
    now = datetime.utcnow()
    payload = {
        'sub': entry['uid'],
        'email': entry['email'],
        'iat': int(now.timestamp()),
        'exp': int((now + timedelta(hours=1)).timestamp())
    }
    access = jwt.encode(payload, JWT_SECRET, algorithm='HS256')
    if isinstance(access, bytes):
        access = access.decode('utf-8')

    return {'access_token': access, 'token_type': 'bearer', 'uid': entry['uid'], 'email': entry['email']}

# Future: add endpoints to verify token, refresh tokens, use Firebase Admin SDK, etc.
