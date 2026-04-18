import { DatabaseManager, MessageRecord } from '../database/DatabaseManager'
import batteryInfo from '@ohos.batteryInfo'
import deviceInfo from '@ohos.deviceInfo'

interface SystemInfo {
  currentTime: string
  date: string
  weekday: string
  period: string
  batterySOC: number
  deviceModel: string
}


/**
 * 读执行体 (同学B的核心任务2)
 * 负责采集系统信息和最近对话，组装给大模型的 Prompt (即 generatePrompt 逻辑)。
 */
export class ReadExecutor {
  private dbManager: DatabaseManager

  constructor(dbManager: DatabaseManager) {
    this.dbManager = dbManager
  }

  // 构建发给大模型的最终 Prompt
  async buildPrompt(userInput: string): Promise<string> {
    const systemInfo: SystemInfo = this.getSystemInfo()
    const memory: string = await this.getMemory()
    return this.assemblePrompt(systemInfo, memory, userInput)
  }

  /** 获取系统上下文（包含时间、设备型号和电量） */
  private getSystemInfo(): SystemInfo {
    const now = new Date()
    const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六']

    // 获取系统电量 (为了防止在某些模拟器上报错，加上try-catch保护)
    let batterySOC = 100
    try {
      batterySOC = batteryInfo.batterySOC
    } catch (e) {
      console.warn('获取电量失败，使用默认值100')
    }

    // 获取设备型号
    let model = 'HarmonyOS Device'
    try {
      model = deviceInfo.marketName || deviceInfo.productModel || 'Unknown Device'
    } catch (e) {
      console.warn('获取设备型号失败')
    }

    return {
      currentTime: now.toLocaleString('zh-CN'),
      date: now.toLocaleDateString('zh-CN'),
      weekday: weekdays[now.getDay()],
      period: now.getHours() < 12 ? '上午' : '下午',
      batterySOC: batterySOC,
      deviceModel: model
    }
  }

  /** 获取最近 5 条消息作为大模型的短期记忆 */
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

  /** 组装 Prompt：将系统状态、记忆和用户输入拼接成大模型能理解的格式 */
  private assemblePrompt(systemInfo: SystemInfo, memory: string, userInput: string): string {
    return [
      '你是一个 AI 秘书，需要将用户输入归类为 chat、schedule、study、psych 四类之一。',
      '请只返回 JSON，不要返回 Markdown，不要返回额外解释。',
      '',
      '【当前系统信息】',
      `- 时间：${systemInfo.currentTime}`,
      `- 日期：${systemInfo.date} 星期${systemInfo.weekday}`,
      `- 时段：${systemInfo.period}`,
      `- 设备型号：${systemInfo.deviceModel}`,
      `- 当前电量：${systemInfo.batterySOC}% (如果用户说很累或者电量低于20%，可在回复中顺便关心用户或提醒充电)`,
      '',
      '【对话历史】',
      memory,
      '',
      '【用户最新输入】',
      userInput,
      '',
      '【返回格式要求】',
      '{"action":"chat|schedule|study|psych","reply":"给用户的自然语言回复","data":"可选补充数据"}'
    ].join('\n')
  }
}