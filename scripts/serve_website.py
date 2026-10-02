"""Local dev server for website/ that tells the browser never to cache, so edits show on reload."""
import functools, http.server, sys

class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 3000
handler = functools.partial(NoCacheHandler, directory="website")
http.server.ThreadingHTTPServer(("", port), handler).serve_forever()
