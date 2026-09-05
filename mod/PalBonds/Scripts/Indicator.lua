--[[
    Indicator.lua — DESIGN.md Phase 6, on-screen trust indicator

    FORTY-THIRD PASS (2026-09-02): first attempt, hooking the HUD's own
    per-frame canvas draw event (AHUD:ReceiveDrawHUD) and drawing flat
    rectangles via AHUD:DrawRect. Installed cleanly (no Lua error), but
    Dragón's live test found NO bar anywhere over a full ~7-minute session
    where the underlying trust/capture logic worked perfectly. The log
    made this precise: the hook's own one-time "first frame seen"
    confirmation line never printed, across the whole session. Conclusion:
    Palworld's real HUD doesn't route through that legacy Blueprint event
    at all. Dead end, not a tuning problem.

    FORTY-FOURTH PASS (2026-09-03): switched to
    `UKismetSystemLibrary:DrawDebugString` (a real, native engine debug-
    text call, confirmed via this UE4SS install's own bundled `LineTraceMod`
    using the same library successfully in this game). Installed without
    error, ran for ~3.5 minutes in Dragón's next test — also no bar. THIS
    PASS'S OWN MISTAKE: no success-confirmation log was ever added inside
    the per-tick draw path (unlike the forty-third pass's one-shot "first
    frame seen" line), so there was no way to tell from the log whether it
    silently failed or silently succeeded somewhere wrong. Real, most
    likely explanation, found after the fact: Palworld ships as a Shipping
    build, and Unreal strips essentially all `DrawDebug*` calls
    (`UKismetSystemLibrary::DrawDebugString` included) out of Shipping
    builds by design (`#if ENABLE_DRAW_DEBUG`, compiled to 0/false in
    Shipping) — the call becomes a silent no-op, no error, nothing drawn,
    which matches exactly what was observed. Not confirmable from Lua
    directly, but it's the single most common, well-documented cause of
    this exact symptom in Unreal modding generally, and it means NO
    debug-draw function (this one or any other) can ever work here,
    regardless of positioning — a dead end on principle, not just in
    practice.

    FORTY-FIFTH PASS (2026-09-03): Dragón found a real precedent —
    "VisiblePalCaptureCounter" (a Nexus mod, source dropped into the
    Proyectos folder), built for an OLDER Palworld version, which shows
    small text next to a wild Pal's own real HP gauge by writing directly
    into that gauge's own UMG widget tree — NOT debug-draw, so it can't be
    stripped, since it's part of the shipped game's own real UI. Its
    technique: hook `WBP_PalNPCHPGauge_C:BindFromHandle`/`:Unbind` (a
    Blueprint widget class) to get the live per-Pal gauge widget instance,
    then call `widget.WBP_EnemyGauge.Text_WorkName:SetText_GDKInternal(1,
    text)` on it directly.

    Checked what's still real in THIS game's own header dump before
    reusing any of that blind, per Dragón's own instruction not to assume
    the old names still apply:
      - `SetText_GDKInternal(bool, FString)` — CONFIRMED still exists,
        unchanged, on the native `UPalTextBlockBase : public
        UCommonTextBlock` (the game's real text-widget base class). The
        actual "how do you set text on a widget" mechanism is fine.
      - The exact old asset path, `/Game/Pal/Blueprint/UI/NPCHPGauge/
        WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C`, has NO matching dumped
        header anywhere in this install's CXXHeaderDump folder (which does
        contain plenty of other individually-dumped WBP_* Blueprint
        classes, so the dumper does capture Blueprint widgets when they've
        been loaded at least once — this one just isn't among them,
        meaning either it was never loaded during whatever dump session
        ran, or it was genuinely renamed/restructured since Dragón's old
        mod was built).
      - Found what's very likely its modern replacement instead: two
        native base classes, `UPalUICharacterHPGaugeBase` (real methods:
        `SetTargetCharacter(APalCharacter*)`, `SetHPPercent(float)`,
        `UpdatePosition()`, `UpdateVisibility()`) and
        `UPalUINPCHPGaugeCanvasBase` (a likely container/canvas managing
        several gauge widgets on screen at once — a common, more
        draw-call-efficient successor architecture to "one Blueprint
        widget per visible Pal").

    THIS PASS DOES NOT YET WRITE ANY TEXT. Following this project's own
    established rule (confirm with a read-only watch before ever calling/
    writing something new) and Dragón's explicit instruction this time
    ("check how they do it, then use those terms to find first if they're
    still called like that"), this hooks the two NATIVE
    `UPalUICharacterHPGaugeBase` functions read-only, to get the real live
    widget instance and log its actual current class name/hierarchy —
    hooking the NATIVE base means it fires regardless of whatever the
    Blueprint subclass is actually named today, sidestepping the exact
    "did the asset path change" question entirely. Logging is capped (see
    MAX_DIAGNOSTIC_LOGS) since call frequency here is unknown, and this
    project has already been burned once by treating an unknown-frequency
    native hook as if it were a rare event
    (`SelectResponseBySenses`, thirty-third pass).

    FORTY-SIXTH PASS (2026-09-03): Dragón tested the forty-fifth pass's
    two hooks directly — walked up to a wild Lamball, petted it (a real,
    confirmed `interaction #1` in the log), then hit it by accident (its
    health bar visibly dropped, per Dragón). Neither `SetTargetCharacter`
    nor `SetHPPercent` fired ONCE across the whole ~10-minute session — a
    third "installs cleanly, never fires" result in a row (after
    ReceiveDrawHUD and, implicitly, whatever DrawDebugString needed).
    Real, useful negative result: those two specific functions are not
    what actually drives a WILD Pal's in-field HP gauge in this game
    version, whatever they're for instead (a different, unused, or
    editor/preview-only gauge context is plausible).

    Rather than guess at yet another function name blind, this pass adds
    a DIFFERENT kind of check: does `UPalUICharacterHPGaugeBase` (or its
    likely sibling `UPalUINPCHPGaugeCanvasBase`) even get INSTANTIATED at
    all during ordinary wild-Pal play? `FindAllOf(ClassName)` is a real,
    already-proven UE4SS Lua global in this project (same family as
    `FindFirstOf`, used constantly elsewhere, e.g. Capture.lua's
    `FindFirstOf("PalPlayerCharacter")`) that returns every live object of
    a given class. A periodic (not per-frame) scan for live instances of
    both classes, logging counts and each instance's real `GetFullName()`
    whenever any exist, answers the question directly: if instances show
    up, the classes are real but something else (not these two functions)
    sets them up — worth then inspecting further. If NOTHING ever shows
    up, these aren't the classes actually used to render a wild Pal's
    gauge at all, and the real one is something this project hasn't found
    yet (possibly rendered a completely different way, e.g. procedurally
    by the "Canvas" class without discrete per-Pal widget objects at all).

    FORTY-SIXTH PASS RESULT: a real hit. Dragón walked up to several wild
    Pals to look at their gauges/details, and the scan caught it —
    `PalUICharacterHPGaugeBase` stayed at 0 the whole time (confirming
    it's genuinely not used for wild Pals here), but
    `PalUINPCHPGaugeCanvasBase` showed 1-2 live instances throughout:
    real class `WBP_PalNPCHPGaugeCanvas_C`. One instance's full name
    starts with `/Game/Pal/Blueprint/UI/WBP_PlayerUI.WBP_PlayerUI_C:
    WidgetTree.WBP_PalNPCHPGaugeCanvas` (the archetype baked into the
    Blueprint asset itself, not live gameplay state); the other starts
    with `/Engine/Transient...WBP_PlayerUI_C_...WidgetTree_....
    WBP_PalNPCHPGaugeCanvas` (a real, live instance under the actual
    running PlayerUI's widget tree). This directly confirms the
    hypothesis: the modern game consolidated what the old mod knew as
    individual `WBP_PalNPCHPGauge_C` widgets (one per visible wild Pal)
    into a single shared `WBP_PalNPCHPGaugeCanvas_C` that manages
    multiple Pals' gauges itself — which also explains why hooking
    per-instance functions on the old per-gauge base class never fired:
    there ARE no more per-Pal widget objects to call those functions on.

    FORTY-SEVENTH PASS (2026-09-03): with a real, confirmed, live object
    in hand, no more guessing is needed — this project already has a
    proven technique for reading a live Blueprint widget's actual fields
    directly (Interaction.lua's `dump_interesting_properties`, twelfth
    pass, itself modeled on the bundled `ConsoleCommandsMod/dump_object.lua`):
    `Class:ForEachProperty()` walked up `GetSuperStruct()`, which surfaces
    Blueprint-ADDED fields too, not just what a static header dump would
    show. Added an unfiltered version here (we don't know what to filter
    for yet) that also handles ArrayProperty specially — logging its
    length and, if the array holds objects, each element's real class
    name — since the canvas almost certainly holds its multiple per-Pal
    gauge "slots" in exactly this kind of array. Runs ONCE, the first
    time the periodic scan finds the real live instance (identified by
    its full name starting with `/Engine/Transient`, not the Blueprint
    archetype). Still fully read-only — this logs field names/types/values,
    changes nothing.

    FORTY-SEVENTH PASS RESULT: the live canvas's own class hierarchy
    confirmed (`WBP_PalNPCHPGaugeCanvas_C` -> `PalUINPCHPGaugeCanvasBase`
    -> `PalUserWidget` -> ... -> `UserWidget`), plus real fields including
    `DisplayedPalGaugeMap`/`DisplayedBossUGaugeMap`/`DisplayedPlayerGaugeMap`
    (all `MapProperty`) and `Canvas_Root` (a `CanvasPanel`) / `WrapBox` (a
    `WrapBox`), both `ObjectProperty`. `dump_all_properties` doesn't handle
    `MapProperty` at all (falls through to "(not read)") — checked whether
    this project's own model for that function, the bundled
    `ConsoleCommandsMod/dump_object.lua`, handles it, and it explicitly
    doesn't either (`ValueStr = "UNHANDLED_VALUE"`, with its own comment
    "Need to add support eventually for MapProperty when UE4SS Lua supports
    MapProperty") — so reading `DisplayedPalGaugeMap` directly is, at best,
    unsupported by this project's current tooling, and quite possibly by
    this whole UE4SS Lua build.

    FORTY-EIGHTH PASS (2026-09-03): pivoted to the `WrapBox` field instead,
    since a `WrapBox` widget's entire standard UMG purpose is auto-arranging
    multiple child widgets in a flow layout — a very natural fit for "one
    small gauge widget per visible wild Pal". Confirmed via a fresh grep of
    the CXXHeaderDump (`UMG.hpp`) AND the bundled Lua API stub file
    (`shared/types/UMG.lua`, which is generated from this exact game's real
    reflection data, so it's authoritative for THIS build) that
    `UPanelWidget` (the base class of both `WrapBox` and `CanvasPanel`) has
    two real, ordinary, still-present functions:
    `GetChildrenCount() -> int32` and `GetChildAt(int32 Index) -> UWidget*`.
    These are standard, well-known UMG functions in virtually every Unreal
    version — a much safer bet than guessing at Map-reading APIs that may
    not exist here at all.

    This pass keeps a reference to the live canvas instance once found
    (module-level `liveCanvasInstance`, no behavior change to the existing
    one-shot property dump above) and, on every scan tick afterward, reads
    `liveCanvasInstance.WrapBox`, calls `GetChildrenCount()` on it, and logs
    the count (capped, so it's safe to log every tick even though the count
    can go up/down as Pals come in/out of range). The FIRST time that count
    is > 0, it walks every child via `GetChildAt(i)`, logs each child's real
    `GetFullName()`/class once, and runs the full `dump_all_properties` dump
    on the first child only — to find, from that child's own real fields,
    both the text-block sub-widget the old mod would have called
    `Text_WorkName` (this game's still-valid `SetText_GDKInternal` needs a
    real `UPalTextBlockBase`/`UCommonTextBlock` target to call on) and
    whatever field identifies WHICH Pal that specific gauge child belongs to
    (a handle, character reference, or save-parameter — needed to match a
    gauge child back to one of this mod's own tracked Pals in
    `Trust.GetFollowingSnapshot()`). Raised `MAX_PROPERTY_DUMP_LOGS` from 60
    to 200 to leave room for both the canvas's own dump (which alone nearly
    filled the old 60-line cap) and this new child dump in the same session.
    Still fully read-only — logs only, no widget is written to yet.

    FORTY-EIGHTH PASS RESULT: inconclusive, not negative. Dragón's test
    session was only ~95 seconds long (game launch to log's last line) —
    the live canvas was found immediately and its property dump ran fine,
    but `WrapBox:GetChildrenCount()` stayed at 0 for the entire session,
    which never gave the pass a real chance to see a Pal's gauge appear.
    Separately, on reflection, `WrapBox` may simply be the wrong container
    on structural grounds regardless of test length: a WrapBox's whole
    purpose is auto-flowing multiple children into ONE shared list
    position — reasonable for something like a stacked buff-icon row, but
    not for gauges that each need to float independently above their own
    Pal's own, separately-moving screen position. `Canvas_Root` (a
    `CanvasPanel`, confirmed also present on the same canvas instance)
    positions each child via its own `CanvasPanelSlot` with independent
    coordinates — a much better structural fit for "one gauge that tracks
    Pal X's position, another that tracks Pal Y's."

    FORTY-NINTH PASS (2026-09-03): rather than re-run the exact same
    single-container check and hope for a longer test, generalized
    `check_wrapbox_children` into `check_panel_children(fieldName)` (same
    real `UPanelWidget:GetChildrenCount()`/`GetChildAt(Index)`, just keyed
    by field name so per-field state — has-dumped flag, last logged count
    — doesn't collide) and now call it for BOTH `WrapBox` and
    `Canvas_Root` every scan tick via `check_all_panels()`. Whichever
    field gets a live child first gets its children listed and its first
    child fully dumped — still fully read-only. This needs a genuinely
    longer live test than last time: stand near a wild Pal with its real
    HP bar visible on screen for a good stretch (10-15+ seconds, not just
    a quick glance) so there's actually time for either container to
    populate.

    FORTY-NINTH PASS RESULT: real signal at last. Dragón's longer test
    (walked among several wild Pals, pet a ChickenPal and a SheepBall)
    showed `Canvas_Root`'s child count climbing steadily as the session
    went on — 2, then 11, then 17, 19, 20 — tracking Pals coming into
    view exactly as hoped. `WrapBox`'s count never changed at all this
    time either. This settles it: `Canvas_Root` is the real, actively
    populated per-entity gauge container; `WrapBox` is not.

    BUT: the dump itself was still wrong, for a subtle reason. Only
    `GetChildAt(0)` was ever dumped (the "first time count > 0" guard),
    and the first moment `Canvas_Root`'s count went from 0 to 1, THAT
    single child was the `WrapBox` itself — confirmed by the log:
    `Canvas_RootChild0 (class WrapBox)`. In other words, `WrapBox` isn't
    a sibling field pointing somewhere else — it's the FIRST, always-
    present structural child living inside `Canvas_Root`'s own widget
    tree (added at construction, before any Pal is ever nearby), and our
    one-shot "dump child 0" logic caught that fixture instead of any of
    the real per-Pal children that only show up later, at indices 1 and
    up, as the count climbs to 11, 17, 19, 20.

    FIFTIETH PASS (2026-09-03): two fixes. First, list ALL of a panel's
    children EVERY time its count changes (not just the first time it
    goes above zero) — real per-Pal children come and go continuously as
    Pals enter/leave range, so a single early snapshot can land before
    any exist. Second, stop hardcoding "always dump index 0": maintain a
    small blocklist of known structural/generic container class names
    (`WrapBox`, `CanvasPanel`, `HorizontalBox`, etc.) and, among the
    children actually present at each listing, fully dump the first one
    whose class ISN'T in that blocklist and hasn't already been dumped —
    that's the real, novel per-entity content, wherever it lands in the
    index order. A `dumpedClasses` set (shared across both panel fields)
    keeps each distinct real class from being dumped more than once, even
    across many count changes. Still fully read-only. Needs one more live
    test, same as before: stand near several wild Pals for a good stretch
    so `Canvas_Root` fills up with real per-Pal children, not just the
    fixed `WrapBox` fixture.

    FIFTIETH PASS RESULT: the big one. Dragón's test showed `Canvas_Root`
    filling up with real content — count climbed 1, 6, 10, 13... — and
    every single one of those new children (index 1 and up) turned out to
    be class **`WBP_PalNPCHPGauge_C`**. That is the EXACT class name the
    forty-fifth pass's reference mod (VisiblePalCaptureCounter, built for
    an older Palworld version) used, which earlier passes concluded must
    have been renamed/restructured — it turns out it was never renamed at
    all, it just never showed up in this install's static header dump
    (which only captures Blueprint classes it happened to see loaded
    during whatever dump session produced it) until now, found live and
    unambiguous via `GetChildAt`. Dragón's own instruction from the start
    of this whole effort — verify old names against the current game's
    real state rather than assume — turned out to cut both ways: the old
    name wasn't wrong, it just wasn't independently confirmable until the
    live container itself was found.

    Its generic property dump (still capped by `MAX_PROPERTY_DUMP_LOGS`,
    which is shared across the whole session and was nearly exhausted by
    this point) confirmed real, exactly-relevant fields before hitting the
    cap: `WBP_EnemyGauge` (an `ObjectProperty`, a `WBP_EnemyGauge_C`
    instance) — the exact sub-widget path the old mod wrote text into
    (`WBP_EnemyGauge.Text_WorkName:SetText_GDKInternal(...)`) — and,
    inherited from `WBP_IndividualParameterBindWidget_C`, a `SyncId`
    field typed `/Script/Pal.PalInstanceID` (this project's own Q5, the
    stable per-Pal GUID struct), plus a `IsBindFriendShip` bool and real
    `OnChangedFriendshipRank`/`OnChangedFriendshipPoint` delegates —
    meaning this exact widget class already has native, if currently
    unused for wild Pals, support for friendship-driven display.

    FIFTY-FIRST PASS (2026-09-03): with the real gauge widget class
    confirmed, added a targeted `inspect_gauge_widget()` that runs once
    on the first live `WBP_PalNPCHPGauge_C` found (separate from, and in
    addition to, the generic per-class dump above, which can't see a
    child's OWN sub-widgets or read struct-property field values). It
    reads `.WBP_EnemyGauge` directly and fully dumps that sub-widget's own
    fields (looking for the real, current name of what the old mod called
    `Text_WorkName`), and reads `.SyncId`'s own sub-fields
    (`DebugName`/`InstanceId`/`PlayerUId`) by indexing directly into the
    struct value — the same technique already proven safe on other small
    hook-argument structs (e.g. `FPalDamageResult.Defender` in Trust.lua),
    as opposed to the by-value struct RETURN pattern that caused this
    project's three real crashes early on. Still fully read-only. Needs
    one more live test, same as before.

    FIFTY-FIRST PASS RESULT: another clean, real confirmation.
    `WBP_EnemyGauge_C`'s own dump showed **`Text_WorkName`** — a
    `BP_PalTextBlock_C` (Blueprint subclass of the native, confirmed-valid
    `UPalTextBlockBase`) — present under the EXACT same path the old
    reference mod used (`WBP_EnemyGauge.Text_WorkName`). Also present:
    `Text_Name`, `Text_LevelNum`, `Text_GuildName` (other real UI text
    fields, already used for name/level/guild display) and
    `ProgressBar_HP`/`ProgressBar_HPBack` (the real HP bar itself — not
    free to repurpose). `SyncId`'s sub-fields came back mostly useless
    though: `DebugName` printed empty and `InstanceId`/`PlayerUId` printed
    a generic struct-wrapper identity string, not real values — because
    each of those is ITSELF a plain `FGuid` struct (`{ uint32 A, B, C, D
    }`), one more level of indexing beyond what fifty-first pass tried.

    FIFTY-SECOND PASS (2026-09-03): two changes. First, added
    `describe_guid()` to properly index into an `FGuid`'s own `A`/`B`/`C`/
    `D` fields instead of stringifying the wrapper object — should finally
    produce a real, comparable identifier for matching a gauge to one of
    this mod's own tracked Pals. Second, and much bigger: with
    `Text_WorkName` now confirmed real, this pass makes this whole
    effort's FIRST ACTUAL WRITE — a single, harmless, static test string
    (`SetText_GDKInternal(true, "PalBonds TEST")`) on the one already-live
    gauge widget found, exactly once. This is a text-set call on a widget
    that already exists and already renders every frame — a fundamentally
    safer shape than any of the gameplay-action calls that caused this
    project's three real crashes (those were native functions invoked
    out of their normal internal call context; this is the same kind of
    property/method access this project already uses constantly for
    reading, just writing instead). If Dragón sees "PalBonds TEST" appear
    over a wild Pal in-game, the hard research question — where does
    trust-progress text actually go — is answered, and the rest is wiring
    real numbers through instead of a static string.

    FIFTY-SECOND PASS RESULT: the write call itself returned OK (no Lua
    error, confirmed in the log) — but Dragón saw no text at all in-game.
    `SyncId`'s GUIDs also came back all-zero (`00000000-...`), suggesting
    either this specific gauge's handle wasn't fully bound at read time,
    or the `A`/`B`/`C`/`D` indexing still isn't reaching the real values —
    a separate, lower-priority loose end. The main mystery: a successful
    call with nothing visible is the exact signature of a widget that
    silently accepted the new text while its own `Visibility` stayed
    `Collapsed` (or similar) — `SetText_GDKInternal` sets underlying text
    state; it doesn't force the widget on screen. `Text_WorkName`'s own
    field NAME, plus its siblings on `WBP_EnemyGauge_C`
    (`CachedIsWork`, `Anm_WorkIcon*`, `WBP_MainMenu_Pal_State`), all point
    the same direction: this text is very likely meant only for a Pal
    actively doing a base-camp JOB, collapsed for an ordinary wild/roaming
    Pal — which would explain this exact silent no-op perfectly.

    FIFTY-THIRD PASS (2026-09-03): before writing text, now dumps
    `Text_WorkName`'s own properties (to see its real current
    `Visibility` value directly, rather than guessing) and forces it to
    `Visible` via the standard, universal `UWidget:SetVisibility(0)`
    (ordinal 0 confirmed = `ESlateVisibility::Visible` from this same
    project's own earlier enum dumps) immediately before calling
    `SetText_GDKInternal` again. Dumps the widget's properties a second
    time afterward too, so the before/after `Visibility` values are both
    on record regardless of whether the visible-text test finally works.
    If forcing visibility is what was missing, this should finally show
    "PalBonds TEST" in-game; if it still doesn't, the next diagnostic step
    is checking the WIDGET TREE's own visibility chain (a parent container
    collapsed higher up would hide this even if `Text_WorkName` itself
    reports `Visible`), not just this one widget in isolation.

    Dragón's own course-correction, right after this pass (2026-09-03):
    the fifty-second/fifty-third passes' `Text_WorkName` write was only
    ever meant to sanity-check that WRITING to a live widget works at all
    — after 50+ passes of everything silently failing, that was a
    reasonable thing to want proof of. But it is NOT the actual
    deliverable. Dragón's original spec, unchanged since the start of
    Phase 6, is a real graphical FILL BAR under the Pal's existing HP bar
    tracking live FriendshipPoint — not text anywhere. Dragón was also
    explicit that the three reference mods (VisiblePalCaptureCounter, Pal
    Analyzer, RemoteAccessEverything) were given purely to learn HOW
    widget manipulation is done in this game, never as literal templates
    to copy. Nothing before this point in the file has been treated as
    "solved" for the wrong reason — but it's worth being explicit that
    confirming the write mechanism was a means, not the end, before
    continuing.

    FIFTY-FOURTH PASS (2026-09-03): per Dragón's explicit choice
    ("research the real bar first"), pivoted to the actual hard question:
    can UE4SS Lua construct a brand-new UMG widget at runtime and insert
    it into an existing live widget tree? Everything this project has done
    with widgets so far — every pass above — only ever read or wrote
    fields on widgets the GAME already constructed. Nothing has ever
    created one from scratch.

    Research (grepping this game's own `CXXHeaderDump/UMG.hpp`, plus a
    real, currently-shipping precedent in the UE4SS-bundled
    `Mods/BPML_GenericFunctions/Scripts/main.lua` mod):
      - `StaticConstructObject(Class, Outer, Name, SetFlags,
        InternalSetFlags, bCopyTransientsFromClassDefaults,
        bAssumeTemplateIsArchetype, Template, InInstanceGraph,
        ExternalPackage)` is a REAL global Lua function UE4SS itself
        exposes — not something a mod defines. Confirmed by
        `BPML_GenericFunctions`'s own `ConstructPersistentObject` custom
        event, which is live, working code in this exact install: it
        calls `StaticConstructObject` with a `UClass` found via
        `StaticFindObject`, checks `:IsValid()`, and returns the result —
        the exact same shape this pass needs, just with a `UProgressBar`
        class instead of an arbitrary one.
      - `UPanelWidget:AddChild(UWidget* Content) -> UPanelSlot*` and the
        more specific `UCanvasPanel:AddChildToCanvas(UWidget* Content) ->
        UCanvasPanelSlot*` are both real, unchanged functions in this
        game's `UMG.hpp`. `Canvas_Innner` (the private, per-Pal-gauge
        CanvasPanel found on `WBP_PalNPCHPGauge_C` back in the
        fifty-first pass, never yet explored further) IS a
        `UCanvasPanel`, so `AddChildToCanvas` is the exact call needed to
        parent a new widget into it.
      - `UProgressBar` (UMG.hpp) is real and unchanged:
        `SetPercent(float)`, `SetFillColorAndOpacity(FLinearColor)`,
        `SetIsMarquee(bool)`. This is the actual class that matches
        Dragón's original spec (a filling bar), not anything text-based.
      - `UCanvasPanelSlot` (what `AddChildToCanvas` returns) has real
        `SetPosition(FVector2D)` / `SetSize(FVector2D)` /
        `SetAnchors(FAnchors)` functions for placing the new bar once one
        exists to compare position against.

    This pass makes the actual first attempt, once per session, on the
    first live gauge widget found: find the `UProgressBar` UClass via
    `StaticFindObject`, construct one via `StaticConstructObject` (Outer =
    `Canvas_Innner` itself — a valid, related, already-live UObject,
    matching the "outer must be real" pattern `BPML_GenericFunctions`
    itself uses with `GameInstance`), set an obvious test percent/color
    (50%, bright magenta — deliberately nothing like the real HP bar's own
    color, so if it renders at all it's unmistakable), add it to
    `Canvas_Innner` via `AddChildToCanvas`, and give its slot a
    provisional position/size just under where the real HP bar sits.
    Every step is its own pcall, logged individually (`DIAG-CREATE`) —
    this is genuinely unproven ground, and if it fails, the log needs to
    show exactly which step broke, not just "it didn't work."
]]

local Logger = require("Logger")
local Trust = require("Trust") -- fifty-seventh pass: reuse Trust's own CAPTURE_AT_FRIENDSHIP_POINT rather than duplicating the number
local UEHelpers = require("UEHelpers") -- sixty-fourth pass: for UEHelpers.GetGameplayStatics(), the same bundled shared module Mods/SplitScreenMod/Scripts/main.lua already uses for static Blueprint-library calls
local Personality = require("Personality") -- hundred-and-fiftieth pass: for the temporary personality-label debug text (install_personality_label below) — no circular require (Personality.lua doesn't require Indicator)

local Indicator = {}

local function safe_call(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil, result
end

local function hook_get(param)
    if param == nil then return nil end
    local ok, value = pcall(function() return param:get() end)
    if ok then return value end
    return nil
end

local MAX_DIAGNOSTIC_LOGS = 20 -- cap total log lines from these two research hooks combined, in case call frequency turns out to be high
local logCount = 0

local function diagnostic_log(msg)
    if logCount >= MAX_DIAGNOSTIC_LOGS then return end
    logCount = logCount + 1
    Logger.log(msg)
    if logCount == MAX_DIAGNOSTIC_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG] reached the diagnostic log cap (" .. MAX_DIAGNOSTIC_LOGS .. ") — going quiet for the rest of this session to avoid spam; what's logged so far should already answer the real questions")
    end
end

local function describe_widget(widget)
    if widget == nil then return "nil" end
    local ok, fullName = pcall(function() return widget:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end

local function describe_pal(pal)
    if pal == nil then return "nil" end
    local ok, fullName = pcall(function() return pal:GetFullName() end)
    if ok and fullName then return fullName end
    return "[could not read GetFullName]"
end

-- Forty-sixth pass: does the gauge class even get instantiated at all?
-- Periodic (not per-frame) existence scan, separate cap from the hook
-- diagnostics above.
local SCAN_INTERVAL_MS = 2000
local MAX_SCAN_LOGS = 25
local scanLogCount = 0
local hasLoggedScanAlive = false

-- Forty-seventh pass: full, unfiltered property dump of the real live
-- canvas instance, run exactly once. Same ForEachProperty/GetSuperStruct
-- technique already proven in Interaction.lua's dump_interesting_properties
-- (itself modeled on ConsoleCommandsMod/dump_object.lua), just unfiltered
-- and with extra ArrayProperty handling (length + element class names)
-- since the per-Pal gauge slots are very likely held in an array.
local MAX_PROPERTY_DUMP_LOGS = 700 -- raised again in the fifty-third pass: now dumping Text_WorkName itself twice (before/after) on top of the canvas + gauge + WBP_EnemyGauge dumps already happening in the same session
local propertyDumpLogCount = 0
local hasDumpedCanvas = false

-- Forty-eighth pass: once the real live canvas is found, keep a handle to
-- it so later scan ticks can check its panel children without having to
-- re-run FindAllOf/re-match the /Engine/Transient name every time.
local liveCanvasInstance = nil

local function property_dump_log(msg)
    if propertyDumpLogCount >= MAX_PROPERTY_DUMP_LOGS then return end
    propertyDumpLogCount = propertyDumpLogCount + 1
    Logger.log(msg)
    if propertyDumpLogCount == MAX_PROPERTY_DUMP_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-DUMP] reached the property-dump log cap (" .. MAX_PROPERTY_DUMP_LOGS .. ") — stopping here, this should already be enough to see the real field names")
    end
end

local function dump_all_properties(obj, label)
    local ok, err = pcall(function()
        if obj == nil or not obj:IsValid() then return end
        local class = obj:GetClass()
        local seen = {}
        while class ~= nil and class:IsValid() do
            local classNameOk, className = pcall(function() return class:GetFName():ToString() end)
            property_dump_log(string.format("[PalBonds/Indicator] [DIAG-DUMP] === %s (class %s) ===", label, classNameOk and className or "?"))

            class:ForEachProperty(function(prop)
                local propOk, propName = pcall(function() return prop:GetFName():ToString() end)
                if not (propOk and propName) or seen[propName] then return end
                seen[propName] = true

                local typeOk, typeName = pcall(function() return prop:GetClass():GetFName():ToString() end)
                typeName = typeOk and typeName or "?"
                local valueStr = "(not read)"

                local readOk, result = pcall(function()
                    if typeName == "BoolProperty" or typeName == "ByteProperty"
                        or typeName == "IntProperty" or typeName == "FloatProperty" then
                        return tostring(obj[propName])
                    elseif typeName == "NameProperty" then
                        local v = obj[propName]
                        return v and v:ToString()
                    elseif typeName == "StrProperty" then
                        local v = obj[propName]
                        return v and v:ToString()
                    elseif typeName == "EnumProperty" then
                        local v = obj[propName]
                        local enumOk, enumName = pcall(function() return prop:GetEnum():GetNameByValue(v):ToString() end)
                        return enumOk and string.format("%s(%s)", enumName, tostring(v)) or tostring(v)
                    elseif typeName == "ObjectProperty" then
                        local v = obj[propName]
                        if v == nil then return "nil" end
                        local vOk, vName = pcall(function() return v:GetFullName() end)
                        return vOk and vName or "[object, GetFullName failed]"
                    elseif typeName == "StructProperty" then
                        local v = obj[propName]
                        if v == nil then return "nil" end
                        local vOk, vName = pcall(function() return v:GetFullName() end)
                        return vOk and vName or "[struct]"
                    elseif typeName == "ArrayProperty" then
                        local v = obj[propName]
                        local numOk, num = pcall(function() return v:GetArrayNum() end)
                        num = numOk and num or -1
                        local innerOk, innerTypeName = pcall(function() return prop:GetInner():GetClass():GetFName():ToString() end)
                        local summary = string.format("array of %s, length=%d", innerOk and innerTypeName or "?", num)
                        if num > 0 and innerOk and innerTypeName == "ObjectProperty" then
                            local elementNames = {}
                            v:ForEach(function(index, elem)
                                if index <= 5 then
                                    local eOk, e = pcall(function() return elem:get() end)
                                    local eNameOk, eName = pcall(function() return e:GetFullName() end)
                                    elementNames[#elementNames + 1] = (eOk and eNameOk and eName) or "[unreadable]"
                                end
                            end)
                            summary = summary .. " — first elements: " .. table.concat(elementNames, " | ")
                        end
                        return summary
                    end
                    return nil
                end)
                if readOk and result ~= nil then valueStr = tostring(result) end

                property_dump_log(string.format("[PalBonds/Indicator] [DIAG-DUMP]   %s (%s) = %s", propName, typeName, valueStr))
            end)

            class = safe_call(function() return class:GetSuperStruct() end)
        end
    end)
    if not ok then
        Logger.log("[PalBonds/Indicator] [DIAG-DUMP] property dump failed (non-fatal, caught): " .. tostring(err))
    end
end

-- Forty-ninth pass: a WrapBox auto-flows its children into ONE shared
-- list layout — not a great structural fit for gauges that each need to
-- float independently above their own Pal's current screen position.
-- Canvas_Root (a CanvasPanel, whose children are each individually
-- positioned via their own CanvasPanelSlot) is structurally the better
-- fit for that job. The forty-eighth pass's own live test was also
-- inconclusive rather than a real negative: that whole session was only
-- ~95 seconds and the WrapBox never got a single child in that time — not
-- enough time to tell whether it's simply the wrong container or just
-- never got exercised. So this pass checks BOTH panel fields, using the
-- same real UPanelWidget:GetChildrenCount()/GetChildAt(Index), factored
-- into one function keyed by field name so either (or both) can be found
-- independently.
local MAX_PANEL_SCAN_LOGS = 60
local panelScanLogCount = 0
local panelState = {} -- fieldName -> { lastCount = number|nil, listedAtCount = number|nil }

-- Fiftieth pass fix: child[0] turning out to be the WrapBox itself (not a
-- Pal's gauge) is the exact failure mode this guards against — some
-- container classes are structural fixtures of the widget tree, always
-- present, not per-Pal content. Skip dumping these; the first child whose
-- class ISN'T one of these (and hasn't already been dumped) is almost
-- certainly real per-Pal (or per-entity) gauge content.
local KNOWN_CONTAINER_CLASSES = {
    WrapBox = true, CanvasPanel = true, HorizontalBox = true,
    VerticalBox = true, Overlay = true, ScrollBox = true,
    UniformGridPanel = true, GridPanel = true, SizeBox = true,
    Border = true, NamedSlot = true, WidgetSwitcher = true,
}
local dumpedClasses = {} -- className -> true, shared across fields so we don't re-dump the same real class twice

local function panel_scan_log(msg)
    if panelScanLogCount >= MAX_PANEL_SCAN_LOGS then return end
    panelScanLogCount = panelScanLogCount + 1
    Logger.log(msg)
    if panelScanLogCount == MAX_PANEL_SCAN_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-PANEL] reached the panel-scan log cap (" .. MAX_PANEL_SCAN_LOGS .. ") — going quiet")
    end
end

-- Fifty-first pass: WBP_PalNPCHPGauge_C turned out to be real and alive
-- after all (see file header) — the exact class the old reference mod
-- used, just never individually header-dumped before. Two things worth
-- reading off it specifically, beyond the generic property dump:
--   1. Its `WBP_EnemyGauge` sub-widget (an ObjectProperty, real, seen in
--      the generic dump) — the old mod wrote text into
--      `WBP_EnemyGauge.Text_WorkName`. Dump ITS fields too, since the
--      generic per-class dump only ever looks at direct panel children,
--      never a child's own sub-widget fields.
--   2. Its `SyncId` field (StructProperty, real, confirmed type
--      `/Script/Pal.PalInstanceID` — this project's own already-answered
--      Q5, the stable per-Pal GUID). The generic dump can only print a
--      struct property's type name, not its actual field values (structs
--      have no GetFullName() identity the way UObjects do) — so this
--      tries indexing directly into the struct value for its real
--      sub-fields (`DebugName`, `InstanceId`, `PlayerUId`), the same way
--      this project has successfully read fields off other small
--      hook-argument structs before (e.g. FPalDamageResult.Defender).
local hasInspectedGaugeWidget = false

-- Fifty-second pass: the fifty-first pass's naive `tostring(sync.InstanceId)`
-- just printed the nested FGuid struct wrapper's own generic identity
-- ("UScriptStruct: 0x...", not a real value) — an `FGuid` is itself a
-- plain `{ uint32 A, B, C, D }` struct, so it needs one more level of
-- indexing to get real numbers out, the same way `SyncId` itself needed
-- indexing off `WBP_PalNPCHPGauge_C`.
local function describe_guid(guid)
    if guid == nil then return "nil" end
    local ok, a, b, c, d = pcall(function() return guid.A, guid.B, guid.C, guid.D end)
    if ok then
        return string.format("%08X-%08X-%08X-%08X", a or 0, b or 0, c or 0, d or 0)
    end
    return "[unreadable]"
end

-- Fifty-ninth pass: DIAG-HANDLE confirmed the raw `bindedHandle`
-- property value (`handle:type()` = "TSoftObjectPtrUserdata") does not
-- support ANY of the accessors tried (GetFullName/LoadSynchronous/Get/
-- TryGetIndividualActor all FAILED, AssetPathName read nil) — a genuine
-- UE4SS Lua binding gap for this exact wrapped type, the same kind of
-- limitation already documented for MapProperty/DoubleProperty, not a
-- mistake in how it was called. Reading the STORED field after the fact
-- is a dead end with this build.
--
-- Real fix: `BindFromHandle(class UPalIndividualCharacterHandle*
-- targetHandle)` (confirmed real in the header dump, inherited from
-- `WBP_IndividualParameterBindWidget_C`) takes the handle as a plain HARD
-- pointer PARAMETER — a completely different, and much friendlier, shape
-- than the soft-pointer FIELD it presumably gets stored into afterward.
-- This project has always safely read hook arguments this way elsewhere
-- (Trust.lua/Interaction.lua's actor/param reads off hook params) — so
-- hooking this function directly and capturing `targetHandle` at the
-- moment of binding sidesteps the broken soft-pointer read entirely.
--
-- Registered ONCE (globally, keyed off whichever gauge widget's OWN class
-- path we happen to inspect first — `gaugeWidget:GetClass():GetPathName()`
-- gives the exact `/Game/...` Blueprint asset path this specific widget
-- class lives at, so the hook fires only for OUR gauge class, not every
-- individual-parameter-bound widget game-wide). Once registered, it
-- fires for every future BindFromHandle call on any WBP_PalNPCHPGauge_C
-- instance — including ones created after this point, which covers new
-- Pals encountered later in a session. Gauges that were already bound
-- BEFORE this hook was registered (the very first few found each
-- session) won't have a captured handle until their own widget gets
-- destroyed and recreated (which happens naturally as Pals leave/re-enter
-- view) — an acceptable gap, not worth a more invasive fix yet.
local hasRegisteredBindHook = false
local bindHookAttempts = 0
local MAX_BIND_HOOK_ATTEMPTS = 5 -- sixty-first pass: hard cap so a permanently-failing lookup can't spam RegisterHook forever (see below)
local gaugeHandleByKey = {} -- gauge fullName -> live UPalIndividualCharacterHandle captured from the hook

-- Sixty-second pass (2026-09-03): the sixty-first pass's hardcoded short
-- name ("WBP_IndividualParameterBindWidget_C:BindFromHandle") STILL failed
-- with the exact same "no UFunction with the specified name was found"
-- error, even though that's the function's real, confirmed declaring class
-- (from the header dump). That points at UE4SS's short-name RegisterHook
-- resolution simply not being reliable for Blueprint (/Game/...) classes at
-- all — unlike native /Script/ classes, which are globally unique and
-- exactly what short-name resolution is really meant for. The generally
-- correct, more reliable form for hooking a Blueprint function is the FULL
-- asset path (e.g. "/Game/.../WBP_IndividualParameterBindWidget.
-- WBP_IndividualParameterBindWidget_C:BindFromHandle"), which needs the
-- real UClass object's own `GetPathName()` — the exact call that failed
-- with "TrivialObject" when reached via `gaugeWidget:GetClass()`. The fix
-- isn't to give up on the full path, it's to reach the SAME class object a
-- different way: `FindAllOf("WidgetBlueprintGeneratedClass")` returns every
-- compiled Blueprint class as its own proper, fully-wrapped object (the
-- same kind of object this project's other `FindAllOf` calls already work
-- with fine) — a different route than `someInstance:GetClass()`, which
-- apparently hands back a more limited proxy in this Lua binding. Search
-- that list by name (`GetFName():ToString()`, proven reliable) for
-- "WBP_IndividualParameterBindWidget_C", then call `GetPathName()` on THAT
-- object instead. One-shot search, cached either way (found or not) so it
-- only runs once regardless of how many gauges are seen.
local hasSearchedBindWidgetClass = false
local bindWidgetClassPath = nil

local function find_bind_widget_class_path()
    if hasSearchedBindWidgetClass then return bindWidgetClassPath end
    hasSearchedBindWidgetClass = true

    local classes, classesErr = safe_call(function() return FindAllOf("WidgetBlueprintGeneratedClass") end)
    if not classes then
        Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] FindAllOf(WidgetBlueprintGeneratedClass) failed or returned nothing (caught, non-fatal): " .. tostring(classesErr) .. " -- will fall back to the hardcoded short class name")
        return nil
    end

    for _, cls in ipairs(classes) do
        local nameOk, name = pcall(function() return cls:GetFName():ToString() end)
        if nameOk and name == "WBP_IndividualParameterBindWidget_C" then
            local pathOk, path = pcall(function() return cls:GetPathName() end)
            if pathOk and path then
                bindWidgetClassPath = path
                Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] found the real class object via FindAllOf, full path = " .. path)
                return bindWidgetClassPath
            else
                Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] found the class object by name but GetPathName() still failed on it (caught, non-fatal): " .. tostring(path))
            end
        end
    end

    Logger.log("[PalBonds/Indicator] [DIAG-CLASSFIND] scanned " .. #classes .. " WidgetBlueprintGeneratedClass instances, none matched WBP_IndividualParameterBindWidget_C by name")
    return nil
end

-- Sixty-first pass (2026-09-03): Dragón's test showed heavy, escalating lag
-- with the sixtieth pass's build, and the bar was still stuck at 50%. Two
-- separate problems, both explained by the log:
--
-- (1) THE REAL FIX: every single attempt failed with "Tried to register a
-- hook with Lua function 'RegisterHook' but no UFunction with the specified
-- name was found" for "WBP_PalNPCHPGauge_C:BindFromHandle". A fresh look at
-- `CXXHeaderDump/WBP_IndividualParameterBindWidget.hpp` explains why:
-- `BindFromHandle` is declared on `UWBP_IndividualParameterBindWidget_C`
-- (the parent class), NOT on `WBP_PalNPCHPGauge_C` (the runtime instance's
-- own class, which has no header dump of its own — it's Blueprint-only and
-- only inherits the function). UE4SS's short-name `RegisterHook` path
-- resolution apparently needs the function's DECLARING class, not any
-- subclass that merely inherits it. Fix: try the known, hardcoded declaring
-- class name "WBP_IndividualParameterBindWidget_C:BindFromHandle" FIRST —
-- this doesn't depend on reading anything off the live widget at all, so it
-- can't fail from a "TrivialObject" class-object read either.
--
-- (2) THE LAG: the sixtieth pass's retry-forever fix (removing the
-- premature `hasRegisteredBindHook = true`) was correct in isolation, but
-- with EVERY attempt doomed to keep failing on the wrong class name, this
-- function was calling `RegisterHook` (twice per call) on EVERY tick for
-- EVERY currently-visible gauge, forever, with no cooldown — and a failing
-- `RegisterHook` lookup is not a cheap no-op internally. That's almost
-- certainly the whole cause of the reported lag, worsening as more wild
-- Pals came into view (more gauges = more failing attempts per tick). Fix:
-- a hard cap (`MAX_BIND_HOOK_ATTEMPTS`) on total attempt ROUNDS across the
-- whole session — once exhausted without success, give up permanently and
-- say so clearly in the log, instead of retrying indefinitely.
-- Sixty-fifth pass (2026-09-03): Dragón asked for a real, thorough look at
-- ALL the reference mods, not just the ones already in the same format as
-- this project. Doing that surfaced the actual answer, sitting in this
-- project's own reference material since before pass one: the bundled
-- `VisiblePalCaptureCounter/Scripts/main.lua` (a working, shipped UE4SS Lua
-- mod, not a guess) hooks this EXACT function successfully, with this
-- EXACT literal path:
--   "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle"
-- The format for a BLUEPRINT class hook is `<content-browser package
-- path>.<ClassName>:<FunctionName>` — a `.` between the package and the
-- class, not the `/Script/Module.Class:Function` shape this project's own
-- NATIVE hooks correctly use elsewhere (Trust.lua/Interaction.lua), and
-- not a bare short class name either. Every previous attempt (60th-62nd
-- passes) was missing the real package path entirely, or trying to
-- rediscover it programmatically instead of just using the known-correct
-- literal string a working mod already demonstrates. Its handler
-- (`function (self, handler) local targetHandle = handler:get() ... end`)
-- also confirms `:get()` on the hook's handle argument is exactly right,
-- and that the resulting handle supports `TryGetIndividualParameter()`
-- directly — exactly this project's own plan, now with real proof it
-- works on a hook-captured handle (unlike the stored soft-pointer field).
--
-- Same source also hooks `Unbind` on the same class — worth adding too:
-- gauge widgets are apparently POOLED/reused across different Pals (not
-- one permanent widget per Pal), so an entry in `gaugeHandleByKey`/
-- `trackedBars` keyed only by widget identity could otherwise go stale
-- once a widget gets rebound to a different Pal. Clearing the captured
-- handle on Unbind keeps a reused widget from briefly showing its
-- previous Pal's trust value.
-- Hundred-and-fifty-fifth pass (2026-09-04): REAL FIX for a genuine race
-- Dragón caught directly — a wild Pal's gauge (a samurai dog he could
-- see and even pet, for the whole session) never got a real actor
-- resolved for its trust bar/personality label, staying on the "?"
-- placeholder the entire time. Traced it to `register_bind_hook_once`
-- below only ever being CALLED from gauge-DISCOVERY code (this file's
-- periodic canvas scan, `scheduleScan`/`check_panel_children`) — meaning
-- the class-level BindFromHandle hook (which, once registered, catches
-- EVERY future call across ALL gauge instances, not just one) doesn't
-- actually get registered until the FIRST gauge is ever discovered by
-- that scan. Any gauge already on-screen and already bound before that
-- exact moment — very plausibly a Pal already visible right as the
-- session starts — permanently misses capture, with zero further chance
-- to ever resolve (BindFromHandle only fires once per bind, and this
-- project has no mechanism to re-trigger it).
--
-- The fix doesn't need to wait for a live gauge at all: the FIRST
-- candidate path below is already a hardcoded, PROVEN-real literal
-- string (confirmed via a real bundled reference mod, see the big
-- comment on register_bind_hook_once) — it needs no gauge instance to
-- compute. Registering just that one candidate here, unconditionally, at
-- Indicator.Init() time (called before this file's own scan ever runs),
-- closes almost the entire race window. register_bind_hook_once's
-- gauge-dependent fallback candidates stay in place below as a safety
-- net for a future game build where this literal path might change —
-- `hasRegisteredBindHook` being already true after a successful call
-- here makes that later call a clean no-op, not a duplicate registration.
-- Hundred-and-fifty-seventh pass (2026-09-04) FIX, REAL REGRESSION FOUND:
-- Dragón's very next test showed this one-shot attempt FAILING outright
-- at Init() — "no UFunction with the specified name was found" — because
-- moving registration this early meant the target Blueprint class itself
-- isn't loaded into memory yet at that exact moment (the same "class not
-- loaded yet" problem this project has hit and fixed with a bounded
-- retry loop many times before — Radial Menu, Worker Menu, Indicator
-- classes, EMOTE-WATCH). With no retry, this silently fell back to
-- exactly the same race register_bind_hook_once already had — the
-- previous pass's fix accomplished nothing in that specific test.
-- Applying the same already-proven fix here instead of a single attempt:
-- a short, bounded retry (1s cadence, well before most gauges are likely
-- to bind, unlike register_bind_hook_once's path which only ever gets
-- its first chance once a gauge is actually discovered by the scan).
local IMMEDIATE_BIND_HOOK_MAX_ROUNDS = 30
local IMMEDIATE_BIND_HOOK_RETRY_MS = 1000

local function register_bind_hook_immediate(round)
    round = round or 1
    if hasRegisteredBindHook then return end

    local hookPath = "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle"
    local hookOk, hookErr = pcall(function()
        RegisterHook(hookPath, function(Context, TargetHandle)
            local self = hook_get(Context)
            local handle = hook_get(TargetHandle)
            if self == nil or handle == nil then return end
            gaugeHandleByKey[describe_widget(self)] = handle
        end)
    end)
    if hookOk then
        Logger.log(string.format("[PalBonds/Indicator] [DIAG-HOOK] (immediate, round %d) RegisterHook(%s) = OK", round, hookPath))
        hasRegisteredBindHook = true

        local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
        local unbindOk, unbindErr = pcall(function()
            RegisterHook(unbindPath, function(Context)
                local self = hook_get(Context)
                if self == nil then return end
                gaugeHandleByKey[describe_widget(self)] = nil
            end)
        end)
        Logger.log("[PalBonds/Indicator] [DIAG-HOOK] (immediate) RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
        return
    end

    local errFirstLine = tostring(hookErr):match("^[^\n]*") or tostring(hookErr)
    if round >= IMMEDIATE_BIND_HOOK_MAX_ROUNDS then
        Logger.log(string.format("[PalBonds/Indicator] [DIAG-HOOK] (immediate) giving up after %d rounds — FAILED: %s. register_bind_hook_once's scan-triggered fallback is the only remaining path.", round, errFirstLine))
        return
    end
    Logger.log(string.format("[PalBonds/Indicator] [DIAG-HOOK] (immediate, round %d) RegisterHook(%s) = FAILED: %s — retrying", round, hookPath, errFirstLine))
    local rescheduleOk = pcall(function()
        ExecuteInGameThreadWithDelay(IMMEDIATE_BIND_HOOK_RETRY_MS, function()
            safe_call(function() register_bind_hook_immediate(round + 1) end)
        end)
    end)
    if not rescheduleOk then
        Logger.log("[PalBonds/Indicator] [DIAG-HOOK] (immediate) could not schedule a retry round — stopping after round " .. round)
    end
end

local function register_bind_hook_once(gaugeWidget)
    if hasRegisteredBindHook then return end
    if bindHookAttempts >= MAX_BIND_HOOK_ATTEMPTS then return end
    bindHookAttempts = bindHookAttempts + 1

    local candidates = {
        -- Sixty-fifth pass: the real, confirmed-working literal path, tried first.
        "/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle",
    }

    local fullClassPath = find_bind_widget_class_path()
    if fullClassPath then candidates[#candidates + 1] = fullClassPath .. ":BindFromHandle" end

    candidates[#candidates + 1] = "WBP_IndividualParameterBindWidget_C:BindFromHandle"

    local pathOk, classPath = pcall(function() return gaugeWidget:GetClass():GetPathName() end)
    local classNameOk, className = pcall(function() return gaugeWidget:GetClass():GetFName():ToString() end)
    if pathOk and classPath then candidates[#candidates + 1] = classPath .. ":BindFromHandle" end
    if classNameOk and className then candidates[#candidates + 1] = className .. ":BindFromHandle" end

    for _, hookPath in ipairs(candidates) do
        local hookOk, hookErr = pcall(function()
            RegisterHook(hookPath, function(Context, TargetHandle)
                local self = hook_get(Context)
                local handle = hook_get(TargetHandle)
                if self == nil or handle == nil then return end
                gaugeHandleByKey[describe_widget(self)] = handle
            end)
        end)
        Logger.log("[PalBonds/Indicator] [DIAG-HOOK] RegisterHook(" .. hookPath .. ") = " .. (hookOk and "OK" or ("FAILED: " .. tostring(hookErr))))
        if hookOk then
            hasRegisteredBindHook = true

            -- Also hook Unbind (same literal-path convention) so a reused
            -- gauge widget's stale captured handle gets cleared instead of
            -- briefly showing the wrong Pal's trust value.
            local unbindPath = hookPath:gsub(":BindFromHandle$", ":Unbind")
            local unbindOk, unbindErr = pcall(function()
                RegisterHook(unbindPath, function(Context)
                    local self = hook_get(Context)
                    if self == nil then return end
                    gaugeHandleByKey[describe_widget(self)] = nil
                end)
            end)
            Logger.log("[PalBonds/Indicator] [DIAG-HOOK] RegisterHook(" .. unbindPath .. ") = " .. (unbindOk and "OK" or ("FAILED (non-fatal, BindFromHandle hook still stands): " .. tostring(unbindErr))))
            return
        end
    end

    if bindHookAttempts >= MAX_BIND_HOOK_ATTEMPTS then
        Logger.log("[PalBonds/Indicator] [DIAG-HOOK] giving up after " .. MAX_BIND_HOOK_ATTEMPTS .. " attempt rounds — every candidate hook path failed every time, so retrying further would just waste performance for no benefit this session. See the DIAG-HOOK FAILED lines above for the exact errors.")
    end
end

-- Sixty-seventh pass (2026-09-03): Dragón's own hypothesis is that "prism"
-- names the light-beam animation shown on a successful capture, and asked
-- for a live "spy" — real hooks, not just static reading — to confirm or
-- identify it. `grep -rl "Prism" CXXHeaderDump/` found exactly three hits:
--   - BP_CapturePrism.hpp: `ABP_CapturePrism_C : ABP_ThrowWeaponBase_C`, a
--     real dumped Blueprint class. Its fields (`SK_Weapon_PalSphere_001`
--     mesh, `CaptureSphereType`) make clear this IS the Palsphere throw
--     weapon itself, not a beam effect on its own. Real functions:
--     `OnThrowInternal(AActor* Bullet)`, `GetCaptureLevel(int32&)`,
--     `OnEndShootAnimation(UAnimMontage*)`, `On Throw()`,
--     `DecrementBullet()`.
--   - BP_CapturePrismBullet.hpp: `ABP_CapturePrismBullet_C :
--     ABP_ThrowObjectBase_C`, the actual thrown projectile ("bullet").
--     Real fields: `CaptureTarget` (APalCharacter*), `isBound`. Real
--     functions: `SpawnCaptureObject(FGuid, AActor*)`, `OnHitToActor(...)`,
--     `IsDestroy(...)`, plus a per-frame `ReceiveTick`/`UpdateRotation`/
--     `ExecuteUbergraph` deliberately NOT hooked below (every per-frame
--     hook this project has ever added, e.g. `SelectResponseBySenses` in
--     the thirty-third pass, turned into log spam with no benefit).
--   - Engine.hpp: `ConstraintLimitMaterialPrismatic` — a physics
--     constraint's material property. Shares the substring "Prism" and
--     nothing else; ruled out, not a real lead.
--
-- Conclusion from the static read alone: "Prism" looks like this game's
-- own internal/legacy name for the Palsphere WEAPON + its thrown
-- PROJECTILE pair, not a separate light-beam effect by itself. But
-- `SpawnCaptureObject(FGuid, AActor*)` on the bullet is a strong, specific
-- candidate for where a capture-success visual (which could well be a
-- light beam) actually gets triggered — its signature (a Guid plus the
-- target Actor) fits "spawn whatever shows a successful capture" exactly.
--
-- This is the actual "spy": read-only hooks (nothing about capture
-- behavior changes) on the throw/hit/capture lifecycle functions of both
-- classes, so a real in-game capture attempt will show, in the live log,
-- the true firing order — settling this from real behavior instead of
-- guessing from names. Needs Dragón to actually attempt a capture while
-- this is running; nothing here can be confirmed without that live test.
local MAX_PRISM_LOGS = 60
local prismLogCount = 0

local function prism_log(msg)
    if prismLogCount >= MAX_PRISM_LOGS then return end
    prismLogCount = prismLogCount + 1
    Logger.log(msg)
    if prismLogCount == MAX_PRISM_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-PRISM] reached the prism-spy log cap (" .. MAX_PRISM_LOGS .. ") — going quiet")
    end
end

-- Seventy-first pass (2026-09-03): the seventieth pass's "fix" did NOT
-- fix it — Dragón's own console showed the exact same "TrivialObject"
-- error, just moved from a hook-Context object (sixty-second pass) to a
-- FindAllOf-returned instance: `instance:GetClass():GetPathName()` fails
-- identically either way. That's the THIRD distinct technique this
-- project has tried for getting a Blueprint class's real asset path from
-- Lua reflection — FindAllOf("WidgetBlueprintGeneratedClass"),
-- FindAllOf("BlueprintGeneratedClass"), and instance:GetClass() — and all
-- three are now confirmed dead in this UE4SS build, regardless of how the
-- class reference is obtained. Checked the web too (see
-- docs/hook-points.md) for a published literal path the way
-- BindFromHandle's and BP_OtomoPalHolderComponent's were found — nothing
-- surfaced for these two classes.
--
-- WORSE: the dead call was retrying every single 2s scan tick forever,
-- with its failure log NOT behind prism_log's cap — and with TWO live
-- BP_CapturePrism_C instances apparently existing at once (first/third
-- person view-model duplicates, most likely), that was 2 unthrottled,
-- flushed log lines roughly every 2 seconds, forever — real, ongoing spam
-- Dragón caught directly in the console. That regression is on me; it
-- should have been capped from the start.
--
-- Real fix: give up on RegisterHook for these two classes — there is no
-- known literal path, and every way to derive one from Lua reflection is
-- now exhausted. Pivot to the technique that's worked everywhere ELSE in
-- this project when no literal path is available: read fields directly
-- off the live instance FindAllOf already hands us. No path, no
-- RegisterHook, no :GetClass() call at all — just :IsValid(), a full-name
-- identity, and direct field reads, all of which have worked reliably
-- throughout this whole project. Logs a new instance's identity once
-- (existence/creation timing is itself useful — BP_CapturePrismBullet_C
-- in particular should only exist briefly, right around an actual throw)
-- and the bullet's CaptureTarget/isBound whenever they change, not every
-- tick.
local seenPrismInstances = {} -- fullName -> true, so a persistent instance (the weapon) doesn't re-log every tick
local prismBulletLastState = {} -- fullName -> "captureTarget|isBound" snapshot string, to log only on change

local function poll_prism_class(className, describeExtra)
    local instances = safe_call(function() return FindAllOf(className) end)
    if not instances then return end

    for _, inst in ipairs(instances) do
        local validOk, isValid = pcall(function() return inst:IsValid() end)
        if validOk and isValid then
            local fullName = describe_pal(inst)
            if not seenPrismInstances[fullName] then
                seenPrismInstances[fullName] = true
                prism_log("[PalBonds/Indicator] [DIAG-PRISM] new live " .. className .. " instance: " .. fullName)
            end
            if describeExtra then describeExtra(inst, fullName) end
        end
    end
end

local function poll_prism_bullet_state(inst, fullName)
    local targetOk, target = pcall(function() return inst.CaptureTarget end)
    local boundOk, isBound = pcall(function() return inst.isBound end)
    local targetDesc = (targetOk and target ~= nil and describe_pal(target)) or "nil"
    local state = targetDesc .. "|" .. tostring(boundOk and isBound)

    if prismBulletLastState[fullName] ~= state then
        prismBulletLastState[fullName] = state
        prism_log(string.format(
            "[PalBonds/Indicator] [DIAG-PRISM] %s state changed — CaptureTarget=%s isBound=%s",
            fullName, targetDesc, tostring(boundOk and isBound)
        ))
    end
end

local function poll_prism_state()
    poll_prism_class("BP_CapturePrism_C", nil)
    poll_prism_class("BP_CapturePrismBullet_C", poll_prism_bullet_state)
end

-- Sixty-eighth pass (2026-09-03): Dragón reported the game feeling
-- "kind of laggy" and reasonably guessed it was the new prism spy hooks.
-- Checked the actual live log instead of assuming: the prism spies only
-- ever logged 3-4 lines total and failed instantly (see below) — cheap,
-- not the cause. The REAL, log-confirmed cause was sitting right here:
-- this function's fifty-first/fifty-second/fifty-third-pass property
-- dumps and test write, which fully re-run every single game session
-- (gated only by a one-shot flag, not by "has this already been
-- answered") and produced 507 DIAG-DUMP lines in an 8-second window this
-- session (18:02:10-18:02:18) — each one a synchronous, flushed disk
-- write (Logger.lua flushes every line by design, for crash safety). That
-- is real, measurable overhead concentrated in a single burst, and a very
-- plausible source of a felt stutter. The research these dumps were for
-- (does WBP_EnemyGauge/Text_WorkName/SyncId look the way the old
-- reference mod expected) was fully answered back in the fifty-first
-- through fifty-third passes and made moot entirely once Dragón's
-- course-correction repointed this whole effort at a real progress bar
-- instead of text — so none of it needs to keep running. Stripped down to
-- just the one call that's still load-bearing: registering the bind hook.
local function inspect_gauge_widget(gaugeWidget)
    register_bind_hook_once(gaugeWidget)
end

-- Fifty-fifth pass (2026-09-03): the fifty-fourth pass's test came back
-- with every single logged step OK, and Dragón confirmed a real magenta
-- bar rendered on the one Chikipi tested — runtime widget creation is
-- CONFIRMED working in this build. Two real gaps in that first version,
-- exactly matching what Dragón observed:
--   1. It only ever ran once per session (a single global one-shot flag),
--      so only the very first gauge widget the scan ever saw got a bar —
--      Dragón correctly guessed this was the nearest wild Pal at spawn.
--      Fixed here: gating is now keyed per-gauge (by its own GetFullName,
--      which is unique to that specific live instance) via a small table,
--      so every distinct gauge widget gets its own bar exactly once,
--      instead of the whole feature running only once ever. Also moved
--      the call site out of inspect_gauge_widget (which stays its own,
--      separate one-shot deep-dump, to keep log volume down) and into
--      check_panel_children's own per-child loop, unconditionally, so it
--      runs for every gauge child seen, not just whichever one happened
--      to trigger the diagnostic dump.
--   2. Position (0,25) and size (80,6) were blind, arbitrary guesses
--      relative to Canvas_Innner's own coordinate space, made without
--      ever reading anything real to compare against — which is exactly
--      why Dragón saw it "not rightly aligned". Fixed here: read the
--      REAL HP bar's own slot (`WBP_EnemyGauge.ProgressBar_HP.Slot`,
--      inherited from UWidget, a UCanvasPanelSlot since ProgressBar_HP
--      lives in this same kind of canvas) via its own
--      GetPosition()/GetSize(), and place the new bar directly under it
--      (same X/width, Y offset by the real bar's own height + a small
--      gap) instead of a guessed absolute position. Falls back to the
--      old blind guess, clearly logged as a fallback, if any of that
--      read fails.
--
-- Still NOT wired to real FriendshipPoint yet — SetPercent(0.5) and the
-- magenta test color are both still static placeholders, deliberately
-- kept obvious/fake-looking rather than switched to a "real-looking"
-- color, so it stays visually clear this isn't live data yet. Dragón's
-- own observation that "it never moved, stayed at the same half-full
-- look" through the whole capture is the expected, correct behavior of
-- this version — nothing in this pass or the last one calls SetPercent
-- more than once. Wiring a live value needs the still-unresolved
-- gauge-to-Pal matching problem solved first (SyncId's GUIDs still read
-- all-zero; Dragón's own suggested `bindedHandle` lead is still unread) —
-- that's the next real blocker, not this pass's job.
--
-- FIFTY-FIFTH PASS RESULT (2026-09-03): every gauge got its own bar this
-- time (one DIAG-CREATE sequence per Pal in the log, all succeeding), so
-- the per-gauge fix worked. But the screenshot Dragon sent still showed
-- the bar shifted right and visibly WIDER than the real HP bar, not just
-- off vertically. See the FIFTY-SIXTH PASS comment inside
-- install_trust_bar below for the real cause and fix.
local barInstalledForGauge = {} -- fullName -> true, so each distinct live gauge only gets a bar once
local trackedBars = {} -- fullName -> { bar = UProgressBar, actor = APalCharacter }, for periodic real-value refresh

-- FIFTY-SIXTH PASS RESULT (2026-09-03): Dragón confirmed the bar now
-- lines up correctly under the real HP bar. Proceeding to the next part:
-- wiring the bar to the REAL FriendshipPoint instead of the fixed 50%
-- placeholder.
--
-- FIFTY-SEVENTH PASS (2026-09-03): this needs solving the still-open
-- problem — which of this mod's own tracked Pals does a given gauge
-- widget belong to? `bindedHandle` (inherited from
-- WBP_IndividualParameterBindWidget_C) is declared as
-- `TSoftObjectPtr<UPalIndividualCharacterHandle>` (confirmed in the
-- header dump) — this project's `dump_all_properties` never handled
-- SoftObjectProperty, which is why every earlier dump just printed
-- "(not read)" for it. A fresh grep of `Pal.hpp` found what
-- `UPalIndividualCharacterHandle` actually offers once resolved, and it's
-- exactly what's needed:
--   - `TryGetIndividualActor() -> APalCharacter*` — the real, live Pal
--     actor.
--   - `TryGetIndividualParameter() -> UPalIndividualCharacterParameter*`
--     — the SAME kind of object Interaction.lua/Trust.lua already read
--     `GetFriendshipPoint()`/`GetFriendshipRank()` from, just reached via
--     a different starting point.
--
-- The one open unknown was how to get from the raw `bindedHandle`
-- PROPERTY VALUE to a live, callable handle object — no bundled UE4SS Lua
-- mod in this install actually resolves a TSoftObjectPtr at runtime
-- (checked; only EmmyLua type annotations exist, no real usage example).
-- Rather than guess blind, `resolve_pal_actor_from_gauge` below tries the
-- simplest possibility first — the raw property value already behaves
-- like a usable object, since this points at a live gameplay object
-- already in memory, not an on-disk asset needing a load — and logs
-- exactly what happens either way, so even a failure here is a useful,
-- honest result for the next pass.
-- Fifty-seventh pass RESULT: Dragón's test came back with bars still
-- stuck at the 50% placeholder. The log explains exactly why —
-- `handle:IsValid()` itself errored: "attempt to call a nil value
-- (method 'IsValid')". That specific error means `handle` (the raw
-- `bindedHandle` property value) is NOT nil and IS indexable, it just has
-- no `IsValid` method — i.e. it isn't a normal live-UObject wrapper the
-- way every other object this project has ever touched has been. The
-- guess that a TSoftObjectPtr to a live gameplay object would behave like
-- a plain object handle was wrong, or at least incomplete.
--
-- FIFTY-EIGHTH PASS (2026-09-03): rather than guess again, added
-- `inspect_bindedHandle_shape` — a one-shot, fully read-only probe that
-- tries a wide net of plausible accessors (`type()`, `tostring()`, a
-- generic `:type()` method this project has seen used elsewhere in a
-- bundled mod, `GetFullName()`, `LoadSynchronous()` — the standard
-- Blueprint node for resolving a soft pointer, `Get()`, and reading
-- `AssetPathName` directly as if it's a plain `FSoftObjectPath`) and logs
-- each one's real result under DIAG-HANDLE, so the next test tells us the
-- actual shape instead of another blind guess. `resolve_pal_actor_from_gauge`
-- itself now also stops gating on the broken `IsValid()` call — it tries
-- `TryGetIndividualActor()` directly first (skipping the check that was
-- erroring), then falls back to trying `LoadSynchronous()` first in case
-- the raw property value needs an explicit resolve step before the real
-- handle methods become callable.
local hasInspectedBindedHandle = false

local function inspect_bindedHandle_shape(handle)
    if hasInspectedBindedHandle then return end
    hasInspectedBindedHandle = true

    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] inspecting raw bindedHandle shape (one-shot) — lua type=" .. type(handle))

    local tostringOk, str = pcall(function() return tostring(handle) end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] tostring(handle) = " .. (tostringOk and tostring(str) or "FAILED"))

    local typeMethodOk, typeMethodResult = pcall(function() return handle:type() end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle:type() = " .. (typeMethodOk and tostring(typeMethodResult) or "FAILED (no :type() method)"))

    local getFullNameOk, fullName = pcall(function() return handle:GetFullName() end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle:GetFullName() = " .. (getFullNameOk and tostring(fullName) or "FAILED"))

    local loadSyncOk, loaded = pcall(function() return handle:LoadSynchronous() end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle:LoadSynchronous() = " .. (loadSyncOk and tostring(loaded) or "FAILED"))

    local getOk, got = pcall(function() return handle:Get() end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle:Get() = " .. (getOk and tostring(got) or "FAILED"))

    local directActorOk, directActor = pcall(function() return handle:TryGetIndividualActor() end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle:TryGetIndividualActor() (direct) = " .. (directActorOk and tostring(directActor) or "FAILED"))

    local pathOk, pathVal = pcall(function() return handle.AssetPathName end)
    Logger.log("[PalBonds/Indicator] [DIAG-HANDLE] handle.AssetPathName = " .. (pathOk and tostring(pathVal) or "FAILED"))
end

local function resolve_pal_actor_from_gauge(gaugeWidget)
    -- Fifty-ninth pass: try the hook-captured HARD handle first — see
    -- register_bind_hook_once's comment for why this is the real fix,
    -- now that DIAG-HANDLE confirmed the stored soft-pointer FIELD is a
    -- dead end in this UE4SS Lua build.
    local key = describe_widget(gaugeWidget)
    local hookedHandle = gaugeHandleByKey[key]
    if hookedHandle ~= nil then
        local validOk, valid = pcall(function() return hookedHandle:IsValid() end)
        if validOk and valid then
            local actorOk, actor = pcall(function() return hookedHandle:TryGetIndividualActor() end)
            if actorOk and actor ~= nil then
                local actorValidOk, actorValid = pcall(function() return actor:IsValid() end)
                if actorValidOk and actorValid then return actor, nil end
            end
        end
    end

    -- Fall back to the stored bindedHandle field, kept only as a
    -- diagnostic path — DIAG-HANDLE showed this route consistently fails
    -- in this build (the raw value has no working IsValid/GetFullName/
    -- LoadSynchronous/Get/TryGetIndividualActor/AssetPathName), so this
    -- almost never succeeds, but costs nothing to still try.
    local handleOk, handle = pcall(function() return gaugeWidget.bindedHandle end)
    if not (handleOk and handle ~= nil) then
        return nil, "no hooked handle yet, and bindedHandle unreadable: " .. tostring(handle)
    end

    inspect_bindedHandle_shape(handle)

    local directOk, actor = pcall(function() return handle:TryGetIndividualActor() end)
    if directOk and actor ~= nil then
        local validOk, valid = pcall(function() return actor:IsValid() end)
        if validOk and valid then return actor, nil end
    end

    local loadOk, resolved = pcall(function() return handle:LoadSynchronous() end)
    if loadOk and resolved ~= nil then
        local actorOk2, actor2 = pcall(function() return resolved:TryGetIndividualActor() end)
        if actorOk2 and actor2 ~= nil then
            local validOk2, valid2 = pcall(function() return actor2:IsValid() end)
            if validOk2 and valid2 then return actor2, nil end
        end
    end

    return nil, "no hooked handle for this gauge yet (bound before the hook was registered), and the stored bindedHandle field doesn't resolve in this build — see DIAG-HANDLE log"
end

-- Reuses this project's own already-proven route to the friendship value
-- (Interaction.lua's get_individual_parameter: actor.CharacterParameterComponent
-- :GetIndividualParameter()), just starting from an actor resolved via the
-- gauge's bindedHandle instead of a targeted/interacted-with Pal.
local function get_friendship_ratio(actor)
    local paramOk, param = pcall(function()
        local comp = actor.CharacterParameterComponent
        if comp ~= nil and comp:IsValid() then
            return comp:GetIndividualParameter()
        end
        return nil
    end)
    if not (paramOk and param ~= nil and param:IsValid()) then
        return nil, "no readable CharacterParameterComponent/IndividualParameter"
    end

    local pointOk, point = pcall(function() return param:GetFriendshipPoint() end)
    if not (pointOk and point ~= nil) then
        return nil, "GetFriendshipPoint() failed"
    end

    local cap = Trust.CAPTURE_AT_FRIENDSHIP_POINT or 55
    local ratio = point / cap
    if ratio > 1 then ratio = 1 end
    if ratio < 0 then ratio = 0 end
    return ratio, nil
end

-- Sixty-sixth pass (2026-09-03): Dragón asked to stylize the trust bar,
-- specifically a color gradient from white-pinkish (empty) to red (full)
-- as trust rises — replacing both the magenta creation-time placeholder
-- and the never-updated fill color. `UProgressBar:SetFillColorAndOpacity`
-- is a real, already-used call (the magenta placeholder itself proves it
-- works); this just computes a real color instead of a fixed one. Kept as
-- a plain linear interpolation per channel (R/G/B), no extra libraries
-- needed. Real visual-styling options exposed to Lua turned out to be
-- narrow — `UProgressBar`'s own header dump (CXXHeaderDump/UMG.hpp) only
-- exposes `SetPercent`, `SetIsMarquee`, and `SetFillColorAndOpacity` as
-- callable functions; the brush/border imagery live inside `WidgetStyle`
-- (an `FProgressBarStyle` struct holding `FSlateBrush` images), which
-- isn't something safe to construct from scratch via Lua — so the color
-- gradient is the real, deliverable piece of "more design" available
-- here without risking a broken/invisible bar.
-- Sixty-ninth pass (2026-09-03): Dragón tested the white-pink -> red
-- gradient live and it "didn't convince at all" — not readable/distinct
-- enough in practice. First follow-up: a bronze->gold gradient instead.
--
-- Seventy-second pass (2026-09-03): Dragón liked the gold better but
-- asked to drop the gradient entirely — one flat, solid gold color,
-- regardless of ratio. `ratio` is kept as a parameter (harmless, ignored)
-- rather than changing every call site, since the fill LENGTH already
-- shows progress via SetPercent; the color no longer needs to.
local function compute_trust_bar_color(ratio)
    return { R = 1.00, G = 0.84, B = 0.00, A = 1 }
end

-- Hundred-and-eightieth pass (2026-09-05): Dragón asked to try the
-- technique found while reading the "Pal Analyzer" reference mod's
-- extracted Blueprint strings — it keeps its own Pal-actor-keyed map
-- (Map_Add/Map_Find/Map_Keys/Map_Values, confirmed in its strings) and
-- reuses one widget per Pal, rather than rebuilding whenever the
-- underlying gauge changes. A real log breakdown (previous pass) showed
-- 315 full StaticConstructObject+AddChildToCanvas builds in a 3-minute
-- busy-base session — far more than the number of actually-distinct
-- Pals near a base, confirming the game's own gauge-widget pool
-- genuinely recycles/rebinds the SAME small set of widgets across
-- DIFFERENT Pals over time (matches the sixty-fifth pass's own finding,
-- "gauge widgets are apparently POOLED/reused"), and every single
-- recycle was paying full construction cost again even for a Pal this
-- mod was already tracking.
--
-- This moves an ALREADY-BUILT bar+label onto a NEW gauge widget's real
-- parent panel instead of building new ones — `UPanelWidget:RemoveChild`
-- confirmed real in this game's own UMG.hpp (same header this file
-- already trusts for AddChildToCanvas/GetChildrenCount/GetChildAt). The
-- widget OBJECTS themselves persist; only their panel membership and
-- position change, skipping StaticConstructObject/StaticFindObject/the
-- label-class lookup entirely. First attempt at moving an already-added
-- widget between different parent panels in this project — wrapped in
-- the same per-step pcall discipline as every other untested operation
-- here, with a full-construction fallback if any step fails.
local function reparent_existing_bar(entry, newGaugeWidget)
    local barOk, barValid = pcall(function() return entry.bar:IsValid() end)
    if not (barOk and barValid) then return false end

    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = newGaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)

    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
    else
        local innerOk, innerCanvas = pcall(function() return newGaugeWidget.Canvas_Innner end)
        if innerOk and innerCanvas ~= nil and innerCanvas:IsValid() then
            targetPanel = innerCanvas
        else
            return false
        end
    end

    pcall(function()
        local oldParent = entry.bar.Slot and entry.bar.Slot.Parent
        if oldParent ~= nil and oldParent:IsValid() then
            oldParent:RemoveChild(entry.bar)
        end
    end)
    local addOk, newSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.bar) end)
    if not (addOk and newSlot ~= nil and newSlot:IsValid()) then return false end

    local newY = (refY or 0) + (refH or 6) + 2
    pcall(function() newSlot:SetPosition({X = refX or 0, Y = newY}) end)
    pcall(function() newSlot:SetSize({X = refW or 80, Y = 6}) end)

    if entry.label ~= nil then
        local labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
        if labelOk and labelValid then
            pcall(function()
                local oldLabelParent = entry.label.Slot and entry.label.Slot.Parent
                if oldLabelParent ~= nil and oldLabelParent:IsValid() then
                    oldLabelParent:RemoveChild(entry.label)
                end
            end)
            local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(entry.label) end)
            if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
                pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + 12}) end)
                pcall(function() labelSlot:SetSize({X = refW or 80, Y = 14}) end)
            end
        end
    end

    entry.gaugeWidget = newGaugeWidget
    entry.targetPanel = targetPanel
    return true
end

local function install_trust_bar(gaugeWidget)
    local key = describe_widget(gaugeWidget)
    if barInstalledForGauge[key] then return end
    barInstalledForGauge[key] = true

    -- Hundred-and-eightieth pass: try resolving this gauge's real Pal
    -- BEFORE building anything. If this exact Pal already has a live
    -- tracked bar (from a different, now-stale gauge widget the game
    -- already recycled away from), reuse it via reparent_existing_bar
    -- instead of paying full construction cost again. Falls through to
    -- the normal build path below if resolution fails (typical
    -- BindFromHandle race — the same retry mechanism in update_trust_bars
    -- covers that, unchanged) or if reparenting itself fails for any
    -- reason.
    local earlyActor = resolve_pal_actor_from_gauge(gaugeWidget)
    local earlyPalId = earlyActor and safe_call(Personality.GetStableId, earlyActor)
    if earlyPalId and trackedBars[earlyPalId] then
        local reused = reparent_existing_bar(trackedBars[earlyPalId], gaugeWidget)
        if reused then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] REUSED existing bar for already-tracked Pal " .. describe_pal(earlyActor) .. " on recycled gauge " .. key .. " (no new widgets built)")
            return
        end
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] reparent attempt failed for already-tracked Pal " .. describe_pal(earlyActor) .. " — falling back to full construction")
    end

    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] attempting to construct a brand-new UProgressBar widget for gauge: " .. key)

    -- Fifty-sixth pass: the fifty-fifth pass's numbers came back IDENTICAL
    -- across every single Pal (pos=64,26 size=120,4, every time) — that's
    -- correct and expected (it's the Blueprint's own static per-widget
    -- design-space layout, same for every instance of the same class,
    -- with the whole gauge's own screen position handled at a higher
    -- level). But Dragón's screenshot still showed the new bar shifted
    -- right AND noticeably wider than the real HP bar — not just off
    -- vertically. That's the signature of a COORDINATE-SPACE mismatch,
    -- not a wrong offset: the fifty-fifth pass added the new bar into
    -- `Canvas_Innner` (a guess) while reading position numbers that are
    -- only meaningful relative to whatever panel `ProgressBar_HP` ACTUALLY
    -- lives in — if that's a different panel than Canvas_Innner (nested
    -- canvases each have their own local coordinate space), the same raw
    -- numbers land somewhere else entirely.
    --
    -- Real fix: `UPanelSlot` has a real `Parent` field (UMG.hpp) pointing
    -- to the exact live UPanelWidget a widget is already a child of. Read
    -- `ProgressBar_HP.Slot.Parent` and add the new bar into THAT SAME
    -- panel object, instead of guessing Canvas_Innner — guaranteeing
    -- identical coordinate space, so the real bar's own position/size
    -- numbers apply directly with no translation needed. This is also
    -- what Dragón suggested independently ("copy the healthbar
    -- positioning" ) — same idea, just anchored to the real parent panel
    -- so the copy actually lands in the same space instead of a
    -- differently-scaled sibling.
    local refOk, realParent, refX, refY, refW, refH = pcall(function()
        local hpSlot = gaugeWidget.WBP_EnemyGauge.ProgressBar_HP.Slot
        local pos = hpSlot:GetPosition()
        local size = hpSlot:GetSize()
        return hpSlot.Parent, pos.X, pos.Y, size.X, size.Y
    end)

    local targetPanel
    if refOk and realParent ~= nil and realParent:IsValid() then
        targetPanel = realParent
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-CREATE] using ProgressBar_HP's REAL parent panel (%s) — pos=(%s,%s) size=(%s,%s)",
            describe_widget(realParent), tostring(refX), tostring(refY), tostring(refW), tostring(refH)
        ))
    else
        local innerOk, innerCanvas = pcall(function() return gaugeWidget.Canvas_Innner end)
        if not (innerOk and innerCanvas ~= nil and innerCanvas:IsValid()) then
            Logger.log("[PalBonds/Indicator] [DIAG-CREATE] neither ProgressBar_HP's real parent nor Canvas_Innner is readable — cannot proceed: " .. tostring(refX))
            return
        end
        targetPanel = innerCanvas
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] could not read ProgressBar_HP's real parent (caught, non-fatal) — falling back to Canvas_Innner as a guess: " .. tostring(refX))
    end

    local classOk, progressBarClass = pcall(function() return StaticFindObject("/Script/UMG.ProgressBar") end)
    if not (classOk and progressBarClass ~= nil and progressBarClass:IsValid()) then
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticFindObject('/Script/UMG.ProgressBar') failed: " .. tostring(progressBarClass))
        return
    end

    local constructOk, newBar = pcall(function()
        return StaticConstructObject(progressBarClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
    end)
    if not (constructOk and newBar ~= nil and newBar:IsValid()) then
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] StaticConstructObject FAILED (caught, non-fatal): " .. tostring(newBar))
        return
    end

    pcall(function() newBar:SetPercent(0.0) end) -- sixty-sixth pass: starts empty now that the real value resolves almost immediately below/on the next tick, instead of the old 50% guess
    pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(0)) end) -- sixty-sixth pass: real white-pink "empty" color instead of the placeholder magenta
    pcall(function() newBar:SetVisibility(0) end)

    local addOk, slot = pcall(function() return targetPanel:AddChildToCanvas(newBar) end)
    if not (addOk and slot ~= nil and slot:IsValid()) then
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas FAILED (caught, non-fatal) — bar exists but is not in the widget tree, so it cannot render: " .. tostring(slot))
        return
    end
    Logger.log("[PalBonds/Indicator] [DIAG-CREATE] AddChildToCanvas SUCCEEDED — new bar is now a real child of the same panel ProgressBar_HP lives in")

    if refOk then
        -- Same coordinate space now, so the real bar's own numbers apply
        -- directly — just offset Y down by its own height plus a small
        -- gap, same idea Dragón suggested (copy position, push down).
        local newY = (refY or 0) + (refH or 6) + 2
        local posOk = pcall(function() slot:SetPosition({X = refX or 0, Y = newY}) end)
        local sizeOk = pcall(function() slot:SetSize({X = refW or 80, Y = 6}) end)
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-CREATE] SetPosition(%s,%s)=%s SetSize(%s,6)=%s",
            tostring(refX or 0), tostring(newY), posOk and "OK" or "FAILED",
            tostring(refW or 80), sizeOk and "OK" or "FAILED"
        ))
    else
        pcall(function() slot:SetPosition({X = 0, Y = 25}) end)
        pcall(function() slot:SetSize({X = 80, Y = 6}) end)
        Logger.log("[PalBonds/Indicator] [DIAG-CREATE] using blind fallback position/size (0,25)/(80,6) since real geometry wasn't readable")
    end

    -- Fifty-seventh pass: try to wire the REAL FriendshipPoint right away.
    -- Fifty-ninth pass: `BindFromHandle` (captured via the hook above)
    -- may not have fired for THIS gauge yet at the exact moment its bar
    -- is created — binding and gauge-discovery aren't guaranteed to
    -- happen in a fixed order relative to each other. So every installed
    -- bar (resolved or not) is remembered in `trackedBars`, along with
    -- its own `gaugeWidget`, and `update_trust_bars()` below RETRIES
    -- resolution each tick for any entry that hasn't resolved yet —
    -- instead of the fifty-seventh pass's one-shot-at-creation-only
    -- attempt, which could never recover from an early miss.
    -- Hundred-and-eightieth pass: reuse earlyActor (resolved at the top
    -- of this function for the reparent-reuse check) instead of calling
    -- resolve_pal_actor_from_gauge a second time for the same gauge.
    local actor, actorErr = earlyActor, nil
    if actor == nil then
        actor, actorErr = resolve_pal_actor_from_gauge(gaugeWidget)
    end
    if actor then
        local ratio, ratioErr = get_friendship_ratio(actor)
        if ratio then
            pcall(function() newBar:SetPercent(ratio) end)
            pcall(function() newBar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
        end
        Logger.log(string.format(
            "[PalBonds/Indicator] [DIAG-TRUST] resolved real Pal actor for this gauge on first try — initial ratio=%s (%s)",
            ratio and string.format("%.2f", ratio) or "unreadable", describe_pal(actor)
        ))
    else
        Logger.log("[PalBonds/Indicator] [DIAG-TRUST] no real Pal actor yet (caught, non-fatal), will keep retrying each tick: " .. tostring(actorErr))
    end

    -- ---------------------------------------------------------------------
    -- TEMPORARY DEBUG FEATURE (hundred-and-fiftieth pass, 2026-09-04) —
    -- Dragón's request, to compare a wild Pal's rolled personality tier
    -- against its real observed in-game behavior while testing/balancing
    -- the weighted roll. Explicitly meant to be removed later once the
    -- rolls are confirmed working and the good/evil ratio is tuned — this
    -- whole block (here and its counterpart in update_trust_bars below)
    -- is self-contained and safe to delete as a unit when that day comes.
    -- Reuses the exact same widget-construction technique already proven
    -- above for the trust bar itself (StaticFindObject the native UMG
    -- class, StaticConstructObject into the same real parent panel,
    -- AddChildToCanvas, position relative to the trust bar's own real
    -- coordinates) — the only new parts are the widget class (TextBlock
    -- instead of ProgressBar) and setting its text, both first attempts
    -- for this project, wrapped safely and logged honestly per this
    -- file's own established discipline (nothing in this file has ever
    -- worked on the very first try).
    -- Hundred-and-fifty-first/second passes (2026-09-04): this block
    -- caused a real crash on its first live test — root cause found via
    -- [CRASH-DIAG] before/after bracketing (a raw `.Text = string`
    -- property write into an FText field) and fixed by constructing the
    -- game's own real text-widget class (`BP_PalTextBlock_C`, pulled off
    -- an already-live `Text_WorkName` instance on this same gauge) and
    -- writing via the confirmed-safe `SetText_GDKInternal` method
    -- instead. Confirmed crash-free in Dragón's next real test.
    --
    -- Hundred-and-fifty-fourth pass (2026-09-04) FIX, REAL LAG FOUND:
    -- that same [CRASH-DIAG] bracketing was left in AFTER the crash was
    -- already found and fixed — Dragón felt real lag on the very next
    -- test, and the log showed why: [CRASH-DIAG] alone was 516 of 981
    -- Indicator lines in a 140-second session (over half), each one a
    -- forced synchronous disk write (Logger.lua's own crash-safety
    -- design). Exact same self-inflicted-logging lag shape this project
    -- has hit and fixed before (INDICATOR-WATCH, ninety-eighth pass) —
    -- diagnostic bracketing is meant to be temporary, trimmed once the
    -- specific bug it was hunting is confirmed fixed, not left running
    -- forever. Removed here; kept only the one line that reports the
    -- real outcome (OK/FAILED), matching every other one-shot creation
    -- log elsewhere in this function.
    local newLabel = nil
    local labelClassOk, labelClass = pcall(function() return gaugeWidget.WBP_EnemyGauge.Text_WorkName:GetClass() end)
    if labelClassOk and labelClass ~= nil and labelClass:IsValid() then
        local labelConstructOk, labelObj = pcall(function()
            return StaticConstructObject(labelClass, targetPanel, 0, 0, 0x0E000000, false, false, nil, nil, nil)
        end)
        if labelConstructOk and labelObj ~= nil and labelObj:IsValid() then
            local labelAddOk, labelSlot = pcall(function() return targetPanel:AddChildToCanvas(labelObj) end)
            if labelAddOk and labelSlot ~= nil and labelSlot:IsValid() then
                if refOk then
                    pcall(function() labelSlot:SetPosition({X = refX or 0, Y = (refY or 0) + (refH or 6) + 12}) end)
                    pcall(function() labelSlot:SetSize({X = refW or 80, Y = 14}) end)
                else
                    pcall(function() labelSlot:SetPosition({X = 0, Y = 35}) end)
                    pcall(function() labelSlot:SetSize({X = 80, Y = 14}) end)
                end
                pcall(function() labelObj:SetVisibility(0) end)
                local setTextOk, setTextErr = pcall(function() labelObj:SetText_GDKInternal(true, "?") end)
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] personality label created and positioned — initial text write = " .. (setTextOk and "OK" or ("FAILED: " .. tostring(setTextErr))))
                newLabel = labelObj
            else
                Logger.log("[PalBonds/Indicator] [DIAG-LABEL] AddChildToCanvas FAILED for personality label: " .. tostring(labelSlot))
            end
        else
            Logger.log("[PalBonds/Indicator] [DIAG-LABEL] StaticConstructObject FAILED for personality label: " .. tostring(labelObj))
        end
    else
        Logger.log("[PalBonds/Indicator] [DIAG-LABEL] could not read Text_WorkName's real class FAILED: " .. tostring(labelClass))
    end

    -- Hundred-and-eightieth pass: store under the real Pal ID when
    -- already known at this point (either from earlyPalId above, or
    -- resolved fresh in `actor`/get_friendship_ratio just above) rather
    -- than the gauge's own temporary identity — that's what lets a LATER
    -- gauge recycle for this same Pal find and reuse this entry via
    -- reparent_existing_bar instead of building yet another one. Falls
    -- back to the gauge-widget key (old behavior) when the Pal still
    -- isn't resolvable yet; update_trust_bars promotes it to the real
    -- key once resolution succeeds on a later retry.
    local resolvedPalId = earlyPalId or (actor and safe_call(Personality.GetStableId, actor))
    local trackKey = resolvedPalId or key
    trackedBars[trackKey] = { bar = newBar, gaugeWidget = gaugeWidget, actor = actor, label = newLabel, palId = resolvedPalId }
