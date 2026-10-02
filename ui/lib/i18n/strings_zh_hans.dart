import 'app_strings.dart';

/// Simplified Chinese (简体中文) localization strings.
class ZhHansStrings implements AppStrings {
  const ZhHansStrings();

  // --- General & App ---
  @override
  String get appTitle => '超好读';
  @override
  String get appSubtitle => '基于 Typst 高性能排版引擎的新一代 Markdown & PDF 阅读与演示器';
  @override
  String get cancel => '取消';
  @override
  String get close => '关闭';
  @override
  String get save => '保存';
  @override
  String get reset => '重置';
  @override
  String get apply => '应用';
  @override
  String get retry => '重试';
  @override
  String get copy => '复制';
  @override
  String get copied => '已复制';
  @override
  String get delete => '删除';
  @override
  String get edit => '编辑';
  @override
  String get success => '成功';
  @override
  String get error => '错误';
  @override
  String get warning => '警告';
  @override
  String get info => '提示';

  // --- Workspace & Floating Toolbar ---
  @override
  String get openDocument => '打开本地文档';
  @override
  String get exportPdf => '导出出版级 PDF';
  @override
  String get exportPdfDialogTitle => '导出为出版级 PDF';
  @override
  String exportPdfSuccess(String path) => '已成功导出出版级 PDF 至 $path';
  @override
  String get exportPdfFailed => '导出失败，请重试';
  @override
  String openFileFailed(String err) => '打开文件失败: $err';
  @override
  String degradedEquationsWarning(int count) => '$count 个公式渲染异常，已自动降级展示原始 LaTeX';
  @override
  String get copiedSelectedText => '已复制所选文本';
  @override
  String toggleSidebarTooltip(String shortcut) => '切换侧边栏 ($shortcut)';
  @override
  String toggleSidebarCollapse(String shortcut) => '收起侧边栏 ($shortcut)';
  @override
  String toggleSidebarExpand(String shortcut) => '展开侧边栏 ($shortcut)';
  @override
  String sidebarCloseTooltip(String shortcut) => '收起侧边栏 ($shortcut 或 Esc)';
  @override
  String toggleThemeTooltip(bool isDark, String shortcut) =>
      isDark ? '切换为亮色模式 ($shortcut)' : '切换为暗黑模式 ($shortcut)';
  @override
  String toggleModeTooltip(String shortcut) => '切换版式 / 视图模式 ($shortcut)';
  @override
  String togglePresentationTooltip(String shortcut) => '全屏单页演示 ($shortcut / F5)';
  @override
  String toggleTwoPageTooltip(bool isTwoPage, String shortcut) => isTwoPage
      ? '当前为双页对开，点击切换单页 ($shortcut)'
      : '当前为单页纵向，点击切换双页对开 ($shortcut)';
  @override
  String zoomInTooltip(String shortcut) => '放大页面 ($shortcut)';
  @override
  String zoomOutTooltip(String shortcut) => '缩小页面 ($shortcut)';
  @override
  String resetZoomTooltip(String shortcut) => '实际大小 100% ($shortcut)';
  @override
  String get pageNavTooltip => '点击跳转页面';
  @override
  String settingsTooltip(String shortcut) => '偏好设置 ($shortcut)';
  @override
  String get compiling => '排版中...';
  @override
  String get selectAll => '全选';
  @override
  String get previousPage => '上一页';
  @override
  String get nextPage => '下一页';
  @override
  String get fullScreenImmersive => '全屏沉浸浏览';
  @override
  String get originalSize => '100% (原始大小)';
  @override
  String get fitWindowWidth => '满窗口 (适应宽度)';
  @override
  String get fitPageWhole => '满屏 (适应整页)';
  @override
  String get zoomPresetsTooltip => '页面缩放比例与预设';
  @override
  String get layoutSelectTooltip => '选择版式';
  @override
  String hideToolbarTooltip(String shortcut) => '隐藏工具栏 (Esc 或 $shortcut)';
  @override
  String targetDocNotExist(String file) => '目标文档不存在: $file';
  @override
  String get statusReady => '就绪';
  @override
  String get loadSampleDoc => '载入体验';
  @override
  String get discardChanges => '放弃修改';
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
  String get hudActualSize => '实际大小 100%';
  @override
  String hudFitWidth(int percent) => '满窗口 ($percent%)';
  @override
  String hudFitPage(int percent) => '满屏 ($percent%)';
  @override
  String get hudTwoPage => '双页对开浏览';
  @override
  String get hudSinglePage => '单页纵向浏览';
  @override
  String get hudTwoPageA4 => 'A4 双页对开浏览';

