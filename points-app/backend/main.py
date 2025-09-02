"""
FastAPI backend for authentication.
- POST /login accepts {"email","password"}
- Calls Firebase REST API signInWithPassword using FIREBASE_WEB_API_KEY
- On success returns a JWT (HS256) containing sub (firebase uid) and email

Notes:
- Set FIREBASE_WEB_API_KEY and JWT_SECRET in environment or .env
- This implementation is intentionally minimal for the checkpoint.
"""

from fastapi import FastAPI, HTTPException, Depends, Header, status, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, EmailStr, constr, validator
from typing import Optional
import os
import httpx
import jwt
import secrets
import logging
from datetime import datetime, timedelta
from dotenv import load_dotenv
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import firebase_admin
from firebase_admin import credentials, firestore

load_dotenv()

WEB_API_KEY = os.getenv('FIREBASE_WEB_API_KEY')
JWT_SECRET = os.getenv('JWT_SECRET', 'change-me')

app = FastAPI(title='Points Auth Backend')

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger('main')
logger.setLevel(logging.DEBUG)

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


class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    accountName: constr(min_length=3, max_length=30)

    @validator('accountName')
    def strip_account_name(cls, v: str) -> str:
        return v.strip()


class FriendRequestCreate(BaseModel):
    senderId: str
    receiverId: str


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
    account_name = data.get('displayName')
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

    # Issue a refresh token and store it (preserve accountName if present)
    refresh = _create_refresh_token(uid, email, account_name)

    return {
        'access_token': token,
        'token_type': 'bearer',
        'uid': uid,
        'email': email,
        'accountName': account_name,
        'refresh_token': refresh,
    }


@app.post('/register')
async def register(req: RegisterRequest):
    """Create a new Firebase user via REST API (signUp).

    Returns 201 with uid and email on success.
    """
    if not WEB_API_KEY:
        logger.error('FIREBASE_WEB_API_KEY not configured')
        raise HTTPException(status_code=500, detail='FIREBASE_WEB_API_KEY not configured')

    firebase_url = f'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={WEB_API_KEY}'
    payload = {'email': req.email, 'password': req.password, 'returnSecureToken': True}

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(firebase_url, json=payload, timeout=10.0)
        except httpx.RequestError as e:
            logger.exception('Error contacting Firebase for register')
            raise HTTPException(status_code=502, detail=f'Error contacting Firebase: {e}')

    if resp.status_code != 200:
        try:
            err = resp.json()
            msg = err.get('error', {}).get('message', '')
        except Exception:
            msg = resp.text
        logger.info('Registration failed for %s: %s', req.email, msg)
        raise HTTPException(status_code=400, detail=f'Registration failed: {msg}')

    data = resp.json()
    uid = data.get('localId')
    email = data.get('email')
    if not uid or not email:
        logger.error('Missing uid/email in Firebase register response: %s', data)
        raise HTTPException(status_code=500, detail='Invalid response from Firebase')

    # Persist to Firestore users/{uid}
    if not _firebase_initialized or _firestore_client is None:
        logger.error('Firestore not initialized; cannot persist user')
        # Attempt to delete the created Firebase user to avoid inconsistent state
        try:
            firebase_admin.auth.delete_user(uid)
        except Exception:
            logger.exception('Failed to delete Firebase user after missing Firestore')
        raise HTTPException(status_code=501, detail='Firestore not configured; user creation rolled back')

    try:
        users_ref = _firestore_client.collection('users')
        users_ref.document(uid).set({
            'uid': uid,
            'email': email,
            'accountName': req.accountName,
            'createdAt': firestore.SERVER_TIMESTAMP,
        })
    except Exception:
        logger.exception('Failed to write user to Firestore; rolling back')
        # Rollback: delete the user from Firebase Auth
        try:
            firebase_admin.auth.delete_user(uid)
        except Exception:
            logger.exception('Failed to delete Firebase user during rollback')
        raise HTTPException(status_code=500, detail='Failed to persist user data; user creation rolled back')

    # Return created user info including accountName
    return JSONResponse(status_code=201, content={'uid': uid, 'email': email, 'accountName': req.accountName})


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

