#!/usr/bin/env python3
"""Offline HTTP fixtures for the guest component downloader."""
import contextlib
import hashlib
import http.server
import importlib.util
import io
import pathlib
import tempfile
import threading
import unittest
from unittest import mock

spec = importlib.util.spec_from_file_location('download', pathlib.Path(__file__).resolve().parents[1] / 'Runtime/download.py')
download = importlib.util.module_from_spec(spec)
spec.loader.exec_module(download)
PAYLOAD = b'verified download' * 100_000


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        if self.path != '/unknown':
            self.send_header('Content-Length', str(len(PAYLOAD)))
        self.end_headers()
        self.wfile.write(PAYLOAD[:100] if self.path == '/short' else PAYLOAD)


class DownloadTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def run_download(self, path='/', checksum=None):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()) as output, mock.patch.object(download.time, 'sleep'):
            target = pathlib.Path(folder) / 'component'
            url = f'http://127.0.0.1:{self.server.server_port}{path}'
            if path == '/short' or checksum:
                target.write_bytes(b'previous')
                with self.assertRaises(Exception):
                    download.fetch(url, checksum or hashlib.sha256(PAYLOAD).hexdigest(), target, 'wine')
                self.assertEqual(target.read_bytes(), b'previous')
                self.assertFalse(target.with_name('component.partial').exists())
            else:
                download.fetch(url, hashlib.sha256(PAYLOAD).hexdigest(), target, 'wine')
                self.assertEqual(target.read_bytes(), PAYLOAD)
                self.assertIn('"received": ' + str(len(PAYLOAD)), output.getvalue())
                with mock.patch.object(download.urllib.request, 'urlopen', side_effect=AssertionError('cache must avoid network')):
                    download.fetch(url, hashlib.sha256(PAYLOAD).hexdigest(), target, 'wine')

    def test_bytes_and_verified_cache(self): self.run_download()
    def test_unknown_length(self): self.run_download('/unknown')
    def test_truncated_download_preserves_previous(self): self.run_download('/short')
    def test_wrong_digest_preserves_previous(self): self.run_download(checksum='0' * 64)


if __name__ == '__main__':
    unittest.main()
