"""Exercise the actual inline workflow with mocked GitHub API data only."""
import base64
import contextlib
import io
import json
import os
from pathlib import Path
import tempfile
import textwrap
import unittest
from unittest.mock import patch

WORKFLOW = Path(__file__).resolve().parents[2] / '.github/workflows/issue_comment.yml'
SOURCE = WORKFLOW.read_text(encoding='utf-8')
# The workflow intentionally has a single Python step and no checkout/actions.
SCRIPT = textwrap.dedent(SOURCE.split('        run: |\n', 1)[1])


class CommentVerificationTests(unittest.TestCase):
    def run_check(self, manifest='{}', changed_files=1, moved=False, encoding='base64'):
        sha = 'a' * 40
        pr = {'head': {'repo': {'full_name': 'fork/bucket'}, 'sha': sha},
              'changed_files': changed_files}
        responses = [
            pr,
            [{'filename': 'bucket/test.json', 'status': 'modified'}],
            {'type': 'file', 'encoding': encoding,
             'content': base64.b64encode(manifest.encode()).decode()},
            dict(pr, head=dict(pr['head'], sha='b' * 40)) if moved else pr,
        ]
        urls = []

        def open_url(request, timeout):
            urls.append(request.full_url)
            return io.StringIO(json.dumps(responses.pop(0)))

        output = io.StringIO()
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / 'event.json'
            event.write_text(json.dumps({'issue': {'number': 1}}), encoding='utf-8')
            with patch.dict(os.environ, {
                'GITHUB_EVENT_PATH': str(event),
                'GITHUB_REPOSITORY': 'owner/bucket', 'GH_TOKEN': 'dummy',
            }), patch('urllib.request.urlopen', open_url), contextlib.redirect_stdout(output):
                exec(compile(SCRIPT, str(WORKFLOW), 'exec'), {})
        self.assertIn('Validated JSON syntax for 1 changed manifests', output.getvalue())
        return urls

    def test_non_json_constants_rejected(self):
        for constant in ('NaN', 'Infinity', '-Infinity'):
            for manifest in ('{"value": ' + constant + '}',
                             '{"nested": [0, ' + constant + ']}'):
                with self.subTest(manifest=manifest):
                    with self.assertRaisesRegex(ValueError, 'Invalid JSON numeric constant'):
                        self.run_check(manifest)

    def test_quoted_constants_and_valid_numbers_accepted(self):
        self.run_check('{"values": ["NaN", "Infinity", "-Infinity", 0, -42, 1.5, 1e3]}')

    def test_untrusted_script_remains_data_at_pinned_sha(self):
        urls = self.run_check(json.dumps({'checkver': {'script': 'throw "never execute"'}}))
        self.assertIn('?ref=' + 'a' * 40, urls[2])

    def test_invalid_json(self):
        with self.assertRaises(json.JSONDecodeError):
            self.run_check('{')

    def test_array_rejected(self):
        with self.assertRaises(ValueError):
            self.run_check('[]')

    def test_incomplete_listing(self):
        with self.assertRaises(ValueError):
            self.run_check(changed_files=3001)

    def test_head_moved(self):
        with self.assertRaises(ValueError):
            self.run_check(moved=True)

    def test_unsupported_content_encoding(self):
        with self.assertRaises(ValueError):
            self.run_check(encoding='none')

    def test_security_contract(self):
        self.assertIn('permissions:\n  contents: read\n  pull-requests: read\n', SOURCE)
        self.assertNotIn('uses:', SOURCE)
        self.assertNotIn('${{', SCRIPT)
        self.assertIn('github.event.issue.pull_request', SOURCE)


if __name__ == '__main__':
    unittest.main()