  // --- Drag & Drop ---
  @override
  String get dragDropTitle => '释放以在此窗口打开文档';
  @override
  String get dragDropSubtitle =>
      '支持 Markdown (.md, .markdown)、PDF (.pdf)、Typst (.typ) 或包含 README 的项目目录';
  @override
  String unsupportedFileFormat(String ext) =>
      '暂不支持打开 $ext 格式文件，请拖入 Markdown (.md) 或 PDF (.pdf)';
  @override
  String get unsupportedBinaryFile => '暂不支持打开该二进制文件，请拖入 Markdown (.md) 或 PDF (.pdf)';
  @override
  String get unsupportedDirectory => '所选文件夹中未找到可打开的 Markdown 或 PDF 文档';
  @override
  String get unsupportedDropGeneral => '未找到支持打开的 Markdown (.md) 或 PDF (.pdf) 文件';

  // --- Sidebar ---
  @override
  String get sidebarTabOutline => '大纲目录';
  @override
  String get sidebarTabRecent => '最近文件';
  @override
  String get noOutlineFound => '当前文档未检测到标题大纲';
  @override
  String get noRecentFiles => '暂无历史文件';
  @override
  String get clearRecentHistory => '清空';
  @override
  String recentFilesCount(int count) => count > 0 ? '历史文件 ($count)' : '历史文件';
  @override
  String pageNumberBadge(int page) => 'P$page';
  @override
  String get sidebarPositionSection => '侧边栏布局';
  @override
  String get sidebarPosition => '侧边栏显示位置';
  @override
  String get sidebarPositionDesc => '控制大纲目录与最近文件侧边栏停靠在窗口左侧或右侧';
  @override
  String get sidebarPositionLeft => '靠左显示 (默认)';
  @override
  String get sidebarPositionRight => '靠右显示';
  @override
  String get moveSidebarToLeft => '移至左侧';
  @override
  String get moveSidebarToRight => '移至右侧';
  @override
  String get resetSidebarWidthTooltip => '双击恢复默认宽度';

  // --- Search Bar & Jump Dialog ---
  @override
  String get searchPlaceholder => '查找文档内容...';
  @override
  String get searchPrevious => '上一个 (Shift+Enter)';
  @override
  String get searchNext => '下一个 (Enter)';
  @override
  String get closeSearch => '关闭 (Esc)';
  @override
  String matchCount(int current, int total) => '$current / $total';
  @override
  String get noMatches => '无匹配';
  @override
  String get jumpToPageTitle => '跳转到页面';
  @override
  String jumpToPageHint(int min, int max) => '请输入页码 ($min - $max):';
  @override
  String get jumpButton => '跳转';
  @override
  String get pageNavPrev => '上一页 (← 或 [)';
  @override
  String get pageNavNext => '下一页 (→ 或 ])';

  // --- Presentation View ---
  @override
  String get presentationPrev => '上一页 (← / PageUp)';
  @override
  String get presentationNext => '下一页 (→ / Space)';
  @override
  String get exitPresentation => '退出放映 (Esc)';

  // --- Settings Dialog - Common ---
  @override
  String get settingsTitle => '偏好设置';
  @override
  String get tabGeneral => '常规阅读';
  @override
  String get tabLayout => '版式与页眉页脚';
  @override
  String get tabTypography => '排版与字体';
  @override
  String get tabShortcuts => '快捷键';
  @override
  String get tabCli => '命令行 (sgv)';
  @override
  String get tabAbout => '关于软件';
  @override
  String get tabGeneralTitle => '常规与阅读偏好';
  @override
  String get tabLayoutTitle => '版式形态与页眉页脚定制';
  @override
  String get tabTypographyTitle => '字体排版与中英文等宽对齐';
  @override
  String get tabShortcutsTitle => '快捷键自定义设置';
  @override
  String get tabCliTitle => '命令行工具 (sgv) 集成';
  @override
  String get tabAboutTitle => '关于 SuperGoodViewer';

