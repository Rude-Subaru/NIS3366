import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit'
import { window } from '@kit.ArkUI'
import { DatabaseManager } from '../database/DatabaseManager'

/**
 * 应用入口 Ability。
 * 这里只负责启动期判断登录态，并决定首屏加载登录页还是会话中心。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[EntryAbility] onCreate')
  }

  onDestroy(): void {
    console.info('[EntryAbility] onDestroy')
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    const dbManager = new DatabaseManager()
    dbManager.setContext(this.context)
    await dbManager.initDB()

    // 启动时先根据本地登录态决定首屏，避免页面自己来回跳转。
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

  onWindowStageDestroy(): void {
    console.info('[EntryAbility] onWindowStageDestroy')
  }

  onForeground(): void {
    console.info('[EntryAbility] onForeground')
  }

  onBackground(): void {
    console.info('[EntryAbility] onBackground')
  }
}
