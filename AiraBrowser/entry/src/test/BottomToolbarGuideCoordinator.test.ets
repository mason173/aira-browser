import { describe, expect, it } from '@ohos/hypium';
import {
  BottomToolbarGuideCoordinator,
  BottomToolbarGuideShell,
  BottomToolbarGuideShellFacts,
  BottomToolbarGuideSnapshot,
  BottomToolbarGuideSurface
} from '../main/ets/core/onboarding/BottomToolbarGuideCoordinator';
import {
  BottomToolbarGuideRepository,
  BottomToolbarGuideState,
  buildEmptyBottomToolbarGuideState
} from '../main/ets/data/onboarding/BottomToolbarGuideRepository';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../main/ets/core/browser/BrowserTransientSurfaceCoordinator';

const BOTTOM_TOOLBAR_GUIDE_SURFACE_ID: BrowserTransientSurfaceId = 'bottom_toolbar_guide';

function buildIdlePromptBlockingFacts(): BrowserTransientPromptBlockingFacts {
  return {
    tabsSheetVisible: false,
    readerModeVisible: false,
    releaseNoticeVisible: false,
    hlsTakeoverVisible: false,
    topFloatingPromptVisible: false,
    webContextMenuVisible: false,
    pendingJavaScriptPrompt: false,
    pendingSitePermissionPrompt: false,
    manualElementHideSelectionActive: false,
    privateModeLockVisible: false,
    downloadPromptVisible: false
  };
}

/** In-memory stand-in for the preferences-backed guide memory. */
class FixtureBottomToolbarGuideRepository extends BottomToolbarGuideRepository {
  /** What a previous session left on disk; loaded by {@link initialize}. */
  storedState: BottomToolbarGuideState = buildEmptyBottomToolbarGuideState();
  memory: BottomToolbarGuideState = buildEmptyBottomToolbarGuideState();
  initializeCount: number = 0;

  async initialize(): Promise<void> {
    this.initializeCount += 1;
    this.memory = {
      shownAt: this.storedState.shownAt,
      completedAt: this.storedState.completedAt
    };
  }

  getState(): BottomToolbarGuideState {
    return {
      shownAt: this.memory.shownAt,
      completedAt: this.memory.completedAt
    };
  }

  hasCompleted(): boolean {
    return this.memory.shownAt > 0 || this.memory.completedAt > 0;
  }

  async markShown(now: number = Date.now()): Promise<BottomToolbarGuideState> {
    if (this.memory.shownAt <= 0) {
      this.memory.shownAt = now;
    }
    return this.getState();
  }

  async markCompleted(now: number = Date.now()): Promise<BottomToolbarGuideState> {
    if (this.memory.completedAt <= 0) {
      this.memory.completedAt = now;
    }
    return this.getState();
  }
}

class FixtureBottomToolbarGuideSurface implements BottomToolbarGuideSurface {
  presentRequests: BrowserTransientSurfacePresentationRequest[] = [];
  dismissedIds: BrowserTransientSurfaceId[] = [];
  automaticPromptBlocked: boolean = false;

  present = (request: BrowserTransientSurfacePresentationRequest): BrowserTransientSurfaceToken => {
    this.presentRequests.push(request);
    return {
      id: request.id,
      generation: this.presentRequests.length
    };
  };

  dismiss = (id: BrowserTransientSurfaceId): void => {
    this.dismissedIds.push(id);
  };

  isReleaseNoticeBlocked = (_facts: BrowserTransientPromptBlockingFacts): boolean => {
    return this.automaticPromptBlocked;
  };
}

class FixtureBottomToolbarGuideShell implements BottomToolbarGuideShell {
  facts: BottomToolbarGuideShellFacts = {
    shellFamily: 'phone',
    deviceFormFactor: 'phone',
    appVisible: true,
    floatingToolbarChromeActive: true,
    privacyMode: 'normal',
    promptBlockingFacts: buildIdlePromptBlockingFacts()
  };
  publishedSnapshots: BottomToolbarGuideSnapshot[] = [];

  resolveFacts(): BottomToolbarGuideShellFacts {
    return this.facts;
  }

