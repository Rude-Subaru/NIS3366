import { DatabaseManager, MessageRecord } from '../database/DatabaseManager'

interface SystemInfo {
  currentTime: string
  date: string
  weekday: string
  period: string
}

/**
 * 读执行体：负责采集系统信息和最近对话，组装给大模型的 Prompt。
 * 这里保持结构简单，方便课程作业演示读写执行体分离。
 */
export class ReadExecutor {
  private dbManager: DatabaseManager

  constructor(dbManager: DatabaseManager) {
    this.dbManager = dbManager
  }

  async buildPrompt(userInput: string): Promise<string> {
    const systemInfo: SystemInfo = this.getSystemInfo()
    const memory: string = await this.getMemory()
    return this.assemblePrompt(systemInfo, memory, userInput)
  }

  /** 当前至少提供时间、日期、星期和时段信息。 */
  private getSystemInfo(): SystemInfo {
    const now = new Date()
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六']
    return {
      currentTime: now.toLocaleString('zh-CN'),
      date: now.toLocaleDateString('zh-CN'),
      weekday: weekdays[now.getDay()],
      period: now.getHours() < 12 ? '上午' : '下午'
    }
  }

  /** 最近 5 条消息作为大模型的短期记忆。 */
  private async getMemory(): Promise<string> {
    const messages: MessageRecord[] = await this.dbManager.getRecentMessages(5)
    if (messages.length === 0) {
      return '暂无历史记录。'
    }

    return messages.map((msg: MessageRecord): string => {
      const role: string = msg.isUser ? '用户' : 'AI'
      const time: string = new Date(msg.timestamp).toLocaleTimeString('zh-CN', {
        hour: '2-digit',
        minute: '2-digit'
      })
      return `[${time}] ${role}: ${msg.content}`
    }).join('\n')
  }

  private assemblePrompt(systemInfo: SystemInfo, memory: string, userInput: string): string {
    return [
      '你是一个 AI 秘书，需要将用户输入归类为 chat、schedule、study、psych 四类之一。',
      '请只返回 JSON，不要返回 Markdown，不要返回额外解释。',
      '',
      '【当前系统信息】',
      `- 时间：${systemInfo.currentTime}`,
      `- 日期：${systemInfo.date} 星期${systemInfo.weekday}`,
      `- 时段：${systemInfo.period}`,
      '',
      '【对话历史】',
      memory,
      '',
      '【用户最新输入】',
      userInput,
      '',
      '【返回格式】',
      '{"action":"chat|schedule|study|psych","reply":"给用户的自然语言回复","data":"可选补充数据"}'
    ].join('\n')
  }
}
