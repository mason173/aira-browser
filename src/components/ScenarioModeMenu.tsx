import { forwardRef, lazy, Suspense, useEffect, useRef, useState, type ButtonHTMLAttributes } from "react";
import { useTranslation } from "react-i18next";
import { RiDeleteBin6Fill, RiPencilFill } from "@/icons/ri-compat";
import { getScenarioIconByKey, type ScenarioMode } from "@/scenario/scenario";

const LazyConfirmDialog = lazy(() => import("@/components/ConfirmDialog"));

function ScenarioModeChevronDown({ open }: { open: boolean }) {
  return (
    <svg className={`block size-full transition-transform ${open ? "rotate-180" : ""}`} fill="none" viewBox="0 0 24 24">
      <path d="M6 9l6 6 6-6" stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="1.8" />
    </svg>
  );
}

const ScenarioModeButton = forwardRef<
  HTMLButtonElement,
  { mode: ScenarioMode; open: boolean; reduceVisualEffects?: boolean } & ButtonHTMLAttributes<HTMLButtonElement>
>(function ScenarioModeButton({ mode, open, reduceVisualEffects = false, ...buttonProps }, ref) {
  const Icon = getScenarioIconByKey(mode.icon);
  const displayName = mode.name;
  const buttonNode = (
    <button
      ref={ref}
      type="button"
      {...buttonProps}
      className={`content-stretch flex gap-[6px] items-center justify-center p-[3px] relative rounded-[999px] shrink-0 cursor-pointer hover:bg-white/10 transition-colors text-white/90 transform-gpu ${
        reduceVisualEffects ? '' : 'backdrop-blur-md'
      }`}
      data-name="ScenarioMode"
    >
      <div aria-hidden="true" className="absolute border border-white/10 border-solid inset-0 pointer-events-none rounded-[999px]" />
      <div className="relative shrink-0 size-[24px]">
        <div
          className="-translate-x-1/2 -translate-y-1/2 absolute left-1/2 top-1/2 rounded-[999px] size-[24px] flex items-center justify-center text-white"
          style={{ backgroundColor: mode.color }}
        >
          <Icon className="size-[14px]" />
        </div>
      </div>
      <div className="content-stretch flex gap-[4px] items-center justify-center pr-[6px] relative shrink-0">
        <p className="font-['PingFang_SC:Regular',sans-serif] leading-none not-italic relative shrink-0 text-inherit text-[13px]">
          {displayName}
        </p>
        <div className="relative shrink-0 size-[10px] text-white/60">
          <ScenarioModeChevronDown open={open} />
        </div>
      </div>
    </button>
  );
  return buttonNode;
});

