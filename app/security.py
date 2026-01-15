from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import time
from typing import Any, Dict, Optional
from app.config import settings


def _b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("utf-8").rstrip("=")


def _b64url_decode(data: str) -> bytes:
    pad = "=" * (-len(data) % 4)
    return base64.urlsafe_b64decode(data + pad)


def sign_payload(payload: Dict[str, Any]) -> str:
    body = json.dumps(payload, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    b64 = _b64url_encode(body)
    sig = hmac.new(settings.hmac_secret.encode("utf-8"), b64.encode("utf-8"), hashlib.sha256).digest()
    return f"{b64}.{_b64url_encode(sig)}"


def verify_payload(token: str, max_age_seconds: int = 7 * 24 * 3600) -> Optional[Dict[str, Any]]:
    try:
        b64, sig = token.split(".", 1)
        expected = hmac.new(settings.hmac_secret.encode("utf-8"), b64.encode("utf-8"), hashlib.sha256).digest()
        if not hmac.compare_digest(_b64url_encode(expected), sig):
            return None
        data = json.loads(_b64url_decode(b64).decode("utf-8"))
        ts = int(data.get("ts", 0))
        now = int(time.time())
        if ts <= 0 or abs(now - ts) > max_age_seconds:
            return None
        return data
    except Exception:
        return None


def new_nonce(n: int = 10) -> str:
    return _b64url_encode(os.urandom(n))
