import { SiteControlsListRowState } from '../../core/sitecontrols/SiteControlsCoordinator';
import { SiteCustomizationListRowState } from '../../core/sitecustomization/SiteCustomizationManagementCoordinator';

const EMPTY_SITE_CONTROLS_ROW: SiteControlsListRowState = {
  id: '',
  host: '',
  origin: '',
  title: '',
  value: '',
  helperText: '',
  updatedAt: 0
};

const EMPTY_SITE_CUSTOMIZATION_ROW: SiteCustomizationListRowState = {
  id: '',
  host: '',
  origin: '',
  title: '',
  value: '',
  helperText: '',
  updatedAt: 0,
  isEnabled: false
};

export class SiteControlsListRowDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private rows: SiteControlsListRowState[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): SiteControlsListRowState {
    if (index < 0 || index >= this.rows.length) {
      return EMPTY_SITE_CONTROLS_ROW;
    }
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replaceRows(rows: SiteControlsListRowState[]): void {
    this.rows = rows.slice();
    this.notifyDataReload();
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

export class SiteCustomizationListRowDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private rows: SiteCustomizationListRowState[] = [];

  totalCount(): number {
    return this.rows.length;
  }

  getData(index: number): SiteCustomizationListRowState {
    if (index < 0 || index >= this.rows.length) {
      return EMPTY_SITE_CUSTOMIZATION_ROW;
    }
    return this.rows[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replaceRows(rows: SiteCustomizationListRowState[]): void {
    this.rows = rows.slice();
    this.notifyDataReload();
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
