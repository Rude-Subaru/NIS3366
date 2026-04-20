import common from '@ohos.app.ability.common'
import { router } from '@kit.ArkUI'
import { ConversationRecord, DatabaseManager, MessageRecord } from '../database/DatabaseManager'
import { ReadExecutor } from '../executors/ReadExecutor'
import { WriteExecutor, ActionResult } from '../executors/WriteExecutor'
import { SecurityChecker } from '../security/SecurityChecker'
import { LLMService } from '../utils/LLMService'

class ChatMessage {
  id: number
  content: string
  isUser: boolean
  timestamp: string

  constructor(id: number, content: string, isUser: boolean, timestamp: string) {
    this.id = id
    this.content = content
    this.isUser = isUser
    this.timestamp = timestamp
  }
}

@Entry
@Component
/**
 * 心理辅导独立页面。
 * 这里和普通会话分开存储，避免日常助理内容与情绪支持内容混在一起。
 */
struct PsychChat {
  @State private messageList: ChatMessage[] = []
  @State private inputText: string = ''
  @State private isLoading: boolean = false
  @State private isInitializing: boolean = true
  @State private conversationTitle: string = '心理辅导'

  private readonly listScroller: Scroller = new Scroller()
  private readonly dbManager: DatabaseManager = new DatabaseManager()
  private readonly llmService: LLMService = new LLMService()
  private readonly securityChecker: SecurityChecker = new SecurityChecker()
  private readonly writeExecutor: WriteExecutor = new WriteExecutor()
  private currentConversationId: number = 0

