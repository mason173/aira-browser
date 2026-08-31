import { SearchEngineId } from '../../common/models/BrowserModels';
import { SearchEngineIconResources } from '../../app/components/search/SearchEngineIconResources';

export function resolveDesktopCardSearchEngineIcon(searchEngineId: string): Resource {
  return SearchEngineIconResources.builtInIcon(searchEngineId as SearchEngineId) ??
    $r('app.media.aira_logo_brand');
}

export function hasBuiltInDesktopCardSearchEngineIcon(searchEngineId: string): boolean {
  return SearchEngineIconResources.builtInIcon(searchEngineId as SearchEngineId) !== undefined;
}
