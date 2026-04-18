/**
 * 安全检查模块
 * 负责：在写执行体解析前，对大模型返回内容做结构和内容安全校验。
 *
 * 检查范围：
 * 1. 返回必须能提取出合法JSON。
 * 2. action 必须在白名单内。
 * 3. 拦截危险关键词、隐私索取、提示词注入和绕过确认的指令。
 * 4. 标记敏感操作，由主页面做二次确认。
 */

export interface SecurityCheckResult {
  safe: boolean
  reason?: string
  action?: string
  needsConfirmation?: boolean
}

interface ContentReviewResult {
  safe: boolean
  reason?: string
}

interface ParsedSecurityPayload {
  action?: FlexibleValue
  reply?: FlexibleValue
  data?: FlexibleValue
  content?: FlexibleValue
  title?: FlexibleValue
  event?: FlexibleValue
  topic?: FlexibleValue
}

type FlexibleValue = string | number | boolean | object | object[] | null | undefined

export class SecurityChecker {
  private readonly MAX_CONTENT_LENGTH: number = 10000

  // 只允许项目当前真正支持的动作进入后续流程。
  private allowedActions: string[] = [
    'chat',
    'schedule',
    'study',
    'psych'
  ]

  // 需要直接拦截的危险词。可通过 addDangerousKeyword 动态扩展。
  private dangerousKeywords: string[] = [
    '删除系统',
    '格式化',
    'shutdown',
    'rm -rf',
    '删除所有',
    '执行脚本',
    '运行代码',
    '下载文件',
    '访问链接'
  ]

  private harmfulKeywords: string[] = [
    '自杀方法',
    '自残方法',
    '杀人',
    '暴力教程',
    '去死'
  ]

  private privacyKeywords: string[] = [
    '密码',
    '账号',
    '银行卡',
    '身份证',
    '验证码'
  ]

  private privacyRiskVerbs: string[] = [
    '发送',
    '提供',
    '告诉',
    '输入',
    '上传',
    '分享',
    '泄露',
    '保存',
    '提交'
  ]

  private promptInjectionKeywords: string[] = [
    '忽略以上',
    '忽略前面的',
    '忽略系统',
    '绕过安全',
    '无需确认',
    '不要弹窗',
    '越权',
    'system prompt'
  ]

  // 这些动作如果出现在大模型响应中，直接拦截。
  private blockedActions: string[] = [
    'delete',
    'modify',
    'share',
    'purchase',
    'transfer',
    'payment',
    'execute'
  ]

  // 这些动作合法，但必须由用户二次确认。
  // 当前主页面主要对 schedule 做确认弹窗，其余动作预留给后续扩展。
  private sensitiveActions: string[] = [
    'schedule',
    'delete',
    'modify',
    'share',
    'purchase'
  ]

  /**
   * 安全检查主入口。
   *
   * @param content 大模型返回的内容
   * @returns true-安全，false-不安全
   */
  isSafe(content: string): boolean {
    const result = this.checkContent(content)
    if (!result.safe) {
      console.warn(`SecurityChecker: 检查未通过 - ${result.reason || '未知原因'}`)
      return false
    }

    console.info('SecurityChecker: 检查通过')
    return true
  }

  /**
   * 返回更详细的安全检查结果，便于后续UI展示拦截原因。
   */
  checkContent(content: string): SecurityCheckResult {
    console.info('SecurityChecker: 执行安全检查')

    const text = this.normalizeString(content)
    if (text.length === 0) {
      const result: SecurityCheckResult = { safe: false, reason: '内容为空' }
      return result
    }

    if (text.length > this.MAX_CONTENT_LENGTH) {
      const result: SecurityCheckResult = { safe: false, reason: '内容过长' }
      return result
    }

    let parsed: ParsedSecurityPayload
    try {
      parsed = this.extractJSON(text)
    } catch (error) {
      const result: SecurityCheckResult = { safe: false, reason: 'JSON格式异常' }
      return result
    }

    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      const result: SecurityCheckResult = { safe: false, reason: 'JSON结构异常' }
      return result
    }

    const action = this.normalizeAction(parsed.action)
    if (action.length === 0) {
      const result: SecurityCheckResult = { safe: false, reason: '缺少action字段' }
      return result
    }

    if (this.blockedActions.includes(action)) {
      const result: SecurityCheckResult = { safe: false, action: action, reason: `禁止执行${action}操作` }
      return result
    }

    if (!this.allowedActions.includes(action)) {
      const result: SecurityCheckResult = { safe: false, action: action, reason: `不支持的action: ${action}` }
      return result
    }

    // 审核时不只看 reply，也会把 data / title / event 等字段拼起来一起检查。
    const reviewText = this.collectReviewText(parsed)
    const keywordReason = this.findUnsafeKeyword(reviewText, action)
    if (keywordReason.length > 0) {
      const result: SecurityCheckResult = { safe: false, action: action, reason: keywordReason }
      return result
    }

    if (this.containsPromptInjection(reviewText)) {
      const result: SecurityCheckResult = { safe: false, action: action, reason: '疑似提示词注入或绕过确认' }
      return result
    }