  // --- Settings Dialog - General Tab ---
  @override
  String get languageSection => '语言';
  @override
  String get displayLanguage => '界面语言';
  @override
  String get displayLanguageDesc => '选择超好读界面的显示语言，即刻生效';
  @override
  String get appearanceSection => '外观';
  @override
  String get themeMode => '外观主题';
  @override
  String get themeModeDesc => '跟随系统时，会随操作系统的浅色 / 深色外观自动切换';
  @override
  String get themeSystem => '跟随系统';
  @override
  String get themeLight => '明亮模式';
  @override
  String get themeDark => '暗黑模式';
  @override
  String get autoReloadSection => '文档自动重载';
  @override
  String get autoReload => '文件修改自动热重载';
  @override
  String get autoReloadDesc => '本地文件内容变更保存后，无需手动刷新即时重新渲染并保持当前阅读进度';
  @override
  String get sessionSection => '会话与历史记录';
  @override
  String get recentDocsRecord => '最近打开文档记录';
  @override
  String get cacheSection => '预编译 PDF 缓存';
  @override
  String get localDiskCache => '本地磁盘缓存';
  @override
  String get cacheDesc => '本地编译的矢量文档缓存，有效加速二次打开并降低 CPU 占用';
  @override
  String get openCacheDirectory => '打开目录';
  @override
  String get openCacheDirectoryFailed => '打开缓存目录失败';
  @override
  String get clearCache => '清理缓存';
  @override
  String get loadingCacheStats => '正在读取缓存统计...';
  @override
  String get noCacheFiles => '暂无缓存文件 (0 B)';
  @override
  String cacheCleared(String size) => '成功清理缓存，释放了 $size 磁盘空间';
  @override
  String currentCacheSize(int count, String size) => '已缓存 $count 个文档 ($size)';

  // --- Settings Dialog - Layout Tab ---
  @override
  String get layoutModeFluid => '自适应长卷轴';
  @override
  String get layoutModeA4Portrait => 'A4 纵向分页';
  @override
  String get layoutModeA4Landscape => 'A4 横向分页';
  @override
  String get layoutModeSlide169 => '16:9 宽屏幻灯片';
  @override
  String get layoutModeSlide43 => '4:3 传统幻灯片';
  @override
  String get twoPageSpreadDesc => '在分页视图中左右并排展示两页，呈现书籍与画册级对开阅读体验';
  @override
  String get marpCompatibility => 'Marp 语法兼容模式';
  @override
  String get marpCompatibilityDesc => '支持识别 Markdown 文件头部的 marp: true 声明及 --- 分页符，自动启用幻灯片排版';
  @override
  String get headerFooterSection => '页眉与页脚定制';
  @override
  String get slotLeft => '左插槽';
  @override
  String get slotCenter => '中插槽';
  @override
  String get slotRight => '右插槽';
  @override
  String get slotHintCustom => '空或自定义文字';
  @override
  String get slotHintEmpty => '空';
  @override
  String get slotHintCopyright => '空或版权声明';
  @override
  String get slotHintPageTotal => '空或 {page}/{total}';
  @override
  String get headerLeft => '页眉左侧';
  @override
  String get headerCenter => '页眉居中';
  @override
  String get headerRight => '页眉右侧';
  @override
  String get footerLeft => '页脚左侧';
  @override
  String get footerCenter => '页脚居中';
  @override
  String get footerRight => '页脚右侧';
  @override
  String get showHeaderRule => '页眉底端分割线';
  @override
  String get showFooterRule => '页脚顶端分割线';
  @override
  String get skipFirstPage => '首页不显示页眉与页脚';
  @override
  String get clearHeaderSlots => '清空页眉';
  @override
  String get clearFooterSlots => '清空页脚';
  @override
  String get saveAndApplyLayout => '保存并应用版式';
  @override
  String get layoutSavedSuccess => '版式设置已成功保存并应用！';
  @override
  String get layoutHasChanges => '版式与页眉页脚有变动 (未保存)';
  @override
  String get layoutUpToDate => '版式与页眉页脚与当前文档一致';

  // --- Settings Dialog - Typography Tab ---
  @override
  String get pdfTypographyNotice =>
      '当前正在阅读原生 PDF 文件，字号与字体排版由 PDF 原始文件内置字库控制。此处的字体设置将在阅读 Markdown 文档时生效。';
  @override
  String get fontSize => '正文字号大小';
  @override
  String get bodyFont => '正文文本字体';
  @override
  String get codeFont => '等宽代码字体';
  @override
  String get saveAndApplyTypography => '保存并刷新文档';
  @override
  String get typographySavedSuccess => '字体排版设置已保存，正在重新渲染当前文档...';
  @override
  String get typographyHasChanges => '排版设置有变动 (未保存到文档)';
  @override
  String get typographyUpToDate => '排版设置与当前文档一致';