function ScenarioModeMenu({
  scenarioModes,
  selectedScenarioId,
  open,
  onOpenChange,
  onSelect,
  onCreate,
  onEdit,
  onDelete,
  reduceVisualEffects = false,
}: {
  scenarioModes: ScenarioMode[];
  selectedScenarioId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onSelect: (id: string) => void;
  onCreate: () => void;
  onEdit: (id: string) => void;
  onDelete: (id: string) => void;
  reduceVisualEffects?: boolean;
}) {
  const { t } = useTranslation();
  const selectedMode = scenarioModes.find((m) => m.id === selectedScenarioId) ?? scenarioModes[0];
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<ScenarioMode | null>(null);
  const [hoveredId, setHoveredId] = useState<string | null>(null);
  const rootRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!open) return undefined;

    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Node && rootRef.current?.contains(target)) return;
      onOpenChange(false);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onOpenChange(false);
      }
    };

    document.addEventListener("pointerdown", handlePointerDown, true);
    document.addEventListener("keydown", handleKeyDown, true);
    return () => {
      document.removeEventListener("pointerdown", handlePointerDown, true);
      document.removeEventListener("keydown", handleKeyDown, true);
    };
  }, [onOpenChange, open]);

  if (!selectedMode) return null;

  return (
    <div ref={rootRef} className="relative">
      <ScenarioModeButton
        mode={selectedMode}
        open={open}
        reduceVisualEffects={reduceVisualEffects}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => onOpenChange(!open)}
      />
      {open ? (
        <div
          role="menu"
          className="absolute bottom-full left-0 z-[17020] mb-2 w-[320px] rounded-[24px] border border-border bg-popover p-[8px] text-foreground shadow-[0px_8px_24px_rgba(0,0,0,0.2)]"
        >
        <div className="flex flex-col gap-[6px]">
          <div className="px-[10px] pt-[8px] pb-[6px]">
            <p className="text-[12px] text-muted-foreground leading-none">{t('scenario.title')}</p>
          </div>
          <div className="max-h-[260px] overflow-y-auto pr-1">
            <div className="flex flex-col gap-[4px] px-[4px]">
              {scenarioModes.map((mode) => {
                const Icon = getScenarioIconByKey(mode.icon);
                const selected = mode.id === selectedScenarioId;
                const hovered = hoveredId === mode.id;
                const canDelete = mode.id !== "default" && scenarioModes.length > 1;
                const actionsVisible = hovered;
                const displayName = mode.name;
                return (
                  <div
                    key={mode.id}
                    role="button"
                    tabIndex={0}
                    className={`w-full h-[44px] px-[10px] rounded-xl flex items-center justify-between transition-colors ${selected || hovered ? "bg-accent" : ""}`}
                    onMouseEnter={() => setHoveredId(mode.id)}
                    onMouseLeave={() => setHoveredId((prev) => (prev === mode.id ? null : prev))}
                    onFocus={() => setHoveredId(mode.id)}
                    onBlur={() => setHoveredId((prev) => (prev === mode.id ? null : prev))}
                    onClick={() => {
                      onSelect(mode.id);
                      onOpenChange(false);
                    }}
                    onKeyDown={(e) => {
                      if (e.key !== "Enter" && e.key !== " ") return;
                      e.preventDefault();
                      onSelect(mode.id);
                      onOpenChange(false);
                    }}
                  >
                    <div className="flex items-center gap-[10px] min-w-0">
                      <div className="size-[28px] rounded-[999px] shrink-0 flex items-center justify-center text-white" style={{ backgroundColor: mode.color }}>
                        <Icon className="size-[14px]" />
                      </div>
                      <p className="text-[14px] text-foreground leading-none truncate">{displayName}</p>
                    </div>
                    <div className="shrink-0 flex items-center gap-[8px]">
                      <div
                        className={`flex items-center gap-[6px] transition-opacity ${
                          actionsVisible ? "opacity-100" : "opacity-0 pointer-events-none"
                        }`}
                        aria-hidden={!actionsVisible}
                      >
                        <button
                          type="button"
                          className="size-[28px] rounded-[10px] flex items-center justify-center text-muted-foreground hover:text-foreground hover:bg-background/70 transition-colors"
                          aria-label={t('scenario.actionEdit')}
                          onClick={(e) => {
                            e.stopPropagation();
                            onOpenChange(false);
                            onEdit(mode.id);
                          }}
                        >
                          <RiPencilFill className="size-[14px]" />
                        </button>
                        <button
                          type="button"
                          disabled={!canDelete}
                          className={`size-[28px] rounded-[10px] flex items-center justify-center transition-colors ${
                            canDelete
                              ? "text-muted-foreground hover:text-destructive hover:bg-destructive/15"
                              : "opacity-30 cursor-not-allowed text-muted-foreground"
                          }`}
                          aria-label={t('scenario.actionDelete')}
                          onClick={(e) => {
                            e.stopPropagation();
                            if (!canDelete) return;
                            setDeleteTarget(mode);
                            setDeleteOpen(true);
                          }}
                        >
                          <RiDeleteBin6Fill className="size-[14px]" />
                        </button>
                      </div>
                      <div className="shrink-0 size-[18px] flex items-center justify-center">
                        <div className={`size-[6px] rounded-[999px] ${selected ? "bg-primary" : "bg-transparent"}`} />
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
          <div className="px-[4px] pt-[6px]">
            <button
              type="button"
              className="inline-flex w-full h-[40px] items-center justify-center rounded-xl border border-border bg-secondary px-4 py-2 text-sm font-medium text-secondary-foreground transition-colors hover:bg-secondary/80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
              onClick={() => {
                onOpenChange(false);
                onCreate();
              }}
            >
              {t('scenario.createButton')}
            </button>
          </div>
        </div>
        </div>
      ) : null}
      {deleteOpen ? (
        <Suspense fallback={null}>
          <LazyConfirmDialog
            open={deleteOpen}
            onOpenChange={(nextOpen) => {
              setDeleteOpen(nextOpen);
              if (!nextOpen) setDeleteTarget(null);
            }}
            title={t('scenario.deleteTitle')}
            description={deleteTarget ? t('scenario.deleteConfirmWithTarget', { name: deleteTarget.name }) : t('scenario.deleteConfirm')}
            confirmText={t('scenario.deleteButton')}
            onConfirm={() => {
              if (!deleteTarget) return;
              onDelete(deleteTarget.id);
              setDeleteTarget(null);
              setDeleteOpen(false);
            }}
          />
        </Suspense>
      ) : null}
    </div>
  );
}

export default ScenarioModeMenu;
