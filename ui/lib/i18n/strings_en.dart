import 'app_strings.dart';

/// English (en) localization strings.
class EnStrings implements AppStrings {
  const EnStrings();

  // --- General & App ---
  @override
  String get appTitle => 'SuperGoodViewer';
  @override
  String get appSubtitle =>
      'Next-generation Markdown & PDF reader powered by Typst typesetting engine';
  @override
  String get cancel => 'Cancel';
  @override
  String get close => 'Close';
  @override
  String get save => 'Save';
  @override
  String get reset => 'Reset';
  @override
  String get apply => 'Apply';
  @override
  String get retry => 'Retry';
  @override
  String get copy => 'Copy';
  @override
  String get copied => 'Copied';
  @override
  String get delete => 'Delete';
  @override
  String get edit => 'Edit';
  @override
  String get success => 'Success';
  @override
  String get error => 'Error';
  @override
  String get warning => 'Warning';
  @override
  String get info => 'Info';

  // --- Workspace & Floating Toolbar ---
  @override
  String get openDocument => 'Open Document';
  @override
  String get exportPdf => 'Export Print-Ready PDF';
  @override
  String get exportPdfDialogTitle => 'Export Print-Ready PDF';
  @override
  String exportPdfSuccess(String path) => 'Successfully exported print-ready PDF to $path';
  @override
  String get exportPdfFailed => 'Export failed, please try again';
  @override
  String openFileFailed(String err) => 'Failed to open file: $err';
  @override
  String degradedEquationsWarning(int count) =>
      '$count formula(s) failed to render and were degraded to raw LaTeX';
  @override
  String get copiedSelectedText => 'Selected text copied to clipboard';
  @override
  String toggleSidebarTooltip(String shortcut) => 'Toggle Sidebar ($shortcut)';
  @override
  String toggleSidebarCollapse(String shortcut) => 'Collapse Sidebar ($shortcut)';
  @override
  String toggleSidebarExpand(String shortcut) => 'Expand Sidebar ($shortcut)';
  @override
  String sidebarCloseTooltip(String shortcut) => 'Collapse Sidebar ($shortcut or Esc)';
  @override
  String toggleThemeTooltip(bool isDark, String shortcut) =>
      isDark ? 'Switch to Light Mode ($shortcut)' : 'Switch to Dark Mode ($shortcut)';
  @override
  String toggleModeTooltip(String shortcut) => 'Switch Layout / View Mode ($shortcut)';
  @override
  String togglePresentationTooltip(String shortcut) =>
      'Full-Screen Presentation ($shortcut / F5)';
  @override
  String toggleTwoPageTooltip(bool isTwoPage, String shortcut) => isTwoPage
      ? 'Current: Two-Page Spread. Click for Single Page ($shortcut)'
      : 'Current: Single Page. Click for Two-Page Spread ($shortcut)';
  @override
  String zoomInTooltip(String shortcut) => 'Zoom In ($shortcut)';
  @override
  String zoomOutTooltip(String shortcut) => 'Zoom Out ($shortcut)';
  @override
  String resetZoomTooltip(String shortcut) => 'Actual Size 100% ($shortcut)';
  @override
  String get pageNavTooltip => 'Click to Jump to Page';
  @override
  String settingsTooltip(String shortcut) => 'Preferences ($shortcut)';
  @override
  String get compiling => 'Typesetting...';
  @override
  String get selectAll => 'Select All';
  @override
  String get previousPage => 'Previous Page';
  @override
  String get nextPage => 'Next Page';
  @override
  String get fullScreenImmersive => 'Full Screen Immersive';
  @override
  String get originalSize => '100% (Actual Size)';
  @override
  String get fitWindowWidth => 'Fit Window (Width)';
  @override
  String get fitPageWhole => 'Fit Screen (Page)';
  @override
  String get zoomPresetsTooltip => 'Page Zoom & Presets';
  @override
  String get layoutSelectTooltip => 'Select Layout';
  @override
  String hideToolbarTooltip(String shortcut) => 'Hide Toolbar (Esc or $shortcut)';
  @override
  String targetDocNotExist(String file) => 'Target document does not exist: $file';
  @override
  String get statusReady => 'Ready';
  @override
  String get loadSampleDoc => 'Load Sample';
  @override
  String get discardChanges => 'Discard Changes';
  @override
  String get clearSlotTooltip => 'Clear this slot';
  @override
  String layoutModeShortName(String format) {
    switch (format) {
      case 'fluid':
        return 'Fluid';
      case 'slide16x9':
        return '16:9';
      case 'slide4x3':
        return '4:3';
      default:
        return 'A4';
    }
  }

