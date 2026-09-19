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
  String get welcomeTitle => 'Welcome to SuperGoodViewer';
  @override
  String get confirm => 'Confirm';
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
  String get fitWidthTooltip => 'Fit Width';
  @override
  String get fitPageTooltip => 'Fit Page';
  @override
  String get pageNavTooltip => 'Click to Jump to Page';
  @override
  String settingsTooltip(String shortcut) => 'Preferences ($shortcut)';
  @override
  String reloadTooltip(String shortcut) => 'Recompile / Refresh ($shortcut)';
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
  String get statusCompiling => 'Typesetting...';
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
  @override
  String hudZoom(int percent) => 'Zoom: $percent%';

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
  @override
  String get presentationSearch => 'Find in Presentation (Cmd+F / Ctrl+F)';
  @override
  String presentationSlideCount(int current, int total) => '$current / $total';

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
  String get displayLanguage => 'Display Language';
  @override
  String get displayLanguageDesc => 'Select the display language for SuperGoodViewer';
  @override
  String get langSystem => 'System Default';
  @override
  String get langZhHans => '简体中文 (Simplified Chinese)';
  @override
  String get langZhHant => '繁體中文 (Traditional Chinese)';
  @override
  String get langEn => 'English';
  @override
  String get themeMode => 'Appearance Theme';
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
  String get layoutMode => 'Default Layout Mode';
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
  String get twoPageSpread => 'Two-Page Spread (A4 / Slides)';
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
  String get slotNone => 'None (Clear Slot)';
  @override
  String get slotTitle => 'Document Title';
  @override
  String get slotPageNumber => 'Page Number';
  @override
  String get slotTotalPages => 'Total Pages';
  @override
  String get slotPageOfTotal => 'Page X of Y';
  @override
  String get slotDate => 'Current Date';
  @override
  String get slotTime => 'Current Time';
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
  String fontSizePt(String pt) => '$pt pt';
  @override
  String get bodyFont => 'Body Font Family';
  @override
  String get codeFont => 'Monospace Code Font';
  @override
  String get fontDefault => 'System Default / Typst Built-in';
  @override
  String get embeddedFonts => 'Built-in Publishing Fonts';
  @override
  String get systemFonts => 'Installed System Fonts';
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
      case 'toggleMode':
        return 'Switch Layout / View Mode';
      case 'togglePresentation':
        return 'Full-Screen Presentation (PPT)';
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
  String cliInstallFailed(String msg) => 'Installation failed: $msg';
  @override
  String cliUninstallFailed(String msg) => 'Uninstall failed: $msg';
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
  @override
  String get aboutEngine => 'Typesetting Engine: Typst 0.13 High-Performance Core';
  @override
  String get aboutFramework => 'UI Framework: Flutter Desktop (macOS / Windows / Linux)';
  @override
  String get aboutGithub => 'GitHub Open Source Project';
  @override
  String get aboutLicense => 'License: Apache 2.0';

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
}
