/**
 * 数据库管理器 - 接口定义
 * 负责：组员B（数据库模块）
 * 功能：封装所有数据库操作，提供简单的API给主逻辑调用
 * 
 * 【Mock模式】默认使用内存Mock，组员B后续替换为真实SQLite实现
 */

// 消息记录
interface MessageRecord {
  id: number
  content: string
  isUser: boolean
  timestamp: string
}

// 日程记录
interface ScheduleRecord {
  id: number
  content: string
  createdTime: string
  remindTime?: string
  isDone: boolean
}

export class DatabaseManager {
  private isInitialized: boolean = false
  
  // 【Mock数据】内存存储，开发阶段使用
  private mockMessages: MessageRecord[] = []
  private mockSchedules: ScheduleRecord[] = []

  /**
   * 初始化数据库
   * 组员B需要在此创建：
   * - Messages表（聊天记录）
   * - Schedules表（日程安排）
   */
  initDB(): boolean {
    console.info('DatabaseManager: 初始化数据库')
    
    // 【Mock模式】初始化内存数据
    this.mockMessages = []
    this.mockSchedules = []
    this.isInitialized = true
    
    // TODO: 组员B替换为真实SQLite初始化
    // 参考代码：
    // const db = relationalStore.getRdbStore(...)
    // db.executeSql('CREATE TABLE IF NOT EXISTS Messages (...)')
    // db.executeSql('CREATE TABLE IF NOT EXISTS Schedules (...)')
    
    return true
  }

  /**
   * 保存聊天消息
   * @param content 消息内容
   * @param isUser 是否用户发送
   */
  saveMessage(content: string, isUser: boolean): boolean {
    const record: MessageRecord = {
      id: this.mockMessages.length + 1,
      content: content,
      isUser: isUser,
      timestamp: new Date().toISOString()
    }
    this.mockMessages.push(record)
    console.info(`DatabaseManager: 保存消息 - ${content.substring(0, 20)}...`)
    
    // TODO: 组员B替换为真实插入
    // db.executeSql('INSERT INTO Messages (content, isUser, timestamp) VALUES (?, ?, ?)', [content, isUser, timestamp])
    
    return true
  }

  /**
   * 获取最近N条消息（作为记忆）
   * @param count 消息数量
   * @returns 消息列表
   */
  getRecentMessages(count: number): MessageRecord[] {
    const start = Math.max(0, this.mockMessages.length - count)
    const result = this.mockMessages.slice(start)
    console.info(`DatabaseManager: 获取最近${count}条消息`)
    return result
    
    // TODO: 组员B替换为真实查询
    // db.querySql('SELECT * FROM Messages ORDER BY id DESC LIMIT ?', [count])
  }

  /**
   * 保存日程
   * @param content 日程内容
   * @param remindTime 提醒时间（可选）
   */
  saveSchedule(content: string, remindTime?: string): boolean {
    const record: ScheduleRecord = {
      id: this.mockSchedules.length + 1,
      content: content,
      createdTime: new Date().toISOString(),
      remindTime: remindTime,
      isDone: false
    }
    this.mockSchedules.push(record)
    console.info(`DatabaseManager: 保存日程 - ${content}`)
    
    // TODO: 组员B替换为真实插入
    
    return true
  }

  /**
   * 获取所有日程
   */
  getAllSchedules(): ScheduleRecord[] {
    console.info('DatabaseManager: 获取所有日程')
    return [...this.mockSchedules]
    
    // TODO: 组员B替换为真实查询
  }

  /**
   * 标记日程完成
   * @param scheduleId 日程ID
   */
  markScheduleDone(scheduleId: number): boolean {
    const schedule = this.mockSchedules.find(s => s.id === scheduleId)
    if (schedule) {
      schedule.isDone = true
      console.info(`DatabaseManager: 标记日程完成 - ID ${scheduleId}`)
      return true
    }
    return false
    
    // TODO: 组员B替换为真实更新
    // db.executeSql('UPDATE Schedules SET isDone = 1 WHERE id = ?', [scheduleId])
  }

  /**
   * 关闭数据库
   */
  closeDB(): boolean {
    this.isInitialized = false
    console.info('DatabaseManager: 关闭数据库')
    return true
    
    // TODO: 组员B替换为真实关闭
    // db.close()
  }
}