  // --- HUD overlay ---
  @override
  String get hudActualSize => 'Actual Size 100%';
  @override
  String hudFitWidth(int percent) => 'Fit Width ($percent%)';
  @override
  String hudFitPage(int percent) => 'Fit Page ($percent%)';
  @override
  String get hudTwoPage => 'Two-Page Spread';
  @override
  String get hudSinglePage => 'Single Page View';
  @override
  String get hudTwoPageA4 => 'A4 Two-Page Spread';

  // --- Drag & Drop ---
  @override
  String get dragDropTitle => 'Drop to open document in this window';
  @override
  String get dragDropSubtitle =>
      'Supports Markdown (.md, .markdown), PDF (.pdf), Typst (.typ), or folders with README';
  @override
  String unsupportedFileFormat(String ext) =>
      'Format $ext is not supported. Please drop a Markdown (.md) or PDF (.pdf) file';
  @override
  String get unsupportedBinaryFile =>
      'Binary file format not supported. Please drop a Markdown (.md) or PDF (.pdf) file';
  @override
  String get unsupportedDirectory =>
      'No readable Markdown or PDF document found in selected folder';
  @override
  String get unsupportedDropGeneral =>
      'No supported Markdown (.md) or PDF (.pdf) files found';

  // --- Sidebar ---
  @override
  String get sidebarTabOutline => 'Outline';
  @override
  String get sidebarTabRecent => 'Recent';
  @override
  String get noOutlineFound => 'No outline available';
  @override
  String get noRecentFiles => 'No recent files';
  @override
  String get clearRecentHistory => 'Clear Recent History';
  @override
  String recentFilesCount(int count) => '$count recent ${count == 1 ? "file" : "files"}';
  @override
  String pageNumberBadge(int page) => 'P$page';
  @override
  String get sidebarPositionSection => 'Sidebar Placement';
  @override
  String get sidebarPosition => 'Sidebar Position';
  @override
  String get sidebarPositionDesc => 'Control whether the outline & recents sidebar docks to the left or right side of the window';
  @override
  String get sidebarPositionLeft => 'Left Side (Default)';
  @override
  String get sidebarPositionRight => 'Right Side';
  @override
  String get moveSidebarToLeft => 'Move to Left';
  @override
  String get moveSidebarToRight => 'Move to Right';
  @override
  String get resetSidebarWidthTooltip => 'Double-click to reset width';

  // --- Search Bar & Jump Dialog ---
  @override
  String get searchPlaceholder => 'Find in document...';
  @override
  String get searchPrevious => 'Previous (Shift+Enter)';
  @override
  String get searchNext => 'Next (Enter)';
  @override
  String get closeSearch => 'Close (Esc)';
  @override
  String matchCount(int current, int total) => '$current / $total';
  @override
  String get noMatches => 'No matches';
  @override
  String get jumpToPageTitle => 'Jump to Page';
  @override
  String jumpToPageHint(int min, int max) => 'Enter page number ($min - $max):';
  @override
  String get jumpButton => 'Jump';
  @override
  String get pageNavPrev => 'Previous Page (← or [)';
  @override
  String get pageNavNext => 'Next Page (→ or ])';