# Initialize Firebase Admin if service account is present
_firestore_client = None
_firebase_initialized = False
service_account_path = os.path.join(os.path.dirname(__file__), 'secrets', 'firebase-admin.json')
if os.path.exists(service_account_path):
    try:
        cred = credentials.Certificate(service_account_path)
        firebase_admin.initialize_app(cred)
        _firestore_client = firestore.client()
        _firebase_initialized = True
        logger.info('Initialized Firebase Admin SDK')
    except Exception:
        logger.exception('Failed to initialize Firebase Admin SDK')
else:
    logger.warning('Firebase service account not found at %s', service_account_path)


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


def _create_refresh_token(uid: str, email: str, account_name: Optional[str] = None, days: int = 30):
    token = secrets.token_urlsafe(48)
    expires = int((datetime.utcnow() + timedelta(days=days)).timestamp())
    # accountName may be optional
    _refresh_tokens[token] = {'uid': uid, 'email': email, 'expires': expires, 'accountName': account_name}
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

    return {'access_token': access, 'token_type': 'bearer', 'uid': entry['uid'], 'email': entry['email'], 'accountName': entry.get('accountName')}


def _verify_access_token(request: Request, authorization: Optional[str] = Header(None)) -> dict:
    """Verify HS256 access token from Authorization header.

    This dependency reads the standard `Authorization` header (case-insensitive),
    falls back to inspecting request.headers, strips surrounding quotes, accepts
    either 'Bearer <token>' or just the raw token (useful for debugging), and
    logs the raw header and decoded payload for traceability.
    """
    # Try header provided by FastAPI Header param first
    raw = authorization

    # Fallback: inspect request headers (case-insensitive)
    if not raw and request is not None:
        raw = request.headers.get('authorization') or request.headers.get('Authorization') or request.headers.get('auth-header')

    # Helpful debug: log request path/method and headers (may contain Authorization)
    try:
        logger.debug('Incoming request: %s %s', request.method, request.url.path)
        # Convert headers to a regular dict for clearer logging
        logger.debug('Request headers: %s', dict(request.headers))
    except Exception:
        logger.debug('Could not log request headers')

    logger.debug('Authorization header raw: %s', raw)

    if not raw:
        logger.warning('Authorization header missing')
        raise HTTPException(status_code=401, detail='Authorization header missing')

    # Normalize and strip possible surrounding quotes
    raw = raw.strip().strip('"').strip("'")

    parts = raw.split()
    token = None
    # Accept both 'Bearer <token>' and raw token formats (dev/debugging convenience)
    if len(parts) >= 2 and parts[0].lower() == 'bearer':
        token = parts[1]
    elif len(parts) == 1:
        token = parts[0]
    else:
        logger.warning('Invalid authorization header format: %s', raw)
        raise HTTPException(status_code=401, detail='Invalid authorization header')

    # Log server time and unverified token claims to detect clock skew
    try:
        server_ts = int(datetime.utcnow().timestamp())
        logger.debug('Server UTC timestamp: %s', server_ts)
        # Get unverified claims (no signature/exp/iat verification) to inspect iat/exp
        unverified = jwt.decode(token, options={"verify_signature": False, "verify_exp": False, "verify_iat": False})
        logger.debug('Unverified token claims: %s', unverified)
        token_iat = unverified.get('iat')
        token_exp = unverified.get('exp')
        if token_iat is not None:
            logger.debug('Token iat=%s, exp=%s (server_ts=%s)', token_iat, token_exp, server_ts)
    except Exception:
        logger.debug('Failed to decode token without verification for diagnostics', exc_info=True)

    # Allow optional leeway for dev debugging via env var JWT_LEEWAY (seconds). Default 0.
    try:
        leeway = int(os.getenv('JWT_LEEWAY', '0'))
    except Exception:
        leeway = 0

    try:
        # IMPORTANT: disable iat validation because some tokens (e.g. Firebase-issued)
        # may have 'iat' values that are slightly in the future due to clock skew
        # between issuer and validator. We still want to validate 'exp' (expiry)
        # and 'nbf' (not-before) if present. PyJWT allows disabling specific
        # claim validations via the `options` parameter.
        options = {
            'verify_signature': True,
            'verify_exp': True,
            'verify_nbf': True,
            # Turn off iat verification to avoid ImmatureSignatureError
            'verify_iat': False,
        }

        # Decode with explicit options and optional leeway (seconds)
        payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'], options=options, leeway=leeway)
        logger.debug('Decoded JWT payload: %s', payload)
    except jwt.ExpiredSignatureError:
        logger.exception('Token expired while decoding')
        raise HTTPException(status_code=401, detail='Token expired')
    except jwt.ImmatureSignatureError:
        # With verify_iat=False this should not normally occur, but keep handling
        logger.exception('Token not yet valid (iat)')
        raise HTTPException(status_code=401, detail='Token not yet valid (iat)')
    except Exception as e:
        logger.exception('Invalid token while decoding: %s', e)
        raise HTTPException(status_code=401, detail='Invalid token')
    return payload


