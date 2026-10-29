from __future__ import annotations

import uvicorn

from app import create_app
from config import Settings


def main() -> None:
    settings = Settings.load()
    app = create_app(settings)
    uvicorn.run(app, host=settings.host, port=settings.port, log_level="info")


if __name__ == "__main__":
    main()
