import common from '@ohos.app.ability.common'
import { router } from '@kit.ArkUI'
import { LLMService } from '../utils/LLMService'
import { ConversationRecord, DatabaseManager, MessageRecord, ScheduleRecord, UserInfo } from '../database/DatabaseManager'
import { ReadExecutor } from '../executors/ReadExecutor'
import { WriteExecutor, ActionResult, ScheduleDetail } from '../executors/WriteExecutor'
import { SecurityChecker } from '../security/SecurityChecker'
import { ActionDialog } from '../components/ActionDialog'

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

/** 日程编辑表单在页面内的临时状态。 */
interface ScheduleFormState {
  detail: string
  date: string
  time: string
  location: string
}

@Entry
@Component
/**
 * 普通会话主页面。
 * 这里串起了整个 AI 秘书主流程：
 * 1. 读取当前登录用户与当前会话。
 * 2. 展示当前会话的聊天记录和日程。
 * 3. 将用户输入依次交给读执行体、LLM 服务、安全检查和写执行体处理。
 * 4. 按动作类型决定是直接回复、弹窗确认日程，还是跳转心理辅导页面。
 */
struct Index {
  // 页面状态：会随着用户操作和数据库读取实时刷新。
  @State private messageList: ChatMessage[] = []
  @State private scheduleList: ScheduleRecord[] = []
  @State private inputText: string = ''
  @State private isLoading: boolean = false
  @State private isInitializing: boolean = true
  @State private showActionDialog: boolean = false
  @State private dialogTitle: string = ''
  @State private dialogContent: string = ''
  @State private pendingSchedule: ScheduleRecord | null = null
  @State private editingScheduleId: number = 0
  @State private editScheduleDetail: string = ''
  @State private editScheduleDate: string = ''
  @State private editScheduleTime: string = ''
  @State private editScheduleLocation: string = ''
  @State private lastSecurityHint: string = ''
  @State private currentUsername: string = ''
  @State private currentConversationTitle: string = '当前会话'
  @State private currentTab: string = 'dialog'
  @State private showOverviewSection: boolean = false
  @State private showScheduleSection: boolean = false

  private readonly listScroller: Scroller = new Scroller()
  private readonly dbManager: DatabaseManager = new DatabaseManager()
  private readonly llmService: LLMService = new LLMService()
  private readonly securityChecker: SecurityChecker = new SecurityChecker()
  private readonly writeExecutor: WriteExecutor = new WriteExecutor()
  // 当前页面只处理普通会话，心理辅导会话会跳转到独立页面。
  private currentConversationId: number = 0
  private currentConversationType: 'general' | 'psych' = 'general'

