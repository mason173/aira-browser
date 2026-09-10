import { describe, expect, it } from '@ohos/hypium';
import {
  HISTORY_SELECTION_MORE_EMPTY_MESSAGE,
  planHistorySelectionMoreMenu
} from '../main/ets/features/history/HistorySelectionMoreMenu';

export default function historySelectionMoreMenuTest(): void {
  describe('History edit-mode more menu', () => {
    it('still presents timeline actions when the user has not selected any rows', 0, () => {
      const plan = planHistorySelectionMoreMenu('timeline', 0, true);
      expect(plan.selectedCount).assertEqual(0);
      expect(plan.emptySelectionMessage).assertEqual(HISTORY_SELECTION_MORE_EMPTY_MESSAGE);
      expect(plan.items.length).assertEqual(4);
      expect(plan.items[0].id).assertEqual('copy_links');
      expect(plan.items[0].title).assertEqual('批量复制链接');
      expect(plan.items[1].id).assertEqual('add_bookmarks');
      expect(plan.items[1].title).assertEqual('批量添加到书签');
      expect(plan.items[2].id).assertEqual('remove_bookmarks');
      expect(plan.items[2].title).assertEqual('批量取消书签');
      expect(plan.items[3].id).assertEqual('share_links');
      expect(plan.items[3].title).assertEqual('批量分享链接');
    });

    it('still presents the site cleanup action when the user has not selected any sites', 0, () => {
      const plan = planHistorySelectionMoreMenu('sites', 0, false);
      expect(plan.selectedCount).assertEqual(0);
      expect(plan.items.length).assertEqual(1);
      expect(plan.items[0].id).assertEqual('delete_selected_sites');
      expect(plan.items[0].title).assertEqual('删除所选站点历史');
    });
  });
}
