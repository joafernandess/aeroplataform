"""
Fixed-window rate limiter shared by the public API, the private bot API
and the dashboard login.
"""
import time


class RateLimiter:
    def __init__(self, limit: int, window: float = 60.0, max_entries: int = 5000) -> None:
        self.limit = limit
        self.window = window
        self.max_entries = max_entries
        self._hits: dict[str, list] = {}

    def hit(self, bucket: str) -> bool:
        """Counts one request. True when the bucket is over the limit."""
        now = time.time()
        if len(self._hits) > self.max_entries:
            self._hits.clear()
        entry = self._hits.get(bucket)
        if entry is None or now - entry[0] >= self.window:
            self._hits[bucket] = [now, 1]
            return False
        entry[1] += 1
        return entry[1] > self.limit

    def over(self, bucket: str) -> bool:
        """True when the bucket is already over the limit (counts nothing)."""
        entry = self._hits.get(bucket)
        if entry is None or time.time() - entry[0] >= self.window:
            return False
        return entry[1] > self.limit

    def reset(self, bucket: str) -> None:
        self._hits.pop(bucket, None)

    def clear(self) -> None:
        self._hits.clear()
