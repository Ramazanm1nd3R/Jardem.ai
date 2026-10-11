from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.routes import router
from app.config import Settings, get_settings
from app.domain.graph import RoadGraph
from app.runtime import Runtime


def create_app(settings: Settings | None = None, graph: RoadGraph | None = None,
               run_loop: bool = True) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        runtime = Runtime(settings, graph)
        app.state.runtime = runtime
        await runtime.start(run_loop=run_loop)
        yield
        await runtime.stop()

    app = FastAPI(title="Jardem.ai API", version="0.1.0", lifespan=lifespan,
                  docs_url="/api/docs", openapi_url="/api/openapi.json")
    origins = [o.strip() for o in settings.cors_origins.split(",") if o.strip()]
    app.add_middleware(CORSMiddleware, allow_origins=origins, allow_methods=["*"],
                       allow_headers=["*"])
    app.include_router(router)
    return app


app = create_app()
