import 'strings_zh_hans.dart';

/// Traditional Chinese (繁體中文) localization strings.
class ZhHantStrings extends ZhHansStrings {
  const ZhHantStrings();

  // --- General & App ---
  @override
  String get appTitle => '超好讀';
  @override
  String get appSubtitle => '基於 Typst 高效能排版引擎的新一代 Markdown & PDF 閱讀與示範器';
  @override
  String get welcomeTitle => '歡迎使用超好讀';
  @override
  String get confirm => '確認';
  @override
  String get cancel => '取消';
  @override
  String get close => '關閉';
  @override
  String get save => '儲存';
  @override
  String get reset => '重設';
  @override
  String get apply => '套用';
  @override
  String get retry => '重試';
  @override
  String get copy => '複製';
  @override
  String get copied => '已複製';
  @override
  String get delete => '刪除';
  @override
  String get edit => '編輯';
  @override
  String get success => '成功';
  @override
  String get error => '錯誤';
  @override
  String get warning => '警告';
  @override
  String get info => '提示';

  // --- Workspace & Floating Toolbar ---
  @override
  String get openDocument => '開啟本機檔案';
  @override
  String get exportPdf => '匯出出版級 PDF';
  @override
  String get exportPdfDialogTitle => '匯出為出版級 PDF';
  @override
  String exportPdfSuccess(String path) => '已成功匯出出版級 PDF 至 $path';
  @override
  String get exportPdfFailed => '匯出失敗，請重試';
  @override
  String openFileFailed(String err) => '開啟檔案失敗: $err';
  @override
  String degradedEquationsWarning(int count) => '$count 個公式渲染異常，已自動降級顯示原始 LaTeX';
  @override
  String get copiedSelectedText => '已複製所選文字';
  @override
  String toggleSidebarTooltip(String shortcut) => '切換側邊欄 ($shortcut)';
  @override
  String toggleSidebarCollapse(String shortcut) => '收起側邊欄 ($shortcut)';
  @override
  String toggleSidebarExpand(String shortcut) => '展開側邊欄 ($shortcut)';
  @override
  String sidebarCloseTooltip(String shortcut) => '收起側邊欄 ($shortcut 或 Esc)';
  @override
  String toggleThemeTooltip(bool isDark, String shortcut) =>
      isDark ? '切換為亮色模式 ($shortcut)' : '切換為暗黑模式 ($shortcut)';
  @override
  String toggleModeTooltip(String shortcut) => '切換版式 / 檢視模式 ($shortcut)';
  @override
  String togglePresentationTooltip(String shortcut) => '全螢幕單頁示範 ($shortcut / F5)';
  @override
  String toggleTwoPageTooltip(bool isTwoPage, String shortcut) => isTwoPage
      ? '目前為雙頁對開，點擊切換單頁 ($shortcut)'
      : '目前為單頁縱向，點擊切換雙頁對開 ($shortcut)';
  @override
  String zoomInTooltip(String shortcut) => '放大頁面 ($shortcut)';
  @override
  String zoomOutTooltip(String shortcut) => '縮小頁面 ($shortcut)';
  @override
  String resetZoomTooltip(String shortcut) => '實際大小 100% ($shortcut)';
  @override
  String get fitWidthTooltip => '滿視窗寬度';
  @override
  String get fitPageTooltip => '滿屏整頁';
  @override
  String get pageNavTooltip => '點擊跳轉頁面';
  @override
  String settingsTooltip(String shortcut) => '偏好設定 ($shortcut)';
  @override
  String reloadTooltip(String shortcut) => '重新編譯 / 重新整理 ($shortcut)';
  @override
  String get compiling => '排版中...';
  @override
  String get selectAll => '全選';
  @override
  String get previousPage => '上一頁';
  @override
  String get nextPage => '下一頁';
  @override
  String get fullScreenImmersive => '全螢幕沉浸瀏覽';
  @override
  String get originalSize => '100% (原始大小)';
  @override
  String get fitWindowWidth => '滿視窗 (適應寬度)';
  @override
  String get fitPageWhole => '全頁 (適應整頁)';
  @override
  String get zoomPresetsTooltip => '頁面縮放比例與預設';
  @override
  String get layoutSelectTooltip => '選擇版式';
  @override
  String hideToolbarTooltip(String shortcut) => '隱藏工具列 (Esc 或 $shortcut)';
  @override
  String targetDocNotExist(String file) => '目標文件不存在: $file';
  @override
  String get statusReady => '就緒';
  @override
  String get statusCompiling => '排版中...';
  @override
  String get loadSampleDoc => '載入體驗';
  @override
  String get discardChanges => '放棄修改';
  @override
  String get clearSlotTooltip => '清除此插槽';
  @override
  String layoutModeShortName(String format) {
    switch (format) {
      case 'fluid':
        return '流式';
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
  String get hudActualSize => '實際大小 100%';
  @override
  String hudFitWidth(int percent) => '滿視窗 ($percent%)';
  @override
  String hudFitPage(int percent) => '全頁 ($percent%)';
  @override
  String get hudTwoPage => '雙頁對開瀏覽';
  @override
  String get hudSinglePage => '單頁縱向瀏覽';
  @override
  String get hudTwoPageA4 => 'A4 雙頁對開瀏覽';
  @override
  String hudZoom(int percent) => '縮放: $percent%';

  // --- Drag & Drop ---
  @override
  String get dragDropTitle => '放開以在此視窗開啟文件';
  @override
  String get dragDropSubtitle =>
      '支援 Markdown (.md, .markdown)、PDF (.pdf)、Typst (.typ) 或包含 README 的專案目錄';
  @override
  String unsupportedFileFormat(String ext) =>
      '暫不支援開啟 $ext 格式檔案，請拖入 Markdown (.md) 或 PDF (.pdf)';
  @override
  String get unsupportedBinaryFile => '暫不支援開啟該二進位檔案，請拖入 Markdown (.md) 或 PDF (.pdf)';
  @override
  String get unsupportedDirectory => '所選資料夾中未找到可開啟的 Markdown 或 PDF 文件';
  @override
  String get unsupportedDropGeneral => '未找到支援開啟的 Markdown (.md) 或 PDF (.pdf) 檔案';

  // --- Sidebar ---
  @override
  String get sidebarTabOutline => '大綱目錄';
  @override
  String get sidebarTabRecent => '最近檔案';
  @override
  String get noOutlineFound => '暫無大綱目錄';
  @override
  String get noRecentFiles => '暫無歷史檔案';
  @override
  String get clearRecentHistory => '清除最近開啟紀錄';
  @override
  String recentFilesCount(int count) => '$count 個最近檔案';
  @override
  String pageNumberBadge(int page) => 'P$page';
  @override
  String get sidebarPositionSection => '側邊欄佈局';
  @override
  String get sidebarPosition => '側邊欄顯示位置';
  @override
  String get sidebarPositionDesc => '控制大綱目錄與最近檔案側邊欄停靠在視窗左側或右側';
  @override
  String get sidebarPositionLeft => '靠左顯示 (預設)';
  @override
  String get sidebarPositionRight => '靠右顯示';
  @override
  String get moveSidebarToLeft => '移至左側';
  @override
  String get moveSidebarToRight => '移至右側';
  @override
  String get resetSidebarWidthTooltip => '雙擊恢復默認寬度';

  // --- Search Bar & Jump Dialog ---
  @override
  String get searchPlaceholder => '尋找文件內容...';
  @override
  String get searchPrevious => '上一個 (Shift+Enter)';
  @override
  String get searchNext => '下一個 (Enter)';
  @override
  String get closeSearch => '關閉 (Esc)';
  @override
  String matchCount(int current, int total) => '$current / $total';
  @override
  String get noMatches => '無相符項目';
  @override
  String get jumpToPageTitle => '跳轉到頁面';
  @override
  String jumpToPageHint(int min, int max) => '請輸入頁碼 ($min - $max):';
  @override
  String get jumpButton => '跳轉';
  @override
  String get pageNavPrev => '上一頁 (← 或 [)';
  @override
  String get pageNavNext => '下一頁 (→ 或 ])';

  // --- Presentation View ---
  @override
  String get presentationPrev => '上一頁 (← / PageUp)';
  @override
  String get presentationNext => '下一頁 (→ / Space)';
  @override
  String get exitPresentation => '退出放映 (Esc)';
  @override
  String get presentationSearch => '文件內尋找 (Cmd+F / Ctrl+F)';
  @override
  String presentationSlideCount(int current, int total) => '$current / $total';

  // --- Settings Dialog - Common ---
  @override
  String get settingsTitle => '偏好設定';
  @override
  String get tabGeneral => '常規閱讀';
  @override
  String get tabLayout => '版式與頁首頁尾';
  @override
  String get tabTypography => '排版與字型';
  @override
  String get tabShortcuts => '快速鍵';
  @override
  String get tabCli => '命令列 (sgv)';
  @override
  String get tabAbout => '關於軟體';
  @override
  String get tabGeneralTitle => '常規與閱讀偏好';
  @override
  String get tabLayoutTitle => '版式形態與頁首頁尾自訂';
  @override
  String get tabTypographyTitle => '字型排版與中英文等寬對齊';
  @override
  String get tabShortcutsTitle => '快速鍵自訂設定';
  @override
  String get tabCliTitle => '命令列工具 (sgv) 整合';
  @override
  String get tabAboutTitle => '關於 SuperGoodViewer';

  // --- Settings Dialog - General Tab ---
  @override
  String get displayLanguage => '介面語言';
  @override
  String get displayLanguageDesc => '選擇超好讀介面的顯示語言，即刻生效';
  @override
  String get themeMode => '外觀風格';
  @override
  String get themeLight => '明亮模式 (Light)';
  @override
  String get themeDark => '暗黑模式 (Dark)';
  @override
  String get autoReloadSection => '檔案自動重載';
  @override
  String get autoReload => '檔案變動自動熱重載 (Auto Reload)';
  @override
  String get autoReloadDesc => '本機檔案內容變更儲存後，無需手動重新整理即時重新渲染並保持目前閱讀進度';
  @override
  String get sessionSection => '工作階段與歷程紀錄';
  @override
  String get recentDocsRecord => '最近開啟檔案紀錄';
  @override
  String get cacheSection => '預編譯 PDF 快取';
  @override
  String get localDiskCache => '本機磁碟快取';
  @override
  String get cacheDesc => '本機編譯的向量文件快取，有效加速二次開啟並降低 CPU 佔用';
  @override
  String get openCacheDirectory => '開啟目錄';
  @override
  String get openCacheDirectoryFailed => '開啟快取目錄失敗';
  @override
  String get clearCache => '清理快取';
  @override
  String get loadingCacheStats => '正在讀取快取統計...';
  @override
  String get noCacheFiles => '暫無快取檔案 (0 B)';
  @override
  String cacheCleared(String size) => '成功清理快取，釋放了 $size 磁碟空間';
  @override
  String currentCacheSize(int count, String size) => '已快取 $count 個文件 ($size)';

  // --- Settings Dialog - Layout Tab ---
  @override
  String get layoutMode => '預設閱讀版式';
  @override
  String get layoutModeFluid => '自適應長捲軸 (Fluid)';
  @override
  String get layoutModeA4Portrait => 'A4 縱向分頁 (Portrait)';
  @override
  String get layoutModeA4Landscape => 'A4 橫向分頁 (Landscape)';
  @override
  String get layoutModeSlide169 => '16:9 寬螢幕投影片 (Slide)';
  @override
  String get layoutModeSlide43 => '4:3 傳統投影片 (Slide)';
  @override
  String get twoPageSpread => '雙頁對開檢視 (A4 / 投影片)';
  @override
  String get twoPageSpreadDesc => '在分頁檢視中左右並排展示兩頁，呈現書籍與畫冊級對開閱讀體驗';
  @override
  String get marpCompatibility => 'Marp 語法相容模式';
  @override
  String get marpCompatibilityDesc => '支援識別 Markdown 檔案頭部的 marp: true 宣告及 --- 分頁符號，自動啟用投影片排版';
  @override
  String get headerFooterSection => '頁首與頁尾自訂';
  @override
  String get slotLeft => '左插槽';
  @override
  String get slotCenter => '中插槽';
  @override
  String get slotRight => '右插槽';
  @override
  String get slotHintCustom => '空或自訂文字';
  @override
  String get slotHintEmpty => '空';
  @override
  String get slotHintCopyright => '空或版權宣告';
  @override
  String get slotHintPageTotal => '空或 {page}/{total}';
  @override
  String get headerLeft => '頁首左側';
  @override
  String get headerCenter => '頁首置中';
  @override
  String get headerRight => '頁首右側';
  @override
  String get footerLeft => '頁尾左側';
  @override
  String get footerCenter => '頁尾置中';
  @override
  String get footerRight => '頁尾右側';
  @override
  String get slotNone => '無 (清除插槽)';
  @override
  String get slotTitle => '文件標題 (Title)';
  @override
  String get slotPageNumber => '目前頁碼 (Page Number)';
  @override
  String get slotTotalPages => '總頁数 (Total Pages)';
  @override
  String get slotPageOfTotal => '第 X 頁 / 共 Y 頁 (Page of Total)';
  @override
  String get slotDate => '目前日期 (Date)';
  @override
  String get slotTime => '目前時間 (Time)';
  @override
  String get showHeaderRule => '頁首底端分隔線';
  @override
  String get showFooterRule => '頁尾頂端分隔線';
  @override
  String get skipFirstPage => '首頁不顯示頁首與頁尾';
  @override
  String get clearHeaderSlots => '清空頁首';
  @override
  String get clearFooterSlots => '清空頁尾';
  @override
  String get saveAndApplyLayout => '儲存並套用版式';
  @override
  String get layoutSavedSuccess => '版式設定已成功儲存並套用！';
  @override
  String get layoutHasChanges => '版式與頁首頁尾有變動 (未儲存)';
  @override
  String get layoutUpToDate => '版式與頁首頁尾與當前文件一致';

  // --- Settings Dialog - Typography Tab ---
  @override
  String get pdfTypographyNotice =>
      '目前正在閱讀原生 PDF 檔案，字型大小與字型排版由 PDF 原始檔案內建字庫控制。此處的字型設定將在閱讀 Markdown 文件時生效。';
  @override
  String get fontSize => '內文字型大小';
  @override
  String get bodyFont => '內文文字字型';
  @override
  String get codeFont => '等寬程式碼字型';
  @override
  String get fontDefault => '系統預設 / Typst 內建';
  @override
  String get embeddedFonts => '內建出版字型';
  @override
  String get systemFonts => '已安裝系統字型';
  @override
  String get saveAndApplyTypography => '儲存並重新整理文件';
  @override
  String get typographySavedSuccess => '字型排版設定已儲存，正在重新渲染當前文件...';
  @override
  String get typographyHasChanges => '排版設定有變動 (未儲存到文件)';
  @override
  String get typographyUpToDate => '排版設定與當前文件一致';

  // --- Settings Dialog - Shortcuts Tab ---
  @override
  String get shortcutsDesc => '按一下快速鍵卡片後按下鍵盤即可自訂，支援組合鍵與功能鍵。';
  @override
  String get resetAllShortcuts => '恢復全部預設快速鍵';
  @override
  String get pressNewShortcut => '請按下新快速鍵...';
  @override
  String shortcutConflict(String name) => '與操作「$name」衝突，已替換原快速鍵';
  @override
  String shortcutCategoryName(String category) {
    switch (category) {
      case '视图模式':
        return '檢視模式';
      case '文档文件':
        return '檔案文件';
      case '缩放自适应':
        return '縮放自適應';
      case '排版与设置':
        return '排版與設定';
      default:
        return category;
    }
  }
  @override
  String shortcutActionName(String id, String defaultName) {
    switch (id) {
      case 'toggleMode':
        return '切換版式 / 檢視模式';
      case 'togglePresentation':
        return '全螢幕單頁示範 (PPT)';
      case 'toggleTheme':
        return '切換明亮 / 暗黑模式';
      case 'toggleTwoPage':
        return '切換單頁 / 雙頁對開';
      case 'toggleToolbar':
        return '顯示 / 隱藏底部浮動列';
      case 'findInDocument':
        return '尋找文件內容';
      case 'exportPdf':
        return '匯出為出版級 PDF';
      case 'openFile':
        return '開啟本機檔案';
      case 'toggleSidebar':
        return '展開 / 收起側邊欄';
      case 'compileDocument':
        return '重新整理 / 重新編譯';
      case 'openSettings':
        return '開啟偏好設定';
      case 'zoomIn':
        return '放大檢視';
      case 'zoomOut':
        return '縮小檢視';
      case 'resetZoom':
        return '重設縮放 (100%)';
      case 'fitWidth':
        return '適應視窗寬度';
      case 'fitPage':
        return '適應整頁';
      default:
        return defaultName;
    }
  }
  @override
  String shortcutActionDesc(String id, String defaultDesc) {
    switch (id) {
      case 'toggleMode':
        return '在自適應長捲軸、A4 縱向/橫向與 16:9/4:3 投影片版式之間切換';
      case 'togglePresentation':
        return '進入或退出全螢幕單頁投影片示範模式，方便演講展示';
      case 'toggleTheme':
        return '在日間明亮和夜間暗黑閱讀主題之間無縫切換';
      case 'toggleTwoPage':
        return '在 A4 出版模式下切換單頁縱向與雙頁對開書籍排版';
      case 'toggleToolbar':
        return '切換底部浮動工具列顯示狀態，進入極致沉浸 Zen 模式';
      case 'findInDocument':
        return '在目前文件中搜尋關鍵字或大綱章節';
      case 'exportPdf':
        return '匯出目前文件為出版級無損明亮模式向量 PDF';
      case 'openFile':
        return '透過系統檔案選擇器開啟並閱讀本機 Markdown 或 PDF 檔案';
      case 'toggleSidebar':
        return '顯示或收起文件多級大綱目錄及最近開啟歷史';
      case 'compileDocument':
        return '重新觸發 Typst 排版引擎編譯並即時重新整理';
      case 'openSettings':
        return '呼叫全域設定與自訂選項面板';
      case 'zoomIn':
        return '逐步放大目前頁面排版顯示比例';
      case 'zoomOut':
        return '逐步縮小目前頁面排版顯示比例';
      case 'resetZoom':
        return '恢復頁面顯示縮放為標準 1:1 實際大小';
      case 'fitWidth':
        return '自動計算並縮放至文件完全貼合視窗寬度';
      case 'fitPage':
        return '自動縮放使得單頁完整容納於目前視窗內';
      default:
        return defaultDesc;
    }
  }

  // --- Settings Dialog - CLI Tab ---
  @override
  String get cliTitle => '命令列工具 (sgv)';
  @override
  String get cliDescMac => '在 macOS 終端機中隨時透過 sgv 命令開啟 Markdown 或 PDF';
  @override
  String get cliDescWin => '在終端機 (CMD / PowerShell) 中隨時透過 sgv 命令開啟 Markdown 或 PDF';
  @override
  String get cliDescLinux => '在 Linux 終端機中隨時透過 sgv 命令開啟 Markdown 或 PDF';
  @override
  String get cliStatusReady => '已就緒 (已安裝在系統 PATH)';
  @override
  String get cliStatusNotInstalled => '尚未安裝到系統終端機';
  @override
  String get cliStatusPartialPath => '安裝不完整 (未新增到系統 PATH)';
  @override
  String get cliStatusPartialTools => '安裝不完整 (部分工具未就緒)';
  @override
  String cliSymlinkPath(String path) => '符號連結路徑: $path';
  @override
  String get cliInstall => '一鍵安裝到終端機';
  @override
  String get cliRelink => '重新連結 / 修復';
  @override
  String get cliReinstallRepair => '重新安裝 / 修復';
  @override
  String get cliUninstall => '解除安裝';
  @override
  String get cliCleanUninstall => '清除解除安裝';
  @override
  String get cliInstallSuccess => '🎉 \'sgv\' 命令列工具已成功安裝！可在終端機直接使用。';
  @override
  String get cliUninstallSuccess => '已成功解除安裝 \'sgv\' 命令列工具';
  @override
  String get cliAuthCancelled => '已取消授權操作';
  @override
  String cliInstallFailed(String msg) => msg.isEmpty ? '安裝失敗' : '安裝失敗: $msg';
  @override
  String cliUninstallFailed(String msg) => msg.isEmpty ? '解除安裝失敗' : '解除安裝失敗: $msg';
  @override
  String get cliMsgNotInstalled => '未安裝';
  @override
  String get cliErrorAppDataDirFailed => '無法定位本機應用程式資料目錄';
  @override
  String get cliErrorAppPathFailed => '無法取得目前程式路徑';
  @override
  String get cliErrorWriteCmdFailed => '寫入 sgv.cmd 指令碼失敗';
  @override
  String get cliErrorLocateLauncherFailed => '未能定位 sgv 啟動指令碼';
  @override
  String get cliErrorSymlinkFailed => '建立符號連結失敗';
  @override
  String get cliErrorAuthScriptInitFailed => '無法初始化系統授權指令碼';
  @override
  String get cliErrorPlatformNotSupported => '目前平台暫不支援';
  @override
  String get cliErrorUnknown => '未知錯誤';
  @override
  String get cliWarningPathFailed => '未能將安裝目錄新增到環境變數 PATH（登錄檔受限），命令列可能無法直接呼叫';
  @override
  String get cliWarningPs1UpdateFailed => 'sgv.ps1 未能更新（可能被佔用），PowerShell 下可能仍指向舊版本';
  @override
  String get cliWarningPs1CreateFailed => '未能建立 sgv.ps1 指令稿';
  @override
  String get cliWarningCliToolFailed => '未能建立 sgv-cli 捷徑';
  @override
  String cliWarningCombined(List<String> warnings) {
    if (warnings.isEmpty) return '';
    final buffer = StringBuffer('指令稿已產生，但')..write(warnings[0]);
    for (var i = 1; i < warnings.length; i++) {
      buffer.write('；且 ');
      buffer.write(warnings[i]);
    }
    return buffer.toString();
  }
  @override
  String get cliUsageExamples => '使用範例';
  @override
  String get cliExampleCurrentDir => '開啟目前目錄下的 Markdown 文件';
  @override
  String get cliExampleAnyFile => '支援絕對路徑與相對路徑';
  @override
  String get cliExampleLaunch => '快速啟動或啟用超好讀';
  @override
  String get cliExampleStdin => '透過管道即時預覽 stdin';
  @override
  String get cliExampleOpenMarkdown => '在閱讀器中開啟 Markdown 文件';
  @override
  String get cliExampleExportSingle => '無周邊匯出單篇 Markdown 為出版級 PDF';
  @override
  String get cliExampleExportBatch => '批次將目錄下全部 Markdown 匯出為 PDF';
  @override
  String get cliHintQuickPreview => '安裝後可直接在終端機中輸入 sgv README.md 極速預覽任何文件';
  @override
  String get cliTipMac => '提示：點擊安裝若系統需要權限，macOS 會自動快顯指紋或管理員密碼授權視窗，無需手動開啟終端機輸入任何命令。';
  @override
  String get cliTipWin => '提示：安裝後可在命令提示字元、PowerShell 或 Windows Terminal 中直接執行 sgv 命令。';
  @override
  String get cliTipLinux => '提示：安裝將在 ~/.local/bin 中建立 sgv 符號連結，請確保該目錄在 PATH 環境變數中。';
  @override
  String get copyCommandTooltip => '複製命令';
  @override
  String copiedCommand(String cmd) => '已複製命令: $cmd';

  // --- Settings Dialog - About Tab ---
  @override
  String aboutVersion(String ver) => '版本 $ver';
  @override
  String get aboutEngine => '排版引擎: Typst 0.13 高效能原生核心';
  @override
  String get aboutFramework => '介面架構: Flutter Desktop (macOS / Windows / Linux)';
  @override
  String get aboutGithub => 'GitHub 開源專案';
  @override
  String get aboutLicense => '開源協議: Apache 2.0';

  // --- Auto Update ---
  @override
  String get checkForUpdates => '檢查更新';
  @override
  String get checkingForUpdates => '正在檢查更新...';
  @override
  String get upToDate => '目前已是最新版本';
  @override
  String get updateAvailable => '發現新版本';
  @override
  String get updateNow => '立即更新';
  @override
  String get downloadingUpdate => '正在下載更新...';
  @override
  String get restartToUpdate => '立即重啟以完成更新';
  @override
  String get skipThisVersion => '忽略此版本';
  @override
  String get remindMeLater => '稍後提醒';
  @override
  String get viewOnWeb => '在網頁查看';
  @override
  String get autoCheckUpdates => '啟動時自動檢查更新';
  @override
  String get updateFailed => '檢查或下載更新失敗';
  @override
  String get installingUpdate => '正在準備更新並重啟...';
}
