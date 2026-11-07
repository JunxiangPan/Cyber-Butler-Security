from __future__ import annotations

# SERVICE_SYS_PATH_GUARD
import os as _cb_os
import sys as _cb_sys
_cb_webui = _cb_os.path.dirname(_cb_os.path.abspath(__file__))
_cb_root = _cb_os.path.dirname(_cb_webui)
for _cb_path in (_cb_webui, _cb_root):
    _cb_sys.path.insert(0, _cb_path)

import uvicorn

from app import create_app
from settings import Settings


def main() -> None:
    """Main.
    
    Args:
        None.
    
    Returns:
        Function result, or None when no value is returned.
    """
    settings = Settings.load()
    app = create_app(settings)
    uvicorn.run(app, host=settings.host, port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
