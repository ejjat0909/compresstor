"""Color palette tokens (Tailwind-inspired) for light and dark themes.

Every color the UI needs lives here; QSS and custom painting read from
these tokens so a single accent change re-themes the whole app.
"""

from __future__ import annotations

from dataclasses import dataclass, field


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
    # dark-mode extras
    overlay: str = "rgba(0,0,0,0.45)"   # modal scrim
    backdrop: str = "rgba(0,0,0,0.28)"  # page backdrop


LIGHT = Palette(
    bg="#f8fafc",                  # slate-50
    card="#ffffff",
    card_hover="#fbfcfd",
    input="#ffffff",
    input_hover="#f8fafc",
    border="#e2e8f0",              # slate-200
    border_soft="#f1f5f9",         # slate-100
    border_strong="#cbd5e1",       # slate-300
    text="#0f172a",                # slate-900
    text_secondary="#475569",      # slate-600
    text_muted="#94a3b8",          # slate-400
    text_inverse="#ffffff",
    hover="rgba(15,23,42,0.05)",
    active="rgba(15,23,42,0.08)",
    accent="#2563eb",              # blue-600
    accent_hover="#1d4ed8",        # blue-700
    accent_active="#1e40af",       # blue-800
    accent_soft="rgba(37,99,235,0.10)",
    accent_foreground="#ffffff",
    success="#059669",             # emerald-600
    success_soft="rgba(5,150,105,0.10)",
    warning="#d97706",             # amber-600 (amber-500 too light on white)
    warning_soft="rgba(217,119,6,0.10)",
    danger="#dc2626",              # red-600
    danger_soft="rgba(220,38,38,0.10)",
    danger_hover="#b91c1c",        # red-700
    info="#0ea5e9",                # sky-500
    info_soft="rgba(14,165,233,0.10)",
    scrollbar="rgba(100,116,139,0.35)",
    scrollbar_hover="rgba(100,116,139,0.55)",
    selection="rgba(37,99,235,0.18)",
    shadow="rgba(15,23,42,0.08)",
    skeleton="rgba(148,163,184,0.18)",
    header="#ffffff",
    sidebar="#ffffff",
)

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
