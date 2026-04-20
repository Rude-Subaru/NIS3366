import common from '@ohos.app.ability.common'
import { DatabaseManager } from '../database/DatabaseManager'
import { router } from '@kit.ArkUI'

/**
 * 登录/注册页。
 * 这里只负责账号进入，不承载具体业务；登录成功后统一跳转到会话中心。
 */
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

  /** 若本地已有登录态，则直接跳过登录页。 */
  async aboutToAppear(): Promise<void> {
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext
    this.dbManager.setContext(abilityContext)
    await this.dbManager.initDB()

    const loggedIn: boolean = await this.dbManager.isLoggedIn()
    if (loggedIn) {
      router.replaceUrl({ url: 'pages/SessionSelect' })
    }
  }

  /** 离开页面时关闭数据库连接。 */
  async aboutToDisappear(): Promise<void> {
    await this.dbManager.closeDB()
  }

  /** 页面内的基础输入校验，避免无效请求直接进入数据库层。 */
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

  /** 登录成功后进入会话中心，而不是直接进入某个具体业务页。 */
  async handleLogin(): Promise<void> {
    if (!this.validateInput()) {
      return
    }

    this.isLoading = true
    const result = await this.dbManager.loginUser(this.username.trim(), this.password)
    this.isLoading = false

    if (result.success) {
      router.replaceUrl({ url: 'pages/SessionSelect' })
    } else {
      this.errorMessage = result.message
    }
  }

  /** 注册成功后会立即尝试登录，减少一次重复输入。 */
  async handleRegister(): Promise<void> {
    if (!this.validateInput()) {
      return
    }

    this.isLoading = true
    const result = await this.dbManager.registerUser(this.username.trim(), this.password)
    this.isLoading = false

    if (!result.success) {
      this.errorMessage = result.message
      return
    }

    const loginResult = await this.dbManager.loginUser(this.username.trim(), this.password)
    if (loginResult.success) {
      router.replaceUrl({ url: 'pages/SessionSelect' })
    } else {
      this.isRegisterMode = false
      this.errorMessage = '注册成功，请重新登录。'
    }
  }

  /** 在登录和注册模式之间切换。 */
  private toggleMode(): void {
    this.isRegisterMode = !this.isRegisterMode
    this.errorMessage = ''
    this.confirmPassword = ''
  }

  build(): void {
    Column({ space: 0 }) {
      Column({ space: 8 }) {
        Text('AI 秘书')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text('登录后先选择会话，再进入不同功能场景')
          .fontSize(13)
          .fontColor('rgba(255,255,255,0.82)')
      }
      .width('100%')
      .padding({ top: 64, bottom: 42 })
      .alignItems(HorizontalAlign.Center)
      .linearGradient({
        direction: GradientDirection.Bottom,
        colors: [['#163B2E', 0], ['#2D6A4F', 0.65], ['#4A8F70', 1]]
      })

      Column({ space: 18 }) {
        Text(this.isRegisterMode ? '创建账号' : '欢迎回来')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#0F172A')
          .margin({ top: 26, bottom: 8 })

        Column({ space: 6 }) {
          Text('用户名')
            .fontSize(13)
            .fontColor('#64748B')
            .width('100%')
          TextInput({ placeholder: '请输入用户名', text: $$this.username })
            .width('100%')
            .height(48)
            .fontSize(14)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
        }
        .width('100%')

        Column({ space: 6 }) {
          Text('密码')
            .fontSize(13)
            .fontColor('#64748B')
            .width('100%')
          TextInput({ placeholder: '请输入密码', text: $$this.password })
            .width('100%')
            .height(48)
            .fontSize(14)
            .type(InputType.Password)
            .backgroundColor('#F8FAFC')
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
        }
        .width('100%')

        if (this.isRegisterMode) {
          Column({ space: 6 }) {
            Text('确认密码')
              .fontSize(13)
              .fontColor('#64748B')
              .width('100%')
            TextInput({ placeholder: '请再次输入密码', text: $$this.confirmPassword })
              .width('100%')
              .height(48)
              .fontSize(14)
              .type(InputType.Password)
              .backgroundColor('#F8FAFC')
              .borderRadius(12)
              .padding({ left: 14, right: 14 })
          }
          .width('100%')
        }

        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .width('100%')
            .fontSize(12)
            .fontColor('#DC2626')
        }

        Button(this.isRegisterMode ? '注册并进入会话中心' : '登录并进入会话中心')
          .width('100%')
          .height(48)
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

        if (this.isLoading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color('#2D6A4F')
        }

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