  // --- Presentation View ---
  @override
  String get presentationPrev => 'Previous Slide (← / PageUp)';
  @override
  String get presentationNext => 'Next Slide (→ / Space)';
  @override
  String get exitPresentation => 'Exit Presentation (Esc)';

  // --- Settings Dialog - Common ---
  @override
  String get settingsTitle => 'Preferences';
  @override
  String get tabGeneral => 'General';
  @override
  String get tabLayout => 'Layout';
  @override
  String get tabTypography => 'Typography';
  @override
  String get tabShortcuts => 'Shortcuts';
  @override
  String get tabCli => 'CLI Tool';
  @override
  String get tabAbout => 'About';
  @override
  String get tabGeneralTitle => 'General & Reading Preferences';
  @override
  String get tabLayoutTitle => 'Page Layout & Header / Footer Slots';
  @override
  String get tabTypographyTitle => 'Typography & CJK Character Alignment';
  @override
  String get tabShortcutsTitle => 'Keyboard Shortcuts Configuration';
  @override
  String get tabCliTitle => 'Command Line Tool (sgv) Integration';
  @override
  String get tabAboutTitle => 'About SuperGoodViewer';

  // --- Settings Dialog - General Tab ---
  @override
  String get languageSection => 'Language';
  @override
  String get displayLanguage => 'Display Language';
  @override
  String get displayLanguageDesc => 'Select the display language for SuperGoodViewer';
  @override
  String get appearanceSection => 'Appearance';
  @override
  String get themeMode => 'Appearance Theme';
  @override
  String get themeModeDesc => 'Follow System switches automatically with the OS light / dark appearance';
  @override
  String get themeSystem => 'Follow System';
  @override
  String get themeLight => 'Light Mode';
  @override
  String get themeDark => 'Dark Mode';
  @override
  String get autoReloadSection => 'Document Auto Reload';
  @override
  String get autoReload => 'Live File Auto-Reload';
  @override
  String get autoReloadDesc =>
      'Automatically re-renders when local file is saved, preserving your current reading position';
  @override
  String get sessionSection => 'Session & History';
  @override
  String get recentDocsRecord => 'Recent Documents History';
  @override
  String get cacheSection => 'Compiled PDF Cache';
  @override
  String get localDiskCache => 'Local Disk Cache';
  @override
  String get cacheDesc =>
      'Local vector cache speeds up reopening documents and lowers CPU usage';
  @override
  String get openCacheDirectory => 'Open Folder';
  @override
  String get openCacheDirectoryFailed => 'Failed to open cache directory';
  @override
  String get clearCache => 'Clear Cache';
  @override
  String get loadingCacheStats => 'Loading cache stats...';
  @override
  String get noCacheFiles => 'No cached files (0 B)';
  @override
  String cacheCleared(String size) => 'Cache cleared successfully, freed $size disk space.';
  @override
  String currentCacheSize(int count, String size) => '$count ${count == 1 ? "document" : "documents"} cached ($size)';