  // --- Settings Dialog - Shortcuts Tab ---
  @override
  String get shortcutsDesc => '单击快捷键按键卡片后按下键盘即可自定义，支持组合键与功能键。';
  @override
  String get resetAllShortcuts => '恢复全部默认快捷键';
  @override
  String get pressNewShortcut => '请按下新快捷键...';
  @override
  String shortcutConflict(String name) => '与操作「$name」冲突，已替换原快捷键';
  @override
  String shortcutCategoryName(String category) => category;
  @override
  String shortcutActionName(String id, String defaultName) {
    switch (id) {
      case 'toggleMode':
        return '切换版式 / 视图模式';
      case 'togglePresentation':
        return '全屏单页演示';
      case 'toggleTheme':
        return '切换明亮 / 暗黑模式';
      case 'toggleTwoPage':
        return '切换单页 / 双页对开';
      case 'toggleToolbar':
        return '显示 / 隐藏底部浮动栏';
      case 'findInDocument':
        return '查找文档内容';
      case 'exportPdf':
        return '导出为出版级 PDF';
      case 'openFile':
        return '打开本地文档';
      case 'toggleSidebar':
        return '展开 / 收起侧边栏';
      case 'compileDocument':
        return '刷新 / 重新编译';
      case 'openSettings':
        return '打开偏好设置';
      case 'zoomIn':
        return '放大视图';
      case 'zoomOut':
        return '缩小视图';
      case 'resetZoom':
        return '重置缩放 (100%)';
      case 'fitWidth':
        return '适应窗口宽度';
      case 'fitPage':
        return '适应整页';
      default:
        return defaultName;
    }
  }
  @override
  String shortcutActionDesc(String id, String defaultDesc) {
    switch (id) {
      case 'toggleMode':
        return '在自适应长卷轴、A4 纵向/横向与 16:9/4:3 幻灯片版式之间切换';
      case 'togglePresentation':
        return '进入或退出全屏单页幻灯片演示模式，方便演讲展示';
      case 'toggleTheme':
        return '在日间明亮和夜间暗黑阅读主题之间无缝切换';
      case 'toggleTwoPage':
        return '在 A4 出版模式下切换单页纵向与双页对开书籍排版';
      case 'toggleToolbar':
        return '切换底部浮动工具栏显示状态，进入极致沉浸 Zen 模式';
      case 'findInDocument':
        return '在当前文档中搜索关键词或大纲章节';
      case 'exportPdf':
        return '导出当前文档为出版级无损明亮模式矢量 PDF';
      case 'openFile':
        return '通过系统文件选择器打开并阅读本地 Markdown 或 PDF 文件';
      case 'toggleSidebar':
        return '显示或收起文档多级大纲目录及最近打开历史';
      case 'compileDocument':
        return '重新触发 Typst 排版引擎编译并即时刷新';
      case 'openSettings':
        return '呼出全局配置与自定义选项面板';
      case 'zoomIn':
        return '逐步放大当前页面排版显示比例';
      case 'zoomOut':
        return '逐步缩小当前页面排版显示比例';
      case 'resetZoom':
        return '恢复页面显示缩放为标准 1:1 实际大小';
      case 'fitWidth':
        return '自动计算并缩放至文档完全贴合窗口宽度';
      case 'fitPage':
        return '自动缩放使得单页完整容纳于当前窗口内';
      default:
        return defaultDesc;
    }
  }

