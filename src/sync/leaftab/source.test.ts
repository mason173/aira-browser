import { describe, expect, test } from 'vitest';
import {
  resolveLeafTabSyncMergeIntent,
  type LeafTabSyncRemoteKind,
} from './source';

type MergeIntentCase = [
  LeafTabSyncRemoteKind | null,
  LeafTabSyncRemoteKind,
  'ordinary' | 'provider-switch',
];

const mergeIntentCases: MergeIntentCase[] = [
  [null, 'aira-cloud', 'ordinary'],
  [null, 'webdav', 'ordinary'],
  ['aira-cloud', 'aira-cloud', 'ordinary'],
  ['webdav', 'webdav', 'ordinary'],
  ['aira-cloud', 'webdav', 'provider-switch'],
  ['webdav', 'aira-cloud', 'provider-switch'],
];

describe('resolveLeafTabSyncMergeIntent', () => {
  test.each(mergeIntentCases)(
    'maps selected source %s and target %s to %s',
    (selectedSource, targetSource, expected) => {
    expect(resolveLeafTabSyncMergeIntent(selectedSource, targetSource)).toBe(expected);
    },
  );
});
