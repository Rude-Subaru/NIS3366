import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { DatabaseManager } from '../database/DatabaseManager'

/**
 * 应用入口 Ability。
 * 负责启动期判断登录态，决定首屏加载登录页还是会话中心。
 */
export default class EntryAbility extends UIAbility {
  /** 应用创建时触发。 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[EntryAbility] onCreate')
  }

  /** 应用销毁时触发，用于释放资源。 */
  onDestroy(): void {
    console.info('[EntryAbility] onDestroy')
  }

  /**
   * 窗口阶段创建时触发。
   * 先初始化数据库，再根据本地登录态决定首屏页面，
   * 避免页面自己来回跳转。
   */
  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    const dbManager = new DatabaseManager()
    dbManager.setContext(this.context)
    await dbManager.initDB()

    const isLoggedIn: boolean = await dbManager.isLoggedIn()
    await dbManager.closeDB()

    const targetPage: string = isLoggedIn ? 'pages/SessionSelect' : 'pages/Login'
    windowStage.loadContent(targetPage, (err) => {
      if (err.code) {
        console.error('[EntryAbility] Failed to load content')
        return
      }
      console.info('[EntryAbility] load content succeed')
    })
  }

  /** 窗口阶段销毁时触发。 */
  onWindowStageDestroy(): void {
    console.info('[EntryAbility] onWindowStageDestroy')
  }

  /** 应用进入前台时触发。 */
  onForeground(): void {
    console.info('[EntryAbility] onForeground')
  }

  /** 应用退到后台时触发。 */
  onBackground(): void {
    console.info('[EntryAbility] onBackground')
  }
}
