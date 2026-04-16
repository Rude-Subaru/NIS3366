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
 * 注意：这里不改写执行体和安全模块的内部逻辑，只消费它们暴露的结果。
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

    // 首次进入没有记录时，自动补一条欢迎语。
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

  /** 正常消息会持久化到数据库。 */
  private async addMessage(content: string, isUser: boolean): Promise<void> {
    const record: MessageRecord = await this.dbManager.saveMessage(content, isUser)
    const newMessage: ChatMessage = new ChatMessage(record.id, record.content, record.isUser, this.formatTime(record.timestamp))
    this.messageList = [...this.messageList, newMessage]
    this.refreshOverviewStats()
    this.scrollToBottom()
  }

  /** 临时提示只显示在界面上，不写数据库。 */
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

  /**
   * 消费写执行体的标准化结果。
   * 这里不重新解析 JSON，只根据 actionResult 中的字段驱动 UI 和数据库。
   */
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
        return {
          id: item.id,
          content: item.content,
          createdTime: item.createdTime,
          remindTime: item.remindTime,
          isDone: true
        }
      }
      return item
    })
    this.refreshOverviewStats()
    await this.addMessage('已将该日程标记为完成。', false)
  }

  private handleDialogConfirm(): void {
    this.onDialogConfirm()
  }

  private handleDialogCancel(): void {
    this.onDialogCancel()
  }

  private handleMarkScheduleDone(scheduleId: number): void {
    this.markScheduleDone(scheduleId)
  }

  @Builder
  private HeaderBuilder(): void {
    Column({ space: 4 }) {
      Text('AI 秘书')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')

      Text('聊天、日程和学习建议都在这里')
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.85)')

      if (this.lastSecurityHint.length > 0) {
        Text(`最近一次拦截：${this.lastSecurityHint}`)
          .fontSize(10)
          .fontColor('rgba(255,255,255,0.75)')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#2D6A4F')
  }

  @Builder
  private OverviewBuilder(): void {
    Row() {
      Column({ space: 8 }) {
        Text('聊天记录')
          .fontSize(12)
          .fontColor('#52606D')
        Text(`${this.messageList.length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2933')
      }
      .width('31%')
      .padding(12)
      .backgroundColor('#F4FBF6')
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('待办日程')
          .fontSize(12)
          .fontColor('#52606D')
        Text(`${this.scheduleList.filter((item: ScheduleRecord): boolean => !item.isDone).length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2933')
      }
      .width('31%')
      .padding(12)
      .backgroundColor('#FFF7ED')
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('已完成')
          .fontSize(12)
          .fontColor('#52606D')
        Text(`${this.scheduleList.filter((item: ScheduleRecord): boolean => item.isDone).length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2933')
      }
      .width('31%')
      .padding(12)
      .backgroundColor('#EEF2FF')
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 6 })
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private SchedulePanelBuilder(): void {
    Column({ space: 10 }) {
      Row() {
        Text('日程安排')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2933')

        Blank()

        Text(`${this.scheduleList.length} 条记录`)
          .fontSize(12)
          .fontColor('#7B8794')
      }
      .width('100%')

      if (this.scheduleList.length === 0) {
        Text('还没有保存的日程，试试发送“帮我安排明天下午3点开会”。')
          .fontSize(13)
          .fontColor('#7B8794')
          .width('100%')
      } else {
        List() {
          ForEach(this.scheduleList, (item: ScheduleRecord): void => {
            ListItem() {
              this.ScheduleItemBuilder(item)
            }
          }, (item: ScheduleRecord): string => `${item.id}-${item.isDone ? 'done' : 'todo'}-${item.content}`)
        }
        .width('100%')
        .height(180)
        .divider({ strokeWidth: 8, color: '#F8FAFC' })
      }
    }
    .width('100%')
    .padding(14)
    .margin({ left: 12, right: 12, top: 6, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  private ScheduleItemBuilder(schedule: ScheduleRecord): void {
    Row() {
      Column({ space: 6 }) {
        Text(schedule.content)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(schedule.isDone ? '#7B8794' : '#1F2933')
          .decoration({ type: schedule.isDone ? TextDecorationType.LineThrough : TextDecorationType.None })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatDateTime(schedule.remindTime ?? schedule.createdTime))
          .fontSize(11)
          .fontColor('#7B8794')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (!schedule.isDone) {
        Button('完成')
          .fontSize(12)
          .height(34)
          .backgroundColor('#2D6A4F')
          .fontColor('#FFFFFF')
          .borderRadius(10)
          .onClick((): void => this.handleMarkScheduleDone(schedule.id))
      } else {
        Text('已完成')
          .fontSize(12)
          .fontColor('#2D6A4F')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor('#E8F5E9')
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
        Text('聊天记录')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1F2933')

        Blank()

        if (this.isLoading) {
          Row() {
            LoadingProgress()
              .width(14)
              .height(14)
              .color('#2D6A4F')

            Text('AI 正在思考')
              .fontSize(11)
              .fontColor('#52606D')
              .margin({ left: 6 })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 14, bottom: 6 })

      List({ scroller: this.listScroller }) {
        ForEach(this.messageList, (item: ChatMessage): void => {
          ListItem() {
            this.MessageItemBuilder(item)
          }
        }, (item: ChatMessage): string => `${item.id}-${item.timestamp}-${item.isUser ? 'user' : 'ai'}`)
      }
      .layoutWeight(1)
      .width('100%')
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor('#EEF2F6')
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private MessageItemBuilder(message: ChatMessage): void {
    Row() {
      if (!message.isUser) {
        this.AvatarBuilder('AI', '#3F5E7A')
      }

      Column() {
        Text(message.content)
          .fontSize(15)
          .lineHeight(22)
          .fontColor('#1F2933')
          .padding(12)
          .backgroundColor(message.isUser ? '#D8F3DC' : '#FFFFFF')
          .borderRadius(12)
          .constraintSize({ maxWidth: '78%' })

        Text(message.timestamp)
          .fontSize(10)
          .fontColor('#7B8794')
          .margin({ top: 4 })
      }
      .alignItems(message.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
      .layoutWeight(1)
      .margin(message.isUser ? { right: 12 } : { left: 12 })

      if (message.isUser) {
        this.AvatarBuilder('我', '#2D6A4F')
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .justifyContent(message.isUser ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private AvatarBuilder(label: string, color: string): void {
    Column() {
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFF')
    }
    .width(36)
    .height(36)
    .borderRadius(8)
    .backgroundColor(color)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private InputBuilder(): void {
    Row() {
      TextInput({ placeholder: '输入消息，例如：帮我安排明天下午3点开会', text: $$this.inputText })
        .layoutWeight(1)
        .height(46)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onSubmit((): void => {
          this.sendMessage()
        })

      Button('发送')
        .width(76)
        .height(46)
        .margin({ left: 10 })
        .borderRadius(12)
        .backgroundColor(this.isLoading || this.isInitializing ? '#9FB7A8' : '#2D6A4F')
        .enabled(!this.isLoading && !this.isInitializing && this.inputText.trim().length > 0)
        .onClick((): void => {
          this.sendMessage()
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor('#F8FAFC')
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
      .backgroundColor('#EEF2F6')

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
    .backgroundColor('#EEF2F6')
  }
}

