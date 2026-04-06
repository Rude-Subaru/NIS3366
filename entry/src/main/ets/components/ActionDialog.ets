/**
 * 执行确认弹窗组件
 * 负责：组长（UI）
 * 功能：显示操作确认弹窗，用户确认后才执行写操作
 */

@Component
export struct ActionDialog {
  @Prop isShow: boolean
  @Prop title: string
  @Prop content: string
  onConfirm: () => void = () => {}
  onCancel: () => void = () => {}

  build() {
    Column() {
      if (this.isShow) {
        // 遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .position({ x: 0, y: 0 })
          .onClick(() => this.onCancel())

        // 弹窗内容
        Column() {
          // 标题
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333')
            .margin({ top: 20, bottom: 16 })

          // 内容
          Text(this.content)
            .fontSize(15)
            .fontColor('#666')
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .constraintSize({ maxWidth: '80%' })
            .margin({ bottom: 20 })

          // 分隔线
          Divider()
            .strokeWidth(0.5)
            .color('#E5E5E5')
            .width('100%')

          // 按钮区
          Row() {
            // 取消按钮
            Button('拒绝')
              .fontSize(16)
              .fontColor('#999')
              .backgroundColor('transparent')
              .layoutWeight(1)
              .onClick(() => this.onCancel())

            // 分隔线
            Divider()
              .vertical(true)
              .strokeWidth(0.5)
              .color('#E5E5E5')
              .height(40)

            // 确认按钮
            Button('同意执行')
              .fontSize(16)
              .fontColor('#07C160')
              .fontWeight(FontWeight.Bold)
              .backgroundColor('transparent')
              .layoutWeight(1)
              .onClick(() => this.onConfirm())
          }
          .width('100%')
          .height(50)
        }
        .width('80%')
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.2)' })
        .position({ x: '10%', y: '35%' })
      }
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .pointerEvents(this.isShow ? PointerEvents.Auto : PointerEvents.None)
  }
}