  publishState(snapshot: BottomToolbarGuideSnapshot): void {
    this.publishedSnapshots.push(snapshot);
  }
}

interface GuideFixture {
  repository: FixtureBottomToolbarGuideRepository;
  surface: FixtureBottomToolbarGuideSurface;
  shell: FixtureBottomToolbarGuideShell;
  coordinator: BottomToolbarGuideCoordinator;
}

function buildGuideFixture(): GuideFixture {
  const repository = new FixtureBottomToolbarGuideRepository();
  const surface = new FixtureBottomToolbarGuideSurface();
  const shell = new FixtureBottomToolbarGuideShell();
  // A zero delay keeps the test on the same scheduling path the shell uses while
  // staying deterministic.
  const coordinator = new BottomToolbarGuideCoordinator(repository, surface, shell, 0);
  return {
    repository: repository,
    surface: surface,
    shell: shell,
    coordinator: coordinator
  };
}

async function flushEvaluation(): Promise<void> {
  for (let turn = 0; turn < 3; turn += 1) {
    await new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, 0);
    });
  }
}

export default function bottomToolbarGuideCoordinatorTest(): void {
  describe('BottomToolbarGuideCoordinator', () => {
    it('presents the guide once after the first Web page load', 0, async () => {
      const fixture = buildGuideFixture();

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(1);
      expect(fixture.surface.presentRequests[0].id).assertEqual(BOTTOM_TOOLBAR_GUIDE_SURFACE_ID);
      expect(fixture.coordinator.getSnapshot().visible).assertTrue();
      expect(fixture.coordinator.getSnapshot().title.length > 0).assertTrue();

      // The lesson is only spent once the card actually reached the user.
      expect(fixture.repository.memory.shownAt).assertEqual(0);
      fixture.coordinator.handleSurfaceRevealed();
      expect(fixture.repository.memory.shownAt > 0).assertTrue();

      fixture.coordinator.handleSurfaceDismissed();
      expect(fixture.coordinator.getSnapshot().visible).assertFalse();

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('waits for a free lane instead of dropping the pending lesson', 0, async () => {
      const fixture = buildGuideFixture();
      fixture.surface.automaticPromptBlocked = true;

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.surface.automaticPromptBlocked = false;
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('never teaches the gesture on a desktop that only looks like a phone shell', 0, async () => {
      const fixture = buildGuideFixture();
      // A PC and a 2in1 device fall back to the phone shell, and neither has a bottom
      // floating toolbar to swipe away.
      fixture.shell.facts.deviceFormFactor = 'pc';

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.deviceFormFactor = 'two_in_one';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.deviceFormFactor = 'car';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.deviceFormFactor = 'tablet';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('stays silent without a Web page load, on a large screen, and in a private session', 0, async () => {
      const fixture = buildGuideFixture();

      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.shellFamily = 'large_screen';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.shellFamily = 'phone';
      fixture.shell.facts.privacyMode = 'private';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.shell.facts.privacyMode = 'normal';
      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('honours never_show_again and stays silent afterwards', 0, async () => {
      const fixture = buildGuideFixture();

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);

      fixture.coordinator.handleAction('never_show_again');
      expect(fixture.surface.dismissedIds.length).assertEqual(1);
      expect(fixture.surface.dismissedIds[0]).assertEqual(BOTTOM_TOOLBAR_GUIDE_SURFACE_ID);
      expect(fixture.repository.memory.completedAt > 0).assertTrue();

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('drops the pending lesson on a shell reset and offers it on the next load', 0, async () => {
      const fixture = buildGuideFixture();
      fixture.surface.automaticPromptBlocked = true;

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.coordinator.handleShellReset();
      expect(fixture.coordinator.getSnapshot().visible).assertFalse();

      fixture.surface.automaticPromptBlocked = false;
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('reloads the stored memory before presenting', 0, async () => {
      const fixture = buildGuideFixture();
      fixture.repository.storedState = {
        shownAt: 1,
        completedAt: 0
      };

      fixture.coordinator.handleWebPageLoadCompleted();
      await flushEvaluation();

      expect(fixture.repository.initializeCount > 0).assertTrue();
      expect(fixture.surface.presentRequests.length).assertEqual(0);
    });
  });
}