  // --- Settings Dialog - Layout Tab ---
  @override
  String get layoutModeFluid => 'Continuous Scroll (Fluid)';
  @override
  String get layoutModeA4Portrait => 'A4 Portrait Paged (Print)';
  @override
  String get layoutModeA4Landscape => 'A4 Landscape Paged';
  @override
  String get layoutModeSlide169 => '16:9 Widescreen Slides';
  @override
  String get layoutModeSlide43 => '4:3 Standard Slides';
  @override
  String get twoPageSpreadDesc =>
      'Displays two facing pages side-by-side for a book-like reading experience';
  @override
  String get marpCompatibility => 'Marp Syntax Compatibility';
  @override
  String get marpCompatibilityDesc =>
      'Enables slide presentation mode when marp: true or --- slide separators are detected';
  @override
  String get headerFooterSection => 'Header & Footer Slots';
  @override
  String get slotLeft => 'Left Slot';
  @override
  String get slotCenter => 'Center Slot';
  @override
  String get slotRight => 'Right Slot';
  @override
  String get slotHintCustom => 'Empty or custom text';
  @override
  String get slotHintEmpty => 'Empty';
  @override
  String get slotHintCopyright => 'Empty or copyright notice';
  @override
  String get slotHintPageTotal => 'Empty or {page}/{total}';
  @override
  String get headerLeft => 'Header Left';
  @override
  String get headerCenter => 'Header Center';
  @override
  String get headerRight => 'Header Right';
  @override
  String get footerLeft => 'Footer Left';
  @override
  String get footerCenter => 'Footer Center';
  @override
  String get footerRight => 'Footer Right';
  @override
  String get showHeaderRule => 'Header Dividing Line';
  @override
  String get showFooterRule => 'Footer Dividing Line';
  @override
  String get skipFirstPage => 'Skip Header & Footer on First Page';
  @override
  String get clearHeaderSlots => 'Clear Headers';
  @override
  String get clearFooterSlots => 'Clear Footers';
  @override
  String get saveAndApplyLayout => 'Save and Apply Layout';
  @override
  String get layoutSavedSuccess => 'Layout preferences saved and applied successfully!';
  @override
  String get layoutHasChanges => 'Layout & header/footer modified (Unsaved)';
  @override
  String get layoutUpToDate => 'Layout & header/footer match document';

  // --- Settings Dialog - Typography Tab ---
  @override
  String get pdfTypographyNotice =>
      'You are currently viewing a native PDF file. Typography and fonts are fixed by the PDF document. These font settings apply to Markdown documents.';
  @override
  String get fontSize => 'Body Font Size';
  @override
  String get bodyFont => 'Body Font Family';
  @override
  String get codeFont => 'Monospace Code Font';
  @override
  String get saveAndApplyTypography => 'Save & Refresh Document';
  @override
  String get typographySavedSuccess => 'Typography settings saved. Re-rendering document...';
  @override
  String get typographyHasChanges => 'Typography settings modified (Unsaved)';
  @override
  String get typographyUpToDate => 'Typography settings match document';

