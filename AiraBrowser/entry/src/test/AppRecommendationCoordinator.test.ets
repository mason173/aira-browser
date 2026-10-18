import { describe, expect, it } from '@ohos/hypium';
import {
  AppRecommendationCoordinator,
  AppRecommendationShell,
  AppRecommendationShellFacts,
  AppRecommendationSnapshot,
  AppRecommendationSurface
} from '../main/ets/core/onboarding/AppRecommendationCoordinator';
import {
  AppRecommendationRecord,
  AppRecommendationRepository,
  AppRecommendationState,
  buildEmptyAppRecommendationState
} from '../main/ets/data/onboarding/AppRecommendationRepository';
import {
  BrowserTransientPromptBlockingFacts,
  BrowserTransientSurfaceId,
  BrowserTransientSurfacePresentationRequest,
  BrowserTransientSurfaceToken
} from '../main/ets/core/browser/BrowserTransientSurfaceCoordinator';

const APP_RECOMMENDATION_SURFACE_ID: BrowserTransientSurfaceId = 'app_recommendation';
const FIRST_CAMPAIGN: string = 'shengxi';
const SECOND_CAMPAIGN: string = 'pinecone';

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

function findRecord(records: AppRecommendationRecord[], id: string): AppRecommendationRecord | undefined {
  for (let index = 0; index < records.length; index++) {
    if (records[index].id === id) {
      return records[index];
    }
  }
  return undefined;
}

/** In-memory stand-in for the preferences-backed, per-campaign recommendation memory. */
class FixtureAppRecommendationRepository extends AppRecommendationRepository {
  /** What a previous session left on disk; loaded by {@link initialize}. */
  storedState: AppRecommendationState = buildEmptyAppRecommendationState();
  memory: AppRecommendationRecord[] = [];

  async initialize(): Promise<void> {
    this.memory = [];
    for (let index = 0; index < this.storedState.records.length; index++) {
      const record = this.storedState.records[index];
      this.memory.push({ id: record.id, shownAt: record.shownAt, dismissedAt: record.dismissedAt });
    }
  }

  getState(): AppRecommendationState {
    return { records: this.memory };
  }

  hasCompleted(id: string): boolean {
    const record = findRecord(this.memory, id);
    return record !== undefined && (record.shownAt > 0 || record.dismissedAt > 0);
  }

  shownAtFor(id: string): number {
    const record = findRecord(this.memory, id);
    return record === undefined ? 0 : record.shownAt;
  }

  dismissedAtFor(id: string): number {
    const record = findRecord(this.memory, id);
    return record === undefined ? 0 : record.dismissedAt;
  }

  async markShown(id: string, now: number = Date.now()): Promise<AppRecommendationState> {
    this.commitRecord(id, now, false);
    return this.getState();
  }

  async markDismissed(id: string, now: number = Date.now()): Promise<AppRecommendationState> {
    this.commitRecord(id, now, true);
    return this.getState();
  }

  private commitRecord(id: string, now: number, dismissed: boolean): void {
    let record = findRecord(this.memory, id);
    if (record === undefined) {
      record = { id: id, shownAt: 0, dismissedAt: 0 };
      this.memory.push(record);
    }
    if (record.shownAt <= 0) {
      record.shownAt = now;
    }
    if (dismissed && record.dismissedAt <= 0) {
      record.dismissedAt = now;
    }
  }
}

class FixtureAppRecommendationSurface implements AppRecommendationSurface {
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

class FixtureAppRecommendationShell implements AppRecommendationShell {
  facts: AppRecommendationShellFacts = {
    shellFamily: 'phone',
    homeVisible: true,
    appVisible: true,
    privacyMode: 'normal',
    recommendationIds: [FIRST_CAMPAIGN],
    promptBlockingFacts: buildIdlePromptBlockingFacts()
  };
  publishedSnapshots: AppRecommendationSnapshot[] = [];
  openedStores: string[] = [];

  resolveFacts(): AppRecommendationShellFacts {
    return this.facts;
  }

  publishState(snapshot: AppRecommendationSnapshot): void {
    this.publishedSnapshots.push(snapshot);
  }

  openStore(recommendationId: string): void {
    this.openedStores.push(recommendationId);
  }
}

interface RecommendationFixture {
  repository: FixtureAppRecommendationRepository;
  surface: FixtureAppRecommendationSurface;
  shell: FixtureAppRecommendationShell;
  coordinator: AppRecommendationCoordinator;
}

function buildRecommendationFixture(): RecommendationFixture {
  const repository = new FixtureAppRecommendationRepository();
  const surface = new FixtureAppRecommendationSurface();
  const shell = new FixtureAppRecommendationShell();
  // A zero delay keeps the test on the same scheduling path the shell uses while
  // staying deterministic.
  const coordinator = new AppRecommendationCoordinator(repository, surface, shell, 0);
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

/** Publishes the whole path the shell uses when the user closes the card. */
async function closeCurrentRecommendation(fixture: RecommendationFixture): Promise<void> {
  fixture.coordinator.handleSurfaceRevealed();
  fixture.coordinator.handleAction('dismiss');
  fixture.coordinator.handleSurfaceDismissed();
  await flushEvaluation();
}

export default function appRecommendationCoordinatorTest(): void {
  describe('AppRecommendationCoordinator', () => {
    it('offers the recommendation once per homepage arrival', 0, async () => {
      const fixture = buildRecommendationFixture();

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(1);
      expect(fixture.surface.presentRequests[0].id).assertEqual(APP_RECOMMENDATION_SURFACE_ID);
      expect(fixture.coordinator.getSnapshot().visible).assertTrue();
      expect(fixture.coordinator.getSnapshot().recommendationId).assertEqual(FIRST_CAMPAIGN);

      // The campaign is only spent once it actually reached the user.
      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN)).assertEqual(0);
      fixture.coordinator.handleSurfaceRevealed();
      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN) > 0).assertTrue();

      fixture.coordinator.handleSurfaceDismissed();
      expect(fixture.coordinator.getSnapshot().visible).assertFalse();

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
      expect(fixture.repository.dismissedAtFor(FIRST_CAMPAIGN)).assertEqual(0);
    });

