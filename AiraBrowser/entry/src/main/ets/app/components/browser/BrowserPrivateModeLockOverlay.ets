import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BROWSER_GLOBAL_SYMBOL_WEIGHT } from './BrowserIconStyle';
import { BrowserPrivateModeLockUserAction } from '../../../core/privacy/BrowserPrivateModeLockCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';

const PRIVATE_LOCK_CONTENT_MAX_WIDTH: number = 360;
const PRIVATE_LOCK_ICON_FRAME_SIZE: number = 74;
const PRIVATE_LOCK_ACTION_WIDTH: number = 168;
const PRIVATE_LOCK_ACTION_HEIGHT: number = 44;
const PRIVATE_LOCK_SIDE_PADDING: number = 28;

@Component
export struct BrowserPrivateModeLockOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111827';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#667085';
  @Prop message: string = '';
  @Prop authenticationInProgress: boolean = false;
  @Prop zIndexValue: number = 0;
  onAction: (action: BrowserPrivateModeLockUserAction) => void =
    (_action: BrowserPrivateModeLockUserAction): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildPrivacyVeil()
      this.buildLockContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .zIndex(this.zIndexValue)
  }

  @Builder
  private buildPrivacyVeil() {
    Stack() {
      SymbolGlyph($r('sys.symbol.person_shield_fill'))
        .fontSize(188)
        .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
        .fontColor([this.storedAccentColor])
        .opacity(0.08)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .opacity(0.98)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildLockContent() {
    Column({ space: 18 }) {
      Stack({ alignContent: Alignment.Center }) {
        FloatingGlassMaterialSurface({
          surfaceWidth: PRIVATE_LOCK_ICON_FRAME_SIZE,
          surfaceHeight: PRIVATE_LOCK_ICON_FRAME_SIZE,
          surfaceRadius: PRIVATE_LOCK_ICON_FRAME_SIZE / 2,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          SymbolGlyph($r('sys.symbol.lock_fill'))
            .fontSize(34)
            .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
            .fontColor([this.storedAccentColor])
            .hitTestBehavior(HitTestMode.None)
        }
      }
      .width(PRIVATE_LOCK_ICON_FRAME_SIZE)
      .height(PRIVATE_LOCK_ICON_FRAME_SIZE)
      .borderRadius(PRIVATE_LOCK_ICON_FRAME_SIZE / 2)

      Text('隐私模式已锁定')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.message)
        .fontSize(15)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .lineHeight(22)
        .padding({ left: 8, right: 8 })

      Row() {
        BrowserSheetActionButton({
          label: this.authenticationInProgress ? '正在验证' : '解锁',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          fillAvailableWidth: false,
          buttonWidth: PRIVATE_LOCK_ACTION_WIDTH,
          buttonHeight: PRIVATE_LOCK_ACTION_HEIGHT,
          onAction: () => {
            this.onAction('unlock');
          }
        })
      }
      .width(PRIVATE_LOCK_ACTION_WIDTH)
      .height(PRIVATE_LOCK_ACTION_HEIGHT)

      Row() {
        BrowserSheetActionButton({
          label: '回到普通模式',
          fillAvailableWidth: false,
          buttonWidth: PRIVATE_LOCK_ACTION_WIDTH,
          buttonHeight: 40,
          fontSize: 14,
          onAction: () => {
            this.onAction('return_to_regular');
          }
        })
      }
      .width(PRIVATE_LOCK_ACTION_WIDTH)
      .height(40)
    }
    .width(`calc(100% - ${PRIVATE_LOCK_SIDE_PADDING * 2}vp)`)
    .constraintSize({ maxWidth: PRIVATE_LOCK_CONTENT_MAX_WIDTH })
    .padding({ top: 28, bottom: 24, left: 20, right: 20 })
    .alignItems(HorizontalAlign.Center)
  }
}
