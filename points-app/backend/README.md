Points backend (FastAPI)

Quickstart
1. Copy `.env.example` to `.env` and set `FIREBASE_WEB_API_KEY` and `JWT_SECRET`.
2. (Optional) Place your Firebase admin private key JSON in `backend/secrets/firebase-admin.json` for future admin SDK use.
3. Create a venv and install dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

4. Run the server:

```powershell
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

Endpoint
- POST /login
  - body: {"email":"...","password":"..."}
  - success: 200 {"access_token":"...","token_type":"bearer","uid":"...","email":"..."}
  - failure: 401

Security notes
- This example uses the Firebase REST endpoint with your Web API key. Keep WEB API key private.
- Do NOT commit files in `backend/secrets/` or `.env` to source control.
