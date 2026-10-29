import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/dialog/material_bottom_sheet.dart';
import 'package:kazumi/bean/widget/kazumi_menu.dart';
import 'package:kazumi/bean/widget/loading_indicator.dart';
import 'package:kazumi/bean/widget/empty_state_widget.dart';
import 'package:kazumi/bean/widget/split_list_row.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/plugins/anti_crawler_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/plugin/captcha_verification_service.dart';
import 'package:kazumi/services/plugin/plugin_search_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/utils/device.dart';
import 'package:url_launcher/url_launcher.dart';

part 'source_alias_dialog.dart';
part 'source_captcha_flow.dart';
part 'source_sheet_view.dart';

class SourceSheet extends StatefulWidget {
  const SourceSheet({super.key, required this.infoController});

  final InfoController infoController;

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

class _SourceSheetState extends State<SourceSheet> with KazumiDialogOwner {
  final CollectController _collectController = inject<CollectController>();
  final PluginsController _pluginsController = inject<PluginsController>();

  /// Source of this show's latest online watch, else of the latest online
  /// watch overall; listed first while it can still offer results.
  late final String? _lastUsedSource = _findLastUsedSource();

  String? _findLastUsedSource() {
    final installed = {
      for (final plugin in _pluginsController.pluginList) plugin.name,
    };
    final watched = inject<IHistoryRepository>()
        .getAllHistories()
        .where(
          (history) =>
              history.entryKind == HistoryEntryKind.online &&
              installed.contains(history.adapterName),
        )
        .toList();
    final showId = widget.infoController.bangumiItem.id;
    for (final history in watched) {
      if (history.bangumiItem.id == showId) return history.adapterName;
    }
    return watched.isEmpty ? null : watched.first.adapterName;
  }

  final Map<String, String> _sourceKeywords = {};

  late final String _keyword;
  late final PluginSearchService _searchService;
  late final _SourceCaptchaFlow _captchaFlow;

  @override
  void initState() {
    super.initState();
    final item = widget.infoController.bangumiItem;
    _keyword = item.nameCn.isEmpty ? item.name : item.nameCn;
    _searchService = PluginSearchService(
      infoController: widget.infoController,
      pluginsController: _pluginsController,
    );
    _captchaFlow = _SourceCaptchaFlow(
      onVerified: _showVerifiedResult,
      onCancelled: (plugin) => _retry(plugin.name),
    );
    _searchService.queryAllSource(_keyword);
  }

  @override
  void dispose() {
    _searchService.cancel();
    _captchaFlow.dispose();
    super.dispose();
  }

  String _keywordFor(String name) => _sourceKeywords[name] ?? _keyword;

  Plugin _pluginFor(String name) =>
      _pluginsController.pluginList.firstWhere((plugin) => plugin.name == name);

  void _querySource(String keyword, String pluginName) {
    final trimmed = keyword.trim();
    if (!mounted || trimmed.isEmpty) return;
    setState(() => _sourceKeywords[pluginName] = trimmed);
    _searchService.querySource(trimmed, pluginName);
  }

  void _retry(String name) => _querySource(_keywordFor(name), name);

  void _showVerifiedResult(Plugin plugin, String pageHtml) {
    if (!mounted) return;
    if (_searchService.applyHarvestedSearchResult(plugin.name, pageHtml)) {
      KazumiDialog.showToast(message: '验证成功');
      return;
    }
    _captchaFlow.showSuccess(
      plugin.name,
      onComplete: () => _retry(plugin.name),
    );
  }