  // --- Settings Dialog - CLI Tab ---
  @override
  String get cliTitle => '命令行工具 (sgv)';
  @override
  String get cliDescMac => '在 macOS 终端中随时通过 sgv 命令打开 Markdown 或 PDF';
  @override
  String get cliDescWin => '在终端 (CMD / PowerShell) 中随时通过 sgv 命令打开 Markdown 或 PDF';
  @override
  String get cliDescLinux => '在 Linux 终端中随时通过 sgv 命令打开 Markdown 或 PDF';
  @override
  String get cliStatusReady => '已就绪 (已安装在系统 PATH)';
  @override
  String get cliStatusNotInstalled => '尚未安装到系统终端';
  @override
  String get cliStatusPartialPath => '安装不完整 (未添加到系统 PATH)';
  @override
  String get cliStatusPartialTools => '安装不完整 (部分工具未就绪)';
  @override
  String cliSymlinkPath(String path) => '软链接路径: $path';
  @override
  String get cliInstall => '一键安装到终端';
  @override
  String get cliRelink => '重新链接 / 修复';
  @override
  String get cliReinstallRepair => '重新安装 / 修复';
  @override
  String get cliUninstall => '卸载';
  @override
  String get cliCleanUninstall => '卸载清理';
  @override
  String get cliInstallSuccess => '🎉 \'sgv\' 命令行工具已成功安装！可在终端直接使用。';
  @override
  String get cliUninstallSuccess => '已成功卸载 \'sgv\' 命令行工具';
  @override
  String get cliAuthCancelled => '已取消授权操作';
  @override
  String cliInstallFailed(String msg) => msg.isEmpty ? '安装失败' : '安装失败: $msg';
  @override
  String cliUninstallFailed(String msg) => msg.isEmpty ? '卸载失败' : '卸载失败: $msg';
  @override
  String get cliMsgNotInstalled => '未安装';
  @override
  String get cliErrorAppDataDirFailed => '无法定位本地应用数据目录';
  @override
  String get cliErrorAppPathFailed => '无法获取当前程序路径';
  @override
  String get cliErrorWriteCmdFailed => '写入 sgv.cmd 脚本失败';
  @override
  String get cliErrorLocateLauncherFailed => '未能定位 sgv 启动脚本';
  @override
  String get cliErrorSymlinkFailed => '创建符号链接失败';
  @override
  String get cliErrorAuthScriptInitFailed => '无法初始化系统授权脚本';
  @override
  String get cliErrorPlatformNotSupported => '当前平台暂不支持';
  @override
  String get cliErrorUnknown => '未知错误';
  @override
  String get cliWarningPathFailed => '未能将安装目录添加到环境变量 PATH（注册表受限），命令行可能无法直接调用';
  @override
  String get cliWarningPs1UpdateFailed => 'sgv.ps1 未能更新（可能被占用），PowerShell 下可能仍指向旧版本';
  @override
  String get cliWarningPs1CreateFailed => '未能创建 sgv.ps1 脚本';
  @override
  String get cliWarningCliToolFailed => '未能创建 sgv-cli 快捷方式';
  @override
  String cliWarningCombined(List<String> warnings) {
    if (warnings.isEmpty) return '';
    final buffer = StringBuffer('脚本已生成，但')..write(warnings[0]);
    for (var i = 1; i < warnings.length; i++) {
      buffer.write('；且 ');
      buffer.write(warnings[i]);
    }
    return buffer.toString();
  }
  @override
  String get cliUsageExamples => '使用示例';
  @override
  String get cliExampleCurrentDir => '打开当前目录下的 Markdown 文档';
  @override
  String get cliExampleAnyFile => '支持绝对路径与相对路径';
  @override
  String get cliExampleLaunch => '快速激活或启动超好读';
  @override
  String get cliExampleStdin => '通过管道即时预览 stdin';
  @override
  String get cliExampleOpenMarkdown => '在阅读器中打开 Markdown 文档';
  @override
  String get cliExampleExportSingle => '无头导出单篇 Markdown 为出版级 PDF';
  @override
  String get cliExampleExportBatch => '批量将目录下全部 Markdown 导出为 PDF';
  @override
  String get cliHintQuickPreview => '安装后可直接在终端中输入 sgv README.md 极速预览任何文档';
  @override
  String get cliTipMac => '提示：点击安装若系统需要权限，macOS 会自动弹出指纹或管理员密码授权窗口，无需您手动打开终端输入任何命令。';
  @override
  String get cliTipWin => '提示：安装后可在命令提示符、PowerShell 或 Windows Terminal 中直接运行 sgv 命令。';
  @override
  String get cliTipLinux => '提示：安装将在 ~/.local/bin 中创建 sgv 软链接，请确保该目录在 PATH 环境变量中。';
  @override
  String get copyCommandTooltip => '复制命令';
  @override
  String copiedCommand(String cmd) => '已复制命令: $cmd';

  // --- Settings Dialog - About Tab ---
  @override
  String aboutVersion(String ver) => '版本 $ver';

