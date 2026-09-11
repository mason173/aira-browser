import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AiraSyncJankProbe } from '../../common/debug/AiraSyncJankProbe';

export const HUAWEI_SPACE_BOOKMARK_HEAD_TABLE: string = 'AiraG8BookmarkHeads';
export const HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE: string = 'AiraG8BookmarkBlocks';
export const HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE: string = 'AiraG2PersonalizationCommits';
export const HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_TABLE: string = 'AiraG2NovelBookshelfCommits';
export const HUAWEI_SPACE_HISTORY_TABLE: string = 'AiraH1HistoryRecords';
export const HUAWEI_SPACE_HISTORY_HEAD_TABLE: string = 'AiraH2HistoryHeads';
export const HUAWEI_SPACE_HISTORY_BLOCK_TABLE: string = 'AiraH2HistoryBlocks';

const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE: string =
  'AiraHuaweiSpaceDistributedRegistration';
const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_ROW_ID: string = 'active-cloud-tables';
export const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION: number = 6;
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
const HUAWEI_SPACE_HISTORY_HEAD_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_HISTORY_HEAD_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    recordKind TEXT,
    logicalId TEXT,
    data TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_HISTORY_HEAD_ACCOUNT_KIND_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH2HistoryHeadsAccountKind
    ON ${HUAWEI_SPACE_HISTORY_HEAD_TABLE}(accountUid, recordKind, updatedAt)`;
const HUAWEI_SPACE_HISTORY_HEAD_ACCOUNT_LOGICAL_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH2HistoryHeadsAccountLogical
    ON ${HUAWEI_SPACE_HISTORY_HEAD_TABLE}(accountUid, recordKind, logicalId)`;
const HUAWEI_SPACE_HISTORY_BLOCK_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_HISTORY_BLOCK_TABLE} (
    rowId TEXT PRIMARY KEY,
    accountUid TEXT,
    recordKind TEXT,
    logicalId TEXT,
    data TEXT,
    updatedAt INTEGER
  )`;
const HUAWEI_SPACE_HISTORY_BLOCK_ACCOUNT_KIND_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH2HistoryBlocksAccountKind
    ON ${HUAWEI_SPACE_HISTORY_BLOCK_TABLE}(accountUid, recordKind, updatedAt)`;
const HUAWEI_SPACE_HISTORY_BLOCK_ACCOUNT_LOGICAL_INDEX: string =
  `CREATE INDEX IF NOT EXISTS idxAiraH2HistoryBlocksAccountLogical
    ON ${HUAWEI_SPACE_HISTORY_BLOCK_TABLE}(accountUid, recordKind, logicalId)`;
const HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_SCHEMA: string =
  `CREATE TABLE IF NOT EXISTS ${HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_TABLE} (
    rowId TEXT PRIMARY KEY,
    registrationVersion INTEGER,
    updatedAt INTEGER
  )`;

const HUAWEI_SPACE_RDB_LOG_DOMAIN: number = 0x0000;
const HUAWEI_SPACE_RDB_LOG_TAG: string = 'HuaweiSpaceRdb';