@app.post('/friend_requests')
async def create_friend_request(req: FriendRequestCreate, token_payload: dict = Depends(_verify_access_token), request: Request = None):
    """Create a friend request document in Firestore.

    Rules:
    - Caller must be authenticated.
    - senderId must match authenticated sub (uid).
    - senderId != receiverId.
    - No existing pending request from sender to receiver.
    """
    # Trace: log body + auth payload early for debugging
    try:
        logger.info('create_friend_request called; body=%s auth_payload=%s', req.dict(), token_payload)
        logger.debug('Request headers at friend_requests: %s', dict(request.headers) if request is not None else None)
    except Exception:
        logger.debug('Failed logging friend request debug info')

    if not _firebase_initialized or _firestore_client is None:
        raise HTTPException(status_code=501, detail='Firestore not configured on backend')

    sender = (req.senderId or '').strip()
    receiver = (req.receiverId or '').strip()

    if not sender or not receiver:
        raise HTTPException(status_code=400, detail='senderId and receiverId are required')

    # Ensure the authenticated user is the sender
    auth_sub = token_payload.get('sub')
    if auth_sub != sender:
        raise HTTPException(status_code=403, detail='senderId does not match authenticated user')

    if sender == receiver:
        raise HTTPException(status_code=400, detail='Cannot send friend request to yourself')

    try:
        users_ref = _firestore_client.collection('friend_requests')

        # Check for existing pending request from sender -> receiver
        import asyncio
        loop = asyncio.get_event_loop()

        def _query_pending():
            q = users_ref.where('senderId', '==', sender).where('receiverId', '==', receiver).where('status', '==', 'pending').limit(1).get()
            return list(q)

        pending_docs = await loop.run_in_executor(None, _query_pending)
        if pending_docs:
            raise HTTPException(status_code=409, detail='A pending friend request already exists')

        # Read sender and receiver profiles to denormalize display names and emails
        sender_profile = None
        receiver_profile = None
        try:
            sender_doc = _firestore_client.collection('users').document(sender).get()
            if sender_doc.exists:
                sender_profile = sender_doc.to_dict()
        except Exception:
            logger.debug('Failed to read sender profile for %s', sender, exc_info=True)

        try:
            receiver_doc = _firestore_client.collection('users').document(receiver).get()
            if receiver_doc.exists:
                receiver_profile = receiver_doc.to_dict()
        except Exception:
            logger.debug('Failed to read receiver profile for %s', receiver, exc_info=True)

        def _extract_name_and_email(profile):
            if not profile:
                return (None, None)
            name = profile.get('accountName') or profile.get('displayName') or profile.get('name') or profile.get('email')
            email = profile.get('email')
            return (name, email)

        sender_name, sender_email = _extract_name_and_email(sender_profile)
        receiver_name, receiver_email = _extract_name_and_email(receiver_profile)

        # Create friend request with denormalized sender/receiver metadata
        doc_ref = users_ref.document()
        payload = {
            'senderId': sender,
            'receiverId': receiver,
            'status': 'pending',
            'createdAt': firestore.SERVER_TIMESTAMP,
        }
        if sender_name:
            payload['senderDisplayName'] = sender_name
        if sender_email:
            payload['senderEmail'] = sender_email
        if receiver_name:
            payload['receiverDisplayName'] = receiver_name
        if receiver_email:
            payload['receiverEmail'] = receiver_email

        doc_ref.set(payload)

        return JSONResponse(status_code=201, content={'message': 'Friend request created', 'requestId': doc_ref.id})

    except HTTPException:
        raise
    except Exception:
        logger.exception('Failed to create friend request from %s to %s', sender, receiver)
        raise HTTPException(status_code=500, detail='Failed to create friend request')


