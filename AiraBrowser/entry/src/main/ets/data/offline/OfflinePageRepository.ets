import { OfflinePageRecord } from '../../common/models/OfflinePageModels';
import { BrowserDatabase } from '../database/BrowserDatabase';

export interface OfflinePageRepository {
  initialize(): Promise<void>;
  list(limit?: number): Promise<OfflinePageRecord[]>;
  findById(id: string): Promise<OfflinePageRecord | undefined>;
  findByUrlHash(urlHash: string): Promise<OfflinePageRecord | undefined>;
  upsert(record: OfflinePageRecord): Promise<void>;
  delete(id: string): Promise<boolean>;
}

export class RdbOfflinePageRepository implements OfflinePageRepository {
  private database: BrowserDatabase;

  constructor(database: BrowserDatabase) {
    this.database = database;
  }

  async initialize(): Promise<void> {
    await this.database.initialize();
  }

  async list(limit?: number): Promise<OfflinePageRecord[]> {
    return await this.database.listOfflinePages(limit);
  }

  async findById(id: string): Promise<OfflinePageRecord | undefined> {
    return await this.database.findOfflinePageById(id);
  }

  async findByUrlHash(urlHash: string): Promise<OfflinePageRecord | undefined> {
    return await this.database.findOfflinePageByUrlHash(urlHash);
  }

  async upsert(record: OfflinePageRecord): Promise<void> {
    await this.database.upsertOfflinePage(record);
  }

  async delete(id: string): Promise<boolean> {
    return await this.database.deleteOfflinePage(id);
  }
}
