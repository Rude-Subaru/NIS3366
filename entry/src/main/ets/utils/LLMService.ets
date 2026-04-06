/**
 * 大模型调用服务
 * 负责：组长（框架）+ 组员A（具体实现）
 * 功能：封装HTTP请求调用大模型API
 * 
 * 【Mock模式】开发阶段先用Mock数据，后期替换成真实API
 */

import http from '@ohos.net.http'

export class LLMService {
  // API配置（由组员A填写）
  private API_URL: string = 'https://api.deepseek.com/chat/completions'
  private API_KEY: string = 'your-api-key-here'
  private MODEL: string = 'deepseek-chat'
  
  // 是否使用Mock模式
  private USE_MOCK: boolean = true

  /**
   * 调用大模型
   * @param prompt 组装好的Prompt
   * @returns 大模型返回的JSON字符串
   */
  async callLLM(prompt: string): Promise<string> {
    if (this.USE_MOCK) {
      // 【Mock模式】模拟大模型返回
      return this.mockResponse(prompt)
    }

    // 【真实模式】发起HTTP请求
    return this.realAPICall(prompt)
  }

  /**
   * 【Mock响应】根据用户输入返回模拟的大模型响应
   * 用于开发测试，无需真实API Key
   */
  private mockResponse(prompt: string): Promise<string> {
    return new Promise((resolve) => {
      // 模拟网络延迟
      setTimeout(() => {
        const lowerPrompt = prompt.toLowerCase()
        
        // 日程相关
        if (lowerPrompt.includes('日程') || lowerPrompt.includes('会议') || lowerPrompt.includes('预约') || lowerPrompt.includes('提醒')) {
          resolve(JSON.stringify({
            action: 'schedule',
            reply: '好的，我帮你安排这个日程~',
            data: this.extractEventName(prompt)
          }))
        }
        // 学习相关
        else if (lowerPrompt.includes('学习') || lowerPrompt.includes('课程') || lowerPrompt.includes('推荐') || lowerPrompt.includes('复习')) {
          resolve(JSON.stringify({
            action: 'study',
            reply: '根据你的情况，我为你推荐以下内容：',
            data: '学习推荐'
          }))
        }
        // 心理相关
        else if (lowerPrompt.includes('焦虑') || lowerPrompt.includes('压力') || lowerPrompt.includes('难过') || lowerPrompt.includes('心情') || lowerPrompt.includes('累')) {
          resolve(JSON.stringify({
            action: 'psych',
            reply: '听起来你现在有些情绪波动，要不要聊聊？有时候把感受说出来会好受一些。'
          }))
        }
        // 默认聊天
        else {
          const chatReplies = [
            { action: 'chat', reply: '收到！我会记录下来的。还有什么需要帮忙的吗？' },
            { action: 'chat', reply: '明白~ 我会持续关注这个问题的。' },
            { action: 'chat', reply: '好的，有什么新情况随时告诉我！' },
            { action: 'chat', reply: '了解了！我会帮你跟进这件事的。' }
          ]
          const randomReply = chatReplies[Math.floor(Math.random() * chatReplies.length)]
          resolve(JSON.stringify(randomReply))
        }
      }, 800) // 模拟800ms延迟
    })
  }

  /**
   * 从Prompt中提取事件名称（简单提取）
 */
  private extractEventName(prompt: string): string {
    // 简单提取引号或关键词后的内容
    const matches = prompt.match(/[""']([^""']+)[""']/) || 
                    prompt.match(/日程[是为：:]+\s*(.+?)(?:\s|$)/) ||
                    prompt.match(/会议[是为：:]+\s*(.+?)(?:\s|$)/)
    return matches ? matches[1] : '新日程安排'
  }

  /**
   * 【真实API调用】使用ArkTS http模块
   * 注意：需要配置网络权限 ohos.permission.INTERNET
   */
  private async realAPICall(prompt: string): Promise<string> {
    const httpRequest = http.createHttp()
    
    const requestData = {
      model: this.MODEL,
      messages: [
        { role: 'system', content: '你是一个AI秘书助手，请用JSON格式返回你的决策。' },
        { role: 'user', content: prompt }
      ],
      temperature: 0.7
    }

    try {
      const response = await httpRequest.request(
        this.API_URL,
        {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${this.API_KEY}`
          },
          extraData: JSON.stringify(requestData),
          expectDataType: http.HttpDataType.STRING
        }
      )

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string)
        return result.choices[0].message.content
      } else {
        throw new Error(`HTTP ${response.responseCode}`)
      }
    } catch (error) {
      console.error('LLM API Error:', JSON.stringify(error))
      // 失败时降级到Mock
      return this.mockResponse(prompt)
    } finally {
      httpRequest.destroy()
    }
  }

  /**
   * 设置API配置（供组员A调用）
   */
  setAPIConfig(url: string, key: string, model: string) {
    this.API_URL = url
    this.API_KEY = key
    this.MODEL = model
    this.USE_MOCK = false
  }

  /**
   * 切换Mock模式
   */
  setMockMode(useMock: boolean) {
    this.USE_MOCK = useMock
  }
}
