/**
 * 写执行体
 * 负责：解析大模型返回的JSON，并把不同Action整理成主页面可执行的数据。
 *
 * 设计约束：
 * 1. 主页面会直接读取 actionResult.action / reply / data。
 * 2. schedule 的 data 必须保持为可展示、可保存的字符串，避免弹窗出现 [object Object]。
 * 3. 扩展信息放在 scheduleDetail / studyRecommendation / psychState 中。
 */

export interface ScheduleDetail {
  rawContent: string
  event: string
  extractedTime: string | null
  extractedLocation: string | null
  remindTime: string | null
  confidence: number
  displayContent: string
}

export interface StudyRecommendation {
  topic: string
  difficulty: string
  duration: string
  resources: string[]
  plan: string[]
}

export interface PsychState {
  level: 'low' | 'medium' | 'high'
  keywords: string[]
  suggestion: string
}

export interface ActionResult {
  action: 'chat' | 'schedule' | 'study' | 'psych' | 'unknown'
  reply: string
  data?: string
  rawData?: string
  scheduleDetail?: ScheduleDetail
  studyRecommendation?: StudyRecommendation
  psychState?: PsychState
  valid: boolean
  errorMessage?: string
}

/** 模型原始 JSON 在进入业务层前的中间表示。 */
interface ParsedActionPayload {
  action?: FlexibleValue
  reply?: FlexibleValue
  data?: FlexibleValue
  content?: FlexibleValue
  title?: FlexibleValue
  event?: FlexibleValue
  topic?: FlexibleValue
}

type FlexibleValue = string | number | boolean | object | object[] | null | undefined

export class WriteExecutor {
  private readonly MAX_REPLY_LENGTH: number = 1000

  /**
   * 解析大模型返回的JSON，提取动作信息。
   *
   * 支持以下返回形式：
   * - {"action":"chat","reply":"..."}
   * - ```json ... ```
   * - 大模型额外输出说明文字时，从文本中提取第一段合法JSON。
   */
  parseAction(llmResponse: string): ActionResult {
    console.info('WriteExecutor: 解析动作')

    const responseText = this.normalizeString(llmResponse)
    if (responseText.length === 0) {
      return this.createChatFallback('抱歉，我没有收到有效回复。', '空响应')
    }

    try {
      const parsed = this.extractJSON(responseText)
      const action = this.validateAction(this.normalizeString(parsed.action))
      const reply = this.normalizeReply(parsed.reply, action)
      const rawData = this.normalizeData(parsed.data, parsed)

      switch (action) {
        case 'chat': {
          const result: ActionResult = {
            action: 'chat',
            reply: reply,
            rawData: rawData,
            valid: true
          }
          if (rawData.length > 0) {
            result.data = rawData
          }
          return result
        }

        case 'schedule': {
          // 日程动作要求输出可直接展示、可直接保存的结构化文本，避免页面层再拼装。
          const scheduleContent = rawData.length > 0 ? rawData : this.extractScheduleContentFromReply(reply)
          const scheduleDetail = this.parseScheduleDetail(scheduleContent.length > 0 ? scheduleContent : '新日程安排')
          const result: ActionResult = {
            action: 'schedule',
            reply: reply,
            data: scheduleDetail.displayContent,
            rawData: scheduleDetail.rawContent,
            scheduleDetail: scheduleDetail,
            valid: true
          }
          return result
        }

        case 'study': {
          // 学习建议允许模型给一个主题，具体推荐内容由本地规则补齐，保证离线也能演示。
          const topic = rawData.length > 0 ? rawData : this.extractStudyTopic(reply)
          const recommendation = this.getStudyRecommendation(topic.length > 0 ? topic : '当前学习内容')
          const result: ActionResult = {
            action: 'study',
            reply: reply,
            data: recommendation.topic,
            rawData: rawData,
            studyRecommendation: recommendation,
            valid: true
          }
          return result
        }

        case 'psych': {
          // 心理辅导动作除了正常回复外，还会额外分析当前情绪等级与建议。
          const psychState = this.analyzePsychState(`${reply} ${rawData}`)
          const result: ActionResult = {
            action: 'psych',
            reply: reply,
            rawData: rawData,
            psychState: psychState,
            valid: true
          }
          if (rawData.length > 0) {
            result.data = rawData
          }
          return result
        }

        default: {
          const result: ActionResult = {
            action: 'unknown',
            reply: reply.length > 0 ? reply : '收到，但我暂时不支持这个操作。',
            rawData: rawData,
            valid: false,
            errorMessage: `未知action: ${this.normalizeString(parsed.action)}`
          }
          if (rawData.length > 0) {
            result.data = rawData
          }
          return result
        }
      }
    } catch (error) {
      console.error(`WriteExecutor: 解析失败 ${JSON.stringify(error)}`)
      return this.createChatFallback('抱歉，我没理解你的意思，能再说一遍吗？', 'JSON解析失败')
    }
  }