  // --- Settings Dialog - Shortcuts Tab ---
  @override
  String get shortcutsDesc =>
      'Click a shortcut card and press keys on your keyboard to customize. Supports modifiers and function keys.';
  @override
  String get resetAllShortcuts => 'Reset All Shortcuts to Defaults';
  @override
  String get pressNewShortcut => 'Press new shortcut combination...';
  @override
  String shortcutConflict(String name) =>
      'Conflicts with "$name", replaced previous shortcut.';
  @override
  String shortcutCategoryName(String category) {
    switch (category) {
      case '视图模式':
        return 'View & Layout';
      case '文档文件':
        return 'Documents & Files';
      case '缩放自适应':
        return 'Zoom & Fit';
      case '排版与设置':
        return 'Typography & Settings';
      default:
        return category;
    }
  }
  @override
  String shortcutActionName(String id, String defaultName) {
    switch (id) {
      case 'preferences':
        return 'Preferences';
      case 'fontSettings':
        return 'Typography Settings';
      case 'keyboardShortcuts':
        return 'Keyboard Shortcuts';
      case 'toggleMode':
        return 'Switch Layout / View Mode';
      case 'togglePresentation':
        return 'Full-Screen Presentation';
      case 'toggleTheme':
        return 'Toggle Light / Dark Mode';
      case 'toggleTwoPage':
        return 'Toggle Single / Two-Page Spread';
      case 'toggleToolbar':
        return 'Toggle Floating Toolbar';
      case 'findInDocument':
        return 'Find in Document';
      case 'exportPdf':
        return 'Export Print-Ready PDF';
      case 'openFile':
        return 'Open Local Document';
      case 'toggleSidebar':
        return 'Toggle Sidebar';
      case 'compileDocument':
        return 'Recompile / Refresh';
      case 'openSettings':
        return 'Open Preferences';
      case 'zoomIn':
        return 'Zoom In';
      case 'zoomOut':
        return 'Zoom Out';
      case 'resetZoom':
        return 'Reset Zoom (100%)';
      case 'fitWidth':
        return 'Fit Window Width';
      case 'fitPage':
        return 'Fit Entire Page';
      default:
        return defaultName;
    }
  }
  @override
  String shortcutActionDesc(String id, String defaultDesc) {
    switch (id) {
      case 'preferences':
        return 'Open Settings (general, typography, shortcuts, CLI)';
      case 'fontSettings':
        return 'Open CJK typography and 1:2 monospace alignment settings';
      case 'keyboardShortcuts':
        return 'Open shortcut settings to rebind keys';
      case 'toggleMode':
        return 'Switch between Fluid Scroll, A4 Portrait/Landscape, and 16:9/4:3 Slides';
      case 'togglePresentation':
        return 'Enter or exit full-screen presentation mode for speeches and sharing';
      case 'toggleTheme':
        return 'Seamlessly switch between daylight and dark reading themes';
      case 'toggleTwoPage':
        return 'Toggle between single page and two-page facing spread in A4 mode';
      case 'toggleToolbar':
        return 'Toggle bottom floating toolbar visibility for immersive Zen reading';
      case 'findInDocument':
        return 'Search keywords or outline chapters in current document';
      case 'exportPdf':
        return 'Export current document to lossless print-grade vector PDF';
      case 'openFile':
        return 'Open and view local Markdown or PDF files via system file picker';
      case 'toggleSidebar':
        return 'Show or hide document outline and recent file history';
      case 'compileDocument':
        return 'Recompile Typst typesetting engine and refresh immediately';
      case 'openSettings':
        return 'Open global configuration and preference dialog';
      case 'zoomIn':
        return 'Increase document zoom level';
      case 'zoomOut':
        return 'Decrease document zoom level';
      case 'resetZoom':
        return 'Reset document zoom to 100% actual size';
      case 'fitWidth':
        return 'Auto-fit document width to window';
      case 'fitPage':
        return 'Auto-fit entire page to window';
      default:
        return defaultDesc;
    }
  }

