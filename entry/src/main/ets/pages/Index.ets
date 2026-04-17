import common from '@ohos.app.ability.common'
import { LLMService } from '../utils/LLMService'
import { DatabaseManager, MessageRecord, ScheduleRecord } from '../database/DatabaseManager'
import { ReadExecutor } from '../executors/ReadExecutor'
import { WriteExecutor, ActionResult } from '../executors/WriteExecutor'
import { SecurityChecker } from '../security/SecurityChecker'
import { ActionDialog } from '../components/ActionDialog'

/** 聊天气泡在页面层使用的轻量模型。 */
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

/**
 * 主页面负责串联 UI、数据库、读执行体、大模型、写执行体和安全检查。
 */
@Entry
@Component
struct Index {
  @State private messageList: ChatMessage[] = []
  @State private scheduleList: ScheduleRecord[] = []
  @State private messageCount: number = 0
  @State private pendingScheduleCount: number = 0
  @State private completedScheduleCount: number = 0
  @State private inputText: string = ''
  @State private isLoading: boolean = false
  @State private isInitializing: boolean = true
  @State private showActionDialog: boolean = false
  @State private dialogTitle: string = ''
  @State private dialogContent: string = ''
  @State private pendingSchedule: ScheduleRecord | null = null
  @State private lastSecurityHint: string = ''
  @State private sendBtnScale: number = 1