@app.get('/users/search')
async def users_search(query: str):
    """Search users by accountName or email using prefix matching.

    Note: Firestore does not support arbitrary substring contains efficiently.
    This endpoint performs prefix (startsWith) matches using range queries.
    """
    if not _firebase_initialized or _firestore_client is None:
        raise HTTPException(status_code=501, detail='Firestore not configured on the backend')

    q = (query or '').strip()
    if not q:
        return []

    # For prefix queries, use range trick: field >= q and field <= q + '\uf8ff'
    end = q + '\uf8ff'
    results = {}

    try:
        users_ref = _firestore_client.collection('users')

        # Try searching accountName field (case-sensitive). Projects should maintain a lowercased index if needed.
        acct_query = users_ref.where('accountName', '>=', q).where('accountName', '<=', end).limit(50).stream()
        async for doc in _aiter_firestore_stream(acct_query):
            data = doc.to_dict()
            results[doc.id] = {'userId': doc.id, 'accountName': data.get('accountName'), 'email': data.get('email')}

        # Search email field
        email_query = users_ref.where('email', '>=', q).where('email', '<=', end).limit(50).stream()
        async for doc in _aiter_firestore_stream(email_query):
            data = doc.to_dict()
            results[doc.id] = {'userId': doc.id, 'accountName': data.get('accountName'), 'email': data.get('email')}

    except Exception:
        logger.exception('Error querying Firestore for users')
        raise HTTPException(status_code=500, detail='Error querying Firestore')

    return list(results.values())


async def _aiter_firestore_stream(stream):
    """Helper to iterate over Firestore python synchronous stream in async context.

    Firestore Python client returns a generator; to avoid blocking the event loop, yield from it in a thread.
    """
    # Since firestore.stream() is blocking, run in thread and yield results
    import asyncio
    loop = asyncio.get_event_loop()
    gen = stream

    def _collect():
        return list(gen)

    docs = await loop.run_in_executor(None, _collect)
    for d in docs:
        yield d


@app.get('/users/{uid}')
async def get_user_by_uid(uid: str):
    """Return user document stored in Firestore at users/{uid}.

    Returns 404 if not found. Requires Firestore to be configured.
    """
    if not _firebase_initialized or _firestore_client is None:
        raise HTTPException(status_code=501, detail='Firestore not configured')

    try:
        users_ref = _firestore_client.collection('users')

        import asyncio
        loop = asyncio.get_event_loop()

        def _get_doc():
            return users_ref.document(uid).get()

        doc = await loop.run_in_executor(None, _get_doc)
        if not doc.exists:
            raise HTTPException(status_code=404, detail='User not found')
        data = doc.to_dict()
        return {'uid': uid, 'email': data.get('email'), 'accountName': data.get('accountName')}
    except HTTPException:
        raise
    except Exception:
        logger.exception('Error fetching user %s from Firestore', uid)
        raise HTTPException(status_code=500, detail='Error fetching user')

# Future: add endpoints to verify token, refresh tokens, use Firebase Admin SDK, etc.