  /**
   * 执行动作的轻量校验入口。
   * 具体弹窗、保存数据库等动作仍由主页面统一处理。
   */
  executeAction(actionResult: ActionResult): boolean {
    if (!actionResult || !actionResult.valid) {
      return false
    }

    switch (actionResult.action) {
      case 'chat':
        return actionResult.reply.length > 0

      case 'schedule':
        return !!actionResult.data && actionResult.data.length > 0

      case 'study':
        return !!actionResult.studyRecommendation || !!actionResult.data

      case 'psych':
        return actionResult.reply.length > 0

      default:
        return false
    }
  }

  /**
   * 从日程内容中提取时间、地点、事件。
   *
   * 示例：
   * 输入：明天下午3点在会议室开会
   * 输出：时间=yyyy-MM-dd 15:00，地点=会议室，事件=开会
   */
  parseScheduleDetail(scheduleContent: string): ScheduleDetail {
    const rawContent = this.normalizeString(scheduleContent)
    const content = rawContent.length > 0 ? rawContent : '新日程安排'
    const datePart = this.extractDate(content)
    const timePart = this.extractTime(content)
    const location = this.extractLocation(content)
    const event = this.extractEvent(content, location)

    // 时间允许“只给日期”或“只给时段”，页面层会继续结合用户原话做补强。
    let extractedTime: string | null = null
    if (datePart || timePart) {
      const target = datePart ? datePart : this.startOfToday()
      if (timePart) {
        target.setHours(timePart[0], timePart[1], 0, 0)
      } else {
        target.setHours(9, 0, 0, 0)
      }
      extractedTime = this.formatDateTime(target)
    }

    const normalizedEvent: string = event.length > 0 ? event : this.buildFallbackEvent(content, location)
    const displayParts: string[] = [`详情：${normalizedEvent}`]
    if (extractedTime) {
      displayParts.push(`日期：${extractedTime.substring(0, 10)}`)
      displayParts.push(`时间：${extractedTime.substring(11, 16)}`)
    } else {
      displayParts.push('日期：未设置')
      displayParts.push('时间：未设置')
    }
    displayParts.push(`地点：${location ?? '未设置'}`)

    // 置信度主要用于后续页面层判断是否需要更强的人工确认。
    const confidence = this.calculateScheduleConfidence(normalizedEvent, content, extractedTime, location)

    return {
      rawContent: content,
      event: normalizedEvent,
      extractedTime: extractedTime,
      extractedLocation: location,
      remindTime: extractedTime,
      confidence: confidence,
      displayContent: displayParts.join('\n')
    }
  }

