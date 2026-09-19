/// Abstract base class defining all user-facing strings across SuperGoodViewer.
/// Concrete subclasses implement specific language bundles (e.g. ZhHansStrings, ZhHantStrings, EnStrings).
abstract class AppStrings {
  // --- General & App ---
  String get appTitle;
  String get appSubtitle;
  String get welcomeTitle;
  String get confirm;
  String get cancel;
  String get close;
  String get save;
  String get reset;
  String get apply;
  String get retry;
  String get copy;
  String get copied;
  String get delete;
  String get edit;
  String get success;
  String get error;
  String get warning;
  String get info;

  // --- Workspace & Floating Toolbar ---
  String get openDocument;
  String get exportPdf;
  String get exportPdfDialogTitle;
  String exportPdfSuccess(String path);
  String get exportPdfFailed;
  String openFileFailed(String err);
  String get copiedSelectedText;
  String toggleSidebarTooltip(String shortcut);
  String toggleSidebarCollapse(String shortcut);
  String toggleSidebarExpand(String shortcut);
  String sidebarCloseTooltip(String shortcut);
  String toggleThemeTooltip(bool isDark, String shortcut);
  String toggleModeTooltip(String shortcut);
  String togglePresentationTooltip(String shortcut);
  String toggleTwoPageTooltip(bool isTwoPage, String shortcut);
  String zoomInTooltip(String shortcut);
  String zoomOutTooltip(String shortcut);
  String resetZoomTooltip(String shortcut);
  String get fitWidthTooltip;
  String get fitPageTooltip;
  String get pageNavTooltip;
  String settingsTooltip(String shortcut);
  String reloadTooltip(String shortcut);
  String get compiling;
  String get selectAll;
  String get previousPage;
  String get nextPage;
  String get fullScreenImmersive;
  String get originalSize;
  String get fitWindowWidth;
  String get fitPageWhole;
  String get zoomPresetsTooltip;
  String get layoutSelectTooltip;
  String hideToolbarTooltip(String shortcut);
  String targetDocNotExist(String file);
  String get statusReady;
  String get statusCompiling;
  String get loadSampleDoc;
  String get discardChanges;
  String get clearSlotTooltip;
  String layoutModeShortName(String format);

  // --- HUD overlay ---
  String get hudActualSize;
  String hudFitWidth(int percent);
  String hudFitPage(int percent);
  String get hudTwoPage;
  String get hudSinglePage;
  String get hudTwoPageA4;
  String hudZoom(int percent);

  // --- Drag & Drop ---
  String get dragDropTitle;
  String get dragDropSubtitle;
  String unsupportedFileFormat(String ext);
  String get unsupportedBinaryFile;
  String get unsupportedDirectory;
  String get unsupportedDropGeneral;

  // --- Sidebar ---
  String get sidebarTabOutline;
  String get sidebarTabRecent;
  String get noOutlineFound;
  String get noRecentFiles;
  String get clearRecentHistory;
  String recentFilesCount(int count);
  String pageNumberBadge(int page);

  // --- Search Bar & Jump Dialog ---
  String get searchPlaceholder;
  String get searchPrevious;
  String get searchNext;
  String get closeSearch;
  String matchCount(int current, int total);
  String get noMatches;
  String get jumpToPageTitle;
  String jumpToPageHint(int min, int max);
  String get jumpButton;
  String get pageNavPrev;
  String get pageNavNext;

  // --- Presentation View ---
  String get presentationPrev;
  String get presentationNext;
  String get exitPresentation;
  String get presentationSearch;
  String presentationSlideCount(int current, int total);

  // --- Settings Dialog - Common ---
  String get settingsTitle;
  String get tabGeneral;
  String get tabLayout;
  String get tabTypography;
  String get tabShortcuts;
  String get tabCli;
  String get tabAbout;
  String get tabGeneralTitle;
  String get tabLayoutTitle;
  String get tabTypographyTitle;
  String get tabShortcutsTitle;
  String get tabCliTitle;
  String get tabAboutTitle;

  // --- Settings Dialog - General Tab ---
  String get displayLanguage;
  String get displayLanguageDesc;
  String get langSystem;
  String get langZhHans;
  String get langZhHant;
  String get langEn;
  String get themeMode;
  String get themeLight;
  String get themeDark;
  String get autoReloadSection;
  String get autoReload;
  String get autoReloadDesc;
  String get sessionSection;
  String get recentDocsRecord;
  String get cacheSection;
  String get localDiskCache;
  String get cacheDesc;
  String get clearCache;
  String get loadingCacheStats;
  String get noCacheFiles;
  String cacheCleared(String size);
  String currentCacheSize(int count, String size);

