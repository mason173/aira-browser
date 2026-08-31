import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';

export const HUAWEI_SPACE_BOOKMARK_HEAD_TABLE: string = 'AiraG8BookmarkHeads';
export const HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE: string = 'AiraG8BookmarkBlocks';
export const HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE: string = 'AiraG2PersonalizationCommits';
export const HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE: string = 'AiraG2NovelBookshelfCommits';
export const HUAWEI_SPACE_HISTORY_TABLE: string = 'AiraH1HistoryRecords';

const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE: string =
  'AiraHuaweiSpaceDistributedRegistration';
const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_ROW_ID: string = 'active-cloud-tables';
const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION: number = 5;
const HUAWEI_SPACE_PRE_NOVEL_REGISTRATION_VERSION: number = 1;

const HUAWEI_SPACE_BOOKMARK_HEAD_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_BOOKMARK_HEAD_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    recordKind TEXT,
    logicalId TEXT,
    storageEpoch INTEGER,
    data TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_KIND_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG8BookmarkHeadsAccountKind
    ON ${HUAWEI_SPACE_BOOKMARK_HEAD_TABLE}(accountUid, recordKind, storageEpoch, updatedAt)`;
const HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_LOGICAL_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG8BookmarkHeadsAccountLogical
    ON ${HUAWEI_SPACE_BOOKMARK_HEAD_TABLE}(accountUid, recordKind, logicalId)`;
const HUAWEI_SPACE_BOOKMARK_BLOCK_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    recordKind TEXT,
    logicalId TEXT,
    storageEpoch INTEGER,
    data TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_KIND_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG8BookmarkBlocksAccountKind
    ON ${HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE}(accountUid, recordKind, storageEpoch, updatedAt)`;
const HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_LOGICAL_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG8BookmarkBlocksAccountLogical
    ON ${HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE}(accountUid, recordKind, logicalId)`;
const HUAWEI_SPACE_PERSONALIZATION_COMMIT_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    commitId TEXT,
    parentCommitIdsJson TEXT,
    snapshotJson BLOB,
    deviceId TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_PERSONALIZATION_COMMIT_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG2PersonalizationCommitsAccountUpdated
    ON ${HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE}(accountUid, updatedAt)`;
const HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    commitId TEXT,
    parentCommitIdsJson TEXT,
    snapshotJson BLOB,
    deviceId TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraG2NovelBookshelfCommitsAccountUpdated
    ON ${HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE}(accountUid, updatedAt)`;
const HUAWEI_SPACE_HISTORY_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_HISTORY_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    recordKind TEXT,
    logicalId TEXT,
    data TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_HISTORY_ACCOUNT_KIND_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH1HistoryRecordsAccountKind
    ON ${HUAWEI_SPACE_HISTORY_TABLE}(accountUid, recordKind, updatedAt)`;
const HUAWEI_SPACE_HISTORY_ACCOUNT_LOGICAL_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH1HistoryRecordsAccountLogical
    ON ${HUAWEI_SPACE_HISTORY_TABLE}(accountUid, recordKind, logicalId)`;
