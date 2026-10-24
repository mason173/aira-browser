import { describe, expect, it } from '@ohos/hypium';
import {
  buildDownloadSelectionTitle,
  canSelectDownloadTask,
  collectSelectableDownloadGuids,
  DownloadSelectionCandidate,
  pruneDownloadSelection
} from '../main/ets/core/download/DownloadSelectionViewModel';
import {
  DOWNLOAD_ROW_ENTER_SELECTION_ACTION,
  DownloadManagerViewModel
} from '../main/ets/core/download/DownloadManagerViewModel';

export default function downloadSelectionModeTest(): void {
  describe('Download edit-mode selection', () => {
    it('offers active and completed downloads for batch selection', 0, () => {
      expect(canSelectDownloadTask('completed')).assertTrue();
      expect(canSelectDownloadTask('running')).assertTrue();
      expect(canSelectDownloadTask('paused')).assertTrue();
      expect(canSelectDownloadTask('queued')).assertTrue();
      expect(canSelectDownloadTask('failed')).assertTrue();
      expect(canSelectDownloadTask('canceled')).assertFalse();
      expect(canSelectDownloadTask('removed')).assertFalse();
    });

    it('selects every active and completed row and skips removed tasks', 0, () => {
      const candidates: DownloadSelectionCandidate[] = [
        { guid: 'a', status: 'completed' },
        { guid: 'b', status: 'running' },
        { guid: 'c', status: 'completed' },
        { guid: 'd', status: 'failed' },
        { guid: 'e', status: 'removed' }
      ];
      const selected = collectSelectableDownloadGuids(candidates);
      expect(selected.length).assertEqual(4);
      expect(selected[0]).assertEqual('a');
      expect(selected[1]).assertEqual('b');
      expect(selected[2]).assertEqual('c');
      expect(selected[3]).assertEqual('d');
    });

    it('drops selections that are no longer selectable after a refresh', 0, () => {
      const pruned = pruneDownloadSelection(['a', 'b', 'c'], ['a', 'c']);
      expect(pruned.length).assertEqual(2);
      expect(pruned[0]).assertEqual('a');
      expect(pruned[1]).assertEqual('c');
    });

    it('reports the selection count in the title', 0, () => {
      expect(buildDownloadSelectionTitle(0)).assertEqual('已选 0 项');
      expect(buildDownloadSelectionTitle(3)).assertEqual('已选 3 项');
    });
  });

  describe('Download long-press menu ordering', () => {
    it('leads a completed download menu with the multi-select entry', 0, () => {
      const viewModel = new DownloadManagerViewModel();
      const views = viewModel.buildRowMenuActions(
        ['save_to_system', 'open_file', 'open_location', 'remove_record'],
        'completed',
        'open_file'
      );
      expect(views.length).assertEqual(6);
      expect(views[0].action).assertEqual(DOWNLOAD_ROW_ENTER_SELECTION_ACTION);
      expect(views[0].label).assertEqual('多选');
      expect(views[1].action).assertEqual('save_to_system');
      expect(views[2].action).assertEqual('open_location');
      expect(views[3].action).assertEqual('remove_record');
      expect(views[4].action).assertEqual('delete_task_and_file');
      expect(views[5].action).assertEqual('copy_link');
    });

    it('leads a running download menu with the multi-select entry', 0, () => {
      const viewModel = new DownloadManagerViewModel();
      const views = viewModel.buildRowMenuActions(['pause', 'cancel'], 'running', 'pause');
      expect(views.length).assertEqual(3);
      expect(views[0].action).assertEqual(DOWNLOAD_ROW_ENTER_SELECTION_ACTION);
      expect(views[1].action).assertEqual('cancel');
      expect(views[2].action).assertEqual('copy_link');
    });
  });
}