  /**
   * 根据学习主题生成离线推荐。
   * 不依赖外部API，适合课堂演示和Mock模式。
   */
  getStudyRecommendation(topic: string): StudyRecommendation {
    const normalizedTopic = this.normalizeStudyTopic(topic)
    const lowerTopic = normalizedTopic.toLowerCase()

    if (lowerTopic.includes('python')) {
      const result: StudyRecommendation = {
        topic: 'Python',
        difficulty: '初级',
        duration: '2周',
        resources: ['Python官方教程', '廖雪峰Python教程', '基础语法练习题'],
        plan: ['第1-3天：变量、条件、循环', '第4-7天：函数、列表、字典', '第2周：文件处理和小项目']
      }
      return result
    }

    if (normalizedTopic.includes('数据结构') || normalizedTopic.includes('算法')) {
      const result: StudyRecommendation = {
        topic: '数据结构与算法',
        difficulty: '中级',
        duration: '3周',
        resources: ['数组与链表专题', '栈队列树图专题', 'LeetCode基础题单'],
        plan: ['第1周：线性结构', '第2周：树和图', '第3周：排序、搜索和综合练习']
      }
      return result
    }

    if (normalizedTopic.includes('鸿蒙') || lowerTopic.includes('arkts') || lowerTopic.includes('harmony')) {
      const result: StudyRecommendation = {
        topic: 'HarmonyOS ArkTS',
        difficulty: '初级',
        duration: '2周',
        resources: ['ArkTS基础语法', '声明式UI组件', '应用状态管理示例'],
        plan: ['第1周：语法和常用组件', '第2周：页面跳转、网络请求和数据存储']
      }
      return result
    }

    if (normalizedTopic.includes('英语')) {
      const result: StudyRecommendation = {
        topic: '英语',
        difficulty: '按当前水平调整',
        duration: '4周',
        resources: ['高频词汇表', '听力精听材料', '口语跟读练习'],
        plan: ['每天20分钟单词', '每天15分钟听力', '每周完成2次口语复述']
      }
      return result
    }

    const result: StudyRecommendation = {
      topic: normalizedTopic,
      difficulty: '初级',
      duration: '2周',
      resources: ['入门教程', '基础练习', '阶段性复盘清单'],
      plan: ['先梳理核心概念', '再完成小练习', '最后做一次总结复盘']
    }
    return result
  }

  /**
   * 记录心理状态。
   * 当前项目没有心理日志表，这里先做分析和日志输出，后续可由数据库模块持久化。
   */
  recordPsychState(userInput: string, aiReply: string): boolean {
    const state = this.analyzePsychState(`${userInput} ${aiReply}`)
    console.info(`WriteExecutor: 心理状态记录 level=${state.level}, keywords=${state.keywords.join(',')}`)
    return true
  }

  private createChatFallback(reply: string, reason: string): ActionResult {
    const result: ActionResult = {
      action: 'chat',
      reply: reply,
      valid: false,
      errorMessage: reason
    }
    return result
  }