  // --- Auto Update ---
  @override
  String get checkForUpdates => '检查更新';
  @override
  String get checkingForUpdates => '正在检查更新...';
  @override
  String get upToDate => '当前已是最新版本';
  @override
  String get updateAvailable => '发现新版本';
  @override
  String get updateNow => '立即更新';
  @override
  String get downloadingUpdate => '正在下载更新...';
  @override
  String get restartToUpdate => '立即重启以完成更新';
  @override
  String get skipThisVersion => '忽略此版本';
  @override
  String get remindMeLater => '稍后提醒';
  @override
  String get viewOnWeb => '在网页查看';
  @override
  String get autoCheckUpdates => '启动时自动检查更新';
  @override
  String get updateFailed => '检查或下载更新失败';
  @override
  String get installingUpdate => '正在准备更新并重启...';

  // --- Settings Dialog - General Tab (cont.) ---
  @override
  String get restoreSession => '启动恢复上次会话';
  @override
  String get restoreSessionDesc => '重新启动应用时自动还原上次浏览文档与阅读进度';
  @override
  String get enabledBadge => '已启用';

  // --- Settings Dialog - Layout Tab (cont.) ---
  @override
  String get pageFormatSection => '页面排版版式';
  @override
  String get pageFormatDesc => '设置文档默认排版形态。演示请选择 16:9 / 4:3 幻灯片，出版阅读请选择 A4 或自适应流式。';
  @override
  String get pageFormatFluidDesc => '锁定黄金阅读行宽，高度自适应，连续无缝卷轴滚动，适合技术文档与长文';
  @override
  String get pageFormatA4PortraitDesc => '标准 A4 出版纵向 (595.28 × 841.89 pt)，带页眉页脚与孤行控制，适合出版打印';
  @override
  String get pageFormatA4LandscapeDesc => '标准 A4 出版横向 (841.89 × 595.28 pt)，适合架构图与横向宽表排版';
  @override
  String get pageFormatSlide169Desc => '16:9 现代宽屏幻灯片 (960 × 540 pt)，大字号，适合高保真演示';
  @override
  String get pageFormatSlide43Desc => '4:3 经典传统幻灯片 (960 × 720 pt)，适合传统投影仪演示与学术报告';
  @override
  String get headerFooterDesc => '支持三插槽定制。可用占位宏：{title} (标题)、{page} (当前页)、{total} (总页数)、{date} (日期)。在流式模式下页眉页脚自动隐藏。';
  @override
  String get skipFirstPageDesc => '出版物与演示文稿的标题页惯例，第一页不打印页眉页脚';
  @override
  String get headerSlotsTitle => '页眉插槽';
  @override
  String get footerSlotsTitle => '页脚插槽';

