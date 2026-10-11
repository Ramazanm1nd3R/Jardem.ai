"""Demo-grade authentication: signed bearer tokens, no passwords stored.

Citizens sign in by phone number without an SMS code and staff accounts share a PIN from
configuration. That is enough to separate roles in the prototype; a pilot needs real
identity (SMS OTP / eGov IDP for citizens, agency SSO for staff).
"""

from __future__ import annotations

import hashlib
import time
from dataclasses import dataclass

import jwt

TOKEN_TTL_S = 30 * 24 * 3600


@dataclass(frozen=True, slots=True)
class Principal:
    role: str  # citizen | responder | dispatcher
    sub: str
    name: str = ""
    phone: str = ""
    unit_id: str | None = None


def citizen_id(phone: str) -> str:
    digits = "".join(ch for ch in phone if ch.isdigit())
    return "cit-" + hashlib.sha256(digits.encode()).hexdigest()[:12]


def make_token(principal: Principal, secret: str, now: float | None = None) -> str:
    issued = int(now if now is not None else time.time())
    payload = {"sub": principal.sub, "role": principal.role, "name": principal.name,
               "phone": principal.phone, "unit": principal.unit_id, "iat": issued,
               "exp": issued + TOKEN_TTL_S}
    return jwt.encode(payload, secret, algorithm="HS256")


def read_token(token: str, secret: str) -> Principal | None:
    try:
        data = jwt.decode(token, secret, algorithms=["HS256"])
    except jwt.PyJWTError:
        return None
    return Principal(data["role"], data["sub"], data.get("name", ""), data.get("phone", ""),
                     data.get("unit"))
