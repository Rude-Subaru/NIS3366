/**
 * 读执行体 - 接口定义
 * 负责：组员C（读执行体模块）
 * 功能：读取系统信息和历史记忆，组装Prompt
 */

import { DatabaseManager } from '../database/DatabaseManager'

export class ReadExecutor {
  private dbManager: DatabaseManager

  constructor(dbManager: DatabaseManager) {
    this.dbManager = dbManager
  }

  /**
   * 构建Prompt（核心方法）
   * 
   * 【调用关系】
   * 1. 主页面 (Index.ets) 调用此方法
   * 2. 此方法内部调用 DatabaseManager 获取历史记录
   * 3. 返回的Prompt字符串传递给 LLMService.callLLM()
   * 
   * @param userInput 用户最新输入
   * @returns 组装好的完整Prompt
   */
  buildPrompt(userInput: string): string {
    // 1. 获取系统信息
    const systemInfo = this.getSystemInfo()
    
    // 2. 获取历史记忆（最近5条）
    const memory = this.getMemory()
    
    // 3. 组装Prompt
    const prompt = this.assemblePrompt(systemInfo, memory, userInput)
    
    console.info('ReadExecutor: Prompt构建完成')
    console.info('Prompt内容:', prompt.substring(0, 200) + '...')
    
    return prompt
  }

  /**
   * 获取系统信息
   * 
   * 【当前Mock实现】
   * - 只返回当前时间
   * 
   * 【可选扩展】组员C可以添加：
   * - 设备信息（电量、网络状态等）
   * - 系统日志
   * - 位置信息
   * - 应用使用统计
   */
  private getSystemInfo(): object {
    const now = new Date()
    return {
      currentTime: now.toLocaleString('zh-CN'),
      date: now.toLocaleDateString('zh-CN'),
      weekday: ['日', '一', '二', '三', '四', '五', '六'][now.getDay()],
      // TODO: 组员C可以扩展更多系统信息
      // batteryLevel: 85,
      // networkStatus: 'WiFi',
      // location: '北京市'
    }
  }

  /**
   * 获取记忆（历史聊天记录）
   * 
   * 【调用关系】
   * - 内部调用 DatabaseManager.getRecentMessages()
   * 
   * @returns 格式化的历史记录字符串
   */
  private getMemory(): string {
    const messages = this.dbManager.getRecentMessages(5)
    
    if (messages.length === 0) {
      return '（暂无历史记录）'
    }
    
    // 格式化为对话形式
    const formatted = messages.map(msg => {
      const role = msg.isUser ? '用户' : 'AI'
      const time = new Date(msg.timestamp).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
      return `[${time}] ${role}: ${msg.content}`
    }).join('\n')
    
    return formatted
  }

  /**
   * 组装完整Prompt
   * 
   * 【Prompt模板说明】
   * 这个Prompt告诉大模型：
   * 1. 它的角色是AI秘书
   * 2. 当前系统时间和历史上下文
   * 3. 用户最新输入
   * 4. 要求返回JSON格式，包含action字段
   * 
   * 【Action类型】
   * - chat: 普通聊天
   * - schedule: 日程安排
   * - study: 学习推荐
   * - psych: 心理咨询
   */
  private assemblePrompt(systemInfo: object, memory: string, userInput: string): string {
    return `你是一个AI秘书助手，帮助用户管理日程、推荐学习、提供心理支持。

【当前系统信息】
- 时间：${systemInfo.currentTime}
- 日期：${systemInfo.date} 星期${systemInfo.weekday}

【对话历史】
${memory}

【用户最新输入】
${userInput}

【你的任务】
分析用户意图，决定执行什么动作。请按以下JSON格式返回你的决策：

1. 如果只是普通聊天：
   {"action": "chat", "reply": "你的回复内容"}

2. 如果用户要安排日程/会议/提醒：
   {"action": "schedule", "reply": "确认消息", "data": "日程具体内容"}

3. 如果用户需要学习推荐：
   {"action": "study", "reply": "回复内容"}

4. 如果用户需要心理支持：
   {"action": "psych", "reply": "安慰和鼓励的话"}

请直接返回JSON，不要添加其他说明。`
  }

  /**
   * 【扩展接口】获取更详细的系统信息
   * 组员C可以实现此方法来获取更多系统数据
   */
  getDetailedSystemInfo(): object {
    // TODO: 组员C实现
    return {}
  }

  /**
   * 【扩展接口】获取系统日志
   * 组员C可以实现此方法来读取系统日志
   */
  getSystemLogs(): string[] {
    // TODO: 组员C实现
    return []
  }
}
