import relationalStore from '@ohos.data.relationalStore'
import common from '@ohos.app.ability.common'


/** 聊天记录表对应的数据模型 */
export interface MessageRecord {
  id: number
  content: string
  isUser: boolean
  timestamp: string
}

/** 日程表对应的数据模型 */
export interface ScheduleRecord {
  id: number
  content: string
  createdTime: string
  remindTime?: string
  isDone: boolean
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'AIAssistant.db',
  securityLevel: relationalStore.SecurityLevel.S1
}

const MESSAGE_COLUMNS: string[] = ['id', 'content', 'isUser', 'timestamp']
const SCHEDULE_COLUMNS: string[] = ['id', 'content', 'createdTime', 'remindTime', 'isDone']

/**
 * 数据库管理器 (同学B的核心任务1)
 * 负责 SQLite 数据库的初始化以及 Messages 和 Schedules 表的 CRUD 操作。
 */
export class DatabaseManager {
  private static context: common.UIAbilityContext | null = null
  private static store: relationalStore.RdbStore | null = null
  private static initialized: boolean = false

  setContext(context: common.UIAbilityContext): void {
    DatabaseManager.context = context
  }

  // 1. 初始化并建表
  async initDB(): Promise<boolean> {
    if (DatabaseManager.initialized && DatabaseManager.store !== null) {
      return true
    }

    if (DatabaseManager.context === null) {
      console.error('DatabaseManager context is not set')
      return false
    }

    try {
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(DatabaseManager.context, STORE_CONFIG)
      // 创建聊天记录表
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Messages (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, isUser INTEGER NOT NULL, timestamp TEXT NOT NULL)'
      )
      // 创建日程表
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Schedules (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, createdTime TEXT NOT NULL, remindTime TEXT, isDone INTEGER DEFAULT 0)'
      )

      DatabaseManager.store = store
      DatabaseManager.initialized = true
      return true
    } catch (error) {
      console.error('DatabaseManager initDB error:', JSON.stringify(error))
      return false
    }
  }

  // 2. 存储聊天消息 (对应分工图中的 saveMessage)
  async saveMessage(content: string, isUser: boolean): Promise<MessageRecord> {
    await this.ensureStoreReady()
    const timestamp: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      content,
      isUser: isUser ? 1 : 0,
      timestamp
    }

    const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Messages', valueBucket)
    return { id: rowId, content, isUser, timestamp }
  }

  // 3. 获取近期对话记忆 (对应分工图中的 getRecentMemory)
  async getRecentMessages(count: number): Promise<MessageRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Messages')
    predicates.orderByDesc('id').limitAs(count)
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, MESSAGE_COLUMNS)
    const records: MessageRecord[] = this.readMessages(resultSet)
    // 按照时间正序排列给大模型
    records.reverse()
    return records
  }

  // 4. 存储日程安排 (对应分工图中的 saveSchedule)
  async saveSchedule(content: string, remindTime?: string): Promise<ScheduleRecord> {
    await this.ensureStoreReady()
    const createdTime: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      content,
      createdTime,
      remindTime: remindTime ?? null,
      isDone: 0
    }

    const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Schedules', valueBucket)
    return { id: rowId, content, createdTime, remindTime, isDone: false }
  }

  async getAllSchedules(): Promise<ScheduleRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.orderByDesc('id')
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, SCHEDULE_COLUMNS)
    return this.readSchedules(resultSet)
  }

  async markScheduleDone(scheduleId: number): Promise<boolean> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.equalTo('id', scheduleId)
    const valueBucket: relationalStore.ValuesBucket = { isDone: 1 }

    const changedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
    return changedRows > 0
  }

  async closeDB(): Promise<boolean> {
    if (DatabaseManager.store !== null) {
      DatabaseManager.store = null
      DatabaseManager.initialized = false
    }
    return true
  }

  private async ensureStoreReady(): Promise<void> {
    const ready: boolean = await this.initDB()
    if (!ready || DatabaseManager.store === null) {
      throw new Error('Database is not ready')
    }
  }

  private readMessages(resultSet: relationalStore.ResultSet): MessageRecord[] {
    const records: MessageRecord[] = []
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return records
    }

    const idIndex: number = resultSet.getColumnIndex('id')
    const contentIndex: number = resultSet.getColumnIndex('content')
    const isUserIndex: number = resultSet.getColumnIndex('isUser')
    const timestampIndex: number = resultSet.getColumnIndex('timestamp')

    if (resultSet.goToFirstRow()) {
      do {
        records.push({
          id: resultSet.getLong(idIndex),
          content: resultSet.getString(contentIndex),
          isUser: resultSet.getLong(isUserIndex) === 1,
          timestamp: resultSet.getString(timestampIndex)
        })
      } while (resultSet.goToNextRow())
    }

    resultSet.close()
    return records
  }

  private readSchedules(resultSet: relationalStore.ResultSet): ScheduleRecord[] {
    const records: ScheduleRecord[] = []
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return records
    }

    const idIndex: number = resultSet.getColumnIndex('id')
    const contentIndex: number = resultSet.getColumnIndex('content')
    const createdTimeIndex: number = resultSet.getColumnIndex('createdTime')
    const remindTimeIndex: number = resultSet.getColumnIndex('remindTime')
    const isDoneIndex: number = resultSet.getColumnIndex('isDone')

    if (resultSet.goToFirstRow()) {
      do {
        const remindTime: string | undefined = resultSet.isColumnNull(remindTimeIndex) ? undefined : resultSet.getString(remindTimeIndex)
        records.push({
          id: resultSet.getLong(idIndex),
          content: resultSet.getString(contentIndex),
          createdTime: resultSet.getString(createdTimeIndex),
          remindTime,
          isDone: resultSet.getLong(isDoneIndex) === 1
        })
      } while (resultSet.goToNextRow())
    }

    resultSet.close()
    return records
  }
}