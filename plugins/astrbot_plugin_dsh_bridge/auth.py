"""Owner/private-chat authorization for the /dsh bridge."""

from __future__ import annotations

from collections.abc import Iterable

from astrbot.api.message_components import Plain


def parse_owner_ids(raw: object) -> set[str]:
    """Parse comma-separated owner IDs without wildcards.

    Args:
        raw: A string, iterable of IDs, or an empty value from plugin config.

    Returns:
        The normalized set of owner IDs. Wildcards are ignored.
    """
    if raw is None:
        return set()
    if isinstance(raw, (list, tuple, set)):
        values = [str(item) for item in raw]
    else:
        values = str(raw).replace("，", ",").split(",")
    return {value.strip() for value in values if value.strip() and value.strip() != "*"}


def parse_platform_names(raw: object) -> set[str]:
    """Parse allowed platform adapter names.

    Args:
        raw: A comma-separated string or iterable of platform names.

    Returns:
        Lowercase platform adapter names.
    """
    if raw is None:
        return {"aiocqhttp", "qq"}
    if isinstance(raw, (list, tuple, set)):
        values: Iterable[object] = raw
    else:
        values = str(raw).replace("，", ",").split(",")
    return {str(value).strip().lower() for value in values if str(value).strip()}


def is_owner_event(
    event: object,
    owner_ids: set[str],
    platform_names: set[str],
) -> bool:
    """Return whether an event is an allowed owner private text message.

    Args:
        event: AstrBot message event.
        owner_ids: Allowed sender IDs.
        platform_names: Allowed platform adapter names.

    Returns:
        True only for a private, owner-authored, plain-text event on an allowed
        platform. Any missing attribute or non-text component fails closed.
    """
    try:
        if not owner_ids:
            return False
        if not bool(event.is_private_chat()):
            return False
        if str(event.get_platform_name()).lower() not in platform_names:
            return False
        if str(event.get_sender_id()) not in owner_ids:
            return False
        messages = event.get_messages()
        if messages:
            for component in messages:
                if not isinstance(component, Plain):
                    return False
        return True
    except Exception:
        return False
