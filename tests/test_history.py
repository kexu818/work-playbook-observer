import copy
import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import subprocess

spec = importlib.util.spec_from_file_location('history', Path(__file__).parents[1] / 'backend/history.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / 'history'
        self.memories = self.base / 'memories'
        self.data = self.base / 'data'
        self.file = self.root / 'segments/2026-10-26T07-00-00Z/events.jsonl'
        self.file.parent.mkdir(parents=True)
        self.memories.mkdir()
        self.start = h.timestamp('2026-10-26T07:00:00Z')
        self.end = h.timestamp('2026-10-26T08:00:00Z')
        self.reader = h.HistoryReader(self.root, self.memories)

    def tearDown(self):
        self.temp.cleanup()

    def event(self, when='2026-10-26T07:05:00Z', **extra):
        return dict({'timestamp': when, 'kind': 'window.changed', 'app': {'name': 'Sample App'}, 'ax': {'text': '核对任务来源'}}, **extra)

    def put(self, rows, tail=b''):
        data = b''.join((json.dumps(row, ensure_ascii=False) + '\n').encode() for row in rows) + tail
        self.file.write_bytes(data)
        return data

    def snapshot(self):
        return self.reader.snapshot(self.start, self.end)

    def candidate(self):
        return {'title': '核对来源', 'problem': '容易遗漏', 'why': '需要逐项核对', 'trigger': '汇总工作时', 'steps': ['核对'], 'checks': ['每项可追溯'], 'missing': ['失败例子'], 'sourceIds': ['e-1']}

    def test_window_is_start_inclusive_end_exclusive(self):
        self.put([self.event('2026-10-26T06:59:59Z'), self.event('2026-10-26T07:00:00Z'), self.event('2026-10-26T08:00:00Z')])
        self.assertEqual(self.snapshot()['eventCount'], 1)

    def test_export_preserves_raw_unknown_fields_and_unicode(self):
        raw = self.put([self.event(future={'nested': ['未知字段', 3]})])
        result = h.export_snapshot(self.snapshot(), self.data)
        out = Path(result['path'])
        self.assertEqual((out / 'events.jsonl').read_bytes(), raw)
        self.assertEqual(result['manifest']['artifacts'][0]['sha256'], hashlib.sha256(raw).hexdigest())
        self.assertEqual(self.file.read_bytes(), raw)

    def test_exports_are_unique_and_private(self):
        self.put([self.event()]); snap = self.snapshot()
        a = h.export_snapshot(snap, self.data); b = h.export_snapshot(snap, self.data)
        self.assertNotEqual(a['path'], b['path'])
        self.assertEqual((Path(a['path']) / 'events.jsonl').stat().st_mode & 0o777, 0o600)
        self.assertEqual(Path(a['path']).stat().st_mode & 0o777, 0o700)

    def test_partial_utf8_tail_is_not_exported(self):
        raw = self.put([self.event()], b'{"text":"\xe4\xb8')
        snap = self.snapshot()
        self.assertEqual(snap['eventCount'], 1)
        self.assertTrue(snap['files'][0]['partialTail'])
        self.assertEqual(snap['files'][0]['snapshotSha256'], h.digest(raw))

    def test_bad_and_untimed_lines_are_reported(self):
        self.put([self.event(), {'kind': 'unknown'}], b'not-json\n[1,2]\n')
        snap = self.snapshot()
        self.assertEqual(snap['files'][0]['badLines'], 2)
        self.assertEqual(snap['files'][0]['untimedLines'], 1)
        self.assertTrue(snap['issues'])

    def test_unknown_app_shape_does_not_break_reader(self):
        event = self.event(); event['app'] = {'name': {'future': 1}}
        self.put([event]); self.assertEqual(self.snapshot()['events'][0]['app'], '未知应用')

    def test_missing_app_shape_does_not_break_analysis(self):
        event = self.event(); event['app'] = None
        self.put([event]); self.assertEqual(h.analysis_packet(self.snapshot())['coverage']['includedEvents'], 1)

    def test_naive_or_bad_event_times_are_not_assumed_local(self):
        self.put([self.event('2026-10-26T07:05:00'), self.event('yesterday')])
        self.assertEqual(self.snapshot()['eventCount'], 0)
        self.assertEqual(self.snapshot()['files'][0]['untimedLines'], 2)

    def test_summary_with_actual_no_z_filename_is_read(self):
        file = self.memories / '2026-10-26T07-00-00-abc-10min-summary.md'
        content = '---\ntitle: 会议整理\n---\n\n原始摘要。\n'.encode()
        file.write_bytes(content)
        self.put([])
        snap = self.snapshot(); self.assertEqual(snap['summaryCount'], 1)
        out = Path(h.export_snapshot(snap, self.data)['path'])
        self.assertEqual((out / 'summaries' / file.name).read_bytes(), content)

    def test_summary_levels_and_approximate_overlap_are_explicit(self):
        (self.memories / '2026-10-26T06-55-00Z-a-10min-note.md').write_text('before window but overlap')
        (self.memories / '2026-10-25T01-00-00Z-b-6h-note.md').write_text('outside')
        self.put([])
        snap = self.snapshot(); self.assertEqual(snap['summaryCount'], 1)
        self.assertEqual(snap['summaryCount'], len(snap['summaries']))

    def test_summary_unknown_timestamp_is_reported(self):
        (self.memories / 'untimed.md').write_text('unknown')
        self.put([]); self.assertTrue(any('时间格式' in x for x in self.snapshot()['issues']))

    def test_source_symlinks_cannot_escape_selected_root(self):
        outside = self.base / 'outside.jsonl'; outside.write_text(json.dumps(self.event()) + '\n')
        self.file.symlink_to(outside)
        snap = self.snapshot(); self.assertEqual(snap['eventCount'], 0)
        self.assertTrue(any('越界' in x for x in snap['issues']))

    def test_summary_symlinks_cannot_escape(self):
        outside = self.base / 'secret.md'; outside.write_text('must not read')
        (self.memories / '2026-10-26T07-00-00Z-a-10min-x.md').symlink_to(outside)
        self.put([]); self.assertEqual(self.snapshot()['summaryCount'], 0)

    def test_invalid_window_rejected(self):
        with self.assertRaises(ValueError): self.reader.snapshot(self.end, self.start)

    def test_missing_sources_are_visible(self):
        snap = h.HistoryReader(self.base / 'missing', self.base / 'missing2').snapshot(self.start, self.end)
        self.assertFalse(snap['available']); self.assertEqual(len(snap['issues']), 2)
        with self.assertRaises(ValueError): h.export_snapshot(snap, self.data)

    def test_public_preview_is_bounded_but_export_is_full(self):
        self.put([self.event(future=i) for i in range(300)])
        snap = self.snapshot(); view = h.public_snapshot(snap)
        self.assertEqual(len(view['events']), 250); self.assertEqual(view['eventCount'], 300)
        self.assertNotIn('_raw', view['events'][0]); self.assertTrue(view['previewLimited'])
        out = Path(h.export_snapshot(snap, self.data)['path'])
        self.assertEqual(len((out / 'events.jsonl').read_bytes().splitlines()), 300)

    def test_analysis_packet_is_bounded_with_coverage(self):
        self.put([self.event(future=i) for i in range(300)])
        packet = h.analysis_packet(self.snapshot(), max_chars=50, max_events=5)
        self.assertLessEqual(packet['coverage']['textCharacters'], 50)
        self.assertLessEqual(packet['coverage']['includedEvents'], 5)
        self.assertTrue(packet['coverage']['truncated'])

    def test_observer_ui_is_exported_but_not_reused_as_work_evidence(self):
        observer = self.event(); observer['app'] = {'name': 'Playbook 工作台', 'bundleIdentifier': 'io.github.kexu818.work-playbook-observer'}
        self.put([self.event(), observer]); snap = self.snapshot()
        packet = h.analysis_packet(snap)
        self.assertEqual(packet['coverage']['totalEvents'], 2)
        self.assertEqual(packet['coverage']['observerEventsExcluded'], 1)
        self.assertEqual(packet['coverage']['includedEvents'], 1)
        self.assertEqual(snap['eventCount'], 2)

    def test_analysis_shares_budget_across_all_day_summaries_and_events(self):
        self.put([self.event(f'2026-10-26T07:{i:02d}:00Z') for i in range(60)])
        snap = self.snapshot()
        snap['summaries'] = [dict(id=f's-{i}', timestamp=f'2026-10-26T07:{i:02d}:00Z',
                                  level='10min', text=str(i) + 'x' * 3000) for i in range(24)]
        packet = h.analysis_packet(snap)
        summaries = [s for s in packet['sources'] if s['type'] == 'summary']
        events = [s for s in packet['sources'] if s['type'] == 'event']
        self.assertEqual(len(summaries), 24)
        self.assertEqual(summaries[-1]['id'], 's-23')
        self.assertEqual(events[0]['id'], snap['events'][0]['id'])
        self.assertEqual(events[-1]['id'], snap['events'][-1]['id'])
        self.assertLessEqual(packet['coverage']['textCharacters'], 18000)
        self.assertTrue(packet['coverage']['truncated'])

    def test_oversized_summary_list_samples_both_ends_of_interval(self):
        self.put([])
        snap = self.snapshot()
        snap['summaries'] = [dict(id=f's-{i}', timestamp=f'{i:04d}', level='10min',
                                  text='x' * 3000) for i in range(100)]
        packet = h.analysis_packet(snap, max_chars=1200)
        self.assertEqual([s['id'] for s in packet['sources']], ['s-0', 's-33', 's-66', 's-99'])
        self.assertLessEqual(packet['coverage']['textCharacters'], 1200)

    def test_export_history_survives_reload(self):
        self.put([self.event()]); result = h.export_snapshot(self.snapshot(), self.data)
        exports = h.export_list(self.data)['exports']
        self.assertEqual(exports[0]['path'], result['path'])
        self.assertEqual(exports[0]['eventCount'], 1)

    def test_export_package_is_a_supported_readonly_source(self):
        self.put([self.event()]); result = h.export_snapshot(self.snapshot(), self.data)
        package = Path(result['path']); before = (package / 'events.jsonl').read_bytes()
        snap = h.HistoryReader(package, self.base / 'missing').snapshot(self.start, self.end)
        self.assertEqual(snap['sourceMode'], 'export'); self.assertEqual(snap['eventCount'], 1)
        self.assertTrue(snap['rawReadable']); self.assertEqual((package / 'events.jsonl').read_bytes(), before)

    def test_permission_denied_directory_is_not_reported_as_empty(self):
        with mock.patch.object(h.os, 'scandir', side_effect=PermissionError('denied')):
            snap = self.snapshot()
        self.assertFalse(snap['rawReadable']); self.assertTrue(any('PermissionError' in item for item in snap['issues']))

    def test_empty_input_does_not_call_model(self):
        self.put([])
        with self.assertRaises(ValueError): h.analysis_packet(self.snapshot())

    def test_clipped_single_summary_reports_truncation(self):
        (self.memories / '2026-10-26T07-00-00Z-x-6h-test.md').write_text('a' * 7000)
        self.put([])
        self.assertTrue(h.analysis_packet(self.snapshot())['coverage']['truncated'])

    def test_valid_and_empty_model_outputs(self):
        parsed = h.parse_candidates(json.dumps({'candidates': [self.candidate()], 'note': 'one example only'}), {'e-1'})
        self.assertEqual(len(parsed['candidates']), 1)
        self.assertEqual(h.parse_candidates('{"candidates":[],"note":"不足"}', set())['candidates'], [])

    def test_model_cannot_invent_evidence_or_unknown_fields(self):
        candidate = self.candidate(); candidate['sourceIds'] = ['elsewhere']
        with self.assertRaises(ValueError): h.parse_candidates(json.dumps({'candidates': [candidate], 'note': ''}), {'e-1'})
        candidate = self.candidate(); candidate['command'] = 'run-this'
        with self.assertRaises(ValueError): h.parse_candidates(json.dumps({'candidates': [candidate], 'note': ''}), {'e-1'})

    def test_model_bad_types_or_missing_acceptance_are_rejected(self):
        for field, value in [('steps', []), ('checks', []), ('title', 3), ('sourceIds', []), ('missing', 'no')]:
            candidate = self.candidate(); candidate[field] = value
            with self.assertRaises(ValueError): h.parse_candidates(json.dumps({'candidates': [candidate], 'note': ''}), {'e-1'})

    def test_feedback_requires_actual_note_and_known_candidate(self):
        h.private_dir(self.data)
        candidate = self.candidate(); candidate.update(id='c1', status='draft', feedback=[])
        record = {'id': 'a1', 'window': {'start': 'start', 'end': 'end'}, 'candidates': [candidate]}
        h.atomic_json(self.data / 'state.json', {'analyses': [record]})
        with self.assertRaises(ValueError): h.feedback(self.data, 'c1', 'effective', '')
        with self.assertRaises(ValueError): h.feedback(self.data, 'missing', 'effective', 'tested')
        saved = h.feedback(self.data, 'c1', 'partial', '遗漏了异常分支')
        self.assertEqual(saved['status'], 'partial')
        self.assertIn('部分有效', h.draft(self.data, 'c1')['markdown'])

    def test_draft_export_does_not_promote_effectiveness(self):
        candidate = self.candidate(); candidate.update(id='c1', status='draft', feedback=[])
        text = h.markdown(candidate, {'window': {'start': 'start', 'end': 'end'}})
        self.assertIn('尚未验证', text); self.assertEqual(candidate['status'], 'draft')

    def test_corrupt_state_is_not_overwritten(self):
        h.private_dir(self.data); file = self.data / 'state.json'; file.write_text('{broken')
        with self.assertRaises(ValueError): h.analysis_result(self.data)
        self.assertEqual(file.read_text(), '{broken')

    def test_cancel_terminates_and_waits_for_child(self):
        process = mock.Mock(); process.poll.return_value = None
        h.ACTIVE_PROCESS = process
        try:
            with self.assertRaises(SystemExit) as stopped: h.cancel(15, None)
            self.assertEqual(stopped.exception.code, 130)
            process.terminate.assert_called_once(); process.wait.assert_called_once_with(timeout=15)
        finally: h.ACTIVE_PROCESS = None

    def test_unclean_receipt_never_saves_success(self):
        runner = self.base / 'runner'; runner.write_text('test runner placeholder')
        self.put([self.event()]); packet = h.analysis_packet(self.snapshot())
        process = mock.Mock(); process.wait.return_value = 0
        login = subprocess.CompletedProcess([], 0, stdout='Logged in using ChatGPT', stderr='')
        with mock.patch.dict(os.environ, {'PLAYBOOK_CODEX_BIN': str(runner)}), mock.patch.object(h.Path, 'home', return_value=self.base), mock.patch.object(h.subprocess, 'run', return_value=login), mock.patch.object(h.subprocess, 'Popen', return_value=process):
            with self.assertRaisesRegex(ValueError, '认证清理'): h.run_analysis(packet, self.data, runner=runner)
        self.assertFalse((self.data / 'state.json').exists())

    def test_non_subscription_login_stops_before_analysis(self):
        runner = self.base / 'runner'; runner.write_text('test runner placeholder')
        self.put([self.event()]); packet = h.analysis_packet(self.snapshot())
        login = subprocess.CompletedProcess([], 0, stdout='Logged in using an API key', stderr='')
        with mock.patch.dict(os.environ, {'PLAYBOOK_CODEX_BIN': str(runner)}), mock.patch.object(h.Path, 'home', return_value=self.base), mock.patch.object(h.subprocess, 'run', return_value=login), mock.patch.object(h.subprocess, 'Popen') as launch:
            with self.assertRaisesRegex(ValueError, 'ChatGPT'): h.run_analysis(packet, self.data, runner=runner)
            launch.assert_not_called()


if __name__ == '__main__': unittest.main()
