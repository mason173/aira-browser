import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';

@Reusable
@Component
export struct SiteControlsWebsiteRecordRow {
  @Prop rowId: string = '';
  @Prop title: string = '';
  @Prop host: string = '';
  @Prop origin: string = '';
  @Prop iconUri: string = '';
  @Prop pressed: boolean = false;
  @Prop rowHeight: number = 58;
  @Prop showDivider: boolean = false;
  @Prop rowBorderRadius: number | BorderRadiuses = 18;
  @Prop iconCornerRadiusRatio: number = 0.3;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop pressedBackgroundColor: ResourceColor | undefined = undefined;

  onTouchAction: (type: TouchType) => void = (_type: TouchType) => {};
  onRowClick: () => void = () => {};

  @BuilderParam trailing: () => void = this.emptyBuilder;

  aboutToReuse(params: Record<string, Object>): void {
    this.rowId = params.rowId as string;
    this.title = params.title as string;
    this.host = params.host as string;
    this.origin = params.origin as string;
    this.iconUri = params.iconUri as string;
    this.pressed = params.pressed as boolean;
    this.rowHeight = params.rowHeight as number;
    this.showDivider = params.showDivider as boolean;
    this.rowBorderRadius = params.rowBorderRadius as number | BorderRadiuses;
    this.iconCornerRadiusRatio = params.iconCornerRadiusRatio as number;
    this.primaryTextColor = params.primaryTextColor as ResourceColor | undefined;
    this.secondaryTextColor = params.secondaryTextColor as ResourceColor | undefined;
    this.pressedBackgroundColor = params.pressedBackgroundColor as ResourceColor | undefined;
    this.onTouchAction = params.onTouchAction as (type: TouchType) => void;
    this.onRowClick = params.onRowClick as () => void;
  }

  build() {
    WebsiteRecordRow({
      iconUri: this.iconUri,
      fallbackLabel: resolveSiteIconFallbackLabel(this.title, this.host),
      title: this.title,
      subtitle: '',
      rowHeight: this.rowHeight,
      rowBorderRadius: this.rowBorderRadius,
      pressed: this.pressed,
      iconCornerRadiusRatio: this.iconCornerRadiusRatio,
      primaryTextColor: this.primaryTextColor,
      secondaryTextColor: this.secondaryTextColor,
      pressedBackgroundColor: this.pressedBackgroundColor,
      showDivider: this.showDivider,
      onTouchAction: (type: TouchType) => {
        this.onTouchAction(type);
      },
      onRowClick: () => {
        this.onRowClick();
      },
      trailing: () => {
        this.trailing()
      }
    })
  }

  @Builder
  private emptyBuilder() {
  }
}
