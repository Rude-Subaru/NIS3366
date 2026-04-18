import common from '@ohos.app.ability.common'
import { DatabaseManager } from '../database/DatabaseManager'
import { router } from '@kit.ArkUI'

@Entry
@Component
struct Login {
  @State private username: string = ''
  @State private password: string = ''
  @State private isRegisterMode: boolean = false
  @State private confirmPassword: string = ''
  @State private isLoading: boolean = false
  @State private errorMessage: string = ''

  private readonly dbManager: DatabaseManager = new DatabaseManager()

  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)
    await this.dbManager.initDB()

    // 如果已登录，直接跳转到首页
    const loggedIn: boolean = await this.dbManager.isLoggedIn()
    if (loggedIn) {
      router.replaceUrl({ url: 'pages/Index' })
    }
  }

  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  private validateInput(): boolean {
    if (this.username.trim().length === 0) {
      this.errorMessage = '请输入用户名'
      return false
    }
    if (this.password.length === 0) {
      this.errorMessage = '请输入密码'
      return false
    }
    if (this.isRegisterMode && this.password !== this.confirmPassword) {
      this.errorMessage = '两次输入的密码不一致'
      return false
    }
    if (this.isRegisterMode && this.password.length < 4) {
      this.errorMessage = '密码长度至少为4位'
      return false
    }
    this.errorMessage = ''
    return true
  }

  async handleLogin(): Promise<void> {
    if (!this.validateInput()) {
      return
    }

    this.isLoading = true
    const result = await this.dbManager.loginUser(this.username.trim(), this.password)
    this.isLoading = false

    if (result.success) {
      router.replaceUrl({ url: 'pages/Index' })
    } else {
      this.errorMessage = result.message
    }
  }

  async handleRegister(): Promise<void> {
    if (!this.validateInput()) {
      return
    }

    this.isLoading = true
    const result = await this.dbManager.registerUser(this.username.trim(), this.password)
    this.isLoading = false

    if (result.success) {
      this.errorMessage = ''
      // 注册成功后自动登录
      const loginResult = await this.dbManager.loginUser(this.username.trim(), this.password)
      if (loginResult.success) {
        router.replaceUrl({ url: 'pages/Index' })
      } else {
        this.isRegisterMode = false
        this.errorMessage = '注册成功，请登录'
      }
    } else {
      this.errorMessage = result.message
    }
  }

  private toggleMode(): void {
    this.isRegisterMode = !this.isRegisterMode
    this.errorMessage = ''
    this.confirmPassword = ''
  }

  build() {
    Column({ space: 0 }) {
      // 顶部装饰区域
      Column({ space: 8 }) {
        Text('✦')
          .fontSize(24)
          .fontColor('rgba(255,255,255,0.6)')
        Text('AI 秘书')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text('你的智能生活助手')
          .fontSize(14)
          .fontColor('rgba(255,255,255,0.8)')
      }
      .width('100%')
      .padding({ top: 60, bottom: 40 })
      .alignItems(HorizontalAlign.Center)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [['#1B4332', 0], ['#2D6A4F', 1]]
      })

      // 表单区域
      Column({ space: 20 }) {
        Text(this.isRegisterMode ? '注册账号' : '欢迎回来')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1E293B')
          .margin({ top: 30, bottom: 10 })

        // 用户名输入
        Column({ space: 6 }) {
          Text('用户名')
            .fontSize(13)
            .fontColor('#64748B')
            .alignSelf(ItemAlign.Start)
          TextInput({ placeholder: '请输入用户名', text: $$this.username })
            .width('100%')
            .height(48)
            .fontSize(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .placeholderColor('#CBD5E1')
        }
        .width('100%')

        // 密码输入
        Column({ space: 6 }) {
          Text('密码')
            .fontSize(13)
            .fontColor('#64748B')
            .alignSelf(ItemAlign.Start)
          TextInput({ placeholder: '请输入密码', text: $$this.password })
            .width('100%')
            .height(48)
            .fontSize(14)
            .type(InputType.Password)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .placeholderColor('#CBD5E1')
        }
        .width('100%')

        // 确认密码（仅注册时显示）
        if (this.isRegisterMode) {
          Column({ space: 6 }) {
            Text('确认密码')
              .fontSize(13)
              .fontColor('#64748B')
              .alignSelf(ItemAlign.Start)
            TextInput({ placeholder: '请再次输入密码', text: $$this.confirmPassword })
              .width('100%')
              .height(48)
              .fontSize(14)
              .type(InputType.Password)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .padding({ left: 14, right: 14 })
              .placeholderColor('#CBD5E1')
          }
          .width('100%')
        }

        // 错误提示
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#EF4444')
            .width('100%')
            .textAlign(TextAlign.Start)
        }

        // 提交按钮
        Button(this.isRegisterMode ? '注册' : '登录')
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .backgroundColor('#2D6A4F')
          .fontColor('#FFFFFF')
          .borderRadius(12)
          .enabled(!this.isLoading)
          .onClick(() => {
            if (this.isRegisterMode) {
              this.handleRegister()
            } else {
              this.handleLogin()
            }
          })

        // 加载指示器
        if (this.isLoading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#2D6A4F')
        }

        // 切换模式
        Row({ space: 4 }) {
          Text(this.isRegisterMode ? '已有账号？' : '还没有账号？')
            .fontSize(13)
            .fontColor('#94A3B8')
          Text(this.isRegisterMode ? '去登录' : '去注册')
            .fontSize(13)
            .fontColor('#2D6A4F')
            .fontWeight(FontWeight.Medium)
            .onClick(() => this.toggleMode())
        }
        .margin({ top: 10 })
      }
      .width('100%')
      .padding({ left: 28, right: 28 })
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
