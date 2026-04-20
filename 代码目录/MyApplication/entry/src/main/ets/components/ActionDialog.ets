/**
 * 执行确认弹窗。
 * 用于日程添加等需要用户二次确认的动作。
 * 回调由父页面注入，组件本身不持有任何业务状态。
 */
@Component
export struct ActionDialog {
  @Prop isShow: boolean
  @Prop title: string
  @Prop content: string

  onConfirm: () => void = () => {}
  onCancel: () => void = () => {}

  build() {
    if (this.isShow) {
      Stack({ alignContent: Alignment.Center }) {
        // 点击半透明遮罩等价于取消，符合移动端弹窗的常见交互。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.4)')
          .onClick(() => this.onCancel())
          .animation({ duration: 200, curve: Curve.EaseInOut })

        Column({ space: 18 }) {
          Text('📌')
            .fontSize(36)
            .margin({ top: 8 })

          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1E293B')

          Text(this.content)
            .fontSize(14)
            .lineHeight(22)
            .fontColor('#64748B')
            .textAlign(TextAlign.Center)
            .width('100%')

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .height(42)
              .backgroundColor('#F1F5F9')
              .fontColor('#64748B')
              .fontSize(14)
              .borderRadius(12)
              .onClick(() => this.onCancel())

            Button('确认添加')
              .layoutWeight(1)
              .height(42)
              .backgroundColor('#2D6A4F')
              .fontColor('#FFFFFF')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .borderRadius(12)
              .shadow({ radius: 6, color: 'rgba(45,106,79,0.3)', offsetX: 0, offsetY: 2 })
              .onClick(() => this.onConfirm())
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('82%')
        .padding(22)
        .backgroundColor('#FFFFFF')
        .borderRadius(20)
        .shadow({ radius: 20, color: 'rgba(0,0,0,0.15)', offsetX: 0, offsetY: 8 })
        .animation({ duration: 250, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .animation({ duration: 200, curve: Curve.EaseInOut })
    }
  }
}
