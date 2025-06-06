import 'dart:async';
import 'dart:io';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/search/view_ancestor_cache.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/document/presentation/editor_notification.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/loading.dart';
import 'package:appflowy/shared/version_checker/version_checker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:appflowy/workspace/application/action_navigation/action_navigation_bloc.dart';
import 'package:appflowy/workspace/application/action_navigation/navigation_action.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/favorite/prelude.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/sidebar/billing/sidebar_plan_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_footer.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_upgrade_application_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_top_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/header/sidebar_user.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_new_page_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/sidebar_space.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_migration.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/workspace/sidebar_workspace.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserProfilePB;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Loading? _duplicateSpaceLoading;

/// Home Sidebar is the left side bar of the home page.
///
/// in the sidebar, we have:
///   - user icon, user name
///   - settings
///   - scrollable document list
///   - trash
class HomeSideBar extends StatelessWidget {
  const HomeSideBar({
    super.key,
    required this.userProfile,
    required this.workspaceSetting,
  });

  final UserProfilePB userProfile;

  final WorkspaceLatestPB workspaceSetting;

  @override
  Widget build(BuildContext context) {
    // Workspace Bloc: control the current workspace
    //   |
    //   +-- Workspace Menu
    //   |    |
    //   |    +-- Workspace List: control to switch workspace
    //   |    |
    //   |    +-- Workspace Settings
    //   |    |
    //   |    +-- Notification Center
    //   |
    //   +-- Favorite Section
    //   |
    //   +-- Public Or Private Section: control the sections of the workspace
    //   |
    //   +-- Trash Section
    return BlocProvider(
      create: (context) => SidebarPlanBloc()
        ..add(SidebarPlanEvent.init(workspaceSetting.workspaceId, userProfile)),
      child: BlocConsumer<UserWorkspaceBloc, UserWorkspaceState>(
        listenWhen: (prev, curr) =>
            prev.currentWorkspace?.workspaceId !=
            curr.currentWorkspace?.workspaceId,
        listener: (context, state) {
          if (FeatureFlag.search.isOn) {
            // Notify command palette that workspace has changed
            context.read<CommandPaletteBloc>().add(
                  CommandPaletteEvent.workspaceChanged(
                    workspaceId: state.currentWorkspace?.workspaceId,
                  ),
                );
          }

          if (state.currentWorkspace != null) {
            context.read<SidebarPlanBloc>().add(
                  SidebarPlanEvent.changedWorkspace(
                    workspaceId: state.currentWorkspace!.workspaceId,
                  ),
                );
          }

          // Re-initialize workspace-specific services
          getIt<CachedRecentService>().reset();
        },
        // Rebuild the whole sidebar when the current workspace changes
        buildWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        builder: (context, state) {
          if (state.currentWorkspace == null) {
            return const SizedBox.shrink();
          }

          final workspaceId = state.currentWorkspace?.workspaceId ??
              workspaceSetting.workspaceId;
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: getIt<ActionNavigationBloc>()),
              BlocProvider(
                create: (_) => SidebarSectionsBloc()
                  ..add(SidebarSectionsEvent.initial(userProfile, workspaceId)),
              ),
              BlocProvider(
                create: (_) => SpaceBloc(
                  userProfile: userProfile,
                  workspaceId: workspaceId,
                )..add(const SpaceEvent.initial(openFirstPage: false)),
              ),
            ],
            child: MultiBlocListener(
              listeners: [
                BlocListener<SidebarSectionsBloc, SidebarSectionsState>(
                  listenWhen: (p, c) =>
                      p.lastCreatedRootView?.id != c.lastCreatedRootView?.id,
                  listener: (context, state) => context.read<TabsBloc>().add(
                        TabsEvent.openPlugin(
                          plugin: state.lastCreatedRootView!.plugin(),
                        ),
                      ),
                ),
                BlocListener<SpaceBloc, SpaceState>(
                  listenWhen: (prev, curr) =>
                      prev.lastCreatedPage?.id != curr.lastCreatedPage?.id ||
                      prev.isDuplicatingSpace != curr.isDuplicatingSpace,
                  listener: (context, state) {
                    final page = state.lastCreatedPage;
                    if (page == null || page.id.isEmpty) {
                      // open the blank page
                      context
                          .read<TabsBloc>()
                          .add(TabsEvent.openPlugin(plugin: BlankPagePlugin()));
                    } else {
                      context.read<TabsBloc>().add(
                            TabsEvent.openPlugin(
                              plugin: state.lastCreatedPage!.plugin(),
                            ),
                          );
                    }

                    if (state.isDuplicatingSpace) {
                      _duplicateSpaceLoading ??= Loading(context);
                      _duplicateSpaceLoading?.start();
                    } else if (_duplicateSpaceLoading != null) {
                      _duplicateSpaceLoading?.stop();
                      _duplicateSpaceLoading = null;
                    }
                  },
                ),
                BlocListener<ActionNavigationBloc, ActionNavigationState>(
                  listenWhen: (_, curr) => curr.action != null,
                  listener: _onNotificationAction,
                ),
                BlocListener<UserWorkspaceBloc, UserWorkspaceState>(
                  listener: (context, state) {
                    final actionType = state.actionResult?.actionType;

                    if (actionType == WorkspaceActionType.create ||
                        actionType == WorkspaceActionType.delete ||
                        actionType == WorkspaceActionType.open) {
                      if (context.read<SpaceBloc>().state.spaces.isEmpty) {
                        context.read<SidebarSectionsBloc>().add(
                              SidebarSectionsEvent.reload(
                                userProfile,
                                state.currentWorkspace?.workspaceId ??
                                    workspaceSetting.workspaceId,
                              ),
                            );
                      } else {
                        context.read<SpaceBloc>().add(
                              SpaceEvent.reset(
                                userProfile,
                                state.currentWorkspace?.workspaceId ??
                                    workspaceSetting.workspaceId,
                                true,
                              ),
                            );
                      }

                      context
                          .read<FavoriteBloc>()
                          .add(const FavoriteEvent.fetchFavorites());
                    }
                  },
                ),
              ],
              child: _Sidebar(userProfile: userProfile),
            ),
          );
        },
      ),
    );
  }

  void _onNotificationAction(
    BuildContext context,
    ActionNavigationState state,
  ) {
    final action = state.action;
    if (action?.type == ActionType.openView) {
      final view = action!.arguments?[ActionArgumentKeys.view];
      if (view != null) {
        final Map<String, dynamic> arguments = {};
        final nodePath = action.arguments?[ActionArgumentKeys.nodePath];
        if (nodePath != null) {
          arguments[PluginArgumentKeys.selection] = Selection.collapsed(
            Position(path: [nodePath]),
          );
        }

        checkForSpace(
          context.read<SpaceBloc>(),
          view,
          () => openView(action, context, view, arguments),
        );
        openView(action, context, view, arguments);
      }
    }
  }

  Future<void> checkForSpace(
    SpaceBloc spaceBloc,
    ViewPB view,
    VoidCallback afterOpen,
  ) async {
    /// open space
    final acestorCache = getIt<ViewAncestorCache>();
    final ancestor = await acestorCache.getAncestor(view.id);
    if (ancestor?.ancestors.isEmpty ?? true) return;
    final firstAncestor = ancestor!.ancestors.first;
    if (firstAncestor.id != spaceBloc.state.currentSpace?.id) {
      final space =
          (await ViewBackendService.getView(firstAncestor.id)).toNullable();
      if (space != null) {
        Log.info(
          'Switching space from (${firstAncestor.name}-${firstAncestor.id}) to (${space.name}-${space.id})',
        );
        spaceBloc.add(SpaceEvent.open(space: space, afterOpen: afterOpen));
      }
    }
  }

  void openView(
    NavigationAction action,
    BuildContext context,
    ViewPB view,
    Map<String, dynamic> arguments,
  ) {
    final blockId = action.arguments?[ActionArgumentKeys.blockId];
    if (blockId != null) {
      arguments[PluginArgumentKeys.blockId] = blockId;
    }

    final rowId = action.arguments?[ActionArgumentKeys.rowId];
    if (rowId != null) {
      arguments[PluginArgumentKeys.rowId] = rowId;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.read<TabsBloc>().openPlugin(view, arguments: arguments);
      }
    });
  }
}