  /**
   * 页面出现时完成会话恢复：
   * 先初始化数据库，再检查登录状态和当前会话，最后加载消息与日程。
   */
  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)

    const initOk: boolean = await this.dbManager.initDB()
    if (!initOk) {
      this.isInitializing = false
      await this.addTransientMessage('数据库初始化失败，请检查运行环境。', false)
      return
    }

    const currentUser: UserInfo | null = await this.dbManager.getCurrentUser()
    if (currentUser === null) {
      router.replaceUrl({ url: 'pages/Login' })
      return
    }
    this.currentUsername = currentUser.username

    const conversation: ConversationRecord | null = await this.dbManager.getCurrentConversation()
    if (conversation === null) {
      router.replaceUrl({ url: 'pages/SessionSelect' })
      return
    }
    if (conversation.type === 'psych') {
      router.replaceUrl({ url: 'pages/PsychChat' })
      return
    }

    this.currentConversationId = conversation.id
    this.currentConversationType = conversation.type
    this.currentConversationTitle = conversation.title

    await this.loadInitialData()
    this.isInitializing = false

    if (this.messageList.length === 0) {
      await this.addMessage('你好，我是你的 AI 秘书。你可以直接聊天、创建日程，或者在需要时切换到心理辅导会话。', false)
    }
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private async loadInitialData(): Promise<void> {
    await this.loadHistoryMessages()
    await this.loadSchedules()
  }

  private async loadHistoryMessages(): Promise<void> {
    const history: MessageRecord[] = await this.dbManager.getRecentMessages(50, this.currentConversationId)
    this.messageList = history.map((msg: MessageRecord): ChatMessage => {
      return new ChatMessage(msg.id, msg.content, msg.isUser, this.formatTime(msg.timestamp))
    })
  }

  private async loadSchedules(): Promise<void> {
    this.scheduleList = await this.dbManager.getAllSchedules(this.currentConversationId)
  }

  private formatTime(timestamp: string): string {
    const date: Date = new Date(timestamp)
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  }

  private formatDateTime(timestamp?: string): string {
    if (timestamp === undefined || timestamp.length === 0) {
      return '未设置提醒时间'
    }

    const date: Date = new Date(timestamp)
    return date.toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
  }

  /**
   * 日程创建时采用“双路合并”：
   * 既参考模型返回的结构化结果，也再次基于用户原话做本地解析，
   * 避免模型漏掉“明天 / 周三 / 下午三点”这类关键信息。
   */
  private mergeScheduleDetail(modelDetail: ScheduleDetail | undefined, userInput: string): ScheduleDetail {
    const inputDetail: ScheduleDetail = this.writeExecutor.parseScheduleDetail(userInput)
    const mergedEvent: string = inputDetail.event.length > 0 && inputDetail.event !== '待办事项'
      ? inputDetail.event
      : (modelDetail?.event ?? inputDetail.event)
    const mergedTime: string | null = inputDetail.extractedTime ?? modelDetail?.extractedTime ?? null
    const mergedLocation: string | null = inputDetail.extractedLocation ?? modelDetail?.extractedLocation ?? null
    const mergedRawContent: string = userInput.trim().length > 0 ? userInput.trim() : (modelDetail?.rawContent ?? inputDetail.rawContent)
    return {
      rawContent: mergedRawContent,
      event: mergedEvent,
      extractedTime: mergedTime,
      extractedLocation: mergedLocation,
      remindTime: mergedTime,
      confidence: modelDetail ? Math.max(modelDetail.confidence, inputDetail.confidence) : inputDetail.confidence,
      displayContent: this.buildStructuredScheduleContent(mergedEvent, mergedTime, mergedLocation)
    }
  }

  private buildStructuredScheduleContent(detail: string, remindTime?: string | null, location?: string | null): string {
    const dateText: string = remindTime && remindTime.length >= 10 ? remindTime.substring(0, 10) : '未设置'
    const timeText: string = remindTime && remindTime.length >= 16 ? remindTime.substring(11, 16) : '未设置'
    const locationText: string = location !== undefined && location !== null && location.trim().length > 0 ? location.trim() : '未设置'
    const detailText: string = detail.trim().length > 0 ? detail.trim() : '待办事项'
    return `详情：${detailText}\n日期：${dateText}\n时间：${timeText}\n地点：${locationText}`
  }

  /** 将数据库中的结构化日程文本拆回编辑表单，便于二次修改。 */
  private parseScheduleForm(content: string, remindTime?: string): ScheduleFormState {
    const lines: string[] = content.split('\n')
    let detail: string = ''
    let date: string = ''
    let time: string = ''
    let location: string = ''

    for (let index = 0; index < lines.length; index++) {
      const line: string = lines[index].trim()
      if (line.indexOf('详情：') === 0 || line.indexOf('事项：') === 0) {
        detail = line.substring(3).trim()
      } else if (line.indexOf('日期：') === 0) {
        date = line.substring(3).trim()
      } else if (line.indexOf('时间：') === 0) {
        time = line.substring(3).trim()
      } else if (line.indexOf('地点：') === 0) {
        location = line.substring(3).trim()
      }
    }

    if ((date.length === 0 || time.length === 0) && remindTime !== undefined && remindTime.length >= 16) {
      if (date.length === 0) {
        date = remindTime.substring(0, 10)
      }
      if (time.length === 0) {
        time = remindTime.substring(11, 16)
      }
    }

    if (detail.length === 0) {
      detail = content.replace(/\n/g, ' ').trim()
    }

    return {
      detail: detail === '未设置' ? '' : detail,
      date: date === '未设置' ? '' : date,
      time: time === '未设置' ? '' : time,
      location: location === '未设置' ? '' : location
    }
  }

  /** 日期和时间在页面内分开编辑，保存前再合并成统一的提醒时间字符串。 */
  private buildRemindTime(date: string, time: string): string | undefined {
    if (date.trim().length === 0 || time.trim().length === 0) {
      return undefined
    }
    return `${date.trim()} ${time.trim()}`
  }

  /** 学习模块采用固定输出套路，和普通聊天在视觉与内容组织上做区分。 */
  private buildStudyReply(actionResult: ActionResult): string {
    const recommendation = actionResult.studyRecommendation
    if (!recommendation) {
      return actionResult.reply
    }

    const intro: string = actionResult.reply.trim().length > 0
      ? actionResult.reply.trim()
      : '我先按你的需求整理一份学习建议。'
    const resourceText: string = recommendation.resources.slice(0, 3).join('、')
    const planText: string = recommendation.plan.map((item: string, index: number): string => `${index + 1}. ${item}`).join('\n')
    const nextStep: string = recommendation.plan.length > 0 ? recommendation.plan[0] : '先花 20 分钟梳理核心概念。'

    return [
      `学习建议：${recommendation.topic}`,
      intro,
      '',
      `学习主题：${recommendation.topic}`,
      `建议难度：${recommendation.difficulty}`,
      `建议周期：${recommendation.duration}`,
      `推荐资料：${resourceText}`,
      '',
      '学习路径：',
      planText,
      '',
      `你现在可以先做：${nextStep}`
    ].join('\n')
  }

  private getTodayDateString(): string {
    const now = new Date()
    const year = now.getFullYear()
    const month = `${now.getMonth() + 1}`.padStart(2, '0')
    const day = `${now.getDate()}`.padStart(2, '0')
    return `${year}-${month}-${day}`
  }

  private getDefaultTimeString(): string {
    return '09:00'
  }

  private getWeekdayLabel(date: Date): string {
    const weekdays: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
    return weekdays[date.getDay()]
  }

  /** 生成日期滚轮可选项，保留“今天/明天/后天”的自然语义提示。 */
  private getDatePickerOptions(): string[] {
    const options: string[] = []
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    for (let offset = 0; offset < 30; offset++) {
      const target = new Date(today.getTime())
      target.setDate(today.getDate() + offset)
      const year = target.getFullYear()
      const month = `${target.getMonth() + 1}`.padStart(2, '0')
      const day = `${target.getDate()}`.padStart(2, '0')
      let label = ''
      if (offset === 0) {
        label = '今天'
      } else if (offset === 1) {
        label = '明天'
      } else if (offset === 2) {
        label = '后天'
      } else {
        label = this.getWeekdayLabel(target)
      }
      options.push(`${year}-${month}-${day} ${label}`)
    }
    return options
  }

  /** 生成时间滚轮可选项，步进为 10 分钟，更贴近日常提醒场景。 */
  private getTimePickerOptions(): string[] {
    const options: string[] = []
    for (let hour = 0; hour < 24; hour++) {
      for (let minute = 0; minute < 60; minute += 10) {
        options.push(`${`${hour}`.padStart(2, '0')}:${`${minute}`.padStart(2, '0')}`)
      }
    }
    return options
  }

  private getDatePickerIndex(): number {
    const options: string[] = this.getDatePickerOptions()
    const targetDate = this.editScheduleDate.trim().length > 0 ? this.editScheduleDate.trim() : this.getTodayDateString()
    for (let index = 0; index < options.length; index++) {
      if (options[index].indexOf(targetDate) === 0) {
        return index
      }
    }
    return 0
  }

  private getTimePickerIndex(): number {
    const options: string[] = this.getTimePickerOptions()
    const targetTime = this.editScheduleTime.trim().length > 0 ? this.editScheduleTime.trim() : this.getDefaultTimeString()
    const index = options.indexOf(targetTime)
    return index >= 0 ? index : 0
  }

  private extractDateFromOption(option: string): string {
    return option.length >= 10 ? option.substring(0, 10) : this.getTodayDateString()
  }
  private getPendingScheduleCount(): number {
    return this.scheduleList.filter((item: ScheduleRecord): boolean => !item.isDone).length
  }

  private getCompletedScheduleCount(): number {
    return this.scheduleList.filter((item: ScheduleRecord): boolean => item.isDone).length
  }

  private async addMessage(content: string, isUser: boolean): Promise<void> {
    const record: MessageRecord = await this.dbManager.saveMessage(content, isUser, this.currentConversationId)
    const newMessage: ChatMessage = new ChatMessage(record.id, record.content, record.isUser, this.formatTime(record.timestamp))
    this.messageList = [...this.messageList, newMessage]
    if (isUser) {
      const updatedConversation = await this.dbManager.getConversationById(this.currentConversationId)
      if (updatedConversation !== null) {
        this.currentConversationTitle = updatedConversation.title
      }
    }
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
      await this.handleActionResult(actionResult, userInput)
    } catch (error) {
      console.error('Index sendMessage error:', JSON.stringify(error))
      await this.addMessage('处理消息时出错，请稍后重试。', false)
    } finally {
      this.isLoading = false
    }
  }

  /**
   * 写执行体只负责“判定动作”，真正的页面行为统一在这里落地：
   * - schedule：先进入确认弹窗
   * - psych：切到对应的心理辅导会话
   * - 其他动作：直接写入聊天记录
   */
  private async handleActionResult(actionResult: ActionResult, userInput: string): Promise<void> {
    if (!actionResult.valid && actionResult.action === 'chat') {
      await this.addMessage(actionResult.reply, false)
      return
    }

    switch (actionResult.action) {
      case 'schedule': {
        const mergedDetail: ScheduleDetail = this.mergeScheduleDetail(actionResult.scheduleDetail, userInput)
        const schedule: ScheduleRecord = {
          id: 0,
          conversationId: this.currentConversationId,
          content: mergedDetail.displayContent,
          createdTime: new Date().toISOString(),
          remindTime: mergedDetail.remindTime ?? undefined,
          isDone: false
        }
        this.pendingSchedule = schedule
        this.dialogTitle = '添加日程'
        this.dialogContent = `${actionResult.reply}\n\n${mergedDetail.displayContent}`
        this.showActionDialog = true
        break
      }
      case 'study': {
        await this.addMessage(this.buildStudyReply(actionResult), false)
        break
      }
      case 'psych': {
        const psychConversation = await this.dbManager.getOrCreatePsychConversation(this.currentConversationId)
        if (psychConversation !== null) {
          await this.dbManager.saveMessage(userInput, true, psychConversation.id)
          await this.dbManager.saveMessage(actionResult.reply, false, psychConversation.id)
          if (actionResult.psychState) {
            await this.dbManager.saveMessage(`情绪评估：${actionResult.psychState.level}；建议：${actionResult.psychState.suggestion}`, false, psychConversation.id)
          }
          router.pushUrl({ url: 'pages/PsychChat' })
          return
        }

        await this.addMessage(actionResult.reply, false)
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
      const savedSchedule: ScheduleRecord = await this.dbManager.saveSchedule(this.pendingSchedule.content, this.pendingSchedule.remindTime, this.currentConversationId)
      this.scheduleList = [savedSchedule, ...this.scheduleList]
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

  /** 进入编辑模式时，将当前日程回填到表单和滚轮选择器。 */
  private startEditSchedule(schedule: ScheduleRecord): void {
    const form: ScheduleFormState = this.parseScheduleForm(schedule.content, schedule.remindTime)
    this.editingScheduleId = schedule.id
    this.editScheduleDetail = form.detail
    this.editScheduleDate = form.date.length > 0 ? form.date : this.getTodayDateString()
    this.editScheduleTime = form.time.length > 0 ? form.time : this.getDefaultTimeString()
    this.editScheduleLocation = form.location
  }

  private cancelEditSchedule(): void {
    this.editingScheduleId = 0
    this.editScheduleDetail = ''
    this.editScheduleDate = ''
    this.editScheduleTime = ''
    this.editScheduleLocation = ''
  }

  /** 保存编辑后的日程，并同步更新页面内缓存列表。 */
  private async saveEditedSchedule(scheduleId: number): Promise<void> {
    const detail: string = this.editScheduleDetail.trim()
    if (detail.length === 0) {
      await this.addMessage('日程详情不能为空。', false)
      return
    }

    const remindTime: string | undefined = this.buildRemindTime(this.editScheduleDate, this.editScheduleTime)
    const content: string = this.buildStructuredScheduleContent(detail, remindTime, this.editScheduleLocation)
    const success: boolean = await this.dbManager.updateSchedule(scheduleId, content, remindTime)
    if (!success) {
      await this.addMessage('更新日程失败，请稍后重试。', false)
      return
    }

    // 保存后重新从数据库读取一次，避免列表里残留旧对象导致界面仍显示初始内容。
    await this.loadSchedules()
    this.cancelEditSchedule()
    await this.addMessage('已更新该日程详情。', false)
  }

  private async deleteSchedule(scheduleId: number): Promise<void> {
    const success: boolean = await this.dbManager.deleteSchedule(scheduleId)
    if (!success) {
      await this.addMessage('删除日程失败，请稍后重试。', false)
      return
    }

    this.scheduleList = this.scheduleList.filter((item: ScheduleRecord): boolean => item.id !== scheduleId)
    if (this.editingScheduleId === scheduleId) {
      this.cancelEditSchedule()
    }
    await this.addMessage('已删除该日程。', false)
  }

  /** 日程完成只更新状态，不改动原始内容，便于之后回看历史。 */
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
          conversationId: item.conversationId,
          content: item.content,
          createdTime: item.createdTime,
          remindTime: item.remindTime,
          isDone: true
        }
      }
      return item
    })
    await this.addMessage('已将该日程标记为完成。', false)
  }

  private async handleLogout(): Promise<void> {
    await this.dbManager.logout()
    router.replaceUrl({ url: 'pages/Login' })
  }

  private goToSessionSelect(): void {
    router.pushUrl({ url: 'pages/SessionSelect' })
  }

  @Builder
  private HeaderBuilder(): void {
    Column({ space: 6 }) {
      Text(this.currentConversationTitle)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text('聊天、日程与学习建议汇总在当前会话中')
        .fontSize(12)
        .fontColor('rgba(255,255,255,0.82)')

      Row({ space: 8 }) {
        Text(this.currentUsername.length > 0 ? `当前用户：${this.currentUsername}` : '未登录')
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.78)')

        Text('切换会话')
          .fontSize(11)
          .fontColor('#163B2E')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor('#D8F3DC')
          .borderRadius(10)
          .onClick(() => this.goToSessionSelect())
      }

      if (this.lastSecurityHint.length > 0) {
        Text(`最近一次拦截：${this.lastSecurityHint}`)
          .fontSize(10)
          .fontColor('#FEF08A')
          .maxLines(1)
      }
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 20, bottom: 18 })
    .alignItems(HorizontalAlign.Start)
    .linearGradient({ direction: GradientDirection.Right, colors: [['#163B2E', 0], ['#2D6A4F', 0.55], ['#4A8F70', 1]] })
  }

  @Builder
  /** 顶部统计区支持折叠，优先给聊天内容让出屏幕空间。 */
  private OverviewBuilder(): void {
    Column({ space: 10 }) {
      Row() {
        Text('会话概览')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Blank()
        Text(this.showOverviewSection ? '收起' : '展开')
          .fontSize(12)
          .fontColor('#2D6A4F')
      }
      .width('100%')
      .onClick((): void => {
        this.showOverviewSection = !this.showOverviewSection
      })

      if (this.showOverviewSection) {
        Row() {
          Column({ space: 6 }) {
            Text('聊天记录')
              .fontSize(12)
              .fontColor('#64748B')
            Text(`${this.messageList.length}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
          }
          .width('31%')
          .padding(14)
          .backgroundColor('#EFF6FF')
          .borderRadius(16)

          Column({ space: 6 }) {
            Text('日程安排')
              .fontSize(12)
              .fontColor('#64748B')
            Text(`${this.getPendingScheduleCount()}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
          }
          .width('31%')
          .padding(14)
          .backgroundColor('#FFF7ED')
          .borderRadius(16)

          Column({ space: 6 }) {
            Text('已完成')
              .fontSize(12)
              .fontColor('#64748B')
            Text(`${this.getCompletedScheduleCount()}`)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor('#0F172A')
          }
          .width('31%')
          .padding(14)
          .backgroundColor('#ECFDF5')
          .borderRadius(16)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
    }
    .width('100%')
    .padding(14)
    .margin({ left: 12, right: 12, top: 12, bottom: 6 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  /** 日程面板同样支持折叠，避免上半区长期占用过多高度。 */
  private SchedulePanelBuilder(): void {
    Column({ space: 10 }) {
      Row() {
        Text('当前会话日程')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Blank()
        Text(this.showScheduleSection ? `收起 · ${this.scheduleList.length} 条` : `展开 · ${this.scheduleList.length} 条`)
          .fontSize(12)
          .fontColor('#2D6A4F')
      }
      .width('100%')
      .onClick((): void => {
        this.showScheduleSection = !this.showScheduleSection
      })

      if (!this.showScheduleSection) {
        Text('点击展开查看、编辑和完成当前会话日程。')
          .fontSize(13)
          .fontColor('#94A3B8')
          .width('100%')
      } else if (this.scheduleList.length === 0) {
        Text('还没有保存的日程，试试发送“帮我安排明天下午3点开会”。')
          .fontSize(13)
          .fontColor('#94A3B8')
          .width('100%')
      } else {
        List({ space: 8 }) {
          ForEach(this.scheduleList, (item: ScheduleRecord): void => {
            ListItem() {
              Column({ space: 10 }) {
                if (this.editingScheduleId === item.id) {
                  // 编辑时采用“文本 + 滚动选择”的组合，兼顾自然输入和时间选择效率。
                  Column({ space: 8 }) {
                    Text('详情')
                      .fontSize(12)
                      .fontColor('#64748B')
                      .width('100%')

                    TextInput({ placeholder: '详情，例如 去上海出差', text: this.editScheduleDetail })
                      .width('100%')
                      .height(42)
                      .backgroundColor('#FFFFFF')
                      .borderRadius(10)
                      .padding({ left: 12, right: 12 })
                      .onChange((value: string): void => {
                        this.editScheduleDetail = value
                      })

                    Row({ space: 8 }) {
                      Column({ space: 6 }) {
                        Text('日期')
                          .fontSize(12)
                          .fontColor('#64748B')
                          .width('100%')

                        TextPicker({ range: this.getDatePickerOptions(), selected: this.getDatePickerIndex() })
                          .canLoop(false)
                          .backgroundColor('#FFFFFF')
                          .borderRadius(10)
                          .height(132)
                          .width('100%')
                          .onChange((value, index): void => {
                            const selectedValue: string = typeof value === 'string' ? value : value[0]
                            this.editScheduleDate = this.extractDateFromOption(selectedValue)
                          })
                      }
                        .layoutWeight(1)

                      Column({ space: 6 }) {
                        Text('时间')
                          .fontSize(12)
                          .fontColor('#64748B')
                          .width('100%')

                        TextPicker({ range: this.getTimePickerOptions(), selected: this.getTimePickerIndex() })
                          .canLoop(true)
                          .backgroundColor('#FFFFFF')
                          .borderRadius(10)
                          .height(132)
                          .width('100%')
                          .onChange((value, index): void => {
                            const selectedValue: string = typeof value === 'string' ? value : value[0]
                            this.editScheduleTime = selectedValue
                          })
                      }
                        .layoutWeight(1)
                    }
                    .width('100%')

                    Text('地点')
                      .fontSize(12)
                      .fontColor('#64748B')
                      .width('100%')

                    TextInput({ placeholder: '地点，例如 上海', text: this.editScheduleLocation })
                      .width('100%')
                      .height(42)
                      .backgroundColor('#FFFFFF')
                      .borderRadius(10)
                      .padding({ left: 12, right: 12 })
                      .onChange((value: string): void => {
                        this.editScheduleLocation = value
                      })

                    Row({ space: 8 }) {
                      Button('取消')
                        .layoutWeight(1)
                        .height(34)
                        .backgroundColor('#E2E8F0')
                        .fontColor('#334155')
                        .borderRadius(10)
                        .onClick((): void => { this.cancelEditSchedule() })

                      Button('保存')
                        .layoutWeight(1)
                        .height(34)
                        .backgroundColor('#2563EB')
                        .fontColor('#FFFFFF')
                        .borderRadius(10)
                        .onClick((): void => { this.saveEditedSchedule(item.id) })
                    }
                    .width('100%')
                  }
                } else {
                  Row() {
                    Column({ space: 6 }) {
                      Text(item.content)
                        .fontSize(14)
                        .lineHeight(22)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(item.isDone ? '#94A3B8' : '#0F172A')
                        .decoration({ type: item.isDone ? TextDecorationType.LineThrough : TextDecorationType.None })
                      Text(this.formatDateTime(item.remindTime ?? item.createdTime))
                        .fontSize(11)
                        .fontColor('#94A3B8')
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Column({ space: 8 }) {
                      if (!item.isDone) {
                        Button('编辑')
                          .height(32)
                          .backgroundColor('#E0F2FE')
                          .fontColor('#0369A1')
                          .borderRadius(10)
                          .onClick((): void => { this.startEditSchedule(item) })

                        Button('删除')
                          .height(32)
                          .backgroundColor('#FEE2E2')
                          .fontColor('#B91C1C')
                          .borderRadius(10)
                          .onClick((): void => { this.deleteSchedule(item.id) })

                        Button('完成')
                          .height(32)
                          .backgroundColor('#2D6A4F')
                          .fontColor('#FFFFFF')
                          .borderRadius(10)
                          .onClick((): void => { this.markScheduleDone(item.id) })
                      } else {
                        Text('已完成')
                          .fontSize(12)
                          .fontColor('#10B981')
                          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                          .backgroundColor('#ECFDF5')
                          .borderRadius(10)
                      }
                    }
                    .alignItems(HorizontalAlign.End)
                  }
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#F8FAFC')
              .borderRadius(14)
            }
          }, (item: ScheduleRecord): string => `${item.id}-${item.isDone ? 'done' : 'todo'}-${item.remindTime ?? ''}-${item.content}`)
        }
        .width('100%')
        .height(this.editingScheduleId > 0 ? 320 : 190)
      }
    }
    .width('100%')
    .padding(14)
    .margin({ left: 12, right: 12, top: 6, bottom: 8 })
    .backgroundColor('#FFFFFF')
    .borderRadius(18)
  }

  @Builder
  /** 聊天区始终占据剩余空间，保证长对话时滚动区域足够大。 */
  private ChatPanelBuilder(): void {
    Column() {
      Row() {
        Text('对话内容')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
        Blank()
        if (this.isLoading) {
          Row({ space: 6 }) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color('#2D6A4F')
            Text('AI 正在思考')
              .fontSize(11)
              .fontColor('#64748B')
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 14, bottom: 8 })

      List({ scroller: this.listScroller, space: 2 }) {
        ForEach(this.messageList, (item: ChatMessage): void => {
          ListItem() {
            Row() {
              if (!item.isUser) {
                Text('AI')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .width(34)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#3B82F6')
                  .borderRadius(17)
              }

              Column() {
                Text(item.content)
                  .fontSize(15)
                  .lineHeight(22)
                  .fontColor(item.isUser ? '#FFFFFF' : '#1E293B')
                  .padding(12)
                  .backgroundColor(item.isUser ? '#2D6A4F' : '#FFFFFF')
                  .borderRadius(14)
                  .constraintSize({ maxWidth: '78%' })
                Text(item.timestamp)
                  .fontSize(10)
                  .fontColor('#94A3B8')
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              .alignItems(item.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
              .margin(item.isUser ? { right: 10 } : { left: 10 })

              if (item.isUser) {
                Text('我')
                  .fontSize(12)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#FFFFFF')
                  .width(34)
                  .height(34)
                  .textAlign(TextAlign.Center)
                  .backgroundColor('#10B981')
                  .borderRadius(17)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .justifyContent(item.isUser ? FlexAlign.End : FlexAlign.Start)
            .alignItems(VerticalAlign.Top)
          }
        }, (item: ChatMessage): string => `${item.id}-${item.timestamp}`)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor('#F8FAFC')
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  private NotifyTabBuilder(): void {
    Column({ space: 12 }) {
      Text('通知与提醒')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
        .width('100%')

      Text(`你当前会话还有 ${this.getPendingScheduleCount()} 条待完成日程。`)
        .fontSize(14)
        .fontColor('#334155')
        .width('100%')

      Text(`已经完成 ${this.getCompletedScheduleCount()} 条日程。`)
        .fontSize(14)
        .fontColor('#334155')
        .width('100%')

      Text(this.scheduleList.length > 0 ? '点击底部“对话”可继续查看完整日程列表。' : '当前会话还没有提醒事项。')
        .fontSize(13)
        .fontColor('#64748B')
        .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .padding(18)
  }

  @Builder
  private MineTabBuilder(): void {
    Column({ space: 14 }) {
      Text('我的')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0F172A')
        .width('100%')

      Text(`用户名：${this.currentUsername}`)
        .fontSize(14)
        .fontColor('#334155')
        .width('100%')

      Text(`当前会话：${this.currentConversationTitle}`)
        .fontSize(14)
        .fontColor('#334155')
        .width('100%')

      Button('切换或新建会话')
        .width('100%')
        .height(44)
        .backgroundColor('#E2E8F0')
        .fontColor('#0F172A')
        .borderRadius(14)
        .onClick(() => this.goToSessionSelect())

      Button('退出登录')
        .width('100%')
        .height(44)
        .backgroundColor('#FEE2E2')
        .fontColor('#991B1B')
        .borderRadius(14)
        .onClick(() => this.handleLogout())
    }
    .layoutWeight(1)
    .width('100%')
    .padding(18)
  }

  @Builder
  private InputBuilder(): void {
    Row({ space: 10 }) {
      TextInput({ placeholder: '输入消息，例如：帮我安排明天下午3点开会', text: $$this.inputText })
        .layoutWeight(1)
        .height(46)
        .fontSize(14)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .padding({ left: 12, right: 12 })
        .onSubmit(() => this.sendMessage())

      Button('发送')
        .width(72)
        .height(46)
        .backgroundColor(this.isLoading || this.isInitializing || this.inputText.trim().length === 0 ? '#9FB7A8' : '#2D6A4F')
        .fontColor('#FFFFFF')
        .borderRadius(12)
        .enabled(!this.isLoading && !this.isInitializing && this.inputText.trim().length > 0)
        .onClick(() => this.sendMessage())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private BottomNavBuilder(): void {
    Row() {
      this.BottomNavItemBuilder('dialog', '对话')
      this.BottomNavItemBuilder('notify', '通知')
      this.BottomNavItemBuilder('mine', '我的')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 12 })
    .backgroundColor('#FFFFFF')
  }

  @Builder
  private BottomNavItemBuilder(tabKey: string, title: string): void {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(13)
        .fontWeight(this.currentTab === tabKey ? FontWeight.Bold : FontWeight.Regular)
        .fontColor(this.currentTab === tabKey ? '#2D6A4F' : '#94A3B8')
      Row()
        .width(18)
        .height(3)
        .backgroundColor(this.currentTab === tabKey ? '#2D6A4F' : '#FFFFFF')
        .borderRadius(2)
    }
    .layoutWeight(1)
    .padding({ top: 4, bottom: 4 })
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.currentTab = tabKey
    })
  }

  build(): void {
    Stack() {
      Column() {
        this.HeaderBuilder()

        if (this.currentTab === 'dialog') {
          this.OverviewBuilder()
          this.SchedulePanelBuilder()
          this.ChatPanelBuilder()
          this.InputBuilder()
        } else if (this.currentTab === 'notify') {
          this.NotifyTabBuilder()
        } else {
          this.MineTabBuilder()
        }

        this.BottomNavBuilder()
      }
      .width('100%')
      .height('100%')
      .backgroundColor('#F1F5F9')

      ActionDialog({
        isShow: this.showActionDialog,
        title: this.dialogTitle,
        content: this.dialogContent,
        onConfirm: (): void => {
          this.onDialogConfirm()
        },
        onCancel: (): void => {
          this.onDialogCancel()
        }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F1F5F9')
  }
}



















