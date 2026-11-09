import { ComponentContent, UIContext } from '@kit.ArkUI'
import { kitappPurchaseConsentBuilder } from './KitappPurchaseConsentDialog'
import {
  KitappPurchaseConsentModel, KitappPurchaseConsentOptions, KitappPurchaseConsentResult
} from './KitappPurchaseConsentModel'

/** Keeps dialog lifetime and result separate from the host's payment/session lock. */
export class KitappPurchaseConsentRequest {
  readonly result: Promise<KitappPurchaseConsentResult>
  private model: KitappPurchaseConsentModel
  private content: ComponentContent<KitappPurchaseConsentModel>

  constructor(ui: UIContext, options: KitappPurchaseConsentOptions) {
    let resolveDecision: (result: KitappPurchaseConsentResult) => void = (): void => {}
    const decision = new Promise<KitappPurchaseConsentResult>((resolve) => { resolveDecision = resolve })
    this.model = new KitappPurchaseConsentModel(options, (result: KitappPurchaseConsentResult): void => {
      resolveDecision(result)
    })
    this.content = new ComponentContent(ui, wrapBuilder(kitappPurchaseConsentBuilder), this.model)
    this.result = this.show(ui, decision)
  }

  cancel(): void { this.model.cancel() }

  private async show(ui: UIContext, decision: Promise<KitappPurchaseConsentResult>): Promise<KitappPurchaseConsentResult> {
    try {
      await ui.getPromptAction().openCustomDialog(this.content, {
        alignment: DialogAlignment.Center,
        autoCancel: true,
        onWillDismiss: (action: DismissDialogAction): void => {
          this.model.cancel()
          action.dismiss()
        }
      })
      const result = await decision
      try { await ui.getPromptAction().closeCustomDialog(this.content) }
      catch (_) { return { accepted: false } }
      return result.accepted && !this.model.isCurrent() ? { accepted: false } : result
    } catch (_) {
      this.model.cancel()
      return { accepted: false }
    } finally {
      this.content.dispose()
    }
  }
}
