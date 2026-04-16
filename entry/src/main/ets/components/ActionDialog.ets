/**
 * 执行确认弹窗。
 * 当前用于日程添加等需要用户二次确认的动作。
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
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
          .onClick(() => this.onCancel())

        Column({ space: 16 }) {
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1F2933')

          Text(this.content)
            .fontSize(14)
            .lineHeight(21)
            .fontColor('#52606D')
            .textAlign(TextAlign.Center)

          Row() {
            Button('取消')
              .layoutWeight(1)
              .backgroundColor('#E5E7EB')
              .fontColor('#374151')
              .onClick(() => this.onCancel())

            Blank()
              .width(12)

            Button('确认')
              .layoutWeight(1)
              .backgroundColor('#2D6A4F')
              .fontColor('#FFFFFF')
              .onClick(() => this.onConfirm())
          }
        }
        .width('82%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(16)
      }
      .width('100%')
      .height('100%')
    }
  }
}