  // --- Settings Dialog - CLI Tab ---
  @override
  String get cliTitle => 'CLI Command Tool (sgv)';
  @override
  String get cliDescMac =>
      'Open Markdown or PDF files instantly from macOS Terminal using the sgv command';
  @override
  String get cliDescWin =>
      'Open Markdown or PDF files instantly from CMD or PowerShell using the sgv command';
  @override
  String get cliDescLinux =>
      'Open Markdown or PDF files instantly from Linux Terminal using the sgv command';
  @override
  String get cliStatusReady => 'Ready (Installed in system PATH)';
  @override
  String get cliStatusNotInstalled => 'Not installed in system PATH';
  @override
  String get cliStatusPartialPath => 'Incomplete installation (Not added to system PATH)';
  @override
  String get cliStatusPartialTools => 'Incomplete installation (Some tools not ready)';
  @override
  String cliSymlinkPath(String path) => 'Symlink path: $path';
  @override
  String get cliInstall => 'Install to Terminal';
  @override
  String get cliRelink => 'Relink / Repair';
  @override
  String get cliReinstallRepair => 'Reinstall / Repair';
  @override
  String get cliUninstall => 'Uninstall';
  @override
  String get cliCleanUninstall => 'Clean Uninstall';
  @override
  String get cliInstallSuccess =>
      '🎉 \'sgv\' command-line tool installed successfully! Ready to use in your terminal.';
  @override
  String get cliUninstallSuccess => 'Successfully uninstalled \'sgv\' CLI tool.';
  @override
  String get cliAuthCancelled => 'Authorization cancelled.';
  @override
  String cliInstallFailed(String msg) => msg.isEmpty ? 'Installation failed' : 'Installation failed: $msg';
  @override
  String cliUninstallFailed(String msg) => msg.isEmpty ? 'Uninstall failed' : 'Uninstall failed: $msg';
  @override
  String get cliMsgNotInstalled => 'Not installed';
  @override
  String get cliErrorAppDataDirFailed => 'Unable to locate local application data directory';
  @override
  String get cliErrorAppPathFailed => 'Unable to get current executable path';
  @override
  String get cliErrorWriteCmdFailed => 'Failed to write sgv.cmd script';
  @override
  String get cliErrorLocateLauncherFailed => 'Failed to locate sgv launcher script';
  @override
  String get cliErrorSymlinkFailed => 'Failed to create symbolic link';
  @override
  String get cliErrorAuthScriptInitFailed => 'Failed to initialize authorization script';
  @override
  String get cliErrorPlatformNotSupported => 'Current platform is not supported';
  @override
  String get cliErrorUnknown => 'Unknown error';
  @override
  String get cliWarningPathFailed =>
      'Failed to add install directory to environment PATH (registry restricted), command may not be directly accessible';
  @override
  String get cliWarningPs1UpdateFailed =>
      'sgv.ps1 could not be updated (may be in use), PowerShell may still point to older version';
  @override
  String get cliWarningPs1CreateFailed => 'Failed to create sgv.ps1 script';
  @override
  String get cliWarningCliToolFailed => 'Failed to create sgv-cli shortcut';
  @override
  String cliWarningCombined(List<String> warnings) {
    if (warnings.isEmpty) return '';
    final buffer = StringBuffer('Scripts generated, but ')..write(warnings[0]);
    for (var i = 1; i < warnings.length; i++) {
      buffer.write('; and ');
      buffer.write(warnings[i]);
    }
    return buffer.toString();
  }
  @override
  String get cliUsageExamples => 'Usage Examples';
  @override
  String get cliExampleCurrentDir => 'Open Markdown file in current directory';
  @override
  String get cliExampleAnyFile => 'Supports absolute and relative paths';
  @override
  String get cliExampleLaunch => 'Quickly launch or activate SuperGoodViewer';
  @override
  String get cliExampleStdin => 'Instant preview via stdin pipe';
  @override
  String get cliExampleOpenMarkdown => 'Open Markdown document in viewer';
  @override
  String get cliExampleExportSingle => 'Headlessly export single Markdown to publication-grade PDF';
  @override
  String get cliExampleExportBatch => 'Batch export all Markdown files in directory to PDF';
  @override
  String get cliHintQuickPreview => 'Once installed, run \'sgv README.md\' in terminal for instant document preview';
  @override
  String get cliTipMac =>
      'Note: If macOS prompts for authorization, provide fingerprint or admin password. No manual terminal commands needed.';
  @override
  String get cliTipWin =>
      'Note: After installation, sgv can be run from Command Prompt, PowerShell, or Windows Terminal.';
  @override
  String get cliTipLinux =>
      'Tip: Installation creates an sgv symlink in ~/.local/bin. Ensure this directory is in your PATH.';
  @override
  String get copyCommandTooltip => 'Copy Command';
  @override
  String copiedCommand(String cmd) => 'Copied command: $cmd';

  // --- Settings Dialog - About Tab ---
  @override
  String aboutVersion(String ver) => 'Version $ver';

  // --- Auto Update ---
  @override
  String get checkForUpdates => 'Check for Updates';
  @override
  String get checkingForUpdates => 'Checking for updates...';
  @override
  String get upToDate => 'SuperGoodViewer is up to date';
  @override
  String get updateAvailable => 'Update Available';
  @override
  String get updateNow => 'Update Now';
  @override
  String get downloadingUpdate => 'Downloading update...';
  @override
  String get restartToUpdate => 'Restart to Update';
  @override
  String get skipThisVersion => 'Skip This Version';
  @override
  String get remindMeLater => 'Remind Me Later';
  @override
  String get viewOnWeb => 'View on Web';
  @override
  String get autoCheckUpdates => 'Automatically check for updates on startup';
  @override
  String get updateFailed => 'Failed to check or download update';
  @override
  String get installingUpdate => 'Preparing update and restarting...';

