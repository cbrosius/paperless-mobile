import 'package:cached_query_flutter/cached_query_flutter.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:paperless_mobile/api/paperless_api.dart';
import 'package:paperless_mobile/core/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/core/repository/saved_view_repository.dart';
import 'package:paperless_mobile/core/widgets/shimmer_placeholder.dart';
import 'package:paperless_mobile/features/documents/view/widgets/saved_views/saved_view_chip.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/helpers/connectivity_aware_action_wrapper.dart';
import 'package:paperless_mobile/routing/routes/saved_views_route.dart';

class SavedViewsWidget extends StatefulWidget {
  final void Function(SavedView view) onViewSelected;
  final void Function(int id, SavedViewRequest view) onUpdateView;
  final void Function(SavedView view) onDeleteView;

  final DocumentFilter filter;
  final ExpansibleController? controller;

  const SavedViewsWidget({
    super.key,
    required this.onViewSelected,
    required this.filter,
    required this.onUpdateView,
    required this.onDeleteView,
    this.controller,
  });

  @override
  State<SavedViewsWidget> createState() => _SavedViewsWidgetState();
}

class _SavedViewsWidgetState extends State<SavedViewsWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _animation = _animationController.drive(Tween(begin: 0, end: 0.5));
  }

  @override
  Widget build(BuildContext context) {
    return QueryBuilder(
      query: context.read<SavedViewRepository>().getAllQuery(),
      builder: (context, state) {
        final selectedView = widget.filter.selectedView != null
            ? state.data?.firstWhereOrNull(
                (view) => view.id == widget.filter.selectedView!,
              )
            : null;
        final selectedViewHasChanged =
            selectedView != null &&
            selectedView.toDocumentFilter() != widget.filter;
        return PageStorage(
          bucket: PageStorageBucket(),
          child: ExpansionTile(
            controller: widget.controller,
            tilePadding: const EdgeInsets.only(left: 8),
            trailing: RotationTransition(
              turns: _animation,
              child: const Icon(Icons.expand_more),
            ).paddedOnly(right: 8),
            onExpansionChanged: (isExpanded) {
              if (isExpanded) {
                _animationController.forward();
              } else {
                _animationController.reverse().then((value) => setState(() {}));
              }
            },
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.of(context)!.views,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      if (selectedView != null)
                        Text(
                          selectedView.name,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(128),
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                AnimatedScale(
                  scale: selectedViewHasChanged ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: TextButton(
                    onPressed: () {
                      final newView = selectedView!.copyWith(
                        filterRules: widget.filter.toFilterRules(),
                        sortField: widget.filter.sortField?.value,
                        sortReverse:
                            widget.filter.sortOrder == SortOrder.descending,
                      );
                      widget.onUpdateView(newView.id, newView.toRequest());
                    },
                    child: Text(S.of(context)!.saveChanges),
                  ),
                ),
              ],
            ),
            childrenPadding: EdgeInsets.only(top: 8),
            leading: Icon(
              Icons.saved_search,
              color: Theme.of(context).colorScheme.primary,
            ).padded(),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.isLoading)
                _buildLoadingState()
              else if (state.isError)
                Text(S.of(context)!.couldNotLoadSavedViews).paddedOnly(left: 16)
              else if (state.data?.isEmpty ?? true)
                Text(
                  S.of(context)!.youDidNotSaveAnyViewsYet,
                  style: Theme.of(context).textTheme.bodySmall,
                ).paddedOnly(left: 16)
              else
                _buildLoadedState(state.data!),
              Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: S.of(context)!.createFromCurrentFilter,
                  child: ConnectivityAwareActionWrapper(
                    child: TextButton.icon(
                      onPressed: () {
                        CreateSavedViewRoute(
                          $extra: widget.filter,
                        ).push(context);
                      },
                      icon: const Icon(Icons.add),
                      label: Text(S.of(context)!.newView),
                    ),
                  ),
                ).padded(4),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadedState(List<SavedView> savedViews) {
    return SizedBox(
      height: kMinInteractiveDimension,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => true,
        child: CustomScrollView(
          scrollDirection: Axis.horizontal,
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(width: 12)),
            SliverList.separated(
              itemBuilder: (context, index) {
                final view = savedViews.elementAt(index);
                final isSelected =
                    (widget.filter.selectedView ?? -1) == view.id;
                return ConnectivityAwareActionWrapper(
                  child: SavedViewChip(
                    view: view,
                    onViewSelected: widget.onViewSelected,
                    selected: isSelected,
                    hasChanged:
                        isSelected && view.toDocumentFilter() != widget.filter,
                    onUpdateView: widget.onUpdateView,
                    onDeleteView: widget.onDeleteView,
                  ),
                );
              },
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemCount: savedViews.length,
            ),
            const SliverToBoxAdapter(child: SizedBox(width: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      height: kMinInteractiveDimension,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => true,
        child: ShimmerPlaceholder(
          child: CustomScrollView(
            scrollDirection: Axis.horizontal,
            slivers: [
              const SliverToBoxAdapter(child: SizedBox(width: 12)),
              SliverList.separated(
                itemBuilder: (context, index) {
                  return Container(
                    width: 130,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.white,
                    ),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
              ),
              const SliverToBoxAdapter(child: SizedBox(width: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
