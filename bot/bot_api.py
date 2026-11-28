"""
Client the bot uses to talk to the private loader API (internal_api.py).

The bot never touches the dashboard: it sends authenticated requests to
INTERNAL_API_URL with BOT_API_TOKEN and gets back the loader to deliver.
"""
import re

import aiohttp

import config


class BotApiError(Exception):
    """Refusal or failure from the private API; str() is user-facing."""

    def __init__(self, message: str, code: str = "error") -> None:
        super().__init__(message)
        self.code = code


class BotApiClient:
    def __init__(
        self,
        base_url: str = config.INTERNAL_API_URL,
        token: str = config.BOT_API_TOKEN,
        timeout: float = 10.0,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._token = token
        self._timeout = aiohttp.ClientTimeout(total=timeout)
        self._session: aiohttp.ClientSession | None = None

    async def _http(self) -> aiohttp.ClientSession:
        if self._session is None or self._session.closed:
            self._session = aiohttp.ClientSession(
                timeout=self._timeout,
                headers={"Authorization": f"Bearer {self._token}"},
            )
        return self._session

    async def close(self) -> None:
        if self._session is not None and not self._session.closed:
            await self._session.close()

    async def _request(self, method: str, path: str, payload: dict | None = None) -> dict:
        session = await self._http()
        try:
            async with session.request(
                method, f"{self.base_url}{path}", json=payload
            ) as resp:
                try:
                    data = await resp.json(content_type=None)
                except ValueError:
                    data = {}
        except (aiohttp.ClientError, TimeoutError) as exc:
            raise BotApiError(
                "The loader service is unavailable right now. Try again in a moment.",
                "unavailable",
            ) from exc
        if not isinstance(data, dict):
            data = {}
        if resp.status >= 400 or not data.get("ok"):
            raise BotApiError(
                str(data.get("error") or f"Loader service error ({resp.status})."),
                str(data.get("code") or "error"),
            )
        return data

    # ------------------------------------------------------------------
    # Aero Platform mode: games/loader come from the platform (Netlify API)
    # instead of the bot's own (disabled) internal API.
    # ------------------------------------------------------------------
    @staticmethod
    def _slug(name: str) -> str:
        return re.sub(r"[^a-z0-9]+", "-", str(name or "").lower()).strip("-")[:40] or "game"

    async def _platform(self, path: str) -> dict:
        session = await self._http()
        try:
            async with session.get(
                f"{config.PLATFORM_API_URL}{path}",
                headers={"Authorization": f"Bearer {config.PLATFORM_API_TOKEN}"},
            ) as resp:
                data = await resp.json(content_type=None)
        except (aiohttp.ClientError, TimeoutError, ValueError) as exc:
            raise BotApiError(
                "The loader service is unavailable right now. Try again in a moment.",
                "unavailable",
            ) from exc
        if not isinstance(data, dict) or not data.get("ok"):
            raise BotApiError("The loader service returned an error.", "error")
        return data.get("data")

    async def _platform_key(self, key: str) -> dict | None:
        from urllib.parse import quote
        data = await self._platform(f"/api/v1/keys?search={quote(key)}&limit=5")
        for row in (data or {}).get("rows", []):
            if row.get("key") == key:
                return row
        return None

    async def _platform_games(self, key_row: dict) -> list[dict]:
        scripts = await self._platform("/api/v1/scripts")
        games, seen = [], set()
        for sc in scripts or []:
            if not sc.get("enabled") or not sc.get("game_id"):
                continue
            if key_row.get("script_id"):
                if sc["id"] != key_row["script_id"]:
                    continue
            elif key_row.get("product_id") and sc.get("product_id") != key_row["product_id"]:
                continue
            if sc["game_id"] in seen:
                continue
            seen.add(sc["game_id"])
            games.append({"id": sc["game_id"], "slug": self._slug(sc.get("game_name")),
                          "name": sc.get("game_name") or "Game"})
        return games

    async def _platform_loader(self, key: str, game: str, discord_id: int) -> dict:
        row = await self._platform_key(key)
        if row is None:
            raise BotApiError("Invalid or unknown key.", "invalid_key")
        if row.get("discord_id") and str(row["discord_id"]) != str(discord_id):
            raise BotApiError("This key belongs to another user.", "forbidden")
        status = row.get("status")
        if status != "active":
            msgs = {"revoked": "This key has been revoked.", "banned": "This key has been banned.",
                    "expired": "This key has expired."}
            raise BotApiError(msgs.get(status, "This key is not active."), "forbidden")
        games = await self._platform_games(row)
        if not games:
            raise BotApiError("No game with a loader is available for your key right now.", "unavailable")
        picked = None
        if game:
            picked = next((g for g in games if g["slug"] == game), None)
            if picked is None:
                raise BotApiError("That game is not available for your key.", "unavailable")
        try:
            with open(config.LOADER_TEMPLATE, "r", encoding="utf-8") as fh:
                template = fh.read()
        except OSError as exc:
            raise BotApiError("The loader template was not found on the server.", "server_error") from exc
        script = (template.replace("{script_key}", key)
                  .replace("{api_url}", config.PLATFORM_API_URL.rstrip("/"))
                  .replace("{game}", picked["slug"] if picked else ""))
        shown = picked or {"id": 0, "slug": "all", "name": "all games"}
        return {"ok": True, "script": script, "game": shown,
                "loader": {"id": "platform", "version": 1, "updated_at": 0}}

    # ------------------------------------------------------------------
    async def games(self, key: str) -> list[dict]:
        """Games this key can request a loader for: [{id, slug, name}]."""
        if config.PLATFORM_ENABLED:
            row = await self._platform_key(key)
            return await self._platform_games(row) if row else []
        data = await self._request("POST", "/internal/v1/games", {"key": key})
        return list(data.get("games") or [])

    async def loader(self, key: str, game: str, discord_id: int) -> dict:
        """{script, game: {id, slug, name}, loader: {id, version, updated_at}}"""
        if config.PLATFORM_ENABLED:
            return await self._platform_loader(key, game, discord_id)
        return await self._request(
            "POST",
            "/internal/v1/loader",
            {"key": key, "game": game, "discord_id": str(discord_id)},
        )

    async def heartbeat(self, status: dict) -> None:
        if config.PLATFORM_ENABLED:
            return  # the platform has no bot-status endpoint
        await self._request("POST", "/internal/v1/heartbeat", status)