  // --- Settings Dialog - General Tab (cont.) ---
  @override
  String get restoreSession => 'Restore Last Session on Launch';
  @override
  String get restoreSessionDesc => 'Reopens the last document at your reading position when the app restarts';
  @override
  String get enabledBadge => 'Enabled';

  // --- Settings Dialog - Layout Tab (cont.) ---
  @override
  String get pageFormatSection => 'Page Format';
  @override
  String get pageFormatDesc => 'Choose the default document layout: 16:9 / 4:3 slides for presenting, A4 or fluid for reading and print.';
  @override
  String get pageFormatFluidDesc => 'Comfortable fixed line width, auto height and seamless scrolling, ideal for technical docs and long reads';
  @override
  String get pageFormatA4PortraitDesc => 'Standard A4 portrait (595.28 × 841.89 pt) with header, footer and widow control, ready for print';
  @override
  String get pageFormatA4LandscapeDesc => 'Standard A4 landscape (841.89 × 595.28 pt) for architecture diagrams and wide tables';
  @override
  String get pageFormatSlide169Desc => '16:9 widescreen slides (960 × 540 pt) with large type for high-fidelity presentations';
  @override
  String get pageFormatSlide43Desc => '4:3 classic slides (960 × 720 pt) for traditional projectors and academic talks';
  @override
  String get headerFooterDesc => 'Three customizable slots each. Placeholders: {title}, {page} (current page), {total} (page count), {date}. Headers and footers are hidden in fluid mode.';
  @override
  String get skipFirstPageDesc => 'Follows the title-page convention of print and slides: no header or footer on page one';
  @override
  String get headerSlotsTitle => 'Header Slots';
  @override
  String get footerSlotsTitle => 'Footer Slots';

  // --- Settings Dialog - Typography Tab (cont.) ---
  @override
  String get mapleLinkCopied => 'Copied the Maple Mono GitHub link to the clipboard';
  @override
  String get pdfTypographyInlineNotice => 'You are reading a standalone PDF; these typography settings apply when reading Markdown documents.';
  @override
  String get fontOptionSystemRecommended => 'System Recommended (Inter + SF Pro + PingFang / Microsoft YaHei)';
  @override
  String get fontOptionPingFang => 'PingFang SC';
  @override
  String get fontOptionSongti => 'Songti SC';
  @override
  String get fontOptionHiragino => 'Hiragino Sans GB';
  @override
  String get fontOptionYaHei => 'Microsoft YaHei';
  @override
  String get fontOptionSourceHanSans => 'Source Han Sans SC';
  @override
  String get fontOptionInter => 'Inter (modern sans-serif)';
  @override
  String get fontOptionMapleMono => 'Maple Mono (recommended: strict 1:2 alignment)';
  @override
  String get fontOptionMenlo => 'Menlo (macOS default monospace)';
  @override
  String get fontOptionMonaco => 'Monaco (classic macOS monospace)';
  @override
  String get fontOptionCourierNew => 'Courier New (classic serif monospace)';
  @override
  String fontOptionCustom(String name) => '$name (custom)';
  @override
  String fontOptionInstalled(String name) => '$name (installed)';
  @override
  String get bodyTypographyTitle => 'Body Typography';
  @override
  String get monoTypographyTitle => 'Code & ASCII Table Font';
  @override
  String get baseFontSizeTitle => 'Base Font Size';
  @override
  String get useRecommended => 'Use Recommended';
  @override
  String get restoreDefault => 'Reset';
  @override
  String restoreDefaultFontSize(String pt) => 'Reset ($pt pt)';
  @override
  String get decreaseFontSize => 'Decrease Font Size';
  @override
  String get increaseFontSize => 'Increase Font Size';
  @override
  String get restoreDefaultFonts => 'Reset Fonts';
  @override
  String get mapleMonoReady => 'Maple Mono ready (strict 1:2 monospace)';
  @override
  String get cjkMonoDetected => 'CJK strict monospace font detected';
  @override
  String get mapleMonoSuggested => 'Maple Mono recommended';
  @override
  String get cjkMonoActiveDesc => 'CJK strict monospace is active: CJK and Latin characters in ASCII tables and code align at exactly 1:2.';
  @override
  String get cjkMonoMissingDesc => 'No CJK monospace font found; ASCII tables and mixed-script code may misalign slightly.';
  @override
  String get downloadFont => 'Download Font';
  @override
  String get copyLink => 'Copy Link';
  @override
  String get detectingFonts => 'Detecting...';
  @override
  String get redetectFonts => 'Re-detect';
  @override
  String get mapleMonoDefault => 'Maple Mono (default)';
  @override
  String get livePreviewBadge => 'Live Preview';
  @override
  String get livePreviewTitle => 'Live Typography Preview';
  @override
  String get previewSpecimenHeading => 'Publisher-Grade Technical Typography';
  @override
  String get previewSpecimenBody => 'SuperGoodViewer is built for dense technical documents, engineering specs and papers. This paragraph uses your current body font and size to show CJK–Latin spacing and line rhythm: 超好读专为高密度技术文档设计，中西文混排间距一目了然。';
  @override
  String previewCodeFont(String name) => 'Code font: $name';
  @override
  String get asciiAlignmentCheck => 'ASCII table full-width / half-width 1:2 alignment check';