  private extractJSON(text: string): ParsedActionPayload {
    try {
      return JSON.parse(text) as ParsedActionPayload
    } catch (error) {
      const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/)
      if (codeBlockMatch && codeBlockMatch[1]) {
        return JSON.parse(codeBlockMatch[1].trim()) as ParsedActionPayload
      }

      const jsonText = this.findFirstJSONObject(text)
      return JSON.parse(jsonText) as ParsedActionPayload
    }
  }

  private findFirstJSONObject(text: string): string {
    let start = -1
    let depth = 0
    let inString = false
    let escaped = false

    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i)

      if (start < 0) {
        if (ch === '{') {
          start = i
          depth = 1
        }
        continue
      }

      if (inString) {
        if (escaped) {
          escaped = false
        } else if (ch === '\\') {
          escaped = true
        } else if (ch === '"') {
          inString = false
        }
        continue
      }

      if (ch === '"') {
        inString = true
      } else if (ch === '{') {
        depth++
      } else if (ch === '}') {
        depth--
        if (depth === 0) {
          return text.substring(start, i + 1)
        }
      }
    }

    throw new Error('无法提取JSON')
  }

  private validateAction(action: string): 'chat' | 'schedule' | 'study' | 'psych' | 'unknown' {
    const normalized = action.trim().toLowerCase()

    if (normalized === 'chat' || normalized === 'talk' || normalized === 'conversation') {
      return 'chat'
    }
    if (normalized === 'schedule' || normalized === 'calendar' || normalized === 'reminder' || normalized === 'todo') {
      return 'schedule'
    }
    if (normalized === 'study' || normalized === 'learn' || normalized === 'course') {
      return 'study'
    }
    if (normalized === 'psych' || normalized === 'mental' || normalized === 'mood' || normalized === 'emotion') {
      return 'psych'
    }

    return 'unknown'
  }

  private normalizeReply(reply: FlexibleValue, action: string): string {
    const text = this.normalizeString(reply)
    if (text.length > 0) {
      return this.truncate(text, this.MAX_REPLY_LENGTH)
    }

    switch (action) {
      case 'schedule':
        return '好的，我来帮你安排这个日程。'
      case 'study':
        return '我为你整理了一份学习建议。'
      case 'psych':
        return '我在，你可以慢慢说。'
      case 'unknown':
        return '收到，但我暂时不支持这个操作。'
      default:
        return '收到。'
    }
  }

  private normalizeData(data: FlexibleValue, parsed?: ParsedActionPayload): string {
    if (data === undefined || data === null) {
      if (parsed) {
        const fallbackValues: FlexibleValue[] = [parsed.content, parsed.title, parsed.event, parsed.topic]
        for (const value of fallbackValues) {
          const normalized = this.normalizeString(value)
          if (normalized.length > 0) {
            return normalized
          }
        }
      }
      return ''
    }

    if (typeof data === 'string') {
      return data.trim()
    }

    if (typeof data === 'number' || typeof data === 'boolean') {
      return `${data}`
    }

    if (Array.isArray(data)) {
      const parts = data.map((item: object | string | number | boolean | null | undefined): string => this.normalizeData(item)).filter((item: string): boolean => item.length > 0)
      return parts.join('；')
    }

    const dataRecord = data as Record<string, FlexibleValue>
    const event = this.normalizeString(dataRecord['event'] ?? dataRecord['title'] ?? dataRecord['content'] ?? dataRecord['name'] ?? dataRecord['topic'])
    const time = this.normalizeString(dataRecord['time'] ?? dataRecord['remindTime'] ?? dataRecord['date'] ?? dataRecord['datetime'])
    const location = this.normalizeString(dataRecord['location'] ?? dataRecord['place'])
    const parts: string[] = []

    if (time.length > 0) {
      parts.push(time)
    }
    if (location.length > 0) {
      parts.push(`在${location}`)
    }
    if (event.length > 0) {
      parts.push(event)
    }

    if (parts.length > 0) {
      return parts.join(' ')
    }

    try {
      return JSON.stringify(data)
    } catch (error) {
      return ''
    }
  }

  private normalizeString(value: FlexibleValue): string {
    if (value === undefined || value === null) {
      return ''
    }
    if (typeof value === 'string') {
      return value.trim()
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return `${value}`
    }
    try {
      return JSON.stringify(value)
    } catch (error) {
      return ''
    }
  }

  private truncate(text: string, maxLength: number): string {
    if (text.length <= maxLength) {
      return text
    }
    return `${text.substring(0, maxLength)}...`
  }

  private extractScheduleContentFromReply(reply: string): string {
    const match = reply.match(/(?:安排|添加|创建|提醒)(?:日程|提醒|会议)?[：:]?\s*(.+)$/)
    return match && match[1] ? match[1].trim() : ''
  }

  private extractStudyTopic(text: string): string {
    const topicPatterns: RegExp[] = [
      /(?:学习|学|复习|推荐)(.+?)(?:课程|资料|内容|$)/,
      /关于(.+?)(?:的学习|的资料|$)/
    ]

    for (const pattern of topicPatterns) {
      const match = text.match(pattern)
      if (match && match[1]) {
        return this.normalizeStudyTopic(match[1])
      }
    }

    return ''
  }

  private normalizeStudyTopic(topic: string): string {
    const text = this.normalizeString(topic)
      .replace(/我想/g, '')
      .replace(/我想要/g, '')
      .replace(/帮我/g, '')
      .replace(/推荐/g, '')
      .replace(/学习/g, '')
      .replace(/课程/g, '')
      .replace(/[，。！？,!?]/g, '')
      .trim()

    return text.length > 0 ? text : '当前学习内容'
  }

  private startOfToday(): Date {
    const now = new Date()
    return new Date(now.getFullYear(), now.getMonth(), now.getDate())
  }

  private extractDate(content: string): Date | null {
    const now = this.startOfToday()

    const fullDateMatch = content.match(/(\d{4})[年\/.-](\d{1,2})[月\/.-](\d{1,2})[日号]?/)
    if (fullDateMatch) {
      return new Date(Number(fullDateMatch[1]), Number(fullDateMatch[2]) - 1, Number(fullDateMatch[3]))
    }

    const monthDateMatch = content.match(/(\d{1,2})月(\d{1,2})[日号]?/)
    if (monthDateMatch) {
      const month = Number(monthDateMatch[1]) - 1
      const day = Number(monthDateMatch[2])
      let date = new Date(now.getFullYear(), month, day)
      if (date.getTime() < now.getTime()) {
        date = new Date(now.getFullYear() + 1, month, day)
      }
      return date
    }

    if (content.includes('大后天')) {
      return this.addDays(now, 3)
    }
    if (content.includes('后天')) {
      return this.addDays(now, 2)
    }
    if (content.includes('明天') || content.includes('明日')) {
      return this.addDays(now, 1)
    }
    if (content.includes('今天') || content.includes('今日') || content.includes('今晚')) {
      return now
    }

    const nextWeekMatch = content.match(/(?:下周|下星期|下礼拜)([一二三四五六日天1-7])/)
    if (nextWeekMatch && nextWeekMatch[1]) {
      return this.getWeekdayDate(this.weekdayToNumber(nextWeekMatch[1]), true)
    }

    const weekMatch = content.match(/(?:周|星期|礼拜)([一二三四五六日天1-7])/)
    if (weekMatch && weekMatch[1]) {
      return this.getWeekdayDate(this.weekdayToNumber(weekMatch[1]), false)
    }

    return null
  }

  private extractTime(content: string): number[] | null {
    const normalized = content.replace(/：/g, ':')
    const colonMatch = normalized.match(/(\d{1,2})\s*:\s*(\d{1,2})/)
    if (colonMatch) {
      const hour = Number(colonMatch[1])
      const minute = Number(colonMatch[2])
      if (this.isValidHourMinute(hour, minute)) {
        return [hour, minute]
      }
    }

    const clockMatch = content.match(/(凌晨|早上|上午|中午|下午|晚上|今晚)?\s*([0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[0-9]{1,2}\s*分?|[零〇一二两三四五六七八九十]{1,3}\s*分?)?/) 
    if (!clockMatch) {
      return null
    }

    const period = clockMatch[1] || ''
    let hour = this.parseNumberText(clockMatch[2])
    let minute = 0

    if (clockMatch[3]) {
      const minuteText = clockMatch[3].replace(/分/g, '').trim()
      if (minuteText === '半') {
        minute = 30
      } else if (minuteText === '一刻') {
        minute = 15
      } else if (minuteText === '三刻') {
        minute = 45
      } else {
        minute = this.parseNumberText(minuteText)
      }
    }

    hour = this.adjustHourByPeriod(hour, period)

    if (this.isValidHourMinute(hour, minute)) {
      return [hour, minute]
    }

    return null
  }

  private extractLocation(content: string): string | null {
    const patterns: RegExp[] = [
      /在([^，。；\n]+?)(?:开会|会议|上课|学习|面试|见面|吃饭|汇报|讨论|提醒|$)/,
      /去([^，。；\n]+?)(?:开会|会议|上课|学习|面试|见面|吃饭|汇报|讨论|提醒|$)/
    ]

    for (const pattern of patterns) {
      const match = content.match(pattern)
      if (match && match[1]) {
        const location = match[1]
          .replace(/(今天|明天|明日|后天|大后天|上午|下午|晚上|今晚|中午|凌晨|早上)/g, '')
          .replace(/[0-9零〇一二两三四五六七八九十]+[点时].*$/g, '')
          .trim()
        if (location.length > 0) {
          return location
        }
      }
    }

    return null
  }

  private extractEvent(content: string, location: string | null): string {
    let event = content

    event = event
      .replace(/帮我/g, '')
      .replace(/请/g, '')
      .replace(/安排/g, '')
      .replace(/添加/g, '')
      .replace(/创建/g, '')
      .replace(/预约/g, '')
      .replace(/提醒我/g, '')
      .replace(/提醒/g, '')
      .replace(/我要/g, '')
      .replace(/我想/g, '')
      .replace(/(今天|明天|明日|后天|大后天|今晚|上午|下午|晚上|中午|凌晨|早上)/g, '')
      .replace(/(?:下周|下星期|下礼拜|周|星期|礼拜)[一二三四五六日天1-7]/g, '')
      .replace(/\d{4}[年\/.-]\d{1,2}[月\/.-]\d{1,2}[日号]?/g, '')
      .replace(/\d{1,2}月\d{1,2}[日号]?/g, '')
      .replace(/\d{1,2}\s*:\s*\d{1,2}/g, '')
      .replace(/([0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3})\s*[点时](半|一刻|三刻|[0-9]{1,2}\s*分?|[零〇一二两三四五六七八九十]{1,3}\s*分?)?/g, '')

    if (location) {
      event = event.replace(new RegExp(`在${this.escapeRegExp(location)}`, 'g'), '')
      event = event.replace(new RegExp(`去${this.escapeRegExp(location)}`, 'g'), '')
    }

    // 第二轮清洗专门兜底“我后天要去北京 -> 我要”这类经过时间剥离后残留的语气词。
    event = event
      .replace(/^(我|我们)/g, '')
      .replace(/^(要|要去|准备|打算|计划|一下|一趟)/g, '')
      .replace(/(一下|一趟)$/g, '')
      .replace(/[，。；,]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()

    if (event === '要' || event === '我要' || event === '我想' || event === '去') {
      return ''
    }

    return event.length > 0 ? event : ''
  }

  private buildFallbackEvent(content: string, location: string | null): string {
    if (location !== null && location.length > 0) {
      return `前往${location}`
    }
    if (content.indexOf('开会') >= 0 || content.indexOf('会议') >= 0) {
      return '参加会议'
    }
    if (content.indexOf('上课') >= 0) {
      return '参加课程'
    }
    if (content.indexOf('考试') >= 0) {
      return '参加考试'
    }
    if (content.indexOf('看医生') >= 0) {
      return '看医生'
    }
    return '待办事项'
  }

  private calculateScheduleConfidence(event: string, rawContent: string, extractedTime: string | null, location: string | null): number {
    let confidence = 0.35
    if (event.length > 0 && event !== rawContent) {
      confidence += 0.2
    }
    if (extractedTime) {
      confidence += 0.3
    }
    if (location) {
      confidence += 0.15
    }
    return Math.min(1, Math.round(confidence * 100) / 100)
  }

  private analyzePsychState(text: string): PsychState {
    const normalized = this.normalizeString(text)
    const highKeywords: string[] = ['崩溃', '绝望', '活不下去', '自杀', '自残']
    const mediumKeywords: string[] = ['焦虑', '压力', '难过', '失眠', '痛苦', '害怕']
    const lowKeywords: string[] = ['累', '烦', '低落', '郁闷', '不开心']

    const matchedHigh = highKeywords.filter((keyword: string): boolean => normalized.includes(keyword))
    if (matchedHigh.length > 0) {
      const result: PsychState = {
        level: 'high',
        keywords: matchedHigh,
        suggestion: '建议尽快联系可信任的人或专业心理援助渠道。'
      }
      return result
    }

    const matchedMedium = mediumKeywords.filter((keyword: string): boolean => normalized.includes(keyword))
    if (matchedMedium.length > 0) {
      const result: PsychState = {
        level: 'medium',
        keywords: matchedMedium,
        suggestion: '建议先做情绪记录，并安排短时间休息。'
      }
      return result
    }

    const matchedLow = lowKeywords.filter((keyword: string): boolean => normalized.includes(keyword))
    const result: PsychState = {
      level: 'low',
      keywords: matchedLow,
      suggestion: '可以继续倾诉，也可以做一次简单复盘。'
    }
    return result
  }

  private addDays(date: Date, days: number): Date {
    const result = new Date(date.getTime())
    result.setDate(result.getDate() + days)
    return result
  }

  private getWeekdayDate(targetWeekday: number, nextWeek: boolean): Date {
    const today = this.startOfToday()
    const currentWeekday = today.getDay()
    let offset = 0

    if (nextWeek) {
      offset = 7 - currentWeekday + targetWeekday
      if (offset <= 0) {
        offset += 7
      }
    } else {
      offset = targetWeekday - currentWeekday
      if (offset <= 0) {
        offset += 7
      }
    }

    return this.addDays(today, offset)
  }

  private weekdayToNumber(text: string): number {
    switch (text) {
      case '日':
      case '天':
      case '7':
        return 0
      case '一':
      case '1':
        return 1
      case '二':
      case '2':
        return 2
      case '三':
      case '3':
        return 3
      case '四':
      case '4':
        return 4
      case '五':
      case '5':
        return 5
      case '六':
      case '6':
        return 6
      default:
        return 1
    }
  }

  private parseNumberText(text: string): number {
    const normalized = this.normalizeString(text)
    const parsed = Number(normalized)
    if (!Number.isNaN(parsed)) {
      return parsed
    }

    if (normalized === '十') {
      return 10
    }

    if (normalized.includes('十')) {
      const parts = normalized.split('十')
      const tens = parts[0].length === 0 ? 1 : this.chineseDigitToNumber(parts[0])
      const ones = parts.length > 1 && parts[1].length > 0 ? this.chineseDigitToNumber(parts[1]) : 0
      return tens * 10 + ones
    }

    return this.chineseDigitToNumber(normalized)
  }

  private chineseDigitToNumber(text: string): number {
    switch (text) {
      case '零':
      case '〇':
        return 0
      case '一':
        return 1
      case '二':
      case '两':
        return 2
      case '三':
        return 3
      case '四':
        return 4
      case '五':
        return 5
      case '六':
        return 6
      case '七':
        return 7
      case '八':
        return 8
      case '九':
        return 9
      default:
        return 0
    }
  }

  private adjustHourByPeriod(hour: number, period: string): number {
    if ((period === '下午' || period === '晚上' || period === '今晚') && hour < 12) {
      return hour + 12
    }
    if (period === '中午' && hour < 11) {
      return hour + 12
    }
    if (period === '凌晨' && hour === 12) {
      return 0
    }
    return hour
  }

  private isValidHourMinute(hour: number, minute: number): boolean {
    return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
  }

  private formatDateTime(date: Date): string {
    return `${date.getFullYear()}-${this.pad2(date.getMonth() + 1)}-${this.pad2(date.getDate())} ${this.pad2(date.getHours())}:${this.pad2(date.getMinutes())}`
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`
  }

  private escapeRegExp(text: string): string {
    return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  }
}





