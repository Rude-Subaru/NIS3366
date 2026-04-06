/**
 * AI秘书 - 主聊天页面
 * 负责：组长（UI与主逻辑）
 * 功能：美观的聊天界面、消息管理、调用各模块
 */

import { LLMService } from '../utils/LLMService'
import { DatabaseManager } from '../database/DatabaseManager'
import { ReadExecutor } from '../executors/ReadExecutor'
import { WriteExecutor } from '../executors/WriteExecutor'
import { SecurityChecker } from '../security/SecurityChecker'
import { ActionDialog } from '../components/ActionDialog'

// 消息数据模型
class ChatMessage {
  id: number
  content: string
  isUser: boolean
  timestamp: string
  avatar: string

  constructor(id: number, content: string, isUser: boolean, timestamp: string) {
    this.id = id
    this.content = content
    this.isUser = isUser
    this.timestamp = timestamp
    this.avatar = isUser ? '' : 'app.media.ai_avatar'
  }
}

@Entry
@Component
struct ChatPage {
  @State messageList: ChatMessage[] = []
  @State inputText: string = ''
  @State isLoading: boolean = false
  @State showActionDialog: boolean = false
  @State dialogTitle: string = ''
  @State dialogContent: string = ''
  @State pendingAction: object = {}
  
  private listScroller: ListScroller = new ListScroller()
  private dbManager: DatabaseManager = new DatabaseManager()

  aboutToAppear() {
    // 初始化数据库
    this.dbManager.initDB()
    // 加载历史消息
    this.loadHistoryMessages()
    // 添加欢迎消息
    if (this.messageList.length === 0) {
      this.addMessage('你好！我是你的AI秘书，可以帮你管理日程、推荐学习、心理咨询。有什么可以帮你的吗？', false)
    }
  }

  // 加载历史消息
  loadHistoryMessages() {
    // TODO: 从数据库加载，目前先Mock几条
    const mockHistory = this.dbManager.getRecentMessages(5)
    this.messageList = mockHistory.map((msg: any, index: number) => {
      return new ChatMessage(index, msg.content, msg.isUser, msg.timestamp)
    })
  }

