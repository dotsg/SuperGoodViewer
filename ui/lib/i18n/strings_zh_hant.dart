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
  String get pageNavTooltip => '點擊跳轉頁面';
  @override
  String settingsTooltip(String shortcut) => '偏好設定 ($shortcut)';
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
  String get languageSection => '語言';
  @override
  String get displayLanguage => '介面語言';
  @override
  String get displayLanguageDesc => '選擇超好讀介面的顯示語言，即刻生效';
  @override
  String get appearanceSection => '外觀';
  @override
  String get themeMode => '外觀風格';
  @override
  String get themeModeDesc => '跟隨系統時，會隨作業系統的淺色 / 深色外觀自動切換';
  @override
  String get themeSystem => '跟隨系統';
  @override
  String get themeLight => '明亮模式';
  @override
  String get themeDark => '暗黑模式';
  @override
  String get autoReloadSection => '檔案自動重載';
  @override
  String get autoReload => '檔案變動自動熱重載';
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
  String get layoutModeFluid => '自適應長捲軸';
  @override
  String get layoutModeA4Portrait => 'A4 縱向分頁';
  @override
  String get layoutModeA4Landscape => 'A4 橫向分頁';
  @override
  String get layoutModeSlide169 => '16:9 寬螢幕投影片';
  @override
  String get layoutModeSlide43 => '4:3 傳統投影片';
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
      case 'preferences':
        return '偏好設定';
      case 'fontSettings':
        return '排版與字型設定';
      case 'keyboardShortcuts':
        return '自訂快捷鍵面板';
      case 'toggleMode':
        return '切換版式 / 檢視模式';
      case 'togglePresentation':
        return '全螢幕單頁示範';
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
      case 'preferences':
        return '開啟全域偏好設定面板（一般、字型、快捷鍵、CLI）';
      case 'fontSettings':
        return '開啟 CJK 字型排版與 1:2 等寬對齊設定面板';
      case 'keyboardShortcuts':
        return '開啟快捷鍵設定面板，可自由修改按鍵';
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

  // --- Settings Dialog - General Tab (cont.) ---
  @override
  String get restoreSession => '啟動時恢復上次工作階段';
  @override
  String get restoreSessionDesc => '重新啟動應用程式時自動還原上次瀏覽的文件與閱讀進度';
  @override
  String get enabledBadge => '已啟用';

  // --- Settings Dialog - Layout Tab (cont.) ---
  @override
  String get pageFormatSection => '頁面排版版式';
  @override
  String get pageFormatDesc => '設定文件預設排版形態。簡報請選擇 16:9 / 4:3 投影片，出版閱讀請選擇 A4 或自適應流式。';
  @override
  String get pageFormatFluidDesc => '鎖定黃金閱讀行寬，高度自適應，連續無縫捲軸捲動，適合技術文件與長文';
  @override
  String get pageFormatA4PortraitDesc => '標準 A4 出版縱向 (595.28 × 841.89 pt)，含頁首頁尾與孤行控制，適合出版列印';
  @override
  String get pageFormatA4LandscapeDesc => '標準 A4 出版橫向 (841.89 × 595.28 pt)，適合架構圖與橫向寬表排版';
  @override
  String get pageFormatSlide169Desc => '16:9 現代寬螢幕投影片 (960 × 540 pt)，大字級，適合高擬真簡報';
  @override
  String get pageFormatSlide43Desc => '4:3 經典傳統投影片 (960 × 720 pt)，適合傳統投影機簡報與學術報告';
  @override
  String get headerFooterDesc => '支援三插槽自訂。可用佔位巨集：{title} (標題)、{page} (目前頁)、{total} (總頁數)、{date} (日期)。流式模式下頁首頁尾會自動隱藏。';
  @override
  String get skipFirstPageDesc => '依出版物與簡報的標題頁慣例，第一頁不列印頁首頁尾';
  @override
  String get headerSlotsTitle => '頁首插槽';
  @override
  String get footerSlotsTitle => '頁尾插槽';

  // --- Settings Dialog - Typography Tab (cont.) ---
  @override
  String get mapleLinkCopied => '已複製 Maple Mono GitHub 連結到剪貼簿';
  @override
  String get pdfTypographyInlineNotice => '目前正在閱讀獨立 PDF 文件，此處的排版設定將在閱讀 Markdown 文件時生效。';
  @override
  String get fontOptionSystemRecommended => '系統出版推薦 (Inter + SF Pro + 蘋方/微軟雅黑)';
  @override
  String get fontOptionPingFang => '蘋方 (PingFang SC)';
  @override
  String get fontOptionSongti => '宋體 (Songti SC)';
  @override
  String get fontOptionHiragino => '冬青黑體 (Hiragino Sans GB)';
  @override
  String get fontOptionYaHei => '微軟雅黑 (Microsoft YaHei)';
  @override
  String get fontOptionSourceHanSans => '思源黑體 (Source Han Sans SC)';
  @override
  String get fontOptionInter => 'Inter (現代無襯線)';
  @override
  String get fontOptionMapleMono => 'Maple Mono (推薦：1:2 嚴格等寬對齊)';
  @override
  String get fontOptionMenlo => 'Menlo (macOS 系統預設等寬)';
  @override
  String get fontOptionMonaco => 'Monaco (macOS 經典等寬)';
  @override
  String get fontOptionCourierNew => 'Courier New (經典襯線等寬)';
  @override
  String fontOptionCustom(String name) => '$name (自訂)';
  @override
  String fontOptionInstalled(String name) => '$name (系統已安裝)';
  @override
  String get bodyTypographyTitle => '正文排版字型';
  @override
  String get monoTypographyTitle => '程式碼與 ASCII 表格字型';
  @override
  String get baseFontSizeTitle => '排版基礎字級';
  @override
  String get useRecommended => '恢復推薦';
  @override
  String get restoreDefault => '恢復預設';
  @override
  String restoreDefaultFontSize(String pt) => '恢復預設 ($pt pt)';
  @override
  String get decreaseFontSize => '縮小字級';
  @override
  String get increaseFontSize => '放大字級';
  @override
  String get restoreDefaultFonts => '恢復預設字型';
  @override
  String get mapleMonoReady => 'Maple Mono 已就緒 (1:2 嚴格等寬)';
  @override
  String get cjkMonoDetected => '偵測到 CJK 嚴格等寬字型';
  @override
  String get mapleMonoSuggested => '建議安裝 Maple Mono 字型';
  @override
  String get cjkMonoActiveDesc => 'CJK 嚴格等寬已生效，ASCII 表格與程式碼中英文嚴格 1:2 對齊。';
  @override
  String get cjkMonoMissingDesc => '缺少 CJK 等寬字型，ASCII 表格或混排程式碼可能有些微錯位。';
  @override
  String get downloadFont => '下載字型';
  @override
  String get copyLink => '複製連結';
  @override
  String get detectingFonts => '偵測中...';
  @override
  String get redetectFonts => '重新偵測';
  @override
  String get mapleMonoDefault => 'Maple Mono (預設)';
  @override
  String get livePreviewBadge => '即時排版預覽';
  @override
  String get livePreviewTitle => '排版即時渲染預覽';
  @override
  String get previewSpecimenHeading => '現代出版級技術文件排版';
  @override
  String get previewSpecimenBody => 'SuperGoodViewer 專為高密度技術文件、工程規格說明書與論文設計。本段文字即時套用目前設定的正文字型與基礎字級，展示精緻的中西文混排字距、行高節奏與標點間隙。The quick brown fox jumps over the lazy dog.';
  @override
  String previewCodeFont(String name) => '程式碼字型渲染：$name';
  @override
  String get asciiAlignmentCheck => 'ASCII 表格全形/半形嚴格 1:2 等寬對齊校驗';

  // --- Settings Dialog - Shortcuts Tab (cont.) ---
  @override
  String get shortcutModified => '已修改';
  @override
  String get resetShortcutToDefault => '恢復此項預設';

  // --- Settings Dialog - About Tab (cont.) ---
  @override
  String get aboutEngineSection => '核心排版渲染引擎';
  @override
  String get aboutTypstDesc => '毫秒級編譯核心，完整支援進階數學公式、表格與程式碼區塊';
  @override
  String get aboutPdfiumTitle => 'PDFium 向量渲染';
  @override
  String get aboutPdfiumDesc => '無損 120 FPS 流暢視口平移與局部預渲染技術';
  @override
  String get aboutCjkTitle => 'CJK 1:2 等寬保障';
  @override
  String get aboutCjkDesc => '內建 CJK 等寬字型感知，杜絕 ASCII 表格與圖表鋸齒錯位';
  @override
  String get loadSampleDocument => '載入精選排版範例';
  @override
  String get loadSampleDocumentDesc => '立即體驗包含複雜數學公式、Mermaid 圖表、Callout 標註與程式碼高亮的示範文件';

  // --- Presentation View (cont.) ---
  @override
  String get presentationNoContent => '找不到可放映的文件內容';
  @override
  String presentationLoadFailed(String error) => '載入放映文件失敗：$error';

  // --- Auto Update (cont.) ---
  @override
  String updateCurrentVersion(String version) => '目前版本：v$version';
  @override
  String updateSize(String size) => '大小：$size';
  @override
  String get releaseNotesTitle => '更新內容與最佳化';
  @override
  String get releaseNotesFallback => '包含效能最佳化與穩定性提升。';
  @override
  String get updateReadyRestart => '更新套件已就緒！重新啟動後即可生效。';
  @override
  String updateInstallError(String error) => '安裝更新時發生錯誤：$error';
  @override
  String get updateMissingExecutable => '更新套件主執行檔不存在，安裝套件可能已損壞';
  @override
  String get updateUnreadableExecutable => '無法解析更新套件主執行檔的架構，安裝套件可能已損壞';
  @override
  String updateArchMismatch(String archs, String host) => '下載的安裝套件架構 ($archs) 與目前硬體 ($host) 不相容';
  @override
  String get updateManualDownloadHint => '請前往 GitHub Releases 頁面手動下載符合目前硬體架構的安裝套件。';

  // --- macOS Menu Bar ---
  @override
  String get cliMenuInstall => '安裝 sgv 命令列工具…';
}