  // --- Settings Dialog - Layout Tab ---
  String get layoutMode;
  String get layoutModeFluid;
  String get layoutModeA4Portrait;
  String get layoutModeA4Landscape;
  String get layoutModeSlide169;
  String get layoutModeSlide43;
  String get twoPageSpread;
  String get twoPageSpreadDesc;
  String get marpCompatibility;
  String get marpCompatibilityDesc;
  String get headerFooterSection;
  String get slotLeft;
  String get slotCenter;
  String get slotRight;
  String get slotHintCustom;
  String get slotHintEmpty;
  String get slotHintCopyright;
  String get slotHintPageTotal;
  String get headerLeft;
  String get headerCenter;
  String get headerRight;
  String get footerLeft;
  String get footerCenter;
  String get footerRight;
  String get slotNone;
  String get slotTitle;
  String get slotPageNumber;
  String get slotTotalPages;
  String get slotPageOfTotal;
  String get slotDate;
  String get slotTime;
  String get showHeaderRule;
  String get showFooterRule;
  String get skipFirstPage;
  String get clearHeaderSlots;
  String get clearFooterSlots;
  String get saveAndApplyLayout;
  String get layoutSavedSuccess;
  String get layoutHasChanges;
  String get layoutUpToDate;

  // --- Settings Dialog - Typography Tab ---
  String get pdfTypographyNotice;
  String get fontSize;
  String fontSizePt(String pt);
  String get bodyFont;
  String get codeFont;
  String get fontDefault;
  String get embeddedFonts;
  String get systemFonts;
  String get saveAndApplyTypography;
  String get typographySavedSuccess;
  String get typographyHasChanges;
  String get typographyUpToDate;

  // --- Settings Dialog - Shortcuts Tab ---
  String get shortcutsDesc;
  String get resetAllShortcuts;
  String get pressNewShortcut;
  String shortcutConflict(String name);
  String shortcutCategoryName(String category);
  String shortcutActionName(String id, String defaultName);
  String shortcutActionDesc(String id, String defaultDesc);

  // --- Settings Dialog - CLI Tab ---
  String get cliTitle;
  String get cliDescMac;
  String get cliDescWin;
  String get cliDescLinux;
  String get cliStatusReady;
  String get cliStatusNotInstalled;
  String get cliStatusPartialPath;
  String get cliStatusPartialTools;
  String cliSymlinkPath(String path);
  String get cliInstall;
  String get cliRelink;
  String get cliReinstallRepair;
  String get cliUninstall;
  String get cliCleanUninstall;
  String get cliInstallSuccess;
  String get cliUninstallSuccess;
  String get cliAuthCancelled;
  String cliInstallFailed(String msg);
  String cliUninstallFailed(String msg);
  String get cliMsgNotInstalled;
  String get cliErrorAppDataDirFailed;
  String get cliErrorAppPathFailed;
  String get cliErrorWriteCmdFailed;
  String get cliErrorLocateLauncherFailed;
  String get cliErrorSymlinkFailed;
  String get cliErrorAuthScriptInitFailed;
  String get cliErrorPlatformNotSupported;
  String get cliErrorUnknown;
  String get cliWarningPathFailed;
  String get cliWarningPs1UpdateFailed;
  String get cliWarningPs1CreateFailed;
  String get cliWarningCliToolFailed;
  String cliWarningCombined(List<String> warnings);
  String get cliUsageExamples;
  String get cliExampleCurrentDir;
  String get cliExampleAnyFile;
  String get cliExampleLaunch;
  String get cliExampleStdin;
  String get cliExampleOpenMarkdown;
  String get cliExampleExportSingle;
  String get cliExampleExportBatch;
  String get cliHintQuickPreview;
  String get cliTipMac;
  String get cliTipWin;
  String get cliTipLinux;
  String get copyCommandTooltip;
  String copiedCommand(String cmd);

  // --- Settings Dialog - About Tab ---
  String aboutVersion(String ver);
  String get aboutEngine;
  String get aboutFramework;
  String get aboutGithub;
  String get aboutLicense;

  // --- Auto Update ---
  String get checkForUpdates;
  String get checkingForUpdates;
  String get upToDate;
  String get updateAvailable;
  String get updateNow;
  String get downloadingUpdate;
  String get restartToUpdate;
  String get skipThisVersion;
  String get remindMeLater;
  String get viewOnWeb;
  String get autoCheckUpdates;
  String get updateFailed;
  String get installingUpdate;
}