  private readonly listScroller: Scroller = new Scroller()
  private readonly dbManager: DatabaseManager = new DatabaseManager()
  private readonly llmService: LLMService = new LLMService()
  private readonly securityChecker: SecurityChecker = new SecurityChecker()
  private readonly writeExecutor: WriteExecutor = new WriteExecutor()

  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)

    const initOk: boolean = await this.dbManager.initDB()
    if (!initOk) {
      this.isInitializing = false
      await this.addTransientMessage('数据库初始化失败，请检查运行环境。', false)
      return
    }

    await this.loadInitialData()
    this.isInitializing = false

    if (this.messageList.length === 0) {
      await this.addMessage(
        '你好，我是你的 AI 秘书。我可以帮你记录日程、推荐学习内容，也可以陪你聊聊近况。',
        false
      )
    }
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private async loadInitialData(): Promise<void> {
    await this.loadHistoryMessages()
    await this.loadSchedules()
  }

  private refreshOverviewStats(): void {
    this.messageCount = this.messageList.length
    this.pendingScheduleCount = this.scheduleList.filter((item: ScheduleRecord): boolean => !item.isDone).length
    this.completedScheduleCount = this.scheduleList.filter((item: ScheduleRecord): boolean => item.isDone).length
  }

  private async loadHistoryMessages(): Promise<void> {
    const history: MessageRecord[] = await this.dbManager.getRecentMessages(20)
    this.messageList = history.map((msg: MessageRecord): ChatMessage => {
      return new ChatMessage(msg.id, msg.content, msg.isUser, this.formatTime(msg.timestamp))
    })
    this.refreshOverviewStats()
  }

  private async loadSchedules(): Promise<void> {
    const schedules: ScheduleRecord[] = await this.dbManager.getAllSchedules()
    this.scheduleList = schedules.map((item: ScheduleRecord): ScheduleRecord => {
      return {
        id: item.id,
        content: item.content,
        createdTime: item.createdTime,
        remindTime: item.remindTime,
        isDone: item.isDone
      }
    })
    this.refreshOverviewStats()
  }

  private formatTime(timestamp: string): string {
    const date: Date = new Date(timestamp)
    return date.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  private formatDateTime(timestamp?: string): string {
    if (timestamp === undefined || timestamp.length === 0) {
      return '未设置提醒时间'
    }
    const date: Date = new Date(timestamp)
    return date.toLocaleString('zh-CN', {
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  private async addMessage(content: string, isUser: boolean): Promise<void> {
    const record: MessageRecord = await this.dbManager.saveMessage(content, isUser)
    const newMessage: ChatMessage = new ChatMessage(record.id, record.content, record.isUser, this.formatTime(record.timestamp))
    this.messageList = [...this.messageList, newMessage]
    this.refreshOverviewStats()
    this.scrollToBottom()
  }

  private async addTransientMessage(content: string, isUser: boolean): Promise<void> {
    const message: ChatMessage = new ChatMessage(
      this.messageList.length + 1,
      content,
      isUser,
      this.formatTime(new Date().toISOString())
    )
    this.messageList = [...this.messageList, message]
    this.refreshOverviewStats()
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
      const readExecutor: ReadExecutor = new ReadExecutor(this.dbManager)
      const prompt: string = await readExecutor.buildPrompt(userInput)
      const llmResponse: string = await this.llmService.callLLM(prompt)

      const securityResult = this.securityChecker.checkContent(llmResponse)
      if (!securityResult.safe) {
        this.lastSecurityHint = securityResult.reason ?? '安全检查未通过'
        await this.addMessage(`我拦截了一条不安全的模型输出：${this.lastSecurityHint}`, false)
        return
      }

      const actionResult: ActionResult = this.writeExecutor.parseAction(llmResponse)
      await this.handleActionResult(actionResult)
    } catch (error) {
      console.error('Index sendMessage error:', JSON.stringify(error))
      await this.addMessage('处理消息时出错，请稍后重试。', false)
    } finally {
      this.isLoading = false
    }
  }

  private async handleActionResult(actionResult: ActionResult): Promise<void> {
    if (!actionResult.valid && actionResult.action === 'chat') {
      await this.addMessage(actionResult.reply, false)
      return
    }

    switch (actionResult.action) {
      case 'schedule': {
        const schedule: ScheduleRecord = {
          id: 0,
          content: actionResult.data ?? actionResult.scheduleDetail?.displayContent ?? '新日程安排',
          createdTime: new Date().toISOString(),
          remindTime: actionResult.scheduleDetail?.remindTime ?? undefined,
          isDone: false
        }
        this.pendingSchedule = schedule
        this.dialogTitle = '添加日程'
        this.dialogContent = `${actionResult.reply}\n\n${schedule.content}`
        this.showActionDialog = true
        break
      }
      case 'study': {
        if (actionResult.studyRecommendation) {
          const recommendation = actionResult.studyRecommendation
          const content: string = `${actionResult.reply}\n\n主题：${recommendation.topic}\n难度：${recommendation.difficulty}\n周期：${recommendation.duration}\n资源：${recommendation.resources.join('；')}\n计划：${recommendation.plan.join('；')}`
          await this.addMessage(content, false)
        } else {
          await this.addMessage(actionResult.reply, false)
        }
        break
      }
      case 'psych': {
        await this.addMessage(actionResult.reply, false)
        if (actionResult.psychState) {
          await this.addMessage(`情绪评估：${actionResult.psychState.level}；建议：${actionResult.psychState.suggestion}`, false)
        }
        this.writeExecutor.recordPsychState(actionResult.rawData ?? actionResult.reply, actionResult.reply)
        break
      }
      case 'unknown': {
        const fallback = actionResult.errorMessage
          ? `${actionResult.reply}\n\n说明：${actionResult.errorMessage}`
          : actionResult.reply
        await this.addMessage(fallback, false)
        break
      }
      case 'chat':
      default:
        await this.addMessage(actionResult.reply, false)
        break
    }
  }

  private async onDialogConfirm(): Promise<void> {
    if (this.pendingSchedule !== null) {
      const savedSchedule: ScheduleRecord = await this.dbManager.saveSchedule(this.pendingSchedule.content, this.pendingSchedule.remindTime)
      this.scheduleList = [savedSchedule, ...this.scheduleList]
      this.refreshOverviewStats()
      await this.addMessage(`已添加日程：${savedSchedule.content}`, false)
    }
    this.showActionDialog = false
    this.pendingSchedule = null
  }

  private async onDialogCancel(): Promise<void> {
    this.showActionDialog = false
    this.pendingSchedule = null
    await this.addMessage('本次日程操作已取消。', false)
  }

  private async markScheduleDone(scheduleId: number): Promise<void> {
    const success: boolean = await this.dbManager.markScheduleDone(scheduleId)
    if (!success) {
      await this.addMessage('标记完成失败，请稍后重试。', false)
      return
    }
    this.scheduleList = this.scheduleList.map((item: ScheduleRecord): ScheduleRecord => {
      if (item.id === scheduleId) {
        return { id: item.id, content: item.content, createdTime: item.createdTime, remindTime: item.remindTime, isDone: true }
      }
      return item
    })
    this.refreshOverviewStats()
    await this.addMessage('已将该日程标记为完成。', false)
  }

  private handleDialogConfirm(): void { this.onDialogConfirm() }
  private handleDialogCancel(): void { this.onDialogCancel() }
  private handleMarkScheduleDone(scheduleId: number): void { this.markScheduleDone(scheduleId) }

  /* ========================= 现代化 UI 构建 ========================= */

  @Builder
  private HeaderBuilder(): void {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Text('✦')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.7)')
        Text('AI 秘书')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text('✦')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.7)')
      }

      Text('聊天 · 日程 · 学习 · 关怀')
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.75)')

      if (this.lastSecurityHint.length > 0) {
        Text(`⚠ 最近一次拦截：${this.lastSecurityHint}`)
          .fontSize(10)
          .fontColor('rgba(255,235,59,0.95)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 14 })
    .alignItems(HorizontalAlign.Center)
    .linearGradient({
      direction: GradientDirection.Bottom,
      colors: [['#1B4332', 0], ['#2D6A4F', 1]]
    })
  }

  @Builder
  private OverviewBuilder(): void {
    Row() {
      this.OverviewCardBuilder(
        '💬 聊天记录',
        `${this.messageList.length}`,
        '#3B82F6',
        '#EFF6FF'
      )
      this.OverviewCardBuilder(
        '📋 待办日程',
        `${this.scheduleList.filter((item: ScheduleRecord): boolean => !item.isDone).length}`,
        '#F59E0B',
        '#FFFBEB'
      )
      this.OverviewCardBuilder(
        '✅ 已完成',
        `${this.scheduleList.filter((item: ScheduleRecord): boolean => item.isDone).length}`,
        '#10B981',
        '#ECFDF5'
      )
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 6 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private OverviewCardBuilder(label: string, value: string, accentColor: string, bgColor: string): void {
    Column({ space: 6 }) {
      Row()
        .width('100%')
        .height(3)
        .backgroundColor(accentColor)
        .borderRadius({ topLeft: 14, topRight: 14 })

      Column({ space: 4 }) {
        Text(label)
          .fontSize(11)
          .fontColor('#64748B')
        Text(value)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1E293B')
      }
      .padding(12)
      .alignItems(HorizontalAlign.Start)
    }
    .width('31%')
    .backgroundColor(bgColor)
    .borderRadius(14)
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
  }

  @Builder
  private SchedulePanelBuilder(): void {
    Column({ space: 10 }) {
      Row() {
        Row({ space: 6 }) {
          Text('📅')
            .fontSize(16)
          Text('日程安排')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E293B')
        }

        Blank()

        Text(`${this.scheduleList.length} 条`)
          .fontSize(12)
          .fontColor('#94A3B8')
          .backgroundColor('#F1F5F9')
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10)
      }
      .width('100%')

      if (this.scheduleList.length === 0) {
        Column({ space: 8 }) {
          Text('🗓')
            .fontSize(32)
            .fontColor('#CBD5E1')
          Text('还没有保存的日程')
            .fontSize(13)
            .fontColor('#94A3B8')
          Text('试试发送"帮我安排明天下午3点开会"')
            .fontSize(12)
            .fontColor('#CBD5E1')
        }
        .width('100%')
        .padding({ top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.scheduleList, (item: ScheduleRecord): void => {
            ListItem() {
              this.ScheduleItemBuilder(item)
            }
            .padding({ top: 4, bottom: 4 })
          }, (item: ScheduleRecord): string => `${item.id}-${item.isDone ? 'done' : 'todo'}-${item.content}`)
        }
        .width('100%')
        .height(180)
        .edgeEffect(EdgeEffect.Spring)
        .divider({ strokeWidth: 8, color: '#F8FAFC' })
      }
    }
    .width('100%')
    .padding(14)
    .margin({ left: 12, right: 12, top: 6, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.05)', offsetX: 0, offsetY: 3 })
  }

  @Builder
  private ScheduleItemBuilder(schedule: ScheduleRecord): void {
    Row() {
      Row()
        .width(4)
        .height('80%')
        .backgroundColor(schedule.isDone ? '#10B981' : '#F59E0B')
        .borderRadius(2)
        .margin({ right: 10 })

      Column({ space: 6 }) {
        Text(schedule.content)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(schedule.isDone ? '#94A3B8' : '#1E293B')
          .decoration({ type: schedule.isDone ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row({ space: 4 }) {
          Text('🕐')
            .fontSize(10)
          Text(this.formatDateTime(schedule.remindTime ?? schedule.createdTime))
            .fontSize(11)
            .fontColor('#94A3B8')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!schedule.isDone) {
        Button('完成')
          .fontSize(12)
          .height(32)
          .backgroundColor('#2D6A4F')
          .fontColor('#FFFFFF')
          .borderRadius(10)
          .shadow({ radius: 4, color: 'rgba(45,106,79,0.25)', offsetX: 0, offsetY: 2 })
          .onClick((): void => this.handleMarkScheduleDone(schedule.id))
      } else {
        Row({ space: 4 }) {
          Text('✓')
            .fontSize(11)
            .fontColor('#10B981')
          Text('已完成')
            .fontSize(12)
            .fontColor('#10B981')
        }
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor('#ECFDF5')
        .borderRadius(10)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('#F8FAFC')
    .borderRadius(14)
  }

  @Builder
  private ChatPanelBuilder(): void {
    Column() {
      Row() {
        Row({ space: 6 }) {
          Text('💬')
            .fontSize(16)
          Text('聊天记录')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E293B')
        }

        Blank()

        if (this.isLoading) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color('#2D6A4F')
            Text('AI 正在思考…')
              .fontSize(11)
              .fontColor('#64748B')
          }
          .animation({ duration: 300, curve: Curve.EaseInOut })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 14, bottom: 6 })

      if (this.messageList.length === 0 && !this.isInitializing) {
        Column({ space: 10 }) {
          Text('🤖')
            .fontSize(48)
            .fontColor('#CBD5E1')
          Text('开始你的第一次对话吧')
            .fontSize(14)
            .fontColor('#94A3B8')
          Text('我可以帮你安排日程、推荐学习计划')
            .fontSize(12)
            .fontColor('#CBD5E1')
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
    }
    .layoutWeight(1)
    .width('100%')
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
  private InputBuilder(): void {
    Row({ space: 10 }) {
      TextInput({ placeholder: '输入消息，例如：帮我安排明天下午3点开会', text: $$this.inputText })
        .layoutWeight(1)
        .height(48)
        .fontSize(14)
        .backgroundColor('#F8FAFC')
        .borderRadius(14)
        .padding({ left: 14, right: 14 })
        .placeholderColor('#CBD5E1')
        .onSubmit((): void => { this.sendMessage() })

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
      .shadow({ radius: 6, color: 'rgba(45,106,79,0.3)', offsetX: 0, offsetY: 3 })
      .scale({ x: this.sendBtnScale, y: this.sendBtnScale })
      .animation({ duration: 150, curve: Curve.EaseInOut })
      .onClick((): void => {
        this.sendBtnScale = 0.9
        setTimeout(() => this.sendBtnScale = 1, 100)
        this.sendMessage()
      })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: -4 })
  }

  build(): void {
    Stack() {
      Column() {
        this.HeaderBuilder()
        this.OverviewBuilder()
        this.SchedulePanelBuilder()
        this.ChatPanelBuilder()
        this.InputBuilder()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F1F5F9')

      ActionDialog({
        isShow: this.showActionDialog,
        title: this.dialogTitle,
        content: this.dialogContent,
        onConfirm: (): void => this.handleDialogConfirm(),
        onCancel: (): void => this.handleDialogCancel()
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F5F9')
  }
}
