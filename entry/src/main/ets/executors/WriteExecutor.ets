/**
 * 写执行体 - 接口定义
 * 负责：组员D（写执行体模块）
 * 功能：解析大模型返回的JSON，执行对应操作
 * 
 * 【核心工作流】
 * 1. 主页面调用 parseAction() 解析大模型返回
 * 2. 根据 action 类型决定如何处理
 * 3. 对于需要确认的操作（如schedule），返回给主页面显示弹窗
 */

// 动作结果类型
interface ActionResult {
  action: 'chat' | 'schedule' | 'study' | 'psych' | 'unknown'
  reply: string
  data?: any
}

export class WriteExecutor {
  
  /**
   * 解析大模型返回的JSON，提取动作信息
   * 
   * 【调用关系】
   * - 由主页面 (Index.ets) 在收到大模型响应后调用
   * - 调用前需要先经过 SecurityChecker 安全检查
   * 
   * @param llmResponse 大模型返回的JSON字符串
   * @returns ActionResult 动作结果对象
   */
  parseAction(llmResponse: string): ActionResult {
    console.info('WriteExecutor: 解析动作')
    
    try {
      // 1. 尝试解析JSON
      const parsed = this.extractJSON(llmResponse)
      
      // 2. 验证并返回结果
      if (parsed && parsed.action) {
        return {
          action: this.validateAction(parsed.action),
          reply: parsed.reply || '收到',
          data: parsed.data
        }
      }
      
      // 3. 解析失败，降级为普通聊天
      return {
        action: 'chat',
        reply: llmResponse.substring(0, 200) // 截取前200字
      }
      
    } catch (error) {
      console.error('WriteExecutor: 解析失败', JSON.stringify(error))
      return {
        action: 'chat',
        reply: '抱歉，我没理解你的意思，能再说一遍吗？'
      }
    }
  }

  /**
   * 从字符串中提取JSON
   * 处理大模型可能返回的Markdown代码块等情况
   */
  private extractJSON(text: string): any {
    // 尝试直接解析
    try {
      return JSON.parse(text)
    } catch (e) {
      // 尝试提取代码块中的JSON
      const codeBlockMatch = text.match(/```(?:json)?\s*([\s\S]*?)```/)
      if (codeBlockMatch) {
        return JSON.parse(codeBlockMatch[1])
      }
      
      // 尝试提取花括号中的内容
      const braceMatch = text.match(/\{[\s\S]*\}/)
      if (braceMatch) {
        return JSON.parse(braceMatch[0])
      }
      
      throw new Error('无法提取JSON')
    }
  }

  /**
   * 验证action类型
   */
  private validateAction(action: string): 'chat' | 'schedule' | 'study' | 'psych' | 'unknown' {
    const validActions = ['chat', 'schedule', 'study', 'psych']
    return validActions.includes(action) ? action as any : 'unknown'
  }

  /**
   * 【可选】执行具体动作（如果需要写执行体内部处理）
   * 目前由主页面统一处理，此方法预留
   */
  executeAction(actionResult: ActionResult): boolean {
    switch (actionResult.action) {
      case 'chat':
        // 普通聊天，无需特殊处理
        return true
        
      case 'schedule':
        // 日程安排 - 需要用户确认，由主页面处理
        // TODO: 组员D可以实现自动日程解析等功能
        return true
        
      case 'study':
        // 学习推荐 - 可以对接学习资源API
        // TODO: 组员D可以实现学习资源检索
        return true
        
      case 'psych':
        // 心理咨询 - 可以记录心理状态
        // TODO: 组员D可以实现心理日志记录
        return true
        
      default:
        return false
    }
  }

  /**
   * 【扩展接口】解析日程详情
   * 从日程内容中提取时间、地点等信息
   */
  parseScheduleDetail(scheduleContent: string): object {
    // TODO: 组员D可以实现更复杂的日程解析
    // 例如：提取"明天下午3点开会"中的时间信息
    
    return {
      rawContent: scheduleContent,
      extractedTime: null,
      extractedLocation: null,
      // ...
    }
  }

  /**
   * 【扩展接口】获取学习推荐
   * 可以对接外部学习资源API
   */
  getStudyRecommendation(topic: string): object {
    // TODO: 组员D可以实现学习推荐逻辑
    
    return {
      topic: topic,
      recommendations: [],
      // ...
    }
  }

  /**
   * 【扩展接口】记录心理状态
   */
  recordPsychState(userInput: string, aiReply: string): boolean {
    // TODO: 组员D可以实现心理状态跟踪
    
    return true
  }
}
