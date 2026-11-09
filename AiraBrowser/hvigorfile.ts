import { appTasks } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';

const sharedComponentGuard: HvigorPlugin = {
  pluginId: 'aira-shared-components',
  apply(node: HvigorNode): void {
    execFileSync(process.execPath, [resolve(node.getNodePath(), '../scripts/check-aira-shared-components.cjs')],
      { stdio: 'inherit' });
  }
};

export default { system: appTasks, plugins: [sharedComponentGuard] };
