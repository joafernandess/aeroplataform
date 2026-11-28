"""
Automatic Pix through Mercado Pago (optional).

The bot creates a Pix charge for the ticket, shows the copy-and-paste code and
QR, then POLLS the payment status. There is no webhook, so nothing public has
to be exposed and nobody can fake a "payment received" request: the only thing
that delivers a key is the bot asking Mercado Pago itself and getting
status == approved for the right amount and the right ticket.

Enabled only when MERCADOPAGO_ACCESS_TOKEN is set. Not verified against the
live Mercado Pago API from this code base (no credentials here): test with a
small amount before trusting it with real sales.
"""
import base64

import aiohttp

import config


class PaymentError(Exception):
    """Mercado Pago refused or could not be reached; str() is loggable."""


class MercadoPagoClient:
    def __init__(
        self,
        token: str = config.MERCADOPAGO_ACCESS_TOKEN,
        base_url: str = config.MERCADOPAGO_API_URL,
        payer_email: str = config.MERCADOPAGO_PAYER_EMAIL,
        timeout: float = 15.0,
    ) -> None:
        self._token = token
        self._base = base_url.rstrip("/")
        self._email = payer_email
        self._timeout = aiohttp.ClientTimeout(total=timeout)

    def _headers(self, extra: dict | None = None) -> dict:
        headers = {
            "Authorization": f"Bearer {self._token}",
            "Content-Type": "application/json",
        }
        headers.update(extra or {})
        return headers

    async def _request(
        self, method: str, path: str, json: dict | None = None,
        headers: dict | None = None,
    ) -> dict:
        try:
            async with aiohttp.ClientSession(timeout=self._timeout) as session:
                async with session.request(
                    method, f"{self._base}{path}", json=json,
                    headers=self._headers(headers),
                ) as resp:
                    try:
                        data = await resp.json(content_type=None)
                    except ValueError:
                        data = {}
                    if resp.status >= 400:
                        detail = ""
                        if isinstance(data, dict):
                            detail = str(data.get("message") or data.get("error") or "")
                        raise PaymentError(
                            f"Mercado Pago answered {resp.status}: {detail or 'no detail'}"
                        )
        except (aiohttp.ClientError, TimeoutError) as exc:
            raise PaymentError(f"Could not reach Mercado Pago: {exc}") from exc
        return data if isinstance(data, dict) else {}

    @staticmethod
    def _normalize(data: dict) -> dict:
        tx = (data.get("point_of_interaction") or {}).get("transaction_data") or {}
        try:
            amount = float(data.get("transaction_amount"))
        except (TypeError, ValueError):
            amount = 0.0
        return {
            "id": str(data.get("id") or ""),
            "status": str(data.get("status") or ""),
            "amount": amount,
            "reference": (
                str(data["external_reference"])
                if data.get("external_reference") is not None else None
            ),
            "qr_code": tx.get("qr_code"),
            "qr_png": _decode_png(tx.get("qr_code_base64")),
        }

    async def create_pix(
        self, amount: float, description: str, reference: str, idempotency_key: str
    ) -> dict:
        """Creates a Pix charge. `reference` comes back on the payment."""
        data = await self._request(
            "POST", "/v1/payments",
            json={
                "transaction_amount": round(float(amount), 2),
                "description": description[:200],
                "payment_method_id": "pix",
                "external_reference": reference,
                "payer": {"email": self._email},
            },
            headers={"X-Idempotency-Key": idempotency_key},
        )
        payment = self._normalize(data)
        if not payment["id"] or not payment["qr_code"]:
            raise PaymentError("Mercado Pago did not return a Pix code.")
        return payment

    async def get_payment(self, payment_id: str) -> dict:
        data = await self._request("GET", f"/v1/payments/{payment_id}")
        return self._normalize(data)


def _decode_png(value: str | None) -> bytes | None:
    if not value:
        return None
    try:
        return base64.b64decode(value, validate=False)
    except (ValueError, TypeError):
        return None