  // --- Settings Dialog - Typography Tab (cont.) ---
  @override
  String get mapleLinkCopied => '已复制 Maple Mono GitHub 链接到剪贴板';
  @override
  String get pdfTypographyInlineNotice => '当前正在阅读独立 PDF 文档，此处的排版设置将在阅读 Markdown 文档时生效。';
  @override
  String get fontOptionSystemRecommended => '系统出版推荐 (Inter + SF Pro + 苹方/微软雅黑)';
  @override
  String get fontOptionPingFang => '苹方 (PingFang SC)';
  @override
  String get fontOptionSongti => '宋体 (Songti SC)';
  @override
  String get fontOptionHiragino => '冬青黑体 (Hiragino Sans GB)';
  @override
  String get fontOptionYaHei => '微软雅黑 (Microsoft YaHei)';
  @override
  String get fontOptionSourceHanSans => '思源黑体 (Source Han Sans SC)';
  @override
  String get fontOptionInter => 'Inter (现代无衬线)';
  @override
  String get fontOptionMapleMono => 'Maple Mono (推荐：1:2 严格等宽对齐)';
  @override
  String get fontOptionMenlo => 'Menlo (macOS 系统默认等宽)';
  @override
  String get fontOptionMonaco => 'Monaco (macOS 经典等宽)';
  @override
  String get fontOptionCourierNew => 'Courier New (经典衬线等宽)';
  @override
  String fontOptionCustom(String name) => '$name (自定义)';
  @override
  String fontOptionInstalled(String name) => '$name (系统已安装)';
  @override
  String get bodyTypographyTitle => '正文排版字体';
  @override
  String get monoTypographyTitle => '代码与 ASCII 表格字体';
  @override
  String get baseFontSizeTitle => '排版基础字号';
  @override
  String get useRecommended => '恢复推荐';
  @override
  String get restoreDefault => '恢复默认';
  @override
  String restoreDefaultFontSize(String pt) => '恢复默认 ($pt pt)';
  @override
  String get decreaseFontSize => '缩小字号';
  @override
  String get increaseFontSize => '放大字号';
  @override
  String get restoreDefaultFonts => '恢复默认字体';
  @override
  String get mapleMonoReady => 'Maple Mono 就绪 (1:2 严格等宽)';
  @override
  String get cjkMonoDetected => '检测到 CJK 严格等宽字体';
  @override
  String get mapleMonoSuggested => '建议安装 Maple Mono 字体';
  @override
  String get cjkMonoActiveDesc => 'CJK 严格等宽已生效，ASCII 表格与代码中英文严格 1:2 对齐。';
  @override
  String get cjkMonoMissingDesc => '缺少 CJK 等宽字体，ASCII 表格或混排代码可能有微弱错位。';
  @override
  String get downloadFont => '下载字体';
  @override
  String get copyLink => '复制链接';
  @override
  String get detectingFonts => '检测中...';
  @override
  String get redetectFonts => '重新检测';
  @override
  String get mapleMonoDefault => 'Maple Mono (默认)';
  @override
  String get livePreviewBadge => '实时排版预览';
  @override
  String get livePreviewTitle => '排版实时渲染预览';
  @override
  String get previewSpecimenHeading => '现代出版级技术文档排版';
  @override
  String get previewSpecimenBody => 'SuperGoodViewer 专为高密度技术文档、工程规格说明书与论文设计。本段文字实时应用当前设置的正文字体与基础字号，展示精致的中西文混排字距、行高节奏与标点间隙。The quick brown fox jumps over the lazy dog.';
  @override
  String previewCodeFont(String name) => '代码字体渲染：$name';
  @override
  String get asciiAlignmentCheck => 'ASCII 表格全角/半角严格 1:2 等宽对齐校验';

  // --- Settings Dialog - Shortcuts Tab (cont.) ---
  @override
  String get shortcutModified => '已修改';
  @override
  String get resetShortcutToDefault => '恢复此项默认';

  // --- Settings Dialog - About Tab (cont.) ---
  @override
  String get aboutEngineSection => '核心排版渲染引擎';
  @override
  String get aboutTypstDesc => '毫秒级编译内核，完美支持高级数学公式、表格与代码块';
  @override
  String get aboutPdfiumTitle => 'PDFium 矢量渲染';
  @override
  String get aboutPdfiumDesc => '无损 120 FPS 丝滑视口平移与部分预渲染技术';
  @override
  String get aboutCjkTitle => 'CJK 1:2 等宽保障';
  @override
  String get aboutCjkDesc => '内置 CJK 等宽字体感知，杜绝 ASCII 表格与图表锯齿撕裂';
  @override
  String get loadSampleDocument => '载入精选排版样例';
  @override
  String get loadSampleDocumentDesc => '即刻体验包含复杂数学公式、Mermaid 图表、Callout 标注与代码高亮的演示文档';

  // --- Presentation View (cont.) ---
  @override
  String get presentationNoContent => '未找到可供放映的文档内容';
  @override
  String presentationLoadFailed(String error) => '加载放映文档失败：$error';

  // --- Auto Update (cont.) ---
  @override
  String updateCurrentVersion(String version) => '当前版本：v$version';
  @override
  String updateSize(String size) => '大小：$size';
  @override
  String get releaseNotesTitle => '更新内容与优化';
  @override
  String get releaseNotesFallback => '包含性能优化与稳定性提升。';
  @override
  String get updateReadyRestart => '更新包已就绪！重启软件后将瞬间生效。';
  @override
  String updateInstallError(String error) => '安装更新时出错：$error';
  @override
  String get updateMissingExecutable => '更新包主执行文件不存在，安装包可能损坏';
  @override
  String get updateUnreadableExecutable => '无法解析更新包主执行文件架构，安装包可能已损坏';
  @override
  String updateArchMismatch(String archs, String host) => '下载的安装包架构 ($archs) 与当前硬件 ($host) 不兼容';
  @override
  String get updateManualDownloadHint => '请前往 GitHub Releases 页面手动下载匹配当前硬件架构的安装包。';

  // --- macOS Menu Bar ---
  @override
  String get cliMenuInstall => '安装 sgv 命令行工具…';
}
