import {
  AdBlockSettings
} from '../../common/models/BrowserModels';
import {
  AdBlockRuntimePolicySettings
} from '../../services/adblock/AdBlockPolicyService';

export interface AdBlockRuntimeSnapshot {
  readonly version: number;
  readonly key: string;
  readonly ruleSetKey: string;
  readonly builtAt: number;
  readonly settings: AdBlockSettings;
  readonly policy: AdBlockRuntimePolicySettings;
}