  // 添加消息到列表
  addMessage(content: string, isUser: boolean) {
    const timestamp = new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    const newMessage = new ChatMessage(this.messageList.length, content, isUser, timestamp)
    this.messageList.push(newMessage)
    
    // 保存到数据库
    this.dbManager.saveMessage(content, isUser)
    
    // 滚动到底部
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom)
    }, 100)
  }

  // 发送消息主流程
  async sendMessage() {
    if (this.inputText.trim() === '' || this.isLoading) return

    const userInput = this.inputText.trim()
    this.inputText = ''
    
    // 1. 显示用户消息
    this.addMessage(userInput, true)
    this.isLoading = true

    try {
      // 2. 读执行体：组装Prompt
      const readExecutor = new ReadExecutor(this.dbManager)
      const prompt = readExecutor.buildPrompt(userInput)
      
      // 3. 调用大模型
      const llmService = new LLMService()
      const llmResponse = await llmService.callLLM(prompt)
      
      // 4. 安全检查
      const securityChecker = new SecurityChecker()
      if (!securityChecker.isSafe(llmResponse)) {
        this.addMessage('抱歉，检测到不安全的指令，已拦截。', false)
        this.isLoading = false
        return
      }

      // 5. 写执行体：解析并执行
      const writeExecutor = new WriteExecutor()
      const actionResult = writeExecutor.parseAction(llmResponse)
      
      await this.handleActionResult(actionResult, llmResponse)
      
    } catch (error) {
      this.addMessage('抱歉，处理出错了，请稍后再试。', false)
      console.error('Error:', JSON.stringify(error))
    } finally {
      this.isLoading = false
    }
  }

  // 处理执行结果
  async handleActionResult(actionResult: any, rawResponse: string) {
    switch (actionResult.action) {
      case 'chat':
        // 普通聊天，直接回复
        this.addMessage(actionResult.reply || '收到你的消息啦~', false)
        break
        
      case 'schedule':
        // 日程管理，弹窗确认
        this.dialogTitle = '📅 添加日程确认'
        this.dialogContent = `是否添加日程：${actionResult.data || '新日程'}？`
        this.pendingAction = { type: 'schedule', data: actionResult.data }
        this.showActionDialog = true
        break
        
      case 'study':
        // 学习推荐，直接回复（可以Mock推荐内容）
        const studyRecommendations = [
          '📚 推荐你学习《数据结构与算法》，今晚8点开始',
          '📖 根据你的进度，建议复习第三章内容',
          '✏️ 为你找到一份相关练习题，要做一下吗？',
          '🎯 本周学习目标：完成Python基础课程'
        ]
        const randomRec = studyRecommendations[Math.floor(Math.random() * studyRecommendations.length)]
        this.addMessage(`${actionResult.reply}\n\n${randomRec}`, false)
        break
        
      case 'psych':
        // 心理咨询，直接回复
        this.addMessage(actionResult.reply || '我理解你的感受，想聊聊吗？', false)
        break
        
      default:
        // 未知动作，显示原始回复
        this.addMessage(actionResult.reply || '收到，我会记着的~', false)
    }
  }

  // 弹窗确认回调
  onDialogConfirm() {
    if (this.pendingAction.type === 'schedule') {
      // 保存日程到数据库
      this.dbManager.saveSchedule(this.pendingAction.data)
      this.addMessage(`✅ 已添加日程：${this.pendingAction.data}`, false)
    }
    this.showActionDialog = false
    this.pendingAction = {}
  }

  // 弹窗取消回调
  onDialogCancel() {
    this.addMessage('❌ 已取消操作', false)
    this.showActionDialog = false
    this.pendingAction = {}
  }

  build() {
    Column() {
      // 顶部标题栏
      this.HeaderBuilder()
      
      // 消息列表
      List({ scroller: this.listScroller }) {
        ForEach(this.messageList, (item: ChatMessage, index: number) => {
          ListItem() {
            this.MessageItemBuilder(item)
          }
        }, (item: ChatMessage) => item.id.toString())
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor('#F5F5F5')

      // 加载指示器
      if (this.isLoading) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color('#07C160')
          Text('AI思考中...')
            .fontSize(12)
            .fontColor('#999')
            .margin({ left: 8 })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding(8)
        .backgroundColor('#F5F5F5')
      }

      // 底部输入区
      this.InputBuilder()
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#EDEDED')

    // 执行确认弹窗
    ActionDialog({
      isShow: this.showActionDialog,
      title: this.dialogTitle,
      content: this.dialogContent,
      onConfirm: () => this.onDialogConfirm(),
      onCancel: () => this.onDialogCancel()
    })
  }

  // 顶部标题栏构建器
  @Builder
  HeaderBuilder() {
    Row() {
      Text('🤖 AI秘书')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
    }
    .width('100%')
    .height(56)
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#07C160')
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.1)', offsetY: 2 })
  }

  // 消息项构建器
  @Builder
  MessageItemBuilder(message: ChatMessage) {
    Row() {
      if (message.isUser) {
        // 用户消息：右侧显示
        Blank()
        
        Column() {
          Text(message.content)
            .fontSize(15)
            .fontColor('#000000')
            .maxLines(20)
            .constraintSize({ maxWidth: '70%' })
            .padding(12)
            .backgroundColor('#95EC69')
            .borderRadius(8)
            .shadow({ radius: 2, color: 'rgba(0,0,0,0.05)', offsetY: 1 })
          Text(message.timestamp)
            .fontSize(10)
            .fontColor('#999')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.End)
        .margin({ right: 12 })

        // 用户头像
        Column() {
          Text('我')
            .fontSize(14)
            .fontColor('#FFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(40)
        .height(40)
        .borderRadius(6)
        .backgroundColor('#07C160')
        .justifyContent(FlexAlign.Center)
        .margin({ right: 12 })
      } else {
        // AI消息：左侧显示
        // AI头像
        Column() {
          Text('AI')
            .fontSize(14)
            .fontColor('#FFF')
            .fontWeight(FontWeight.Bold)
        }
        .width(40)
        .height(40)
        .borderRadius(6)
        .backgroundColor('#576B95')
        .justifyContent(FlexAlign.Center)
        .margin({ left: 12 })

        Column() {
          Text(message.content)
            .fontSize(15)
            .fontColor('#000000')
            .maxLines(20)
            .constraintSize({ maxWidth: '70%' })
            .padding(12)
            .backgroundColor('#FFFFFF')
            .borderRadius(8)
            .shadow({ radius: 2, color: 'rgba(0,0,0,0.05)', offsetY: 1 })
          Text(message.timestamp)
            .fontSize(10)
            .fontColor('#999')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        
        Blank()
      }
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Top)
  }

  // 底部输入区构建器
  @Builder
  InputBuilder() {
    Row() {
      // 输入框
      TextInput({ placeholder: '输入消息...', text: $$this.inputText })
        .placeholderColor('#999')
        .fontSize(15)
        .height(44)
        .backgroundColor('#FFFFFF')
        .borderRadius(6)
        .padding({ left: 12, right: 12 })
        .layoutWeight(1)
        .onSubmit(() => this.sendMessage())

      // 发送按钮
      Button() {
        Image($r('app.media.send_icon'))
          .width(20)
          .height(20)
          .fillColor('#FFFFFF')
      }
      .width(44)
      .height(44)
      .margin({ left: 10 })
      .backgroundColor('#07C160')
      .borderRadius(6)
      .enabled(!this.isLoading && this.inputText.trim() !== '')
      .onClick(() => this.sendMessage())
    }
    .width('100%')
    .height(70)
    .padding({ left: 12, right: 12 })
    .backgroundColor('#F7F7F7')
    .border({ width: { top: 0.5 }, color: '#E5E5E5' })
  }
}
