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
import logging
from datetime import datetime, timedelta
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware

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
        # PyJWT may return bytes in some versions; ensure string
        if isinstance(token, bytes):
            token = token.decode('utf-8')
    except Exception as e:
        logger.exception('Failed to encode JWT')
        raise HTTPException(status_code=500, detail='Failed to create access token')

    return {'access_token': token, 'token_type': 'bearer', 'uid': uid, 'email': email}


@app.get('/ping')
async def ping():
    return {'ok': True}

# Future: add endpoints to verify token, refresh tokens, use Firebase Admin SDK, etc.
