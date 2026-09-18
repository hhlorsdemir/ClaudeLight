import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.state = Path(self.tmp.name) / 'state'
        self.env = dict(os.environ, CLAUDELIGHT_STATE_DIR=str(self.state))

    def send(self, event, sid='one', mode='codex', **fields):
        payload = dict(session_id=sid, hook_event_name=event, **fields)
        result = subprocess.run(['bash', str(ROOT / 'hooks/claude-light.sh'), mode],
                                input=json.dumps(payload), text=True, capture_output=True,
                                env=self.env, check=True)
        self.assertEqual(result.stdout, '')  # Hooks must not influence the agent.
        return self.files()

    def files(self):
        return {p.name: p.read_text() for p in self.state.glob('*')}

    def test_codex_lifecycle(self):
        self.assertEqual(self.send('SessionStart'), {})
        self.assertEqual(self.send('UserPromptSubmit'), {'codex-one': 'working'})
        self.assertEqual(self.send('PermissionRequest'), {'codex-one': 'waiting'})
        self.assertEqual(self.send('PostToolUse'), {'codex-one': 'working'})
        self.assertEqual(self.send('PreToolUse', tool_name='request_user_input'),
                         {'codex-one': 'waiting'})
        self.assertEqual(self.send('PostToolUse', tool_name='request_user_input'),
                         {'codex-one': 'working'})
        self.assertEqual(self.send('Stop'), {})
        for event in ('Interrupt', 'SessionEnd'):
            self.send('UserPromptSubmit')
            self.assertEqual(self.send(event), {})

    def test_mixed_sessions_are_independent(self):
        self.send('', mode='working')
        self.send('UserPromptSubmit')
        self.send('PermissionRequest', sid='two')
        self.assertEqual(self.files(), {'one': 'working', 'codex-one': 'working',
                                       'codex-two': 'waiting'})
        self.send('SessionEnd')
        self.assertEqual(self.files(), {'one': 'working', 'codex-two': 'waiting'})
        self.send('', mode='idle')
        self.send('SessionEnd', sid='two')
        self.assertEqual(self.files(), {})

    def test_nested_session_id_does_not_override_top_level(self):
        self.assertEqual(self.send('PreToolUse', tool_input={'session_id': 'wrong'}),
                         {'codex-one': 'working'})

    def test_bad_payload_does_not_create_unknown_session(self):
        for payload in ('bad json', '{}', '{"session_id":null}', '{"session_id":""}'):
            subprocess.run(['bash', str(ROOT / 'hooks/claude-light.sh'), 'working'],
                           input=payload, text=True, env=self.env, check=True)
        self.assertEqual(self.files(), {})

    def test_legacy_ids(self):
        for field in ('thread_id', 'thread-id'):
            subprocess.run(['bash', str(ROOT / 'hooks/claude-light.sh'), 'codex'],
                           input=json.dumps({field: 'legacy', 'hook_event_name': 'UserPromptSubmit'}),
                           text=True, env=self.env, check=True)
            self.assertEqual(self.files(), {'codex-legacy': 'working'})

    def test_compaction_preserves_activity(self):
        self.send('UserPromptSubmit')
        self.assertEqual(self.send('SessionStart', source='compact'), {'codex-one': 'working'})

    def test_registration_is_idempotent(self):
        # Run only registration, without installing an app or touching user settings.
        installer = (ROOT / 'install.sh').read_text()
        function = installer.split('register_hooks() {', 1)[1].split('\necho "==> Registering', 1)[0]
        config = Path(self.tmp.name) / 'hooks.json'
        original = {'hooks': {'Stop': [{'hooks': [{'type': 'command', 'command': 'echo keep'},
                                                   {'type': 'command', 'command': 'claude-light.sh waiting'}]}]}}
        config.write_text(json.dumps(original))
        script = 'set -e\nregister_hooks() {' + function + '\nregister_hooks "$1" Stop codex Interrupt codex SessionEnd codex\n'
        for _ in range(2):
            subprocess.run(['bash', '-c', script, 'test', str(config)], check=True)
        result = json.loads(config.read_text())
        self.assertEqual(len(result['hooks']['Stop']), 2)
        self.assertEqual(result['hooks']['Stop'][0]['hooks'],
                         [{'type': 'command', 'command': 'echo keep'}])
        self.assertEqual(result['hooks']['Interrupt'][0]['hooks'][0]['timeout'], 3)


if __name__ == '__main__':
    unittest.main()
