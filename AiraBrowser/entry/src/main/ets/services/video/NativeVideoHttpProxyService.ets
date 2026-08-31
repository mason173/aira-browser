import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  NativeHttpProxyResolution,
  NativeHttpProxyResolutionService
} from '../network/NativeHttpProxyResolutionService';

export type NativeVideoHttpProxyResolution = NativeHttpProxyResolution;

export class NativeVideoHttpProxyService extends NativeHttpProxyResolutionService {
  constructor(preferencesRepository?: PreferencesRepository) {
    super(preferencesRepository);
  }
}