    const result: SecurityCheckResult = {
      safe: true,
      action: action,
      needsConfirmation: this.needsConfirmation(action)
    }
    return result
  }

  /**
   * 检查单个动作是否安全。
   * 预留给主页面或写执行体在执行前做二次校验。
   */
  checkActionSafety(action: string, data?: string): SecurityCheckResult {
    const normalizedAction = this.normalizeAction(action)

    if (normalizedAction.length === 0) {
      const result: SecurityCheckResult = { safe: false, reason: '动作为空' }
      return result
    }

    if (this.blockedActions.includes(normalizedAction)) {
      const result: SecurityCheckResult = { safe: false, action: normalizedAction, reason: `禁止执行${normalizedAction}操作` }
      return result
    }

    if (!this.allowedActions.includes(normalizedAction)) {
      const result: SecurityCheckResult = { safe: false, action: normalizedAction, reason: `不支持的action: ${normalizedAction}` }
      return result
    }

    const dataText = this.normalizeString(data)
    const keywordReason = this.findUnsafeKeyword(dataText, normalizedAction)
    if (keywordReason.length > 0) {
      const result: SecurityCheckResult = { safe: false, action: normalizedAction, reason: keywordReason }
      return result
    }

    const result: SecurityCheckResult = {
      safe: true,
      action: normalizedAction,
      needsConfirmation: this.needsConfirmation(normalizedAction)
    }
    return result
  }

  /**
   * 检查是否为敏感操作（需要用户确认）。
   */
  needsConfirmation(action: string): boolean {
    return this.sensitiveActions.includes(this.normalizeAction(action))
  }

  /**
   * 添加危险关键词。
   */
  addDangerousKeyword(keyword: string): void {
    const normalized = this.normalizeString(keyword)
    if (normalized.length > 0 && !this.dangerousKeywords.includes(normalized)) {
      this.dangerousKeywords.push(normalized)
    }
  }

  /**
   * 设置敏感操作列表。
   */
  setSensitiveActions(actions: string[]): void {
    this.sensitiveActions = actions
      .map((action: string): string => this.normalizeAction(action))
      .filter((action: string): boolean => action.length > 0)
  }

  /**
   * 内容审查接口。
   * 当前为本地规则实现，后续可替换为第三方内容审核API。
   */
  async contentReview(text: string): Promise<ContentReviewResult> {
    const reviewText = this.normalizeString(text)
    if (reviewText.length === 0) {
      const result: ContentReviewResult = { safe: false, reason: '内容为空' }
      return result
    }
    if (reviewText.length > this.MAX_CONTENT_LENGTH) {
      const result: ContentReviewResult = { safe: false, reason: '内容过长' }
      return result
    }

    const keywordReason = this.findUnsafeKeyword(reviewText, '')
    if (keywordReason.length > 0) {
      const result: ContentReviewResult = { safe: false, reason: keywordReason }
      return result
    }

    if (this.containsPromptInjection(reviewText)) {
      const result: ContentReviewResult = { safe: false, reason: '疑似提示词注入' }
      return result
    }

    const result: ContentReviewResult = { safe: true }
    return result
  }

  private findUnsafeKeyword(content: string, action: string): string {
    const lowerContent = content.toLowerCase()

    for (const keyword of this.dangerousKeywords) {
      if (lowerContent.includes(keyword.toLowerCase())) {
        return `命中危险关键词: ${keyword}`
      }
    }

    for (const keyword of this.harmfulKeywords) {
      if (lowerContent.includes(keyword.toLowerCase())) {
        if (action === 'psych' && this.isSupportivePsychContent(lowerContent)) {
          continue
        }
        return `命中有害内容关键词: ${keyword}`
      }
    }

    for (const keyword of this.privacyKeywords) {
      if (lowerContent.includes(keyword.toLowerCase()) && this.hasPrivacyRiskIntent(lowerContent)) {
        return `疑似索取或泄露隐私信息: ${keyword}`
      }
    }

    return ''
  }

  private hasPrivacyRiskIntent(content: string): boolean {
    for (const verb of this.privacyRiskVerbs) {
      if (content.includes(verb.toLowerCase())) {
        return true
      }
    }
    return false
  }

  private containsPromptInjection(content: string): boolean {
    const lowerContent = content.toLowerCase()
    for (const keyword of this.promptInjectionKeywords) {
      if (lowerContent.includes(keyword.toLowerCase())) {
        return true
      }
    }
    return false
  }

  private isSupportivePsychContent(content: string): boolean {
    const supportWords: string[] = ['联系', '求助', '专业', '帮助', '热线', '不要伤害', '安全']
    for (const word of supportWords) {
      if (content.includes(word)) {
        return true
      }
    }
    return false
  }

  private collectReviewText(parsed: ParsedSecurityPayload): string {
    const parts: string[] = []
    parts.push(this.normalizeString(parsed.action))
    parts.push(this.normalizeString(parsed.reply))
    parts.push(this.normalizeString(parsed.data))
    parts.push(this.normalizeString(parsed.content))
    parts.push(this.normalizeString(parsed.title))
    parts.push(this.normalizeString(parsed.event))
    parts.push(this.normalizeString(parsed.topic))
    return parts.filter((item: string): boolean => item.length > 0).join('\n')
  }

  private normalizeAction(action: FlexibleValue): string {
    return this.normalizeString(action).trim().toLowerCase()
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

  private extractJSON(text: string): ParsedSecurityPayload {
    try {
      return JSON.parse(text) as ParsedSecurityPayload
    } catch (error) {
      const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/)
      if (codeBlockMatch && codeBlockMatch[1]) {
        return JSON.parse(codeBlockMatch[1].trim()) as ParsedSecurityPayload
      }

      const jsonText = this.findFirstJSONObject(text)
      return JSON.parse(jsonText) as ParsedSecurityPayload
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

    throw new Error('Invalid JSON')
  }
}
