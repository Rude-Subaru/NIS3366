/**
 * 安全检查模块 - 接口定义
 * 负责：组员A 或 组员D（安全模块）
 * 功能：检查大模型返回的内容是否安全
 * 
 * 【安全策略】
 * 1. 关键词过滤：检查是否包含危险指令
 * 2. 内容审查：防止有害内容
 * 3. 操作确认：危险操作需要用户二次确认
 */

export class SecurityChecker {
  
  // 【危险关键词列表】需要拦截的指令
  private dangerousKeywords: string[] = [
    // 系统操作类
    '删除系统',
    '格式化',
    'shutdown',
    'rm -rf',
    '删除所有',
    
    // 敏感内容类
    '自杀',
    '自残',
    '暴力',
    '去死',
    '杀人',
    
    // 隐私安全类
    '密码',
    '账号',
    '银行卡',
    '身份证',
    '验证码',
    
    // 恶意指令类
    '执行脚本',
    '运行代码',
    '下载文件',
    '访问链接'
  ]

  // 【敏感操作列表】需要用户确认的操作
  private sensitiveActions: string[] = [
    'schedule',      // 日程操作
    'delete',        // 删除操作
    'modify',        // 修改操作
    'share',         // 分享操作
    'purchase'       // 购买操作
  ]

  /**
   * 安全检查主入口
   * 
   * 【调用关系】
   * - 由主页面 (Index.ets) 在收到大模型响应后、解析前调用
   * - 如果返回false，主页面会拦截该响应并提示用户
   * 
   * @param content 大模型返回的内容
   * @returns true-安全，false-不安全
   */
  isSafe(content: string): boolean {
    console.info('SecurityChecker: 执行安全检查')
    
    // 1. 检查危险关键词
    if (this.containsDangerousKeywords(content)) {
      console.warn('SecurityChecker: 检测到危险关键词')
      return false
    }
    
    // 2. 检查JSON格式是否合法（防止注入攻击）
    if (!this.isValidJSON(content)) {
      console.warn('SecurityChecker: JSON格式异常')
      return false
    }
    
    // 3. 检查内容长度（防止溢出攻击）
    if (content.length > 10000) {
      console.warn('SecurityChecker: 内容过长')
      return false
    }
    
    console.info('SecurityChecker: 检查通过')
    return true
  }

  /**
   * 检查是否包含危险关键词
   */
  private containsDangerousKeywords(content: string): boolean {
    const lowerContent = content.toLowerCase()
    
    for (const keyword of this.dangerousKeywords) {
      if (lowerContent.includes(keyword.toLowerCase())) {
        console.warn(`SecurityChecker: 命中关键词 "${keyword}"`)
        return true
      }
    }
    
    return false
  }

  /**
   * 检查是否为合法JSON
   */
  private isValidJSON(content: string): boolean {
    try {
      // 尝试提取并解析JSON
      this.extractJSON(content)
      return true
    } catch (e) {
      return false
    }
  }

  /**
   * 从字符串中提取JSON
   */
  private extractJSON(text: string): any {
    try {
      return JSON.parse(text)
    } catch (e) {
      const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/)
      if (codeBlockMatch) {
        return JSON.parse(codeBlockMatch[1])
      }
      const braceMatch = text.match(/\{[\s\S]*\}/)
      if (braceMatch) {
        return JSON.parse(braceMatch[0])
      }
      throw new Error('Invalid JSON')
    }
  }

  /**
   * 检查是否为敏感操作（需要用户确认）
   * 
   * 【调用关系】
   * - 由主页面判断是否需要显示确认弹窗
   * 
   * @param action 动作类型
   * @returns true-需要确认，false-无需确认
   */
  needsConfirmation(action: string): boolean {
    return this.sensitiveActions.includes(action)
  }

  /**
   * 【扩展接口】添加危险关键词
   */
  addDangerousKeyword(keyword: string) {
    this.dangerousKeywords.push(keyword)
  }

  /**
   * 【扩展接口】设置敏感操作列表
   */
  setSensitiveActions(actions: string[]) {
    this.sensitiveActions = actions
  }

  /**
   * 【扩展接口】内容审查（高级）
   * TODO: 可以对接内容审查API
   */
  async contentReview(text: string): Promise<{ safe: boolean, reason?: string }> {
    // Mock实现，始终返回安全
    return { safe: true }
    
    // TODO: 可以对接第三方内容审查服务
    // const response = await callReviewAPI(text)
    // return { safe: response.safe, reason: response.reason }
  }
}
