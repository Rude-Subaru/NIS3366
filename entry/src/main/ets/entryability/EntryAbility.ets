import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { DatabaseManager } from '../database/DatabaseManager';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    console.info('[EntryAbility] onCreate');
  }

  onDestroy(): void {
    console.info('[EntryAbility] onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    console.info('[EntryAbility] onWindowStageCreate');

    // 检查登录状态，决定加载哪个页面
    const dbManager = new DatabaseManager();
    dbManager.setContext(this.context);
    await dbManager.initDB();
    const isLoggedIn = await dbManager.isLoggedIn();
    await dbManager.closeDB();

    const targetPage = isLoggedIn ? 'pages/Index' : 'pages/Login';

    windowStage.loadContent(targetPage, (err) => {
      if (err.code) {
        console.error('[EntryAbility] Failed to load content');
        return;
      }
      console.info('[EntryAbility] load content succeed');
    });
  }

  onWindowStageDestroy(): void {
    console.info('[EntryAbility] onWindowStageDestroy');
  }

  onForeground(): void {
    console.info('[EntryAbility] onForeground');
  }

  onBackground(): void {
    console.info('[EntryAbility] onBackground');
  }
}
