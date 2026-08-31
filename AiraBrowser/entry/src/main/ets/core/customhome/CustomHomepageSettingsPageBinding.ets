export type CustomHomepageSettingsBackHandler = () => boolean;
export type CustomHomepageSettingsPageShowHandler = () => void;

/** Forwards page lifecycle signals into the reusable standalone/embedded settings screen. */
export class CustomHomepageSettingsPageBinding {
  private backHandler?: CustomHomepageSettingsBackHandler;
  private pageShowHandler?: CustomHomepageSettingsPageShowHandler;

  attach(
    backHandler: CustomHomepageSettingsBackHandler,
    pageShowHandler: CustomHomepageSettingsPageShowHandler
  ): void {
    this.backHandler = backHandler;
    this.pageShowHandler = pageShowHandler;
  }

  detach(): void {
    this.backHandler = undefined;
    this.pageShowHandler = undefined;
  }

  dispatchBack(): boolean {
    return this.backHandler?.() ?? false;
  }

  notifyPageShow(): void {
    this.pageShowHandler?.();
  }
}