class _Sidebar extends StatefulWidget {
  const _Sidebar({required this.userProfile});

  final UserProfilePB userProfile;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  final _scrollController = ScrollController();
  Timer? _scrollDebounce;
  bool _isScrolling = false;
  final _isHovered = ValueNotifier(false);
  final _scrollOffset = ValueNotifier<double>(0);

  // mute the update button during the current application lifecycle.
  final _muteUpdateButton = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _scrollOffset.dispose();
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const menuHorizontalInset = EdgeInsets.symmetric(horizontal: 8);
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            right: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // top menu
            Padding(
              padding: menuHorizontalInset,
              child: SidebarTopMenu(
                isSidebarOnHover: _isHovered,
              ),
            ),
            // user or workspace, setting
            BlocBuilder<UserWorkspaceBloc, UserWorkspaceState>(
              builder: (context, state) => Container(
                height: HomeSizes.workspaceSectionHeight,
                padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
                // if the workspaces are empty, show the user profile instead
                child: state.isCollabWorkspaceOn && state.workspaces.isNotEmpty
                    ? SidebarWorkspace(userProfile: widget.userProfile)
                    : SidebarUser(userProfile: widget.userProfile),
              ),
            ),
            if (FeatureFlag.search.isOn) ...[
              const VSpace(6),
              Container(
                padding: menuHorizontalInset,
                height: HomeSizes.searchSectionHeight,
                child: const _SidebarSearchButton(),
              ),
            ],

