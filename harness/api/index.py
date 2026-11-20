"""TrackerPlusPlus harness: stateless FastAPI app (Vercel entry point)."""
from __future__ import annotations

import hmac

from fastapi import Depends, FastAPI, Header, HTTPException

from harness import config
from harness.clients import sie
from harness.evidence import senso
from harness.models import EvidenceRequest, EvidenceResponse, ShoesRequest, ShoesResponse
from harness.recommend import shoes

app = FastAPI(title="TrackerPlusPlus harness", version="0.1.0")


def require_secret(x_harness_secret: str = Header(default="")) -> None:
    """Only enforced when HARNESS_SECRET is set. /evidence stays open: EvidenceClient sends no header."""
    if config.HARNESS_SECRET and not hmac.compare_digest(x_harness_secret, config.HARNESS_SECRET):
        raise HTTPException(status_code=401, detail="bad secret")


@app.get("/health")
def health() -> dict:
    return {"ok": True, "sie": bool(config.SIE_API_KEY), "senso": bool(config.SENSO_API_KEY),
            "secret": bool(config.HARNESS_SECRET), "version": app.version}


@app.post("/warm", dependencies=[Depends(require_secret)])
def warm() -> dict:
    return sie.warm(provision_timeout_s=240)


@app.post("/evidence", response_model=EvidenceResponse)
def evidence(req: EvidenceRequest) -> EvidenceResponse:
    items, live = senso.search(req.purchaseKind, req.query)
    return EvidenceResponse(evidence=items, live=live)


@app.post("/shoes/recommend", response_model=ShoesResponse, response_model_exclude_none=True,
          dependencies=[Depends(require_secret)])
def shoes_recommend(req: ShoesRequest) -> ShoesResponse:
    try:
        return shoes.recommend(req)
    except KeyError:
        raise HTTPException(status_code=404, detail=f"unknown persona {req.persona}")


@app.api_route("/{rest:path}", methods=["GET", "POST"], include_in_schema=False)
def not_found(rest: str):
    raise HTTPException(status_code=404, detail=f"no route /{rest}")