end

-- Fifty-seventh pass: periodic refresh for every installed bar — re-reads
-- the live FriendshipPoint and updates the bar's fill every scan tick, so
-- it actually moves as trust changes (petting, damage, passive gain,
-- capture) instead of staying frozen like the fifty-fourth/fifty-fifth
-- passes' static test value.
--
-- Fifty-ninth pass: also RETRIES actor resolution every tick for any
-- entry that hasn't resolved yet (see install_trust_bar's comment above
-- for why a single attempt at creation time isn't enough), so a gauge
-- whose BindFromHandle hook fires slightly after its bar was created
-- still ends up wired to real data instead of being stuck at the
-- placeholder for the rest of its life. Drops any entry whose bar or
-- gaugeWidget has gone invalid (Pal despawned/left range, or the gauge
-- widget itself was destroyed) rather than erroring on it.
local function update_trust_bars()
    -- Hundred-and-eightieth pass: promotions (moving an entry from its
    -- temporary gauge-widget key to its real Pal-ID key once resolution
    -- succeeds) are collected here and applied AFTER the loop below —
    -- Lua's `pairs()` doesn't allow inserting a NEW key into a table
    -- while traversing it (removing/nil-ing an EXISTING key, as already
    -- done below, is explicitly fine; adding one is not).
    local promotions = {}

    for key, entry in pairs(trackedBars) do
        local barOk, barValid = pcall(function() return entry.bar:IsValid() end)
        local gaugeOk, gaugeValid = pcall(function() return entry.gaugeWidget:IsValid() end)
        if not (barOk and barValid and gaugeOk and gaugeValid) then
            trackedBars[key] = nil
        else
            if entry.actor == nil then
                local actor = resolve_pal_actor_from_gauge(entry.gaugeWidget)
                if actor then
                    entry.actor = actor
                    Logger.log("[PalBonds/Indicator] [DIAG-TRUST] resolved a real Pal actor on a retry for a previously-unresolved gauge: " .. describe_pal(actor))

                    -- This entry may still be keyed by its gauge widget's
                    -- own temporary identity (Pal ID wasn't known yet at
                    -- creation). Now that it is, promote it to the real
                    -- Pal-ID key so a FUTURE gauge recycle for this same
                    -- Pal can find and reuse it (install_trust_bar's
                    -- early-reuse check) instead of building fresh again.
                    -- Skipped if this Pal already has a different tracked
                    -- entry (a rare duplicate — left as accepted, cosmetic
                    -- debt rather than merging/destroying widgets here).
                    if entry.palId == nil then
                        local palId = safe_call(Personality.GetStableId, actor)
                        if palId and palId ~= key and trackedBars[palId] == nil then
                            entry.palId = palId
                            promotions[#promotions + 1] = { oldKey = key, newKey = palId }
                        end
                    end
                end
            end
            if entry.actor ~= nil then
                local actorOk, actorValid = pcall(function() return entry.actor:IsValid() end)
                if not (actorOk and actorValid) then
                    entry.actor = nil -- Pal actor itself went away; keep the bar/gauge entry, it may get re-resolved or the whole entry will drop next time the gauge goes invalid
                else
                    local ratio = get_friendship_ratio(entry.actor)
                    if ratio then
                        pcall(function() entry.bar:SetPercent(ratio) end)
                        pcall(function() entry.bar:SetFillColorAndOpacity(compute_trust_bar_color(ratio)) end)
                    end

                    -- TEMPORARY DEBUG FEATURE (hundred-and-fiftieth pass,
                    -- 2026-09-04) — see install_trust_bar's matching
                    -- comment above. Only writes when the text actually
                    -- CHANGES (labelLastText), not every tick — this runs
                    -- once per tracked bar per scan, same lag discipline
                    -- as everything else in this file, and a personality
                    -- disposition basically never changes after the
                    -- initial roll (Won-Over is the one exception), so
                    -- this should write once per Pal and then go quiet.
                    if entry.label then
                        local labelOk, labelValid = pcall(function() return entry.label:IsValid() end)
                        if labelOk and labelValid then
                            local palId = safe_call(Personality.GetStableId, entry.actor)
                            local disposition = palId and Personality.GetDisposition(palId)
                            local text = disposition or "?"
                            if entry.labelLastText ~= text then
                                entry.labelLastText = text
                                -- Hundred-and-fifty-second pass FIX: same
                                -- crash-causing direct `.Text =` property
                                -- write as install_trust_bar's — switched
                                -- to the confirmed-real SetText_GDKInternal
                                -- method here too. Hundred-and-fifty-fourth
                                -- pass: dropped the [CRASH-DIAG] before/
                                -- after pair once the crash was confirmed
                                -- fixed — see install_trust_bar's matching
                                -- comment for the real lag numbers this
                                -- caused.
                                local setOk, setErr = pcall(function() entry.label:SetText_GDKInternal(true, text) end)
                                if not setOk then
                                    Logger.log("[PalBonds/Indicator] [DIAG-LABEL] text write FAILED for " .. describe_pal(entry.actor) .. ": " .. tostring(setErr))
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    for _, promotion in ipairs(promotions) do
        local entry = trackedBars[promotion.oldKey]
        if entry ~= nil then
            trackedBars[promotion.oldKey] = nil
            trackedBars[promotion.newKey] = entry
        end
    end
end

local function check_panel_children(fieldName)
    if liveCanvasInstance == nil or not liveCanvasInstance:IsValid() then return end

    local state = panelState[fieldName]
    if state == nil then
        state = { lastCount = nil, listedAtCount = nil, seenChildren = {} }
        panelState[fieldName] = state
    end

    local panelOk, panel = pcall(function() return liveCanvasInstance[fieldName] end)
    if not panelOk or panel == nil then
        panel_scan_log("[PalBonds/Indicator] [DIAG-PANEL] canvas." .. fieldName .. " is nil/unreadable — cannot enumerate children this way")
        return
    end

    local countOk, count = pcall(function() return panel:GetChildrenCount() end)
    if not countOk then
        panel_scan_log("[PalBonds/Indicator] [DIAG-PANEL] GetChildrenCount() failed on " .. fieldName .. ": " .. tostring(count))
        return
    end

    if count ~= state.lastCount then
        state.lastCount = count
        panel_scan_log("[PalBonds/Indicator] [DIAG-PANEL] " .. fieldName .. " child count changed -> " .. tostring(count))
    end

    -- Fifty-eighth pass fix: Dragón reported that Pals seen after walking
    -- away from the spawn area got no bar at all. Root cause — this loop
    -- used to only run when `count` DIFFERED from the last count it was
    -- run at (`state.listedAtCount ~= count`). If a Pal leaves range at
    -- the same moment a new one enters, the total count can land back on
    -- a value already seen before (e.g. 5 -> 6 -> 5), so this guard would
    -- skip the loop entirely even though the actual SET of children
    -- changed — the new Pal's gauge would simply never get processed.
    -- Fix: always walk every child when count > 0, every tick — install_
    -- trust_bar/inspect_gauge_widget are already idempotent per-widget
    -- (barInstalledForGauge/hasInspectedGaugeWidget), so re-calling them
    -- on already-handled children is a cheap no-op. Only the VERBOSE
    -- per-child log line and the one-time-per-class property dump are
    -- still gated (via a `seenChildren` set keyed by full name) so this
    -- doesn't spam the log every 2s once a bunch of Pals are on screen.
    if count > 0 then
        if state.listedAtCount ~= count then
            state.listedAtCount = count
            Logger.log("[PalBonds/Indicator] [DIAG-PANEL] " .. fieldName .. " now has " .. tostring(count) .. " live child widget(s)")
        end

        for i = 0, count - 1 do
            local childOk, child = pcall(function() return panel:GetChildAt(i) end)
            if childOk and child ~= nil then
                local classOk, className = pcall(function() return child:GetClass():GetFName():ToString() end)
                className = classOk and className or "?"
                local fullName = describe_widget(child)

                if not state.seenChildren[fullName] then
                    state.seenChildren[fullName] = true
                    Logger.log(string.format(
                        "[PalBonds/Indicator] [DIAG-PANEL]   %s child[%d] class=%s full=%s",
                        fieldName, i, className, fullName
                    ))

                    -- Dump the first NEW, non-structural class we see. A
                    -- container class we already know about (WrapBox etc.)
                    -- gets skipped — those are fixed widget-tree fixtures,
                    -- not per-Pal content. Each real class is only dumped
                    -- once, even if it shows up under both WrapBox and
                    -- Canvas_Root.
                    --
                    -- Sixty-eighth pass: WBP_PalNPCHPGauge_C specifically
                    -- is now fully characterized (fifty-first pass) and
                    -- was re-dumping its whole inheritance chain every
                    -- single session for no reason — a real, measured
                    -- contributor to a 507-line/8-second log burst Dragón
                    -- felt as lag (see inspect_gauge_widget's comment).
                    -- Skip the known one with a one-line ack; still fully
                    -- dump anything genuinely new (e.g. a boss/NPC gauge
                    -- class this project hasn't seen yet) — that case
                    -- still has real diagnostic value.
                    if classOk and not KNOWN_CONTAINER_CLASSES[className] and not dumpedClasses[className] then
                        dumpedClasses[className] = true
                        if className == "WBP_PalNPCHPGauge_C" then
                            Logger.log("[PalBonds/Indicator] [DIAG-PANEL] known class WBP_PalNPCHPGauge_C seen (already fully characterized, fifty-first pass) — skipping the full dump")
                        else
                            Logger.log("[PalBonds/Indicator] [DIAG-PANEL] new non-container class found: " .. className .. " — dumping its fields")
                            dump_all_properties(child, className)
                        end
                    end
                end

                -- Fifty-first pass: regardless of the logging above,
                -- specifically inspect/install a bar on EVERY real gauge
                -- widget seen, EVERY tick — both functions are internally
                -- idempotent (per-widget), so this is what actually
                -- guarantees a Pal that appears after the count has
                -- already cycled back to a "seen" value still gets its
                -- bar (the fifty-eighth pass's fix).
                if classOk and className == "WBP_PalNPCHPGauge_C" then
                    inspect_gauge_widget(child)
                    install_trust_bar(child)
                end
            else
                if not state.seenChildren["unreadable:" .. tostring(i)] then
                    state.seenChildren["unreadable:" .. tostring(i)] = true
                    Logger.log(string.format("[PalBonds/Indicator] [DIAG-PANEL]   %s child[%d] unreadable: %s", fieldName, i, tostring(child)))
                end
            end
        end
    end
end

local function check_all_panels()
    check_panel_children("WrapBox")
    check_panel_children("Canvas_Root")
end

-- FIFTY-EIGHTH PASS RESULT + FIFTY-NINTH PASS (2026-09-03) — the real,
-- severe bug: Dragón's test came back WORSE than before ("pals ahead had
-- no bar at all", "the few bars I saw were still stuck at 50%"). The log
-- explains why, and it's a bug that's been latent since the forty-sixth
-- pass: this whole
-- function used to start with `if scanLogCount >= MAX_SCAN_LOGS then
-- return end`. That cap was written back when this function did nothing
-- but a lightweight existence-scan diagnostic — reasonable to go quiet
-- after MAX_SCAN_LOGS (25) lines. But `canvasCount > 0` is true on EVERY
-- tick forever once the canvas is found (it's a single, always-present
-- live instance), so the `if gaugeCount > 0 or canvasCount > 0` branch
-- unconditionally increments `scanLogCount` by at least 1 EVERY tick —
-- meaning `scanLogCount` reaches 25 after ~25 ticks of the 2-second scan
-- interval, i.e. about 50 SECONDS into every single session. Once that
-- happens, the early `return` at the top skips the ENTIRE rest of the
-- function forever — including `check_all_panels()` (all bar creation)
-- and `update_trust_bars()` (all live refresh), which by this pass now
-- live inside this same function even though the cap was never designed
-- with them in mind. This exactly matches what Dragón saw: a burst of
-- bars near spawn (before the ~50s mark), then nothing at all afterward,
-- for the rest of the session, no matter how far they walked or how many
-- Pals they pet.
--
-- Fix: the log-volume cap now ONLY throttles the verbose DIAG-SCAN print
-- lines (via a small helper, same shared-counter pattern as
-- panel_scan_log/property_dump_log elsewhere in this file) — it no
-- longer gates the function's actual work. FindAllOf, check_all_panels(),
-- and update_trust_bars() now run every tick unconditionally, for the
-- entire session.
local function scan_log(msg)
    if scanLogCount >= MAX_SCAN_LOGS then return end
    scanLogCount = scanLogCount + 1
    Logger.log(msg)
    if scanLogCount == MAX_SCAN_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-SCAN] reached the scan-log cap (" .. MAX_SCAN_LOGS .. ") — going quiet on DIAG-SCAN lines specifically; bar creation/refresh keep running regardless")
    end
end

-- Sixty-third pass (2026-09-03): every attempt to read or hook the game's
-- own internal widget<->Pal link has now failed for a real, confirmed
-- reason each time — the stored soft-pointer field is a dead end (every
-- accessor tried failed), `DisplayedPalGaugeMap` can't be read at all
-- (MapProperty unsupported by this UE4SS Lua build, confirmed via a
-- bundled reference mod's own source), and `RegisterHook` can't resolve
-- `BindFromHandle` under any of four different name/path formats tried —
-- consistent with Blueprint-function short-name hook resolution simply not
-- working reliably in this build, not one specific wrong guess.
--
-- Rather than guess a fifth hook-path string blind, this pivots to a
-- completely different technique that needs none of the game's internal
-- linking at all: matching a gauge widget to a Pal by SCREEN POSITION.
-- Every gauge widget is a child of `Canvas_Root` with its own
-- `CanvasPanelSlot` (screen coordinates, assuming `Canvas_Root` fills the
-- viewport 1:1 — not yet confirmed). Every wild Pal actor has a real world
-- location (`K2_GetActorLocation()`, already proven elsewhere in this
-- project), and `APlayerController:ProjectWorldLocationToScreen` (a real,
-- confirmed function in `CXXHeaderDump/Engine.hpp`) converts a world
-- location into the same kind of screen coordinate. Whichever Pal projects
-- closest to a given gauge's position is almost certainly the Pal that
-- gauge belongs to.
--
-- Following this project's own proven rule — the one every REAL fix in
-- this file actually came from, and the opposite of the last several
-- passes' blind hook-path guessing — this logs BOTH sides side-by-side
-- FIRST, before writing any matching logic, so the numbers themselves
-- settle whether the coordinate-space assumption holds (and by what scale/
-- offset, if any) rather than building a whole matching pipeline on top of
-- an unverified guess. It also probes several different Lua calling
-- conventions for `ProjectWorldLocationToScreen`'s out-parameter, since
-- that's genuinely unknown in this UE4SS Lua build and worth confirming
-- rather than assuming.
local hasRunProjectionProbe = false
local MAX_POSMATCH_LOGS = 60
local posMatchLogCount = 0

local function posmatch_log(msg)
    if posMatchLogCount >= MAX_POSMATCH_LOGS then return end
    posMatchLogCount = posMatchLogCount + 1
    Logger.log(msg)
    if posMatchLogCount == MAX_POSMATCH_LOGS then
        Logger.log("[PalBonds/Indicator] [DIAG-POSMATCH] reached the log cap (" .. MAX_POSMATCH_LOGS .. ") — going quiet on these lines")
    end
end

local function probe_screen_projection()
    if hasRunProjectionProbe then return end

    local player = safe_call(function() return FindFirstOf("PalPlayerCharacter") end)
    if not player then return end -- keep retrying next tick; player may not exist yet

    local controller = safe_call(function() return player:GetController() end)
    local controllerValid = controller ~= nil and pcall(function() return controller:IsValid() end) and controller:IsValid()
    if not controllerValid then
        return -- keep retrying next tick rather than logging noise every frame
    end

    -- Sixty-fourth pass (2026-09-03): Dragón asked why we couldn't just
    -- check how "Pal Analyzer" (one of the three reference mods handed
    -- over at the very start) does this, since it shows live per-Pal info
    -- too. It's a compiled Blueprint LogicMod (.pak), not a UE4SS Lua
    -- script — different format than what this project reads — but a real
    -- .pak IS crackable read-only: extracted it with a standard pak-reader
    -- tool (github.com/panzi/u4pak, no encryption/compression on this
    -- mod) and read the plain-text function/property names embedded in
    -- the resulting .uasset (Unreal stores Blueprint node/function names
    -- as readable strings in the asset's name table even when compiled).
    --
    -- That confirmed something directly useful: PalAnalyzer identifies its
    -- target Pal via a camera-forward sphere trace (SphereTraceMultiForObjects
    -- + BreakHitResult -> HitActor, a "what is the player looking at" check,
    -- a different technique than ours since it only ever needs ONE target
    -- at a time, not every visible Pal simultaneously), then reads that
    -- actor's stats via `GetIndividualCharacterParameterByActor`/
    -- `TryGetIndividualParameter` — the exact same actor->parameter route
    -- this project's own Trust.lua/Interaction.lua already use, independent
    -- confirmation it's the right way to read a Pal's live stats.
    --
    -- Most valuable for THIS pass specifically: its compiled graph also
    -- calls `ProjectWorldToScreen` (node names `CallFunc_ProjectWorldToScreen_
    -- ReturnValue` / `_ScreenPosition`, i.e. Blueprint's own auto-generated
    -- pin names for a bool return + FVector2D out-param — direct
    -- confirmation of the calling shape) — but NOT as an instance method on
    -- the controller like this project's sixty-third pass guessed. Its
    -- owning class is `UGameplayStatics` (confirmed in `Engine.hpp`), a
    -- static Blueprint function library, called the same proven way this
    -- project's own installed UE4SS ships an example for
    -- (`Mods/SplitScreenMod/Scripts/main.lua` calls
    -- `UEHelpers.GetGameplayStatics():CreatePlayer(...)`). So the real,
    -- validated call is `UEHelpers.GetGameplayStatics():ProjectWorldToScreen(
    -- controller, worldLoc, false)` — tried FIRST below, with the sixty-third
    -- pass's guesses kept only as a fallback comparison.
    hasRunProjectionProbe = true -- only run the real probe once we actually have a controller

    local playerLoc = safe_call(function() return player:K2_GetActorLocation() end)
    if not playerLoc then
        posmatch_log("[PalBonds/Indicator] [DIAG-PROJECT] have a controller but could not read player location (caught, non-fatal)")
        return
    end

    local gameplayStatics, gsErr = safe_call(function() return UEHelpers.GetGameplayStatics() end)
    local gsValid = gameplayStatics ~= nil and pcall(function() return gameplayStatics:IsValid() end) and gameplayStatics:IsValid()
    posmatch_log("[PalBonds/Indicator] [DIAG-PROJECT] UEHelpers.GetGameplayStatics() valid=" .. tostring(gsValid) .. " err=" .. tostring(gsErr))

    local function project(worldLoc)
        if gsValid then
            local ok, succ, screen = pcall(function() return gameplayStatics:ProjectWorldToScreen(controller, worldLoc, false) end)
            if ok then return ok, succ, screen, "GameplayStatics" end
        end
        -- Fallback: the sixty-third pass's guesses, kept only for comparison.
        local ok1, succ1, screen1 = pcall(function() return controller:ProjectWorldLocationToScreen(worldLoc, false) end)
        return ok1, succ1, screen1, "PlayerController-fallback"
    end

    local ok1, succ1, screen1, via1 = project(playerLoc)
    posmatch_log(string.format(
        "[PalBonds/Indicator] [DIAG-PROJECT] attempt 1 (%s, 2-3 args, out-param returned) ok=%s ret1=%s(%s) ret2=%s(%s)",
        via1, tostring(ok1), tostring(succ1), type(succ1), tostring(screen1), type(screen1)
    ))

    -- Fallback: pass a plain table as the out-param and see if it's the
    -- return value or gets mutated in place (Lua tables are by-reference).
    local screenTable = {X = 0, Y = 0}
    local ok2, ret2 = pcall(function()
        if gsValid then return gameplayStatics:ProjectWorldToScreen(controller, playerLoc, screenTable, false) end
        return controller:ProjectWorldLocationToScreen(playerLoc, screenTable, false)
    end)
    posmatch_log(string.format(
        "[PalBonds/Indicator] [DIAG-PROJECT] attempt 2 (mutate-in-place table) ok=%s ret=%s(%s) screenTable after call: X=%s Y=%s",
        tostring(ok2), tostring(ret2), type(ret2), tostring(screenTable.X), tostring(screenTable.Y)
    ))

    -- Log every currently-visible wild Pal's world location and whatever
    -- attempt 1 (the most likely convention) projected it to.
    local pals = safe_call(function() return FindAllOf("PalCharacter") end)
    if pals then
        local playerName = safe_call(function() return player:GetFullName() end)
        local loggedPals = 0
        for _, pal in ipairs(pals) do
            if loggedPals >= 8 then break end
            local validOk, isValid = pcall(function() return pal ~= nil and pal:IsValid() end)
            if validOk and isValid then
                local palName = safe_call(function() return pal:GetFullName() end)
                if palName and palName ~= playerName then
                    local loc = safe_call(function() return pal:K2_GetActorLocation() end)
                    if loc then
                        local pOk, pSucc, pScreen, pVia = project(loc)
                        posmatch_log(string.format(
                            "[PalBonds/Indicator] [DIAG-POSMATCH] Pal %s worldLoc=(%.0f,%.0f,%.0f) via=%s ok=%s succ=%s screen=%s",
                            palName, loc.X or 0, loc.Y or 0, loc.Z or 0, pVia, tostring(pOk), tostring(pSucc), tostring(pScreen)
                        ))
                        loggedPals = loggedPals + 1
                    end
                end
            end
        end
    end

    -- Log every currently-installed gauge's own on-screen slot position
    -- (its position as a child of Canvas_Root) for direct comparison.
    local gaugeLogged = 0
    for key, entry in pairs(trackedBars) do
        if gaugeLogged >= 8 then break end
        local slotOk, sx, sy, sw, sh = pcall(function()
            local slot = entry.gaugeWidget.Slot
            local pos = slot:GetPosition()
            local size = slot:GetSize()
            return pos.X, pos.Y, size.X, size.Y
        end)
        posmatch_log(string.format(
            "[PalBonds/Indicator] [DIAG-POSMATCH] gauge %s slot ok=%s pos=(%s,%s) size=(%s,%s)",
            key, tostring(slotOk), tostring(sx), tostring(sy), tostring(sw), tostring(sh)
        ))
        gaugeLogged = gaugeLogged + 1
    end
end

local function scan_for_gauge_widgets()
    local gaugeInstances = safe_call(function() return FindAllOf("PalUICharacterHPGaugeBase") end)
    local canvasInstances = safe_call(function() return FindAllOf("PalUINPCHPGaugeCanvasBase") end)
    local gaugeCount = gaugeInstances and #gaugeInstances or 0
    local canvasCount = canvasInstances and #canvasInstances or 0

    if not hasLoggedScanAlive then
        hasLoggedScanAlive = true
        scan_log("[PalBonds/Indicator] [DIAG-SCAN] first scan ran (FindAllOf works) — real counts only get logged below once either class actually has a live instance")
    end

    if gaugeCount > 0 or canvasCount > 0 then
        scan_log(string.format(
            "[PalBonds/Indicator] [DIAG-SCAN] live instances — PalUICharacterHPGaugeBase=%d PalUINPCHPGaugeCanvasBase=%d",
            gaugeCount, canvasCount
        ))
        if gaugeInstances then
            for i, inst in ipairs(gaugeInstances) do
                if i > 5 then break end
                scan_log("[PalBonds/Indicator] [DIAG-SCAN]   gauge instance: " .. describe_widget(inst))
            end
        end
        if canvasInstances then
            for i, inst in ipairs(canvasInstances) do
                if i > 5 then break end
                scan_log("[PalBonds/Indicator] [DIAG-SCAN]   canvas instance: " .. describe_widget(inst))
            end

            -- Forty-seventh pass: the moment we see the REAL live instance
            -- (not the Blueprint archetype baked into the asset — that one's
            -- full name starts with /Game/..., the live one starts with
            -- /Engine/Transient), grab a handle to it — `liveCanvasInstance`
            -- is still load-bearing (check_all_panels below needs it).
            --
            -- Sixty-eighth pass: the actual field DUMP is not — its
            -- questions were fully answered back in the forty-seventh
            -- pass and it was just re-running every session for free,
            -- contributing real lines to the 507-line/8-second log burst
            -- Dragón felt as lag (see inspect_gauge_widget's comment for
            -- the full log evidence). Keep grabbing the handle; drop the
            -- dump.
            if not hasDumpedCanvas then
                for _, inst in ipairs(canvasInstances) do
                    local nameOk, fullName = pcall(function() return inst:GetFullName() end)
                    if nameOk and fullName and fullName:find("^WBP_PalNPCHPGaugeCanvas_C /Engine/Transient") then
                        hasDumpedCanvas = true
                        liveCanvasInstance = inst
                        Logger.log("[PalBonds/Indicator] [DIAG-SCAN] found the real live canvas instance (already fully characterized, forty-seventh pass — not re-dumping): " .. fullName)
                        break
                    end
                end
            end
        end
    end

    -- Forty-eighth pass: independent of the one-shot canvas dump above,
    -- keep checking the WrapBox's live children on every tick once we
    -- have a handle to the canvas. Fifty-ninth pass: this (and the line
    -- below) now run unconditionally every tick, no matter how much
    -- DIAG-SCAN logging has happened — see the big comment above.
    check_all_panels()

    -- Fifty-seventh pass: refresh every trust bar that resolved a real
    -- Pal actor, every tick, so they actually move.
    update_trust_bars()

    -- Sixty-third pass: one-shot screen-projection probe (see its own
    -- comment above) — needs a valid player controller, so this keeps
    -- retrying each tick until one exists, then runs once.
    probe_screen_projection()

    -- Sixty-seventh pass: try to register the prism spy hooks each tick
    -- until they succeed or the attempt cap is hit (see its own comment
    -- above) — the classes may not be loaded yet this early in a session.
    poll_prism_state()
end

-- Same scheduling approach already proven in Trust.lua.
local function scheduleScan()
    local ok = pcall(function()
        ExecuteInGameThreadWithDelay(SCAN_INTERVAL_MS, function()
            safe_call(scan_for_gauge_widgets)
            scheduleScan()
        end)
    end)
    if not ok then
        pcall(function()
            LoopAsync(SCAN_INTERVAL_MS, function()
                local inGameThread = true
                pcall(function() inGameThread = IsInGameThread() end)
                if inGameThread then
                    safe_call(scan_for_gauge_widgets)
                end
                return false -- keep looping
            end)
        end)
    end
end

function Indicator.Init()
    Logger.log("[PalBonds/Indicator] sixty-fourth pass: extracted the 'Pal Analyzer' reference mod's compiled .pak (a different format than this project's UE4SS Lua, but readable read-only with a standard pak tool) and found it uses GameplayStatics.ProjectWorldToScreen (a static Blueprint-library call, via UEHelpers.GetGameplayStatics() -- the same bundled helper Mods/SplitScreenMod already uses) to place UI at a Pal's world position, and reads Pal stats via the same actor->parameter route Trust.lua/Interaction.lua already use -- independent confirmation this project's approach is on the right track. Switched the screen-projection probe to use this validated call instead of guessing at the PlayerController instance method. See file header.")
    Logger.log("[PalBonds/Indicator] sixty-fifth pass: a full re-read of ALL reference mods (not skipping the ones in a different format) found the actual fix sitting in this project's own bundled VisiblePalCaptureCounter/Scripts/main.lua the whole time -- it hooks BindFromHandle successfully with the literal path '/Game/Pal/Blueprint/UI/NPCHPGauge/WBP_PalNPCHPGauge.WBP_PalNPCHPGauge_C:BindFromHandle' (package-path-dot-ClassName:FunctionName, the real format for a Blueprint hook, distinct from this project's native /Script/Module.Class:Function hooks). Every prior attempt was missing the real package path. Added this literal path as the first candidate, plus an Unbind hook to invalidate a reused gauge widget's stale captured handle. See file header.")
    -- Hundred-and-fifty-fifth pass (2026-09-04): register the class-level
    -- BindFromHandle/Unbind hooks HERE, first thing, rather than waiting
    -- for the periodic scan to discover a gauge widget — see
    -- register_bind_hook_immediate's own comment for the real race this
    -- closes (a Pal already on-screen at session start permanently
    -- missing capture otherwise).
    register_bind_hook_immediate()

    Logger.log("[PalBonds/Indicator] sixty-sixth pass: trust bar now uses a real white-pink (empty) to red (full) color gradient (SetFillColorAndOpacity, recomputed every refresh) instead of the static magenta placeholder, and starts at 0% instead of a 50% guess. See compute_trust_bar_color.")
    Logger.log("[PalBonds/Indicator] sixty-seventh pass: 'prism spy' -- grepped CXXHeaderDump for 'Prism', found BP_CapturePrism_C (the Palsphere throw weapon) and BP_CapturePrismBullet_C (its thrown projectile) are real classes; a third hit (Engine.hpp's ConstraintLimitMaterialPrismatic) is unrelated.")
    Logger.log("[PalBonds/Indicator] seventy-first pass: RegisterHook for BP_CapturePrism_C/BP_CapturePrismBullet_C is abandoned -- three separate Lua-reflection techniques for getting a Blueprint class's real asset path all failed (see file header), and the prior attempt's unthrottled failure log was itself spamming the console every ~2s. Switched to polling live instances' own fields directly (no path/hook needed) -- logs new instances once and BP_CapturePrismBullet_C's CaptureTarget/isBound only on change. See poll_prism_state.")

    local okTarget = pcall(function()
        RegisterHook("/Script/Pal.PalUICharacterHPGaugeBase:SetTargetCharacter", function(Context, TargetCharacter)
            local widget = hook_get(Context)
            local pal = hook_get(TargetCharacter)
            diagnostic_log(string.format(
                "[PalBonds/Indicator] [DIAG] SetTargetCharacter fired — widget class/instance=%s target=%s",
                describe_widget(widget), describe_pal(pal)
            ))
        end)
    end)
    if okTarget then
        Logger.log("[PalBonds/Indicator] hooked PalUICharacterHPGaugeBase:SetTargetCharacter (read-only diagnostic)")
    else
        Logger.log("[PalBonds/Indicator] could not hook PalUICharacterHPGaugeBase:SetTargetCharacter — class/function name may not resolve in this build")
    end

    local okPercent = pcall(function()
        RegisterHook("/Script/Pal.PalUICharacterHPGaugeBase:SetHPPercent", function(Context, Percent)
            local widget = hook_get(Context)
            diagnostic_log(string.format(
                "[PalBonds/Indicator] [DIAG] SetHPPercent fired — widget=%s percent=%s",
                describe_widget(widget), tostring(Percent)
            ))
        end)
    end)
    if okPercent then
        Logger.log("[PalBonds/Indicator] hooked PalUICharacterHPGaugeBase:SetHPPercent (read-only diagnostic)")
    else
        Logger.log("[PalBonds/Indicator] could not hook PalUICharacterHPGaugeBase:SetHPPercent — class/function name may not resolve in this build")
    end

    scheduleScan()
end

return Indicator