            if (context
                    .read<UserWorkspaceBloc>()
                    .state
                    .currentWorkspace
                    ?.role !=
                AFRolePB.Guest) ...[
              const VSpace(6.0),
              // new page button
              const SidebarNewPageButton(),
            ],

            // scrollable document list
            const VSpace(12.0),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: ValueListenableBuilder(
                valueListenable: _scrollOffset,
                builder: (_, offset, child) => Opacity(
                  opacity: offset > 0 ? 1 : 0,
                  child: child,
                ),
                child: const FlowyDivider(),
              ),
            ),

            _renderFolderOrSpace(menuHorizontalInset),

            // trash
            Padding(
              padding: menuHorizontalInset +
                  const EdgeInsets.symmetric(horizontal: 4.0),
              child: const FlowyDivider(),
            ),
            const VSpace(8),

            _renderUpgradeSpaceButton(menuHorizontalInset),
            _buildUpgradeApplicationButton(menuHorizontalInset),

            const VSpace(8),
            Padding(
              padding: menuHorizontalInset +
                  const EdgeInsets.symmetric(horizontal: 4.0),
              child: const SidebarFooter(),
            ),
            const VSpace(14),
          ],
        ),
      ),
    );
  }

  Widget _renderFolderOrSpace(EdgeInsets menuHorizontalInset) {
    final spaceState = context.read<SpaceBloc>().state;
    final workspaceState = context.read<UserWorkspaceBloc>().state;

    if (!spaceState.isInitialized) {
      return const SizedBox.shrink();
    }

    // there's no space or the workspace is not collaborative,
    // show the folder section (Workspace, Private, Personal)
    // otherwise, show the space
    final sidebarSectionBloc = context.watch<SidebarSectionsBloc>();
    final containsSpace = sidebarSectionBloc.state.containsSpace;

    if (containsSpace && spaceState.spaces.isEmpty) {
      context.read<SpaceBloc>().add(const SpaceEvent.didReceiveSpaceUpdate());
    }

    return !containsSpace ||
            spaceState.spaces.isEmpty ||
            !workspaceState.isCollabWorkspaceOn
        ? Expanded(
            child: Padding(
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(right: 6),
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                child: SidebarFolder(
                  userProfile: widget.userProfile,
                  isHoverEnabled: !_isScrolling,
                ),
              ),
            ),
          )
        : Expanded(
            child: Padding(
              padding: menuHorizontalInset - const EdgeInsets.only(right: 6),
              child: FlowyScrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: 6),
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  child: SidebarSpace(
                    userProfile: widget.userProfile,
                    isHoverEnabled: !_isScrolling,
                  ),
                ),
              ),
            ),
          );
  }

  Widget _renderUpgradeSpaceButton(EdgeInsets menuHorizontalInset) {
    final spaceState = context.watch<SpaceBloc>().state;
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    return !spaceState.shouldShowUpgradeDialog ||
            !workspaceState.isCollabWorkspaceOn
        ? const SizedBox.shrink()
        : Padding(
            padding: menuHorizontalInset +
                const EdgeInsets.only(
                  left: 4.0,
                  right: 4.0,
                  top: 8.0,
                ),
            child: const SpaceMigration(),
          );
  }

  Widget _buildUpgradeApplicationButton(EdgeInsets menuHorizontalInset) {
    return ValueListenableBuilder(
      valueListenable: _muteUpdateButton,
      builder: (_, mute, child) {
        if (mute) {
          return const SizedBox.shrink();
        }

        return ValueListenableBuilder(
          valueListenable: ApplicationInfo.latestVersionNotifier,
          builder: (_, latestVersion, child) {
            if (!ApplicationInfo.isUpdateAvailable) {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: menuHorizontalInset +
                  const EdgeInsets.only(
                    left: 4.0,
                    right: 4.0,
                  ),
              child: SidebarUpgradeApplicationButton(
                onUpdateButtonTap: () {
                  versionChecker.checkForUpdate();
                },
                onCloseButtonTap: () {
                  _muteUpdateButton.value = true;
                },
              ),
            );
          },
        );
      },
    );
  }

  void _onScrollChanged() {
    setState(() => _isScrolling = true);

    _scrollDebounce?.cancel();
    _scrollDebounce =
        Timer(const Duration(milliseconds: 300), _setScrollStopped);

    _scrollOffset.value = _scrollController.offset;
  }

  void _setScrollStopped() {
    if (mounted) {
      setState(() => _isScrolling = false);
    }
  }
}

class _SidebarSearchButton extends StatelessWidget {
  const _SidebarSearchButton();

  @override
  Widget build(BuildContext context) {
    return FlowyTooltip(
      richMessage: TextSpan(
        children: [
          TextSpan(
            text: '${LocaleKeys.search_sidebarSearchIcon.tr()}\n',
            style: context.tooltipTextStyle(),
          ),
          TextSpan(
            text: Platform.isMacOS ? '⌘+P' : 'Ctrl+P',
            style: context
                .tooltipTextStyle()
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ],
      ),
      child: FlowyButton(
        onTap: () {
          // exit editing mode when doing search to avoid the toolbar showing up
          EditorNotification.exitEditing().post();
          final workspaceBloc = context.read<UserWorkspaceBloc?>();
          final spaceBloc = context.read<SpaceBloc?>();
          CommandPalette.of(context).toggle(
            workspaceBloc: workspaceBloc,
            spaceBloc: spaceBloc,
          );
        },
        leftIcon: const FlowySvg(FlowySvgs.search_s),
        iconPadding: 12.0,
        margin: const EdgeInsets.only(left: 8.0),
        text: FlowyText.regular(LocaleKeys.search_label.tr()),
      ),
    );
  }
}
