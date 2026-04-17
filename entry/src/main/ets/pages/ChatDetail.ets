import common from '@ohos.app.ability.common'
import { DatabaseManager, MessageRecord } from '../database/DatabaseManager'
import { router } from '@kit.ArkUI'

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
struct ChatDetail {
  @State private messageList: ChatMessage[] = []
  @State private inputText: string = ''
  @State private isLoading: boolean = false
  @State private isInitializing: boolean = true

  private readonly listScroller: Scroller = new Scroller()
  private readonly dbManager: DatabaseManager = new DatabaseManager()

  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)
    await this.dbManager.initDB()
    await this.loadHistoryMessages()
    this.isInitializing = false
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private async loadHistoryMessages(): Promise<void> {
    const history: MessageRecord[] = await this.dbManager.getRecentMessages(100)
    this.messageList = history.map((msg: MessageRecord): ChatMessage => {
      return new ChatMessage(msg.id, msg.content, msg.isUser, this.formatTime(msg.timestamp))
    })
    this.scrollToBottom()
  }

  private formatTime(timestamp: string): string {
    const date: Date = new Date(timestamp)
    return date.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  private async addMessage(content: string, isUser: boolean): Promise<void> {
    const record: MessageRecord = await this.dbManager.saveMessage(content, isUser)
    const newMessage: ChatMessage = new ChatMessage(record.id, record.content, record.isUser, this.formatTime(record.timestamp))
    this.messageList = [...this.messageList, newMessage]
    this.scrollToBottom()
  }

  private scrollToBottom(): void {
    setTimeout((): void => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  async sendMessage(): Promise<void> {
    const userInput: string = this.inputText.trim()
    if (userInput.length === 0 || this.isLoading || this.isInitializing) {
      return
    }

    this.inputText = ''
    await this.addMessage(userInput, true)
    this.isLoading = true

    try {
      await new Promise<void>((resolve) => setTimeout(() => resolve(), 600))
      await this.addMessage('收到你的消息：' + userInput + '。详细处理请返回首页使用 AI 助手功能。', false)
    } catch (error) {
      console.error('ChatDetail sendMessage error:', JSON.stringify(error))
      await this.addMessage('发送失败，请稍后重试。', false)
    } finally {
      this.isLoading = false
    }
  }

  @Builder
  private AvatarBuilder(label: string, colors: string[]): void {
    Column() {
      Text(label)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .width(36)
    .height(36)
    .borderRadius(18)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [[colors[0], 0], [colors[1], 1]]
    })
    .justifyContent(FlexAlign.Center)
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.12)', offsetX: 0, offsetY: 2 })
  }

  @Builder
  private MessageItemBuilder(message: ChatMessage): void {
    Row() {
      if (!message.isUser) {
        this.AvatarBuilder('AI', ['#3B82F6', '#1D4ED8'])
      }

      Column() {
        Text(message.content)
          .fontSize(15)
          .lineHeight(22)
          .fontColor(message.isUser ? '#FFFFFF' : '#1E293B')
          .padding(12)
          .backgroundColor(message.isUser ? '#2D6A4F' : '#FFFFFF')
          .borderRadius({ topLeft: message.isUser ? 16 : 4, topRight: message.isUser ? 4 : 16, bottomLeft: 16, bottomRight: 16 })
          .shadow({
            radius: message.isUser ? 4 : 6,
            color: message.isUser ? 'rgba(45,106,79,0.2)' : 'rgba(0,0,0,0.06)',
            offsetX: 0,
            offsetY: 2
          })
          .constraintSize({ maxWidth: '76%' })

        Text(message.timestamp)
          .fontSize(10)
          .fontColor('#94A3B8')
          .margin({ top: 4 })
      }
      .alignItems(message.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
      .layoutWeight(1)
      .margin(message.isUser ? { right: 10 } : { left: 10 })

      if (message.isUser) {
        this.AvatarBuilder('我', ['#10B981', '#059669'])
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .justifyContent(message.isUser ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .animation({ duration: 250, curve: Curve.EaseOut })
  }

  build() {
    Column() {
      Row() {
        Button() {
          Text('←')
            .fontSize(20)
            .fontColor('#FFFFFF')
        }
        .width(40)
        .height(40)
        .backgroundColor('rgba(255,255,255,0.15)')
        .borderRadius(12)
        .onClick(() => {
          router.back()
        })

        Text('聊天记录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')

        Blank()

        Text(`${this.messageList.length} 条`)
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.8)')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#2D6A4F')
      .alignItems(VerticalAlign.Center)

      if (this.messageList.length === 0 && !this.isInitializing) {
        Column({ space: 10 }) {
          Text('🤖')
            .fontSize(48)
            .fontColor('#CBD5E1')
          Text('暂无聊天记录')
            .fontSize(14)
            .fontColor('#94A3B8')
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
            .padding({ top: 4, bottom: 4 })
          }, (item: ChatMessage): string => `${item.id}-${item.timestamp}-${item.isUser ? 'user' : 'ai'}`)
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor('#F1F5F9')
      }

      Row({ space: 10 }) {
        TextInput({ placeholder: '输入消息...', text: $$this.inputText })
          .layoutWeight(1)
          .height(48)
          .fontSize(14)
          .backgroundColor('#F8FAFC')
          .borderRadius(14)
          .padding({ left: 14, right: 14 })
          .placeholderColor('#CBD5E1')
          .onSubmit(() => this.sendMessage())

        Button() {
          Text('➤')
            .fontSize(18)
            .fontColor('#FFFFFF')
        }
        .width(48)
        .height(48)
        .borderRadius(14)
        .backgroundColor(this.isLoading || this.isInitializing || this.inputText.trim().length === 0 ? '#9FB7A8' : '#2D6A4F')
        .enabled(!this.isLoading && !this.isInitializing && this.inputText.trim().length > 0)
        .onClick(() => this.sendMessage())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 12 })
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 12, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: -4 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F5F9')
  }
}
