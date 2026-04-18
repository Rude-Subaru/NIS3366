import relationalStore from '@ohos.data.relationalStore'
import common from '@ohos.app.ability.common'

/** 聊天记录表对应的数据模型 */
export interface MessageRecord {
  id: number
  conversationId: number
  content: string
  isUser: boolean
  timestamp: string
}

/** 日程表对应的数据模型 */
export interface ScheduleRecord {
  id: number
  conversationId: number
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

/** 会话表对应的数据模型 */
export interface ConversationRecord {
  id: number
  userId: number
  title: string
  type: 'general' | 'psych'
  parentConversationId: number
  createdTime: string
  updatedTime: string
  lastMessage: string
}

export interface AuthResult {
  success: boolean
  message: string
  userId?: number
}

export interface UserInfo {
  userId: number
  username: string
}

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: 'AIAssistant.db',
  securityLevel: relationalStore.SecurityLevel.S1
}

// 统一维护查询列，避免不同查询入口各自手写字段名造成遗漏。
const MESSAGE_COLUMNS: string[] = ['id', 'conversationId', 'content', 'isUser', 'timestamp']
const SCHEDULE_COLUMNS: string[] = ['id', 'conversationId', 'content', 'createdTime', 'remindTime', 'isDone']
const USER_COLUMNS: string[] = ['id', 'username', 'password', 'createdTime']
const CONVERSATION_COLUMNS: string[] = ['id', 'userId', 'title', 'type', 'parentConversationId', 'createdTime', 'updatedTime', 'lastMessage']

/**
 * 数据库管理器。
 * 负责用户、会话、消息和日程数据的统一持久化。
 */
export class DatabaseManager {
  private static context: common.UIAbilityContext | null = null
  private static store: relationalStore.RdbStore | null = null
  private static initialized: boolean = false

  /** 由页面在进入时注入 AbilityContext，数据库实例本身不主动持有页面对象。 */
  setContext(context: common.UIAbilityContext): void {
    DatabaseManager.context = context
  }

