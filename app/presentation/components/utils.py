"""Small formatting utilities used across the UI."""

from __future__ import annotations

from datetime import datetime


def format_size(num_bytes: int) -> str:
    """Human-readable file size (B, KB, MB, GB)."""
    size = float(num_bytes)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if size < 1024 or unit == "TB":
            if unit == "B":
                return f"{int(size)} {unit}"
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def format_timestamp(ts: float) -> str:
    return datetime.fromtimestamp(ts).strftime("%b %d, %Y  %H:%M")