    it('records the close when the user dismisses the card', 0, async () => {
      const fixture = buildRecommendationFixture();

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      await closeCurrentRecommendation(fixture);

      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN) > 0).assertTrue();
      expect(fixture.repository.dismissedAtFor(FIRST_CAMPAIGN) > 0).assertTrue();
      expect(fixture.surface.dismissedIds.length).assertEqual(1);
      expect(fixture.surface.dismissedIds[0]).assertEqual(APP_RECOMMENDATION_SURFACE_ID);
    });

    it('hands the campaign store page over when the user asks for it', 0, async () => {
      const fixture = buildRecommendationFixture();

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      fixture.coordinator.handleSurfaceRevealed();

      fixture.coordinator.handleAction('open_market');
      await flushEvaluation();

      expect(fixture.shell.openedStores.length).assertEqual(1);
      expect(fixture.shell.openedStores[0]).assertEqual(FIRST_CAMPAIGN);
      expect(fixture.surface.dismissedIds.length).assertEqual(1);
      expect(fixture.repository.dismissedAtFor(FIRST_CAMPAIGN) > 0).assertTrue();

      // Acting on the card is still the end of this campaign.
      fixture.coordinator.handleSurfaceDismissed();
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('offers a second, different recommendation after the first was closed', 0, async () => {
      const fixture = buildRecommendationFixture();

      // The user closes the first campaign.
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      await closeCurrentRecommendation(fixture);

      // The same campaign never returns, on this arrival or any later one.
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);

      // A later release appends a second app to the catalog. The user has not seen
      // it, so arriving at the homepage offers it — without reinstalling Aira.
      fixture.shell.facts.recommendationIds = [FIRST_CAMPAIGN, SECOND_CAMPAIGN];
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(2);
      expect(fixture.coordinator.getSnapshot().recommendationId).assertEqual(SECOND_CAMPAIGN);

      // Closing the second one is the end of it, and the first stays closed.
      await closeCurrentRecommendation(fixture);
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(2);
      expect(fixture.repository.dismissedAtFor(SECOND_CAMPAIGN) > 0).assertTrue();
    });

    it('offers at most one pending campaign per homepage arrival', 0, async () => {
      const fixture = buildRecommendationFixture();
      fixture.shell.facts.recommendationIds = [FIRST_CAMPAIGN, SECOND_CAMPAIGN];

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
      expect(fixture.coordinator.getSnapshot().recommendationId).assertEqual(FIRST_CAMPAIGN);

      // Closing the first card frees the prompt lane, which re-evaluates. That must
      // not turn one arrival into a queue of cards.
      await closeCurrentRecommendation(fixture);
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);

      // Arriving at the homepage again is what opens the next opportunity.
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(2);
      expect(fixture.coordinator.getSnapshot().recommendationId).assertEqual(SECOND_CAMPAIGN);
    });

    it('waits for a free lane instead of dropping the pending recommendation', 0, async () => {
      const fixture = buildRecommendationFixture();
      fixture.surface.automaticPromptBlocked = true;

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(0);
      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN)).assertEqual(0);

      fixture.surface.automaticPromptBlocked = false;
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);
    });

    it('stays silent on a device that already spent this campaign', 0, async () => {
      const fixture = buildRecommendationFixture();
      fixture.repository.storedState = {
        records: [{ id: FIRST_CAMPAIGN, shownAt: 1, dismissedAt: 1 }]
      };

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(0);
    });

    it('never presents over a Web page, a private session, or a hidden shell', 0, async () => {
      const webPageFixture = buildRecommendationFixture();
      webPageFixture.shell.facts.homeVisible = false;
      webPageFixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(webPageFixture.surface.presentRequests.length).assertEqual(0);

      const privateFixture = buildRecommendationFixture();
      privateFixture.shell.facts.privacyMode = 'private';
      privateFixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(privateFixture.surface.presentRequests.length).assertEqual(0);

      const hiddenFixture = buildRecommendationFixture();
      hiddenFixture.shell.facts.appVisible = false;
      hiddenFixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(hiddenFixture.surface.presentRequests.length).assertEqual(0);
    });

    it('never presents on the large-screen shell', 0, async () => {
      const fixture = buildRecommendationFixture();
      fixture.shell.facts.shellFamily = 'large_screen';

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();

      expect(fixture.surface.presentRequests.length).assertEqual(0);
      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN)).assertEqual(0);
    });

    it('hides the card without spending it when the shell resets', 0, async () => {
      const fixture = buildRecommendationFixture();

      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.coordinator.getSnapshot().visible).assertTrue();

      fixture.coordinator.handleShellReset();
      expect(fixture.coordinator.getSnapshot().visible).assertFalse();
      expect(fixture.repository.shownAtFor(FIRST_CAMPAIGN)).assertEqual(0);

      // The reset also ends the arrival, so the next card needs a new one.
      fixture.coordinator.scheduleEvaluation();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(1);

      fixture.coordinator.handleSurfaceDismissed();
      fixture.coordinator.handleHomeSurfaceVisible();
      await flushEvaluation();
      expect(fixture.surface.presentRequests.length).assertEqual(2);
    });
  });
}