  /**
   * 初始化数据库与所有业务表。
   * 表结构采用“能向前兼容旧版本”的方式：先建表，再补列，便于课程迭代开发。
   */
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
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Messages (id INTEGER PRIMARY KEY AUTOINCREMENT, conversationId INTEGER DEFAULT 0, content TEXT NOT NULL, isUser INTEGER NOT NULL, timestamp TEXT NOT NULL)'
      )
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Schedules (id INTEGER PRIMARY KEY AUTOINCREMENT, conversationId INTEGER DEFAULT 0, content TEXT NOT NULL, createdTime TEXT NOT NULL, remindTime TEXT, isDone INTEGER DEFAULT 0)'
      )
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Users (id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT NOT NULL UNIQUE, password TEXT NOT NULL, createdTime TEXT NOT NULL)'
      )
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS AppSettings (key TEXT PRIMARY KEY, value TEXT NOT NULL)'
      )
      await store.executeSql(
        'CREATE TABLE IF NOT EXISTS Conversations (id INTEGER PRIMARY KEY AUTOINCREMENT, userId INTEGER NOT NULL, title TEXT NOT NULL, type TEXT NOT NULL, parentConversationId INTEGER DEFAULT 0, createdTime TEXT NOT NULL, updatedTime TEXT NOT NULL, lastMessage TEXT DEFAULT "")'
      )

      await this.safeAddColumn(store, 'Messages', 'conversationId INTEGER DEFAULT 0')
      await this.safeAddColumn(store, 'Schedules', 'conversationId INTEGER DEFAULT 0')
      await this.safeAddColumn(store, 'Conversations', 'parentConversationId INTEGER DEFAULT 0')

      DatabaseManager.store = store
      DatabaseManager.initialized = true
      return true
    } catch (error) {
      console.error('DatabaseManager initDB error:', JSON.stringify(error))
      return false
    }
  }

  /** 保存一条消息，同时刷新对应会话的最近活跃时间和预览内容。 */
  async saveMessage(content: string, isUser: boolean, conversationId?: number): Promise<MessageRecord> {
    await this.ensureStoreReady()
    const resolvedConversationId = await this.resolveConversationId(conversationId)
    const timestamp: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      conversationId: resolvedConversationId,
      content: content,
      isUser: isUser ? 1 : 0,
      timestamp: timestamp
    }

    const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Messages', valueBucket)
    if (resolvedConversationId > 0) {
      await this.updateConversationActivity(resolvedConversationId, content, isUser)
    }

    return {
      id: rowId,
      conversationId: resolvedConversationId,
      content: content,
      isUser: isUser,
      timestamp: timestamp
    }
  }

  /** 读取最近消息，供聊天页展示和读执行体拼装短期记忆使用。 */
  async getRecentMessages(count: number, conversationId?: number): Promise<MessageRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Messages')
    const resolvedConversationId = await this.resolveConversationId(conversationId, false)
    if (resolvedConversationId > 0) {
      predicates.equalTo('conversationId', resolvedConversationId)
    }
    predicates.orderByDesc('id').limitAs(count)
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, MESSAGE_COLUMNS)
    const records: MessageRecord[] = this.readMessages(resultSet)
    records.reverse()
    return records
  }

  /** 保存日程时按当前会话隔离，保证不同会话之间互不干扰。 */
  async saveSchedule(content: string, remindTime?: string, conversationId?: number): Promise<ScheduleRecord> {
    await this.ensureStoreReady()
    const resolvedConversationId = await this.resolveConversationId(conversationId)
    const createdTime: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      conversationId: resolvedConversationId,
      content: content,
      createdTime: createdTime,
      remindTime: remindTime ?? null,
      isDone: 0
    }

    const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Schedules', valueBucket)
    return {
      id: rowId,
      conversationId: resolvedConversationId,
      content: content,
      createdTime: createdTime,
      remindTime: remindTime,
      isDone: false
    }
  }

  async getAllSchedules(conversationId?: number): Promise<ScheduleRecord[]> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    const resolvedConversationId = await this.resolveConversationId(conversationId, false)
    if (resolvedConversationId > 0) {
      predicates.equalTo('conversationId', resolvedConversationId)
    }
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

  async updateSchedule(scheduleId: number, content: string, remindTime?: string): Promise<boolean> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.equalTo('id', scheduleId)
    const valueBucket: relationalStore.ValuesBucket = {
      content: content,
      remindTime: remindTime ?? null
    }
    const changedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
    return changedRows > 0
  }

  async deleteSchedule(scheduleId: number): Promise<boolean> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
    predicates.equalTo('id', scheduleId)
    const deletedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).delete(predicates)
    return deletedRows > 0
  }

  async createConversation(title: string, type: 'general' | 'psych' = 'general', parentConversationId: number = 0): Promise<ConversationRecord | null> {
    await this.ensureStoreReady()
    const currentUser = await this.getCurrentUser()
    if (currentUser === null) {
      return null
    }

    const now: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      userId: currentUser.userId,
      title: title,
      type: type,
      parentConversationId: parentConversationId,
      createdTime: now,
      updatedTime: now,
      lastMessage: ''
    }

    const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Conversations', valueBucket)
    await this.setCurrentConversation(rowId)
    return {
      id: rowId,
      userId: currentUser.userId,
      title: title,
      type: type,
      parentConversationId: parentConversationId,
      createdTime: now,
      updatedTime: now,
      lastMessage: ''
    }
  }

  async getConversations(): Promise<ConversationRecord[]> {
    await this.ensureStoreReady()
    const currentUser = await this.getCurrentUser()
    if (currentUser === null) {
      return []
    }

    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Conversations')
    predicates.equalTo('userId', currentUser.userId).orderByDesc('updatedTime')
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, CONVERSATION_COLUMNS)
    return this.readConversations(resultSet)
  }

  async getConversationById(conversationId: number): Promise<ConversationRecord | null> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Conversations')
    predicates.equalTo('id', conversationId)
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, CONVERSATION_COLUMNS)
    const records: ConversationRecord[] = this.readConversations(resultSet)
    return records.length > 0 ? records[0] : null
  }

  /** 删除普通会话时会级联清理其心理辅导子会话及关联数据。 */
  async deleteConversation(conversationId: number): Promise<boolean> {
    await this.ensureStoreReady()
    const targetConversation: ConversationRecord | null = await this.getConversationById(conversationId)
    if (targetConversation === null) {
      return false
    }

    const deleteIds: number[] = [conversationId]
    if (targetConversation.type === 'general') {
      const allConversations: ConversationRecord[] = await this.getConversations()
      for (let index = 0; index < allConversations.length; index++) {
        if (allConversations[index].parentConversationId === conversationId) {
          deleteIds.push(allConversations[index].id)
        }
      }
    }

    for (let index = 0; index < deleteIds.length; index++) {
      const currentId: number = deleteIds[index]
      const messagePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Messages')
      messagePredicates.equalTo('conversationId', currentId)
      await (DatabaseManager.store as relationalStore.RdbStore).delete(messagePredicates)

      const schedulePredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Schedules')
      schedulePredicates.equalTo('conversationId', currentId)
      await (DatabaseManager.store as relationalStore.RdbStore).delete(schedulePredicates)

      const conversationPredicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Conversations')
      conversationPredicates.equalTo('id', currentId)
      await (DatabaseManager.store as relationalStore.RdbStore).delete(conversationPredicates)
    }

    const currentConversation: ConversationRecord | null = await this.getCurrentConversation()
    if (currentConversation !== null) {
      let wasDeleted: boolean = false
      for (let index = 0; index < deleteIds.length; index++) {
        if (deleteIds[index] === currentConversation.id) {
          wasDeleted = true
          break
        }
      }
      if (wasDeleted) {
        const remainingConversations: ConversationRecord[] = await this.getConversations()
        if (remainingConversations.length > 0) {
          await this.setCurrentConversation(remainingConversations[0].id)
        } else {
          await this.clearCurrentConversation()
        }
      }
    }
    return true
  }

  async getCurrentConversation(): Promise<ConversationRecord | null> {
    await this.ensureStoreReady()
    const conversationIdStr: string | null = await this.getSetting('currentConversationId')
    if (conversationIdStr === null) {
      return null
    }
    return this.getConversationById(Number(conversationIdStr))
  }

  async setCurrentConversation(conversationId: number): Promise<void> {
    await this.ensureStoreReady()
    await this.setSetting('currentConversationId', `${conversationId}`)
  }

  async clearCurrentConversation(): Promise<void> {
    await this.ensureStoreReady()
    await this.deleteSetting('currentConversationId')
  }

  async ensureDefaultConversation(): Promise<ConversationRecord | null> {
    await this.ensureStoreReady()
    const currentConversation = await this.getCurrentConversation()
    if (currentConversation !== null) {
      return currentConversation
    }

    const conversations = await this.getConversations()
    if (conversations.length > 0) {
      await this.setCurrentConversation(conversations[0].id)
      return conversations[0]
    }

    return this.createConversation('新对话 1', 'general')
  }

  async getOrCreatePsychConversation(sourceConversationId?: number): Promise<ConversationRecord | null> {
    await this.ensureStoreReady()
    const currentUser = await this.getCurrentUser()
    if (currentUser === null) {
      return null
    }

    const parentConversationId: number = sourceConversationId ?? 0
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Conversations')
    predicates.equalTo('userId', currentUser.userId)
      .equalTo('type', 'psych')
      .equalTo('parentConversationId', parentConversationId)
      .orderByDesc('updatedTime')
      .limitAs(1)
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, CONVERSATION_COLUMNS)
    const records: ConversationRecord[] = this.readConversations(resultSet)
    if (records.length > 0) {
      await this.setCurrentConversation(records[0].id)
      return records[0]
    }

    const sourceConversation: ConversationRecord | null = parentConversationId > 0
      ? await this.getConversationById(parentConversationId)
      : null
    const title: string = this.buildPsychConversationTitle(sourceConversation)
    return this.createConversation(title, 'psych', parentConversationId)
  }

  async registerUser(username: string, password: string): Promise<AuthResult> {
    await this.ensureStoreReady()
    const exists: boolean = await this.userExists(username)
    if (exists) {
      return { success: false, message: '用户名已存在' }
    }

    const createdTime: string = new Date().toISOString()
    const valueBucket: relationalStore.ValuesBucket = {
      username: username,
      password: password,
      createdTime: createdTime
    }

    try {
      const rowId: number = await (DatabaseManager.store as relationalStore.RdbStore).insert('Users', valueBucket)
      return rowId > 0 ? { success: true, message: '注册成功', userId: rowId } : { success: false, message: '注册失败' }
    } catch (error) {
      console.error('registerUser error:', JSON.stringify(error))
      return { success: false, message: '注册失败' }
    }
  }

  async loginUser(username: string, password: string): Promise<AuthResult> {
    await this.ensureStoreReady()
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Users')
    predicates.equalTo('username', username)

    try {
      const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, USER_COLUMNS)
      if (resultSet.rowCount === 0) {
        resultSet.close()
        return { success: false, message: '用户名或密码错误' }
      }

      resultSet.goToFirstRow()
      const storedPassword: string = resultSet.getString(resultSet.getColumnIndex('password'))
      const userId: number = resultSet.getLong(resultSet.getColumnIndex('id'))
      resultSet.close()

      if (storedPassword !== password) {
        return { success: false, message: '用户名或密码错误' }
      }

      await this.setSetting('currentUserId', `${userId}`)
      await this.setSetting('currentUsername', username)

      const conversations = await this.getConversations()
      if (conversations.length > 0) {
        await this.setCurrentConversation(conversations[0].id)
      } else {
        await this.clearCurrentConversation()
      }

      return { success: true, message: '登录成功', userId: userId }
    } catch (error) {
      console.error('loginUser error:', JSON.stringify(error))
      return { success: false, message: '登录过程发生异常' }
    }
  }

  async logout(): Promise<void> {
    await this.ensureStoreReady()
    await this.deleteSetting('currentConversationId')
    await this.deleteSetting('currentUserId')
    await this.deleteSetting('currentUsername')
  }

  async getCurrentUser(): Promise<UserInfo | null> {
    await this.ensureStoreReady()
    const userIdStr: string | null = await this.getSetting('currentUserId')
    const username: string | null = await this.getSetting('currentUsername')
    if (userIdStr === null || username === null) {
      return null
    }

    return {
      userId: Number(userIdStr),
      username: username
    }
  }

  async isLoggedIn(): Promise<boolean> {
    const user = await this.getCurrentUser()
    return user !== null
  }

  async closeDB(): Promise<boolean> {
    if (DatabaseManager.store !== null) {
      try {
        await (DatabaseManager.store as relationalStore.RdbStore).close()
      } catch (error) {
        console.error('closeDB error:', JSON.stringify(error))
      }
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

  private async safeAddColumn(store: relationalStore.RdbStore, tableName: string, columnSql: string): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE ${tableName} ADD COLUMN ${columnSql}`)
    } catch (error) {
      // 已存在时忽略迁移错误，保证老数据库可以平滑升级。
    }
  }

  private async resolveConversationId(conversationId?: number, autoCreate: boolean = true): Promise<number> {
    if (conversationId !== undefined && conversationId > 0) {
      return conversationId
    }

    const currentConversation = await this.getCurrentConversation()
    if (currentConversation !== null) {
      return currentConversation.id
    }

    if (!autoCreate) {
      return 0
    }

    const createdConversation = await this.ensureDefaultConversation()
    return createdConversation !== null ? createdConversation.id : 0
  }

  private async updateConversationActivity(conversationId: number, content: string, isUser: boolean): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('Conversations')
    predicates.equalTo('id', conversationId)

    const conversation: ConversationRecord | null = await this.getConversationById(conversationId)
    let valueBucket: relationalStore.ValuesBucket = {
      updatedTime: new Date().toISOString(),
      lastMessage: content
    }

    if (isUser && conversation !== null) {
      valueBucket = {
        updatedTime: new Date().toISOString(),
        lastMessage: content,
        title: this.generateConversationTitle(content, conversation.type)
      }
    }

    await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
  }

  private generateConversationTitle(content: string, type: 'general' | 'psych'): string {
    const normalized: string = this.normalizeConversationText(content)
    const sanitized: string = this.removeTitleNoise(normalized)
    if (type === 'psych') {
      const label: string = this.detectPsychLabel(sanitized)
      const phrase: string = this.extractTitlePhrase(sanitized, 'psych')
      return this.combineTitle(label, phrase, true)
    }
    const label: string = this.detectGeneralLabel(sanitized)
    const phrase: string = this.extractTitlePhrase(sanitized, 'general')
    return this.combineTitle(label, phrase, false)
  }

  private normalizeConversationText(content: string): string {
    return content
      .toLowerCase()
      .replace(/[\r\n]+/g, ' ')
      .replace(/[，。！？,.!?：:；;【】\[\]\(\)“”‘’"'、]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  }

  private detectGeneralLabel(content: string): string {
    if (content.length === 0) {
      return '日常对话'
    }
    if (this.containsKeyword(content, ['安排', '提醒', '日程', '待办', '开会', '会议', '上课', '约会', '截止']) || this.containsTimeExpression(content)) {
      return '日程安排'
    }
    if (this.containsKeyword(content, ['学习', '复习', '考试', '作业', '背单词', '英语', '数学', '论文', '刷题', '课程'])) {
      return '学习计划'
    }
    if (this.containsKeyword(content, ['工作', '项目', '方案', '汇报', '客户', '运营', '面试', '简历', '需求', '代码'])) {
      return '工作沟通'
    }
    if (this.containsKeyword(content, ['旅游', '出行', '机票', '火车', '酒店', '路线', '打车', '地铁'])) {
      return '出行安排'
    }
    if (this.containsKeyword(content, ['吃饭', '健身', '减肥', '作息', '睡觉', '购物', '买菜', '周末'])) {
      return '生活规划'
    }
    if (this.containsKeyword(content, ['焦虑', '难过', '压力', '委屈', '崩溃', '生气', '烦', 'emo', '失眠'])) {
      return '情绪倾诉'
    }
    return '日常对话'
  }

  private detectPsychLabel(content: string): string {
    if (this.containsKeyword(content, ['焦虑', '压力', '紧张', '失眠', '害怕', '崩溃'])) {
      return '压力调节'
    }
    if (this.containsKeyword(content, ['难过', '委屈', '低落', '分手', '孤独', '伤心'])) {
      return '情绪疏导'
    }
    if (this.containsKeyword(content, ['家人', '朋友', '同学', '同事', '矛盾', '吵架', '冲突'])) {
      return '关系困扰'
    }
    return '情绪支持'
  }

  private extractTitlePhrase(content: string, type: 'general' | 'psych'): string {
    if (type === 'psych') {
      return this.extractPsychPhrase(content)
    }
    return this.extractGeneralPhrase(content)
  }

  private extractGeneralPhrase(content: string): string {
    const timePhrase: string = this.extractTimePhrase(content)
    const actionPhrase: string = this.extractActionPhrase(content)
    const eventPhrase: string = this.extractKeywordPhrase(content, ['开会', '会议', '上课', '面试', '汇报', '复习', '考试', '作业', '背单词', '健身', '购物', '出行', '旅行', '机票', '酒店', '约会', '看医生'])

    if (timePhrase.length > 0 && actionPhrase.length > 0) {
      return this.trimTitlePhrase(`${timePhrase}${actionPhrase}`)
    }
    if (timePhrase.length > 0 && eventPhrase.length > 0) {
      return this.trimTitlePhrase(`${timePhrase}${eventPhrase}`)
    }
    if (actionPhrase.length > 0) {
      return this.trimTitlePhrase(actionPhrase)
    }
    if (eventPhrase.length > 0) {
      return this.trimTitlePhrase(eventPhrase)
    }
    if (timePhrase.length > 0) {
      return this.trimTitlePhrase(timePhrase)
    }

    const topicPhrase: string = this.extractKeywordPhrase(content, ['英语', '数学', '论文', '项目', '客户', '简历', '路线', '作息', '睡眠', '饮食', '情绪', '上海', '北京', '杭州', '深圳', '广州'])
    if (topicPhrase.length > 0) {
      return this.trimTitlePhrase(topicPhrase)
    }
    return ''
  }

  private extractPsychPhrase(content: string): string {
    const topicPhrase: string = this.extractKeywordPhrase(content, ['失眠', '焦虑', '压力', '紧张', '低落', '委屈', '分手', '孤独', '吵架', '矛盾', '家人', '朋友', '同事', '同学'])
    if (topicPhrase.length > 0) {
      return this.trimTitlePhrase(topicPhrase)
    }
    const timePhrase: string = this.extractTimePhrase(content)
    if (timePhrase.length > 0) {
      return this.trimTitlePhrase(timePhrase)
    }
    return ''
  }

  private extractTimePhrase(content: string): string {
    const matches: RegExpMatchArray | null = content.match(/((今天|明天|后天|周一|周二|周三|周四|周五|周六|周日)?(上午|中午|下午|晚上)?(\d+点半|\d+点)?)/)
    if (matches === null || matches.length === 0) {
      return ''
    }
    const value: string = matches[0].trim()
    return value.length > 1 ? value : ''
  }

  private extractActionPhrase(content: string): string {
    const goMatch: RegExpMatchArray | null = content.match(/去[一-龥a-z0-9]{1,6}/)
    if (goMatch !== null && goMatch.length > 0) {
      return goMatch[0]
    }
    const eventMatch: RegExpMatchArray | null = content.match(/(上课|开会|面试|汇报|复习|考试|健身|购物|看医生)/)
    if (eventMatch !== null && eventMatch.length > 0) {
      return eventMatch[0]
    }
    return ''
  }

  private extractKeywordPhrase(content: string, keywords: string[]): string {
    for (let index = 0; index < keywords.length; index++) {
      if (content.indexOf(keywords[index]) >= 0) {
        return keywords[index]
      }
    }
    return ''
  }

  private trimTitlePhrase(phrase: string): string {
    const compact: string = phrase.replace(/\s+/g, '')
    if (compact.length > 8) {
      return compact.substring(0, 8)
    }
    return compact
  }

  private containsTimeExpression(content: string): boolean {
    return /(今天|明天|后天|周一|周二|周三|周四|周五|周六|周日|上午|中午|下午|晚上|\d+点半|\d+点|\d+月\d+日)/.test(content)
  }

  private combineTitle(label: string, phrase: string, isPsych: boolean): string {
    const prefix: string = isPsych ? '心理：' : ''
    if (phrase.length === 0) {
      return `${prefix}${label}`
    }
    if (label.indexOf(phrase) >= 0 || phrase.indexOf(label) >= 0) {
      return `${prefix}${label}`
    }
    return `${prefix}${label}·${phrase}`
  }

  private removeTitleNoise(content: string): string {
    return content
      .replace(/帮我|请帮我|我想|我希望|需要|想要|一下|可以|请问|然后|就是|麻烦|是否|怎么|怎样|关于|有关/g, ' ')
      .replace(/草你妈|操你妈|我草|卧槽|傻逼|煞笔|妈的|滚蛋|垃圾|废物|去死|脑残|神经病/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()
  }

  private containsKeyword(content: string, keywords: string[]): boolean {
    for (let index = 0; index < keywords.length; index++) {
      if (content.indexOf(keywords[index]) >= 0) {
        return true
      }
    }
    return false
  }

  private buildPsychConversationTitle(sourceConversation: ConversationRecord | null): string {
    if (sourceConversation === null) {
      return '心理：情绪支持'
    }

    const sourceTitle: string = this.sanitizeStoredTitle(sourceConversation.title, 'general').replace(/^心理：/, '').trim()
    if (sourceTitle.length === 0 || sourceTitle === '日常对话' || sourceTitle.indexOf('新对话') === 0) {
      return '心理：情绪支持'
    }
    return `心理：${sourceTitle}`
  }

  private sanitizeStoredTitle(title: string, type: 'general' | 'psych'): string {
    const normalized: string = this.normalizeConversationText(title)
    if (normalized.length === 0) {
      return type === 'psych' ? '心理：情绪支持' : '日常对话'
    }

    if (this.containsKeyword(normalized, ['草你妈', '操你妈', '我草', '卧槽', '傻逼', '煞笔', '妈的', '滚蛋', '垃圾', '废物', '去死', '脑残', '神经病'])) {
      return type === 'psych' ? '心理：情绪支持' : '日常对话'
    }
    return title
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
    const changedRows: number = await (DatabaseManager.store as relationalStore.RdbStore).update(valueBucket, predicates)
    if (changedRows === 0) {
      await (DatabaseManager.store as relationalStore.RdbStore).insert('AppSettings', valueBucket)
    }
  }

  private async getSetting(key: string): Promise<string | null> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('AppSettings')
    predicates.equalTo('key', key)
    const resultSet: relationalStore.ResultSet = await (DatabaseManager.store as relationalStore.RdbStore).query(predicates, ['value'])
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return null
    }
    resultSet.goToFirstRow()
    const value: string = resultSet.getString(resultSet.getColumnIndex('value'))
    resultSet.close()
    return value
  }

  private async deleteSetting(key: string): Promise<void> {
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates('AppSettings')
    predicates.equalTo('key', key)
    await (DatabaseManager.store as relationalStore.RdbStore).delete(predicates)
  }

  private readMessages(resultSet: relationalStore.ResultSet): MessageRecord[] {
    const records: MessageRecord[] = []
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return records
    }

    const idIndex: number = resultSet.getColumnIndex('id')
    const conversationIdIndex: number = resultSet.getColumnIndex('conversationId')
    const contentIndex: number = resultSet.getColumnIndex('content')
    const isUserIndex: number = resultSet.getColumnIndex('isUser')
    const timestampIndex: number = resultSet.getColumnIndex('timestamp')

    if (resultSet.goToFirstRow()) {
      do {
        records.push({
          id: resultSet.getLong(idIndex),
          conversationId: resultSet.getLong(conversationIdIndex),
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
    const conversationIdIndex: number = resultSet.getColumnIndex('conversationId')
    const contentIndex: number = resultSet.getColumnIndex('content')
    const createdTimeIndex: number = resultSet.getColumnIndex('createdTime')
    const remindTimeIndex: number = resultSet.getColumnIndex('remindTime')
    const isDoneIndex: number = resultSet.getColumnIndex('isDone')

    if (resultSet.goToFirstRow()) {
      do {
        records.push({
          id: resultSet.getLong(idIndex),
          conversationId: resultSet.getLong(conversationIdIndex),
          content: resultSet.getString(contentIndex),
          createdTime: resultSet.getString(createdTimeIndex),
          remindTime: resultSet.isColumnNull(remindTimeIndex) ? undefined : resultSet.getString(remindTimeIndex),
          isDone: resultSet.getLong(isDoneIndex) === 1
        })
      } while (resultSet.goToNextRow())
    }

    resultSet.close()
    return records
  }

  private readConversations(resultSet: relationalStore.ResultSet): ConversationRecord[] {
    const records: ConversationRecord[] = []
    if (resultSet.rowCount === 0) {
      resultSet.close()
      return records
    }

    const idIndex: number = resultSet.getColumnIndex('id')
    const userIdIndex: number = resultSet.getColumnIndex('userId')
    const titleIndex: number = resultSet.getColumnIndex('title')
    const typeIndex: number = resultSet.getColumnIndex('type')
    const parentConversationIdIndex: number = resultSet.getColumnIndex('parentConversationId')
    const createdTimeIndex: number = resultSet.getColumnIndex('createdTime')
    const updatedTimeIndex: number = resultSet.getColumnIndex('updatedTime')
    const lastMessageIndex: number = resultSet.getColumnIndex('lastMessage')

    if (resultSet.goToFirstRow()) {
      do {
        const typeValue: string = resultSet.getString(typeIndex)
        records.push({
          id: resultSet.getLong(idIndex),
          userId: resultSet.getLong(userIdIndex),
          title: this.sanitizeStoredTitle(resultSet.getString(titleIndex), typeValue === 'psych' ? 'psych' : 'general'),
          type: typeValue === 'psych' ? 'psych' : 'general',
          parentConversationId: resultSet.isColumnNull(parentConversationIdIndex) ? 0 : resultSet.getLong(parentConversationIdIndex),
          createdTime: resultSet.getString(createdTimeIndex),
          updatedTime: resultSet.getString(updatedTimeIndex),
          lastMessage: resultSet.isColumnNull(lastMessageIndex) ? '' : resultSet.getString(lastMessageIndex)
        })
      } while (resultSet.goToNextRow())
    }

    resultSet.close()
    return records
  }
}










