import common from '@ohos.app.ability.common'
import { router } from '@kit.ArkUI'
import { ConversationRecord, DatabaseManager, UserInfo } from '../database/DatabaseManager'

@Entry
@Component
/**
 * 会话选择页。
 * 用户登录后先进入这里，再决定进入哪个普通会话或心理辅导会话。
 */
struct SessionSelect {
  @State private conversationList: ConversationRecord[] = []
  @State private currentUser: UserInfo | null = null
  @State private isLoading: boolean = true

  private readonly dbManager: DatabaseManager = new DatabaseManager()

  /** 页面每次出现时都刷新一次会话列表，保证新建/删除后立即可见。 */
  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)
    await this.dbManager.initDB()
    await this.refreshSessionData()
  }

  onPageShow(): void {
    this.handlePageShow()
  }

  private handlePageShow(): void {
    this.refreshSessionData()
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private async refreshSessionData(): Promise<void> {
    this.isLoading = true
    const user = await this.dbManager.getCurrentUser()
    if (user === null) {
      this.isLoading = false
      router.replaceUrl({ url: 'pages/Login' })
      return
    }

    this.currentUser = user
    await this.loadConversations()
    this.isLoading = false
  }

  private async loadConversations(): Promise<void> {
    this.conversationList = await this.dbManager.getConversations()
  }

  private formatTime(timestamp: string): string {
    const date = new Date(timestamp)
    return date.toLocaleString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  private async createConversation(type: 'general' | 'psych'): Promise<void> {
    // 新会话先使用占位标题，后续会根据真实聊天内容自动重命名。
    const title = type === 'psych'
      ? `心理辅导 ${this.conversationList.filter((item: ConversationRecord): boolean => item.type === 'psych').length + 1}`
      : `新对话 ${this.conversationList.filter((item: ConversationRecord): boolean => item.type === 'general').length + 1}`

    const conversation = await this.dbManager.createConversation(title, type)
    if (conversation === null) {
      return
    }

    await this.loadConversations()
    this.openConversation(conversation)
  }

  private async openConversation(conversation: ConversationRecord): Promise<void> {
    // 先记录“当前会话”，其他页面只根据这个标记加载对应数据。
    await this.dbManager.setCurrentConversation(conversation.id)
    if (conversation.type === 'psych') {
      router.pushUrl({ url: 'pages/PsychChat' })
      return
    }
    router.pushUrl({ url: 'pages/Index' })
  }

  private async deleteConversation(conversation: ConversationRecord): Promise<void> {
    const success: boolean = await this.dbManager.deleteConversation(conversation.id)
    if (!success) {
      return
    }
    await this.loadConversations()
  }

  private async handleLogout(): Promise<void> {
    await this.dbManager.logout()
    router.replaceUrl({ url: 'pages/Login' })
  }

  @Builder
  /** 会话卡片同时承担摘要展示与进入/删除操作。 */
  private ConversationCardBuilder(item: ConversationRecord): void {
    Row() {
      Column({ space: 6 }) {
        Row({ space: 8 }) {
          Text(item.type === 'psych' ? '心' : '聊')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .backgroundColor(item.type === 'psych' ? '#7C3AED' : '#2D6A4F')
            .borderRadius(13)

          Column({ space: 2 }) {
            Text(item.title)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#1E293B')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(item.type === 'psych' ? '心理辅导会话' : '普通会话')
              .fontSize(11)
              .fontColor('#64748B')
          }
          .alignItems(HorizontalAlign.Start)
        }

        Text(item.lastMessage.length > 0 ? item.lastMessage : '还没有消息，点击开始对话')
          .fontSize(12)
          .fontColor('#475569')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(`最近更新：${this.formatTime(item.updatedTime)}`)
          .fontSize(10)
          .fontColor('#94A3B8')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('删除')
          .fontSize(12)
          .fontColor('#B91C1C')
          .fontWeight(FontWeight.Medium)
          .onClick((): void => { this.deleteConversation(item) })

        Text('进入')
          .fontSize(12)
          .fontColor(item.type === 'psych' ? '#7C3AED' : '#2D6A4F')
          .fontWeight(FontWeight.Medium)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .shadow({ radius: 8, color: 'rgba(15,23,42,0.06)', offsetX: 0, offsetY: 3 })
    .onClick(() => {
      this.openConversation(item)
    })
  }

  build(): void {
    Column({ space: 14 }) {
      Column({ space: 8 }) {
        Text('会话中心')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')

        if (this.currentUser !== null) {
          Text(`你好，${this.currentUser.username}`)
            .fontSize(13)
            .fontColor('rgba(255,255,255,0.82)')
        }

        Text('选择历史会话，或创建一个全新的对话')
          .fontSize(12)
          .fontColor('rgba(255,255,255,0.72)')
      }
      .width('100%')
      .padding({ top: 34, bottom: 22, left: 20, right: 20 })
      .alignItems(HorizontalAlign.Start)
      .linearGradient({
        direction: GradientDirection.Right,
        colors: [['#163B2E', 0], ['#2D6A4F', 0.6], ['#3D8361', 1]]
      })

      Row({ space: 12 }) {
        Button('新建普通对话')
          .layoutWeight(1)
          .height(46)
          .backgroundColor('#2D6A4F')
          .borderRadius(14)
          .fontColor('#FFFFFF')
          .onClick(() => this.createConversation('general'))

        Button('新建心理辅导')
          .layoutWeight(1)
          .height(46)
          .backgroundColor('#7C3AED')
          .borderRadius(14)
          .fontColor('#FFFFFF')
          .onClick(() => this.createConversation('psych'))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 2 })

      Row() {
        Text('历史会话')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Blank()
        Text(`${this.conversationList.length} 个`)
          .fontSize(12)
          .fontColor('#64748B')
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: 6 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#2D6A4F')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.conversationList.length === 0) {
        Column({ space: 12 }) {
          Text('暂无会话')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#334155')
          Text('先创建一个普通对话，或直接进入心理辅导模式。')
            .fontSize(13)
            .fontColor('#64748B')
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.conversationList, (item: ConversationRecord): void => {
            ListItem() {
              this.ConversationCardBuilder(item)
            }
          }, (item: ConversationRecord): string => `${item.id}-${item.updatedTime}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
        .edgeEffect(EdgeEffect.Spring)
      }

      Button('退出登录')
        .width('calc(100% - 32vp)')
        .height(44)
        .margin({ left: 16, right: 16, bottom: 16 })
        .backgroundColor('#E2E8F0')
        .fontColor('#334155')
        .borderRadius(14)
        .onClick(() => this.handleLogout())
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8FAFC')
  }
}




