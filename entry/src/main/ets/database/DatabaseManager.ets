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

/** 用户表对应的数据模型 */
export interface UserRecord {
  id: number
  username: string
  password: string
  createdTime: string
}

// === 新增：为用户认证和状态提取专门的接口，解决 arkts-no-obj-literals-as-types 错误 ===
export interface AuthResult {
  success: boolean
  message: string
  userId?: number
}

export interface UserInfo {
  userId: number
  username: string
}
// =========================================================================

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'AIAssistant.db',
  securityLevel: relationalStore.SecurityLevel.S1
}

const MESSAGE_COLUMNS: string[] = ['id', 'content', 'isUser', 'timestamp']
const SCHEDULE_COLUMNS: string[] = ['id', 'content', 'createdTime', 'remindTime', 'isDone']
const USER_COLUMNS: string[] = ['id', 'username', 'password', 'createdTime']

/**
 * 数据库管理器 (同学B的核心任务1)
 * 负责 SQLite 数据库的初始化以及 Messages、Schedules、Users 表的 CRUD 操作。
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
      await store.executeSql('CREATE TABLE IF NOT EXISTS Messages (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, isUser INTEGER NOT NULL, timestamp TEXT NOT NULL)')
      await store.executeSql('CREATE TABLE IF NOT EXISTS Schedules (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, createdTime TEXT NOT NULL, remindTime TEXT, isDone INTEGER DEFAULT 0)')
      await store.executeSql('CREATE TABLE IF NOT EXISTS Users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, password TEXT NOT NULL, createdTime TEXT NOT NULL)')
      await store.executeSql('CREATE TABLE IF NOT EXISTS AppSettings (key TEXT PRIMARY KEY, value TEXT NOT NULL)')

      DatabaseManager.store = store
      DatabaseManager.initialized = true
      return true
    } catch (error) {
      console.error('DatabaseManager initDB error:', JSON.stringify(error))
      return false
    }
  }

  // 2. 存储聊天消息
  async saveMessage(content: string, isUser: boolean): Promise<MessageRecord> {
    await this.ensureStoreReady()
    const timestamp: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      isUser: isUser ? 1 : 0,
      timestamp: timestamp
    }

    try {
      const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Messages', valueBucket)
      // 使用 as 进行类型断言，解决 arkts-no-untyped-obj-literals 错误
      return { id: rowId, content, isUser, timestamp } as MessageRecord
    } catch (error) {
      console.error('saveMessage error:', JSON.stringify(error))
      // ✅ 正确：抛出标准的 Error 实例
      throw new Error("Database is not ready");
    }
  }

  // 3. 获取近期对话记忆
  async getRecentMessages(count: number): Promise<MessageRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Messages')
    predicates.orderByDesc('id').limitAs(count)
    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, MESSAGE_COLUMNS)
      const records: MessageRecord[] = this.readMessages(resultSet)
      records.reverse()
      return records
    } catch (error) {
      console.error('getRecentMessages error:', JSON.stringify(error))
      return []
    }
  }

  // 4. 存储日程安排
  async saveSchedule(content: string, remindTime?: string): Promise<ScheduleRecord> {
    await this.ensureStoreReady()
    const createdTime: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      createdTime: createdTime,
      remindTime: remindTime ?? null,
      isDone: 0
    }

    try {
      const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Schedules', valueBucket)
      return { id: rowId, content, createdTime, remindTime, isDone: false } as ScheduleRecord
    } catch (error) {
      console.error('saveSchedule error:', JSON.stringify(error))
      // ✅ 正确：抛出标准的 Error 实例
      throw new Error("Database is not ready");
    }
  }

  async getAllSchedules(): Promise<ScheduleRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.orderByDesc('id')
    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, SCHEDULE_COLUMNS)
      return this.readSchedules(resultSet)
    } catch (error) {
      console.error('getAllSchedules error:', JSON.stringify(error))
      return []
    }
  }

  async markScheduleDone(scheduleId: number): Promise<boolean> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.equalTo('id', scheduleId)
    const valueBucket: relationalStore.ValuesBucket = { isDone: 1 }

    try {
      const changedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
      return changedRows > 0
    } catch (error) {
      console.error('markScheduleDone error:', JSON.stringify(error))
      return false
    }
  }

  // ===== 用户相关操作 =====

  // 替换内联返回类型为 AuthResult
  async registerUser(username: string, password: string): Promise<AuthResult> {
    await this.ensureStoreReady()

    const exists: boolean = await this.userExists(username)
    if (exists) {
      return { success: false, message: '用户名已存在' } as AuthResult
    }

    const createdTime: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      username: username,
      password: password,
      createdTime: createdTime
    }

    try {
      const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Users', valueBucket)
      if (rowId > 0) {
        return { success: true, message: '注册成功' } as AuthResult
      }
      return { success: false, message: '注册失败' } as AuthResult
    } catch (error) {
      console.error('registerUser error:', JSON.stringify(error))
      return { success: false, message: '注册失败' } as AuthResult
    }
  }

  // 替换内联返回类型为 AuthResult
  async loginUser(username: string, password: string): Promise<AuthResult> {
    await this.ensureStoreReady()

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Users')
    predicates.equalTo('username', username)

    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, USER_COLUMNS)

      if (resultSet.rowCount === 0) {
        resultSet.close()
        return { success: false, message: '用户名或密码错误' } as AuthResult
      }

      resultSet.goToFirstRow()
      const storedPassword: string = resultSet.getString(resultSet.getColumnIndex('password'))
      const userId: number = resultSet.getLong(resultSet.getColumnIndex('id'))
      resultSet.close()

      if (storedPassword !== password) {
        return { success: false, message: '用户名或密码错误' } as AuthResult
      }

      await this.setSetting('currentUserId', String(userId))
      await this.setSetting('currentUsername', username)

      return { success: true, message: '登录成功', userId: userId } as AuthResult
    } catch (error) {
      console.error('loginUser error:', JSON.stringify(error))
      return { success: false, message: '登录过程发生异常' } as AuthResult
    }
  }

  async logout(): Promise<void> {
    await this.ensureStoreReady()
    await this.deleteSetting('currentUserId')
    await this.deleteSetting('currentUsername')
  }

  // 替换内联返回类型为 UserInfo | null
  async getCurrentUser(): Promise<UserInfo | null> {
    await this.ensureStoreReady()

    const userIdStr: string | null = await this.getSetting('currentUserId')
    const username: string | null = await this.getSetting('currentUsername')

    if (userIdStr === null || username === null) {
      return null
    }

    return { userId: Number(userIdStr), username: username } as UserInfo
  }

  async isLoggedIn(): Promise<boolean> {
    const user = await this.getCurrentUser()
    return user !== null
  }

  private async userExists(username: string): Promise<boolean> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Users')
    predicates.equalTo('username', username)
    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, ['id'])
      const exists: boolean = resultSet.rowCount > 0
      resultSet.close()
      return exists
    } catch (error) {
      console.error('userExists error:', JSON.stringify(error))
      return false
    }
  }

  private async setSetting(key: string, value: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('AppSettings')
    predicates.equalTo('key', key)
    const valueBucket: relationalStore.ValuesBucket = { key: key, value: value }
    try {
      const changedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
      if (changedRows === 0) {
        await (DatabaseManager.store as relationalStore.RdbStore).insert('AppSettings', valueBucket)
      }
    } catch (error) {
      console.error('setSetting error:', JSON.stringify(error))
    }
  }

  private async getSetting(key: string): Promise<string | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('AppSettings')
    predicates.equalTo('key', key)
    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, ['value'])
      if (resultSet.rowCount === 0) {
        resultSet.close()
        return null
      }
      resultSet.goToFirstRow()
      const value: string = resultSet.getString(resultSet.getColumnIndex('value'))
      resultSet.close()
      return value
    } catch (error) {
      console.error('getSetting error:', JSON.stringify(error))
      return null
    }
  }

  private async deleteSetting(key: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('AppSettings')
    predicates.equalTo('key', key)
    try {
      await (DatabaseManager.store as relationalStore.RdbStore).delete(predicates)
    } catch (error) {
      console.error('deleteSetting error:', JSON.stringify(error))
    }
  }

  async closeDB(): Promise<boolean> {
    if (DatabaseManager.store !== null) {
      try {
        await (DatabaseManager.store as relationalStore.RdbStore).close()
        DatabaseManager.store = null
        DatabaseManager.initialized = false
      } catch (error) {
        console.error('closeDB error:', JSON.stringify(error))
      }
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
        } as MessageRecord)
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
          remindTime: remindTime,
          isDone: resultSet.getLong(isDoneIndex) === 1
        } as ScheduleRecord)
      } while (resultSet.goToNextRow())
    }

    resultSet.close()
    return records
  }
}