const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE} (
    rowId TEXT PRIMARY KEY,
    registrationVersion INTEGER,
    updatedAt INTEGER
  )`;

interface HuaweiSpaceRdbStoreState {
  store?: relationalStore.RdbStore;
  promise?: Promise<relationalStore.RdbStore>;
}

export class HuaweiSpaceRdbStoreOwner {
  private static states: Map<string, HuaweiSpaceRdbStoreState> =
    new Map<string, HuaweiSpaceRdbStoreState>();

  static getStore(
    context: common.ApplicationContext | common.UIAbilityContext,
    databaseName: string
  ): Promise<relationalStore.RdbStore> {
    const normalizedDatabaseName = databaseName.trim();
    if (normalizedDatabaseName.length <= 0) {
      return Promise.reject(new Error('Huawei Space database name is empty.'));
    }
    const existing = HuaweiSpaceRdbStoreOwner.states.get(normalizedDatabaseName);
    if (existing?.store !== undefined) {
      return Promise.resolve(existing.store);
    }
    if (existing?.promise !== undefined) {
      return existing.promise;
    }
    const state: HuaweiSpaceRdbStoreState = {};
    HuaweiSpaceRdbStoreOwner.states.set(normalizedDatabaseName, state);
    const promise = HuaweiSpaceRdbStoreOwner.openAndPrepare(context, normalizedDatabaseName)
      .then((store: relationalStore.RdbStore): relationalStore.RdbStore => {
        state.store = store;
        return store;
      })
      .catch((error: Error) => {
        HuaweiSpaceRdbStoreOwner.states.delete(normalizedDatabaseName);
        throw error;
      });
    state.promise = promise;
    return promise;
  }

  private static async openAndPrepare(
    context: common.ApplicationContext | common.UIAbilityContext,
    databaseName: string
  ): Promise<relationalStore.RdbStore> {
    const storeConfig: relationalStore.StoreConfig = {
      name: databaseName,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const bootstrapStore = await relationalStore.getRdbStore(context, storeConfig);
    let shouldRegisterDistributedTables = true;
    try {
      const bookmarkHeadTableHasRows = await HuaweiSpaceRdbStoreOwner.hasAnyRows(
        bootstrapStore,
        HUAWEI_SPACE_BOOKMARK_HEAD_TABLE
      );
      const personalizationTableHasRows = await HuaweiSpaceRdbStoreOwner.hasAnyRows(
        bootstrapStore,
        HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE
      );
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_SCHEMA);
      await HuaweiSpaceRdbStoreOwner.ensureColumn(
        bootstrapStore,
        HUAWEI_SPACE_BOOKMARK_HEAD_TABLE,
        'storageEpoch',
        'INTEGER'
      );
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_KIND_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_LOGICAL_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_SCHEMA);
      await HuaweiSpaceRdbStoreOwner.ensureColumn(
        bootstrapStore,
        HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE,
        'storageEpoch',
        'INTEGER'
      );
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_KIND_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_LOGICAL_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_PERSONALIZATION_COMMIT_SCHEMA);
      await bootstrapStore.executeSql(HUAWEI_SPACE_PERSONALIZATION_COMMIT_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_SCHEMA);
      await bootstrapStore.executeSql(HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_HISTORY_SCHEMA);
      await bootstrapStore.executeSql(HUAWEI_SPACE_HISTORY_ACCOUNT_KIND_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_HISTORY_ACCOUNT_LOGICAL_INDEX);
      await bootstrapStore.executeSql(HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_SCHEMA);
      const registrationVersion = await HuaweiSpaceRdbStoreOwner.readDistributedRegistrationVersion(
        bootstrapStore
      );
      shouldRegisterDistributedTables =
        registrationVersion < HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION;
      if (registrationVersion <= 0 && (bookmarkHeadTableHasRows || personalizationTableHasRows)) {
        await HuaweiSpaceRdbStoreOwner.writeDistributedRegistrationVersion(
          bootstrapStore,
          HUAWEI_SPACE_PRE_NOVEL_REGISTRATION_VERSION
        );
        shouldRegisterDistributedTables = true;
      }
      await bootstrapStore.close();
    } catch (error) {
      try {
        await bootstrapStore.close();
      } catch (_closeError) {
      }
      const candidate = error as Error;
      throw new Error(candidate.message ?? JSON.stringify(error));
    }
    const store = await relationalStore.getRdbStore(context, storeConfig);
    try {
      if (shouldRegisterDistributedTables) {
        await HuaweiSpaceRdbStoreOwner.prepareDistributedTables(store);
        await HuaweiSpaceRdbStoreOwner.writeDistributedRegistrationVersion(store);
      }
      return store;
    } catch (error) {
      try {
        await store.close();
      } catch (_closeError) {
      }
      const candidate = error as Error;
      throw new Error(candidate.message ?? JSON.stringify(error));
    }
  }

  private static async prepareDistributedTables(store: relationalStore.RdbStore): Promise<void> {
    await store.setDistributedTables(
      [
        HUAWEI_SPACE_BOOKMARK_HEAD_TABLE,
        HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE,
        HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE,
        HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE,
        HUAWEI_SPACE_HISTORY_TABLE
      ],
      relationalStore.DistributedType.DISTRIBUTED_CLOUD,
      {
        autoSync: false,
        enableCloud: true
      }
    );
  }

  private static async hasAnyRows(
    store: relationalStore.RdbStore,
    tableName: string
  ): Promise<boolean> {
    const tableResultSet = await store.querySql(
      'SELECT 1 AS present FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
      ['table', tableName]
    );
    try {
      if (!tableResultSet.goToNextRow()) {
        return false;
      }
    } finally {
      tableResultSet.close();
    }
    const rowResultSet = await store.querySql(`SELECT 1 AS present FROM ${tableName} LIMIT 1`);
    try {
      return rowResultSet.goToNextRow();
    } finally {
      rowResultSet.close();
    }
  }

  private static async ensureColumn(
    store: relationalStore.RdbStore,
    tableName: string,
    columnName: string,
    columnType: string
  ): Promise<void> {
    const resultSet = await store.querySql(`PRAGMA table_info(${tableName})`);
    let columnExists = false;
    try {
      const nameIndex = resultSet.getColumnIndex('name');
      while (resultSet.goToNextRow()) {
        if (resultSet.getString(nameIndex) === columnName) {
          columnExists = true;
          break;
        }
      }
    } finally {
      resultSet.close();
    }
    if (!columnExists) {
      await store.executeSql(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${columnType}`);
    }
  }

  private static async readDistributedRegistrationVersion(
    store: relationalStore.RdbStore
  ): Promise<number> {
    const predicates = new relationalStore.RdbPredicates(HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE);
    predicates.equalTo('rowId', HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_ROW_ID);
    const resultSet = await store.queryWithoutRowCount(predicates, ['registrationVersion']);
    try {
      if (!resultSet.goToNextRow()) {
        return 0;
      }
      return resultSet.getLong(resultSet.getColumnIndex('registrationVersion'));
    } finally {
      resultSet.close();
    }
  }

  private static async writeDistributedRegistrationVersion(
    store: relationalStore.RdbStore,
    version: number = HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION
  ): Promise<void> {
    await store.insert(
      HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE,
      {
        rowId: HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_ROW_ID,
        registrationVersion: version,
        updatedAt: Date.now()
      },
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE
    );
  }
}
