"""Consumer that imports from models, including re-exports."""

from ..pkg.models import Optional, dataclass, Query, Response


def process(q: Query) -> Response:
    return Response(data=q.text)