  /** 进入页面时优先恢复当前心理辅导会话；如果没有就按父会话自动创建。 */
  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)
    await this.dbManager.initDB()

    const conversation: ConversationRecord | null = await this.dbManager.getCurrentConversation()
    const psychConversation = conversation !== null && conversation.type === 'psych'
      ? conversation
      : await this.dbManager.getOrCreatePsychConversation(conversation !== null ? conversation.id : 0)

    if (psychConversation === null) {
      router.pushUrl({ url: 'pages/SessionSelect' })
      return
    }

    this.currentConversationId = psychConversation.id
    this.conversationTitle = psychConversation.title
    await this.loadHistoryMessages()
    this.isInitializing = false
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private async loadHistoryMessages(): Promise<void> {
    const history: MessageRecord[] = await this.dbManager.getRecentMessages(100, this.currentConversationId)
    this.messageList = history.map((msg: MessageRecord): ChatMessage => {
      return new ChatMessage(msg.id, msg.content, msg.isUser, this.formatTime(msg.timestamp))
    })
    this.scrollToBottom()
  }

  private formatTime(timestamp: string): string {
    const date: Date = new Date(timestamp)
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  }

  private async addMessage(content: string, isUser: boolean): Promise<void> {
    const record: MessageRecord = await this.dbManager.saveMessage(content, isUser, this.currentConversationId)
    this.messageList = [...this.messageList, new ChatMessage(record.id, record.content, record.isUser, this.formatTime(record.timestamp))]
    if (isUser) {
      const updatedConversation = await this.dbManager.getConversationById(this.currentConversationId)
      if (updatedConversation !== null) {
        this.conversationTitle = updatedConversation.title
      }
    }
    this.scrollToBottom()
  }

  private scrollToBottom(): void {
    setTimeout((): void => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  /** 心理辅导页仍然复用同一套读/写执行体，但会额外强化“温和回应”的提示。 */
  async sendMessage(): Promise<void> {
    const userInput: string = this.inputText.trim()
    if (userInput.length === 0 || this.isLoading || this.isInitializing) {
      return
    }

    this.inputText = ''
    await this.addMessage(userInput, true)
    this.isLoading = true

    try {
      const readExecutor: ReadExecutor = new ReadExecutor(this.dbManager)
      const prompt: string = await readExecutor.buildPrompt(`请用心理支持和温和陪伴的方式回应下面这段内容：${userInput}`)
      const llmResponse: string = await this.llmService.callLLM(prompt)
      const securityResult = this.securityChecker.checkContent(llmResponse)

      if (!securityResult.safe) {
        await this.addMessage('我先陪着你。如果你愿意，可以慢一点继续说，我会认真听。', false)
        return
      }

      const actionResult: ActionResult = this.writeExecutor.parseAction(llmResponse)
      await this.handleActionResult(actionResult)
    } catch (error) {
      console.error('PsychChat sendMessage error:', JSON.stringify(error))
      await this.addMessage('我在这里。网络似乎有点波动，你可以再说一次。', false)
    } finally {
      this.isLoading = false
    }
  }

  /** 心理页主要关心自然回复和情绪观察，不处理日程弹窗这类操作。 */
  private async handleActionResult(actionResult: ActionResult): Promise<void> {
    if (actionResult.reply.length > 0) {
      await this.addMessage(actionResult.reply, false)
    }

    if (actionResult.psychState) {
      await this.addMessage(`情绪观察：${actionResult.psychState.level}；建议：${actionResult.psychState.suggestion}`, false)
    }
  }

  @Builder
  /** 心理辅导页单独使用不同配色，方便用户与普通会话做区分。 */
  private MessageItemBuilder(message: ChatMessage): void {
    Row() {
      if (!message.isUser) {
        Text('心')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('#7C3AED')
          .borderRadius(18)
      }

      Column() {
        Text(message.content)
          .fontSize(15)
          .lineHeight(22)
          .fontColor(message.isUser ? '#FFFFFF' : '#1E293B')
          .padding(12)
          .backgroundColor(message.isUser ? '#5B8CFF' : '#FFFFFF')
          .borderRadius({ topLeft: message.isUser ? 16 : 4, topRight: message.isUser ? 4 : 16, bottomLeft: 16, bottomRight: 16 })
          .constraintSize({ maxWidth: '78%' })

        Text(message.timestamp)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(message.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
      .margin(message.isUser ? { right: 10 } : { left: 10 })

      if (message.isUser) {
        Text('我')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .backgroundColor('#5B8CFF')
          .borderRadius(18)
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .justifyContent(message.isUser ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  build(): void {
    Column() {
      Row({ space: 10 }) {
        Button('←')
          .width(40)
          .height(40)
          .backgroundColor('rgba(255,255,255,0.18)')
          .borderRadius(12)
          .fontColor('#FFFFFF')
          .onClick(() => router.pushUrl({ url: 'pages/SessionSelect' }))

        Column({ space: 2 }) {
          Text(this.conversationTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text('专注倾听、陪伴与情绪疏导')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.8)')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 18, bottom: 14 })
      .linearGradient({
        direction: GradientDirection.Right,
        colors: [['#5B21B6', 0], ['#7C3AED', 0.6], ['#A78BFA', 1]]
      })

      if (this.isLoading) {
        Row({ space: 8 }) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color('#7C3AED')
          Text('AI 正在思考，请稍等…')
            .fontSize(12)
            .fontColor('#6D28D9')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 4 })
      }

      if (this.messageList.length === 0 && !this.isInitializing) {
        Column({ space: 10 }) {
          Text('欢迎来到心理辅导会话')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#334155')
          Text('你可以从最近让你最在意的一件事开始说。')
            .fontSize(13)
            .fontColor('#64748B')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.listScroller }) {
          ForEach(this.messageList, (item: ChatMessage): void => {
            ListItem() {
              this.MessageItemBuilder(item)
            }
          }, (item: ChatMessage): string => `${item.id}-${item.timestamp}`)
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor('#F5F3FF')
      }

      Row({ space: 10 }) {
        TextInput({ placeholder: '把你现在的感受写下来', text: $$this.inputText })
          .layoutWeight(1)
          .height(48)
          .fontSize(14)
          .backgroundColor('#FFFFFF')
          .borderRadius(14)
          .padding({ left: 14, right: 14 })
          .onSubmit(() => this.sendMessage())

        Button('发送')
          .width(64)
          .height(48)
          .backgroundColor(this.isLoading || this.inputText.trim().length === 0 ? '#C4B5FD' : '#7C3AED')
          .fontColor('#FFFFFF')
          .borderRadius(14)
          .enabled(!this.isLoading && this.inputText.trim().length > 0)
          .onClick(() => this.sendMessage())
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F3FF')
  }
}





