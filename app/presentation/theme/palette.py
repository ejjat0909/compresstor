"""Color palette tokens (Tailwind-inspired) for the dark theme.

Every color the UI needs lives here; QSS and custom painting read from
these tokens so a single accent change re-themes the whole app.

Compresstor is dark-only: the light palette was removed deliberately.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Palette:
    # surfaces
    bg: str
    card: str
    card_hover: str
    input: str
    input_hover: str
    # borders
    border: str
    border_soft: str
    border_strong: str
    # text
    text: str
    text_secondary: str
    text_muted: str
    text_inverse: str
    # hover overlays
    hover: str
    active: str
    # accent (primary)
    accent: str
    accent_hover: str
    accent_active: str
    accent_soft: str
    accent_foreground: str
    # semantic
    success: str
    success_soft: str
    warning: str
    warning_soft: str
    danger: str
    danger_soft: str
    danger_hover: str
    info: str
    info_soft: str
    # misc
    scrollbar: str
    scrollbar_hover: str
    selection: str
    shadow: str
    skeleton: str
    header: str
    sidebar: str
    # modal extras
    overlay: str = "rgba(0,0,0,0.45)"   # modal scrim
    backdrop: str = "rgba(0,0,0,0.28)"  # page backdrop


DARK = Palette(
    bg="#020617",                  # slate-950
    card="#0f172a",                # slate-900
    card_hover="#111c31",
    input="#0f172a",
    input_hover="#17223b",
    border="#1e293b",              # slate-800
    border_soft="#16233a",
    border_strong="#334155",       # slate-700
    text="#f1f5f9",                # slate-100
    text_secondary="#94a3b8",      # slate-400
    text_muted="#64748b",          # slate-500
    text_inverse="#ffffff",
    hover="rgba(241,245,249,0.06)",
    active="rgba(241,245,249,0.10)",
    accent="#3b82f6",              # blue-500 (brighter for dark bg)
    accent_hover="#2563eb",        # blue-600
    accent_active="#1d4ed8",       # blue-700
    accent_soft="rgba(59,130,246,0.16)",
    accent_foreground="#ffffff",
    success="#10b981",             # emerald-500
    success_soft="rgba(16,185,129,0.14)",
    warning="#f59e0b",             # amber-500
    warning_soft="rgba(245,158,11,0.14)",
    danger="#ef4444",              # red-500
    danger_soft="rgba(239,68,68,0.14)",
    danger_hover="#dc2626",
    info="#38bdf8",                # sky-400
    info_soft="rgba(56,189,248,0.14)",
    scrollbar="rgba(100,116,139,0.30)",
    scrollbar_hover="rgba(100,116,139,0.5)",
    selection="rgba(59,130,246,0.25)",
    shadow="rgba(0,0,0,0.4)",
    skeleton="rgba(100,116,139,0.2)",
    header="#0b1322",
    sidebar="#0b1322",
)


def hex_to_rgba(hex_color: str, alpha: float) -> str:
    """Convert #rrggbb (or #rgb) to an rgba() string."""
    h = hex_color.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    r, g, b = (int(h[i : i + 2], 16) for i in (0, 2, 4))
    return f"rgba({r},{g},{b},{alpha})"
