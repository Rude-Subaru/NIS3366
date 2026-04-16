import http from '@ohos.net.http'

interface ChatMessagePayload {
  role: string
  content: string
}

interface LLMChoiceMessage {
  content: string
}

interface LLMChoice {
  message: LLMChoiceMessage
}

interface LLMResponsePayload {
  choices: LLMChoice[]
}

/**
 * 大模型服务。
 * 默认保留 Mock 模式，保证课程作业在没有 API Key 时也能运行；
 * 一旦通过 setAPIConfig 注入真实参数，就会切换到在线调用。
 */
export class LLMService {
  private apiUrl: string = 'https://api.deepseek.com/chat/completions'
  private apiKey: string = 'your-api-key-here'
  private model: string = 'deepseek-chat'
  private useMock: boolean = true

  async callLLM(prompt: string): Promise<string> {
    if (this.useMock || this.apiKey === 'your-api-key-here') {
      return this.mockResponse(prompt)
    }

    return this.realAPICall(prompt)
  }

  setAPIConfig(url: string, key: string, model: string): void {
    this.apiUrl = url
    this.apiKey = key
    this.model = model
    this.useMock = false
  }

  setMockMode(useMock: boolean): void {
    this.useMock = useMock
  }

  /** 真实模式下通过 ArkTS http 模块请求大模型接口。 */
  private async realAPICall(prompt: string): Promise<string> {
    const request = http.createHttp()
    const messages: ChatMessagePayload[] = [
      {
        role: 'system',
        content: '你是一个 AI 秘书。只返回 JSON，不要返回额外解释。'
      },
      {
        role: 'user',
        content: prompt
      }
    ]

    try {
      const response = await request.request(this.apiUrl, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`
        },
        extraData: JSON.stringify({
          model: this.model,
          temperature: 0.4,
          messages
        }),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 20000
      })

      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`)
      }

      const result: LLMResponsePayload = JSON.parse(String(response.result)) as LLMResponsePayload
      if (result.choices.length > 0) {
        return result.choices[0].message.content
      }

      return this.mockResponse(prompt)
    } catch (error) {
      console.error('LLMService realAPICall error:', JSON.stringify(error))
      return this.mockResponse(prompt)
    } finally {
      request.destroy()
    }
  }

  /**
   * Mock 响应用于没有 API Key 的演示环境。
   * 它会根据关键词返回符合写执行体要求的 JSON。
   */
  private mockResponse(prompt: string): Promise<string> {
    const userInput: string = this.extractLatestUserInput(prompt)
    const normalized: string = userInput.toLowerCase()

    return new Promise<string>((resolve: (value: string) => void): void => {
      setTimeout((): void => {
        if (this.containsAny(normalized, ['日程', '会议', '提醒', '待办', '安排'])) {
          resolve(JSON.stringify({
            action: 'schedule',
            reply: '我识别到这是一个日程请求，是否要为你创建这条日程？',
            data: userInput
          }))
          return
        }

        if (this.containsAny(normalized, ['学习', '课程', '复习', 'python', '算法', '英语'])) {
          resolve(JSON.stringify({
            action: 'study',
            reply: '我整理了一份适合你当前需求的学习建议。',
            data: userInput
          }))
          return
        }

        if (this.containsAny(normalized, ['焦虑', '压力', '难受', '烦', '累', '低落'])) {
          resolve(JSON.stringify({
            action: 'psych',
            reply: '听起来你最近有些疲惫。先把最紧急的一件事拆出来，我们一步一步处理。',
            data: userInput
          }))
          return
        }

        resolve(JSON.stringify({
          action: 'chat',
          reply: '收到。我已经记下你的信息，有需要的话我可以继续帮你整理成日程或学习计划。',
          data: userInput
        }))
      }, 500)
    })
  }

  private extractLatestUserInput(prompt: string): string {
    const marker: string = '【用户最新输入】'
    const index: number = prompt.lastIndexOf(marker)
    if (index < 0) {
      return prompt
    }

    return prompt.substring(index + marker.length).trim()
  }

  private containsAny(text: string, keywords: string[]): boolean {
    return keywords.some((keyword: string): boolean => text.includes(keyword.toLowerCase()))
  }
}
