import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Searchable bottom-sheet picker shared by onboarding and profile settings.
class SearchPickerSheet<T> extends StatefulWidget {
  const SearchPickerSheet({
    super.key,
    required this.title,
    required this.items,
    required this.selectedKey,
    required this.searchText,
    required this.itemKey,
    required this.titleBuilder,
    required this.subtitleBuilder,
  });

  final String title;
  final List<T> items;
  final String? selectedKey;
  final String Function(T item) searchText;
  final String Function(T item) itemKey;
  final String Function(T item) titleBuilder;
  final String Function(T item) subtitleBuilder;

  @override
  State<SearchPickerSheet<T>> createState() => _SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<SearchPickerSheet<T>> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final filtered = widget.items
        .where((item) => widget.searchText(item).contains(query))
        .toList();
    final height = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: Container(
        height: height,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusXL),
          ),
          border: Border(
            top: BorderSide(color: AppTheme.glassBorder, width: 1.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppTheme.textSecondary.withAlpha(80),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: AppTheme.headlineMedium()),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: AppTheme.bodyLarge(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: AppTheme.bodyMedium(color: AppTheme.textHint),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear_rounded),
                      ),
                filled: true,
                fillColor: AppTheme.bgSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No matches found',
                        style: AppTheme.bodyMedium(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = filtered[index];
                        final selected =
                            widget.itemKey(item) == widget.selectedKey;
                        return ListTile(
                          minVerticalPadding: 10,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSM,
                            ),
                          ),
                          tileColor: selected
                              ? AppTheme.emerald.withAlpha(20)
                              : AppTheme.bgSurface,
                          title: Text(
                            widget.titleBuilder(item),
                            style: AppTheme.bodyLarge(
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            widget.subtitleBuilder(item),
                            style: AppTheme.bodyMedium(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.emerald,
                                )
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
