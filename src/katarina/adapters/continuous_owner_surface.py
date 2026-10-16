"""Foreground HTTP requests run serially inside the existing observation brain."""
from contextlib import contextmanager
import time

from katarina.adapters.owner_dialog_server import create_server


def owner_surface(model, *, workspace=None, sources_config=None, **server_options):
    sources = None
    if sources_config:
        from katarina.adapters.research_sources import load_sources
        sources = load_sources(sources_config)
    @contextmanager
    def attach(brain):
        def turn(text, *, session_id, mode='auto', principal=None):
            # HTTP clients never supply tool grants or Owner research approval.
            role = principal['role'] if principal else 'owner'
            allowed = ['status', 'research'] if role == 'owner' else ['status']
            if role == 'owner' and workspace:
                allowed.append('read_file')
            if role == 'owner' and sources:
                allowed.append('read_source')
            result = brain.converse(text, model=model, session_id=session_id,
                                    mode=mode, allowed_tools=allowed, workspace=workspace, sources=sources)
            brain.control.checkpoint()
            return result
        server = create_server(turn, **server_options)
        try:
            def idle(_):
                started = time.monotonic()
                server.handle_request()
                time.sleep(max(0, 1 - (time.monotonic() - started)))
            yield idle
        finally:
            server.server_close()
    return attach
