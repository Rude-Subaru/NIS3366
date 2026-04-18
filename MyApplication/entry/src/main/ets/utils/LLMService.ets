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

interface APIRequestPayload {
  model: string
  temperature: number
  messages: ChatMessagePayload[]
}

interface ActionResponsePayload {
  action: string
  reply: string
  data: string
}

/**
 * 大模型服务。
 * 已接入上海交大模型服务 API，并修复了降级模式下 prompt 泄露的 Bug。
 */
export class LLMService {
  private apiUrl: string = 'https://models.sjtu.edu.cn/api/v1/chat/completions'
  private apiKey: string = 'API protection'
  private model: string = 'glm-5'
  private useMock: boolean = false

  async callLLM(prompt: string): Promise<string> {
    if (this.useMock) {
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

  private async realAPICall(prompt: string): Promise<string> {
    const request = http.createHttp()

    const messages: ChatMessagePayload[] = [
      {
        role: 'system',
        content: '你是一个智能且灵活的 AI 秘书。你必须只返回合法的 JSON 对象，不要返回任何 Markdown 标记或额外解释。\n' +
          '返回的 JSON 必须包含以下字段：\n' +
          '1. action: 优先分类为 schedule(日程/提醒), study(学习建议), psych(情绪安抚)。如果用户的需求比较宽泛或不在此范围内，请将其作为 default 选项，设为 "chat"。\n' +
          '2. reply: 给用户的自然语言回复，态度要自然、友好。\n' +
          '3. data: 补充数据。为了发挥你的理解能力，你可以返回一段字符串，也可以发挥自由度返回结构化的 JSON 对象（例如对于 schedule，可以返回 {"event":"会议", "time":"明天下午3点", "location":"会议室"}，下游系统能够自动解析它）。'
      },
      {
        role: 'user',
        content: prompt
      }
    ]

    // 【修改点1】移除了 response_format 字段，避免部分代理网关报 HTTP 400 错误
    const requestPayload: APIRequestPayload = {
      model: this.model,
      temperature: 0.4,
      messages: messages
    }

    const requestHeader: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.apiKey}`
    }

    // 【修改点2】将超时时间均提升至 60000 毫秒 (60秒)，防止大模型回复稍慢时直接降级
    const httpRequestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: requestHeader,
      extraData: JSON.stringify(requestPayload),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 60000,
      readTimeout: 60000
    }

    try {
      const response = await request.request(this.apiUrl, httpRequestOptions)

      if (response.responseCode !== 200) {
        console.error(`LLM API 报错：HTTP ${response.responseCode} - ${response.result}`)
        throw new Error(`HTTP ${response.responseCode}`)
      }

      const result: LLMResponsePayload = JSON.parse(String(response.result)) as LLMResponsePayload
      if (result.choices && result.choices.length > 0) {
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

  private mockResponse(prompt: string): Promise<string> {
    const userInput: string = this.extractLatestUserInput(prompt)
    const normalized: string = userInput.toLowerCase()

    return new Promise<string>((resolve: (value: string) => void): void => {
      setTimeout((): void => {

        if (this.containsAny(normalized, ['日程', '会议', '提醒', '待办', '安排'])) {
          const res: ActionResponsePayload = {
            action: 'schedule',
            reply: '(降级模式) 我识别到这是一个日程请求，是否要为你创建这条日程？',
            data: userInput
          }
          resolve(JSON.stringify(res))
          return
        }

        if (this.containsAny(normalized, ['学习', '课程', '复习', 'python', '算法', '英语'])) {
          const res: ActionResponsePayload = {
            action: 'study',
            reply: '(降级模式) 我整理了一份适合你当前需求的学习建议。',
            data: userInput
          }
          resolve(JSON.stringify(res))
          return
        }

        if (this.containsAny(normalized, ['焦虑', '压力', '难受', '烦', '累', '低落'])) {
          const res: ActionResponsePayload = {
            action: 'psych',
            reply: '(降级模式) 听起来你最近有些疲惫。先把最紧急的一件事拆出来，我们一步一步处理。',
            data: userInput
          }
          resolve(JSON.stringify(res))
          return
        }

        const res: ActionResponsePayload = {
          action: 'chat',
          reply: '(降级模式) 收到。我已经记下你的信息，有需要的话我可以继续帮你整理成日程或学习计划。',
          data: userInput
        }
        resolve(JSON.stringify(res))

      }, 500)
    })
  }

  // 【修改点3】精准提取用户输入的内容，排除掉组装 Prompt 时添加的格式要求文字
  private extractLatestUserInput(prompt: string): string {
    const startMarker: string = '【用户最新输入】'
    const endMarker: string = '【返回格式要求】'

    const startIndex: number = prompt.lastIndexOf(startMarker)
    if (startIndex < 0) {
      return prompt
    }

    // 截取开始标记之后的所有内容
    const contentAfterStart: string = prompt.substring(startIndex + startMarker.length)

    // 查找结束标记的位置
    const endIndex: number = contentAfterStart.indexOf(endMarker)

    // 如果找到了结束标记，就只截取它们中间的部分
    if (endIndex >= 0) {
      return contentAfterStart.substring(0, endIndex).trim()
    }

    return contentAfterStart.trim()
  }

  private containsAny(text: string, keywords: string[]): boolean {
    return keywords.some((keyword: string): boolean => text.includes(keyword.toLowerCase()))
  }
}