  Future<void> _openInBrowser(String name) async {
    final plugin = _pluginFor(name);
    final targetUrl = plugin.usesApiSearch
        ? plugin.baseUrl
        : plugin.searchURL.replaceAll(
            '@keyword',
            Uri.encodeQueryComponent(_keywordFor(name)),
          );
    try {
      if (await launchUrl(
        Uri.parse(targetUrl),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (error) {
      KazumiLogger().w('SourceSheet: failed to open browser', error: error);
    }
    if (mounted) KazumiDialog.showToast(message: '无法打开浏览器，请稍后重试');
  }

  Future<void> _openSearchItem(String name, SearchItem searchItem) async {
    if (dialogs.isRunning) return;
    final plugin = _pluginFor(name);
    await dialogs.run(
      (task) async {
        final cancelToken = RuleCancelToken();
        final roads = await task.loading(
          message: '正在获取播放列表',
          barrierDismissible: isDesktop(),
          onCancel: cancelToken.cancel,
          action: () => plugin.queryChapterRoads(
            searchItem.src,
            cancelToken: cancelToken,
          ),
        );
        if (roads.isEmpty) throw ChapterErrorException(plugin.name);
        task.withContext(
          (context) => context.pushNamed(
            '/video/',
            arguments: OnlineVideoPlaybackArgs(
              bangumiItem: widget.infoController.bangumiItem,
              plugin: plugin,
              title: searchItem.name,
              src: searchItem.src,
              roads: roads,
            ),
          ),
        );
      },
      onError: (error, stackTrace) {
        KazumiLogger().w('SourceSheet: failed to query playlist', error: error);
        KazumiDialog.showToast(message: '未能获取播放列表，请重试或选择其他结果');
      },
    );
  }

  void _showAliasPicker(String pluginName) {
    if (widget.infoController.bangumiItem.alias.isEmpty) {
      KazumiDialog.showToast(message: '无可用别名，试试修改检索关键词');
      return;
    }
    _showAliasPickerDialog(
      sourceName: pluginName,
      aliases: widget.infoController.bangumiItem.alias,
      onAliasSelected: (alias) => _querySource(alias, pluginName),
      onAliasesChanged: () => _collectController.updateLocalCollect(
        widget.infoController.bangumiItem,
      ),
    );
  }

  void _showCustomKeyword(String pluginName) => _showCustomKeywordDialog(
    initialKeyword: _keywordFor(pluginName),
    sourceName: pluginName,
    onSubmit: (keyword) {
      final item = widget.infoController.bangumiItem;
      if (!item.alias.contains(keyword)) {
        item.alias.add(keyword);
        _collectController.updateLocalCollect(item);
      }
      _querySource(keyword, pluginName);
    },
  );

  @override
  Widget build(BuildContext context) => Observer(
    builder: (context) {
      // Snapshot observable values here; lazy list builders are not tracked.
      final groupsByName = {
        for (final plugin in _pluginsController.pluginList)
          plugin.name: _SourceSearchGroup(
            name: plugin.name,
            keyword: _keywordFor(plugin.name),
            status:
                widget.infoController.pluginSearchStatus[plugin.name] ??
                PluginSearchStatus.pending,
            results: <SearchItem>[],
            lastUsed: plugin.name == _lastUsedSource,
          ),
      };
      final seenBySource = <String, Set<String>>{};
      final responseOrder = <String, int>{};
      // Responses follow completion order; groups keep configured order.
      for (final response in widget.infoController.pluginSearchResponseList) {
        final group = groupsByName[response.pluginName];
        if (group == null) continue;
        responseOrder.putIfAbsent(group.name, () => responseOrder.length);
        final seen = seenBySource.putIfAbsent(group.name, () => <String>{});
        for (final result in response.data) {
          if (seen.add(result.src)) group.results.add(result);
        }
      }
      // Sources with results go first, fastest to answer on top, so late
      // arrivals append instead of shifting the row being focused.
      // Everything else keeps the configured order.
      final groups = groupsByName.values.toList();
      final configuredOrder = {
        for (final (index, group) in groups.indexed) group.name: index,
      };
      int tieOrder(_SourceSearchGroup group) => group.hasResults
          ? responseOrder[group.name]!
          : configuredOrder[group.name]!;
      // The last used source leads unless it came back empty or failed.
      int pin(_SourceSearchGroup group) =>
          group.lastUsed && group.sortRank <= 2 ? 0 : 1;
      groups.sort((a, b) {
        final byPin = pin(a).compareTo(pin(b));
        if (byPin != 0) return byPin;
        final byRank = a.sortRank.compareTo(b.sortRank);
        return byRank != 0 ? byRank : tieOrder(a).compareTo(tieOrder(b));
      });
      final firstResultSource = groups.first.hasResults
          ? groups.first.name
          : null;
      return _SourceSheetView(
        keyword: _keyword,
        groups: groups,
        firstResultSource: firstResultSource,
        onSourceSearch: _showCustomKeyword,
        onSourceAliasSearch: _showAliasPicker,
        onRetry: _retry,
        onVerify: (name) =>
            _captchaFlow.start(_pluginFor(name), _keywordFor(name)),
        onOpenBrowser: _openInBrowser,
        onPlay: _openSearchItem,
        onClose: () => Navigator.of(context).pop(),
      );
    },
  );
}
