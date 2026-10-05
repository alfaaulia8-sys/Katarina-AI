from __future__ import annotations

import json
from enum import Enum
from typing import Any


class CanonicalizationError(ValueError):
    """Raised when a value cannot be deterministically serialized."""


def _normalize(value: Any) -> Any:
    if value is None or isinstance(value, (bool, int, str)):
        return value

    if isinstance(value, bytes):
        return {"$bytes_hex": value.hex()}

    if isinstance(value, Enum):
        return _normalize(value.value)

    if isinstance(value, tuple):
        return [_normalize(item) for item in value]

    if isinstance(value, list):
        return [_normalize(item) for item in value]

    if isinstance(value, dict):
        normalized: dict[str, Any] = {}
        for key, item in value.items():
            if not isinstance(key, str):
                raise CanonicalizationError(
                    "canonical dictionaries require string keys"
                )
            normalized[key] = _normalize(item)
        return normalized

    if isinstance(value, float):
        raise CanonicalizationError(
            "floats are forbidden in deterministic persistence records; "
            "use fixed-point integer units"
        )

    raise CanonicalizationError(
        f"unsupported canonical value type: {type(value).__name__}"
    )


def canonical_json_bytes(value: Any) -> bytes:
    """Return deterministic UTF-8 JSON bytes.

    The representation is deliberately narrow:
    - dictionary keys are strings and sorted by json.dumps;
    - whitespace is removed;
    - UTF-8 is emitted directly;
    - bytes use an explicit tagged hexadecimal representation;
    - floats are rejected so platform/runtime floating semantics cannot alter
      durable record identity.
    """

    normalized = _normalize(value)
    try:
        text = json.dumps(
            normalized,
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=False,
            allow_nan=False,
        )
    except (TypeError, ValueError) as exc:
        raise CanonicalizationError(str(exc)) from exc
    return text.encode("utf-8")


def canonical_json_text(value: Any) -> str:
    return canonical_json_bytes(value).decode("utf-8")


__all__ = (
    "CanonicalizationError",
    "canonical_json_bytes",
    "canonical_json_text",
)