export function shouldRegisterHuaweiSpaceDistributedTables(
  registrationVersion: number,
  currentVersion: number = HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
  hasLegacyDistributedRows: boolean = false
): boolean {
  if (registrationVersion < currentVersion) {
    return true;
  }
  return registrationVersion <= 0 && hasLegacyDistributedRows;
}

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
    const startedAt = Date.now();
    AiraSyncJankProbe.markExtra('rdb_open_start', databaseName);
    hilog.info(
      HUAWEI_SPACE_RDB_LOG_DOMAIN,
      HUAWEI_SPACE_RDB_LOG_TAG,
      'rdbOpen start db=%{public}s',
      databaseName
    );
    const store = await relationalStore.getRdbStore(context, storeConfig);
    try {
      const bookmarkHeadTableHasRows = await HuaweiSpaceRdbStoreOwner.hasAnyRows(
        store,
        HUAWEI_SPACE_BOOKMARK_HEAD_TABLE
      );
      const personalizationTableHasRows = await HuaweiSpaceRdbStoreOwner.hasAnyRows(
        store,
        HUAWEI_SPACE_PERSONALIZATION_COMMIT_TABLE
      );
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_SCHEMA);
      await HuaweiSpaceRdbStoreOwner.ensureColumn(
        store,
        HUAWEI_SPACE_BOOKMARK_HEAD_TABLE,
        'storageEpoch',
        'INTEGER'
      );
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_KIND_INDEX);
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_HEAD_ACCOUNT_LOGICAL_INDEX);
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_SCHEMA);
      await HuaweiSpaceRdbStoreOwner.ensureColumn(
        store,
        HUAWEI_SPACE_BOOKMARK_BLOCK_TABLE,
        'storageEpoch',
        'INTEGER'
      );
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_KIND_INDEX);
      await store.executeSql(HUAWEI_SPACE_BOOKMARK_BLOCK_ACCOUNT_LOGICAL_INDEX);
      await store.executeSql(HUAWEI_SPACE_PERSONALIZATION_COMMIT_SCHEMA);
      await store.executeSql(HUAWEI_SPACE_PERSONALIZATION_COMMIT_INDEX);
      await store.executeSql(HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_SCHEMA);
      await store.executeSql(HUAWEI_SPACE_NOVEL_BOOKSHELF_COMMIT_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_SCHEMA);
      await store.executeSql(HUAWEI_SPACE_HISTORY_ACCOUNT_KIND_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_ACCOUNT_LOGICAL_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_HEAD_SCHEMA);
      await store.executeSql(HUAWEI_SPACE_HISTORY_HEAD_ACCOUNT_KIND_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_HEAD_ACCOUNT_LOGICAL_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_BLOCK_SCHEMA);
      await store.executeSql(HUAWEI_SPACE_HISTORY_BLOCK_ACCOUNT_KIND_INDEX);
      await store.executeSql(HUAWEI_SPACE_HISTORY_BLOCK_ACCOUNT_LOGICAL_INDEX);
      await store.executeSql(HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_SCHEMA);
      const registrationVersion = await HuaweiSpaceRdbStoreOwner.readDistributedRegistrationVersion(
        store
      );
      const hasLegacyDistributedRows = bookmarkHeadTableHasRows || personalizationTableHasRows;
      const shouldRegisterDistributedTables = shouldRegisterHuaweiSpaceDistributedTables(
        registrationVersion,
        HUAWEI_SPACE_DISTRIBUTED_REGISTRATION_VERSION,
        hasLegacyDistributedRows
      );
      if (registrationVersion <= 0 && hasLegacyDistributedRows) {
        await HuaweiSpaceRdbStoreOwner.writeDistributedRegistrationVersion(
          store,
          HUAWEI_SPACE_PRE_NOVEL_REGISTRATION_VERSION
        );
      }
      if (shouldRegisterDistributedTables) {
        const registerStartedAt = Date.now();
        AiraSyncJankProbe.markExtra('rdb_setDistributedTables_start', databaseName);
        hilog.info(
          HUAWEI_SPACE_RDB_LOG_DOMAIN,
          HUAWEI_SPACE_RDB_LOG_TAG,
          'setDistributedTables start db=%{public}s registrationVersion=%{public}d',
          databaseName,
          registrationVersion
        );
        await HuaweiSpaceRdbStoreOwner.prepareDistributedTables(store);
        await HuaweiSpaceRdbStoreOwner.writeDistributedRegistrationVersion(store);
        AiraSyncJankProbe.endExtra('rdb_setDistributedTables', registerStartedAt, databaseName);
        hilog.info(
          HUAWEI_SPACE_RDB_LOG_DOMAIN,
          HUAWEI_SPACE_RDB_LOG_TAG,
          'setDistributedTables success db=%{public}s durationMs=%{public}d',
          databaseName,
          Date.now() - registerStartedAt
        );
      }
      AiraSyncJankProbe.endExtra(
        'rdb_open',
        startedAt,
        `db=${databaseName} shouldRegister=${shouldRegisterDistributedTables ? 1 : 0}`
      );
      hilog.info(
        HUAWEI_SPACE_RDB_LOG_DOMAIN,
        HUAWEI_SPACE_RDB_LOG_TAG,
        'rdbOpen success db=%{public}s durationMs=%{public}d registrationVersion=%{public}d shouldRegister=%{public}d',
        databaseName,
        Date.now() - startedAt,
        registrationVersion,
        shouldRegisterDistributedTables ? 1 : 0
      );
      return store;
    } catch (error) {
      try {
        await store.close();
      } catch (_closeError) {
      }
      const candidate = error as Error;
      hilog.error(
        HUAWEI_SPACE_RDB_LOG_DOMAIN,
        HUAWEI_SPACE_RDB_LOG_TAG,
        'rdbOpen failed db=%{public}s durationMs=%{public}d message=%{public}s',
        databaseName,
        Date.now() - startedAt,
        candidate.message ?? JSON.stringify(error)
      );
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
        HUAWEI_SPACE_HISTORY_HEAD_TABLE,
        HUAWEI_SPACE_HISTORY_BLOCK_TABLE
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