  // --- Settings Dialog - Shortcuts Tab (cont.) ---
  @override
  String get shortcutModified => 'Modified';
  @override
  String get resetShortcutToDefault => 'Reset to Default';

  // --- Settings Dialog - About Tab (cont.) ---
  @override
  String get openProjectHomepage => 'Open Project Homepage';
  @override
  String get aboutEngineSection => 'Core Rendering Engine';
  @override
  String get aboutTypstDesc => 'Millisecond-level compiler core with full support for advanced math, tables and code blocks';
  @override
  String get aboutPdfiumTitle => 'PDFium Vector Rendering';
  @override
  String get aboutPdfiumDesc => 'Lossless 120 FPS panning with partial pre-rendering';
  @override
  String get aboutCjkTitle => 'CJK 1:2 Monospace Alignment';
  @override
  String get aboutCjkDesc => 'Built-in CJK monospace font detection keeps ASCII tables and diagrams aligned';
  @override
  String get loadSampleDocument => 'Load Sample Document';
  @override
  String get loadSampleDocumentDesc => 'Try a demo with complex math, Mermaid diagrams, callouts and syntax highlighting';

  // --- Presentation View (cont.) ---
  @override
  String get presentationNoContent => 'No document content to present';
  @override
  String presentationLoadFailed(String error) => 'Failed to load presentation: $error';

  // --- Auto Update (cont.) ---
  @override
  String updateCurrentVersion(String version) => 'Current version: v$version';
  @override
  String updateSize(String size) => 'Size: $size';
  @override
  String get releaseNotesTitle => 'Release Notes';
  @override
  String get releaseNotesFallback => 'Includes performance and stability improvements.';
  @override
  String get updateReadyRestart => 'The update is ready and takes effect when you restart.';
  @override
  String updateInstallError(String error) => 'Failed to install the update: $error';
  @override
  String get updateMissingExecutable => 'The update is missing its main executable; the package may be corrupted';
  @override
  String get updateUnreadableExecutable => 'Could not read the architecture of the update executable; the package may be corrupted';
  @override
  String updateArchMismatch(String archs, String host) => 'The downloaded package ($archs) does not support this Mac ($host)';
  @override
  String get updateManualDownloadHint => 'Please download the installer for your hardware from the GitHub Releases page.';

  // --- macOS Menu Bar ---
  @override
  String get cliMenuInstall => 'Install sgv Command Line Tool…';
}
