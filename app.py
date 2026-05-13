"""Backward-compatible ASGI entrypoint.

The assignment requires source code under ``src/``. This wrapper keeps older
commands such as ``uvicorn app:app`` working while the real app lives in the
package.
"""

from cicd_pipeline_demo.app import app as app
