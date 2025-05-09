import 'dart:io';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller_builder.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/common/type_option_separator.dart';
import 'package:appflowy/util/debounce.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/size.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../application/cell/bloc/checklist_cell_bloc.dart';
import 'checklist_cell_textfield.dart';
import 'checklist_progress_bar.dart';

class ChecklistCellEditor extends StatefulWidget {
  const ChecklistCellEditor({required this.cellController, super.key});

  final ChecklistCellController cellController;

  @override
  State<ChecklistCellEditor> createState() => _ChecklistCellEditorState();
}

class _ChecklistCellEditorState extends State<ChecklistCellEditor> {
  /// Focus node for the new task text field
  late final FocusNode newTaskFocusNode;

  @override
  void initState() {
    super.initState();
    newTaskFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          node.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChecklistCellBloc, ChecklistCellState>(
      listener: (context, state) {
        if (state.tasks.isEmpty) {
          newTaskFocusNode.requestFocus();
        }
      },
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.tasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: ChecklistProgressBar(
                  tasks: state.tasks,
                  percent: state.percent,
                ),
              ),
            ChecklistItemList(
              options: state.tasks,
              onUpdateTask: () => newTaskFocusNode.requestFocus(),
            ),
            if (state.tasks.isNotEmpty) const TypeOptionSeparator(spacing: 0.0),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: NewTaskItem(focusNode: newTaskFocusNode),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    newTaskFocusNode.dispose();
    super.dispose();
  }
}

/// Displays the a list of all the existing tasks and an input field to create
/// a new task if `isAddingNewTask` is true
class ChecklistItemList extends StatelessWidget {
  const ChecklistItemList({
    super.key,
    required this.options,
    required this.onUpdateTask,
  });

  final List<ChecklistSelectOption> options;
  final VoidCallback onUpdateTask;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    final itemList = options
        .mapIndexed(
          (index, option) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
            key: ValueKey(option.data.id),
            child: ChecklistItem(
              task: option,
              index: index,
              onSubmitted: index == options.length - 1 ? onUpdateTask : null,
            ),
          ),
        )
        .toList();

    return Flexible(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        proxyDecorator: (child, index, _) => Material(
          color: Colors.transparent,
          child: MouseRegion(
            cursor: UniversalPlatform.isWindows
                ? SystemMouseCursors.click
                : SystemMouseCursors.grabbing,
            child: IgnorePointer(
              child: BlocProvider.value(
                value: context.read<ChecklistCellBloc>(),
                child: child,
              ),
            ),
          ),
        ),
        buildDefaultDragHandles: false,
        itemBuilder: (context, index) => itemList[index],
        itemCount: itemList.length,
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        onReorder: (from, to) {
          context
              .read<ChecklistCellBloc>()
              .add(ChecklistCellEvent.reorderTask(from, to));
        },
      ),
    );
  }
}

class _SelectTaskIntent extends Intent {
  const _SelectTaskIntent();
}

class _EndEditingTaskIntent extends Intent {
  const _EndEditingTaskIntent();
}

class _UpdateTaskDescriptionIntent extends Intent {
  const _UpdateTaskDescriptionIntent();
}

class ChecklistItem extends StatefulWidget {
  const ChecklistItem({
    super.key,
    required this.task,
    required this.index,
    this.onSubmitted,
    this.autofocus = false,
  });

  final ChecklistSelectOption task;
  final int index;
  final VoidCallback? onSubmitted;
  final bool autofocus;

  @override
  State<ChecklistItem> createState() => _ChecklistItemState();
}

class _ChecklistItemState extends State<ChecklistItem> {
  TextEditingController textController = TextEditingController();
  final textFieldFocusNode = FocusNode();
  final focusNode = FocusNode(skipTraversal: true);

  bool isHovered = false;
  bool isFocused = false;
  bool isComposing = false;

  final _debounceOnChanged = Debounce(
    duration: const Duration(milliseconds: 300),
  );

  @override
  void initState() {
    super.initState();
    textController.text = widget.task.data.name;
    textController.addListener(_onTextChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        focusNode.requestFocus();
        textFieldFocusNode.requestFocus();
      });
    }
  }

  void _onTextChanged() =>
      setState(() => isComposing = !textController.value.composing.isCollapsed);

  @override
  void didUpdateWidget(covariant oldWidget) {
    if (!focusNode.hasFocus &&
        oldWidget.task.data.name != widget.task.data.name) {
      textController.text = widget.task.data.name;
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _debounceOnChanged.dispose();

    textController.removeListener(_onTextChanged);
    textController.dispose();
    focusNode.dispose();
    textFieldFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFocusedOrHovered = isHovered || isFocused;
    final color = isFocusedOrHovered || textFieldFocusNode.hasFocus
        ? AFThemeExtension.of(context).lightGreyHover
        : Colors.transparent;
    return FocusableActionDetector(
      focusNode: focusNode,
      onShowHoverHighlight: (value) => setState(() => isHovered = value),
      onFocusChange: (value) => setState(() => isFocused = value),
      actions: _buildActions(),
      shortcuts: _buildShortcuts(),
      child: Container(
        constraints: BoxConstraints(minHeight: GridSize.popoverItemHeight),
        decoration: BoxDecoration(color: color, borderRadius: Corners.s6Border),
        child: _buildChild(isFocusedOrHovered && !textFieldFocusNode.hasFocus),
      ),
    );
  }

  Widget _buildChild(bool showTrash) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableDragStartListener(
          index: widget.index,
          child: MouseRegion(
            cursor: Platform.isWindows
                ? SystemMouseCursors.click
                : SystemMouseCursors.grab,
            child: SizedBox(
              width: 20,
              height: 32,
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FlowySvg(
                  FlowySvgs.drag_element_s,
                  size: const Size.square(14),
                  color: AFThemeExtension.of(context).onBackground,
                ),
              ),
            ),
          ),
        ),
        ChecklistCellCheckIcon(task: widget.task),
        Expanded(
          child: ChecklistCellTextfield(
            textController: textController,
            focusNode: textFieldFocusNode,
            lineHeight: Platform.isWindows ? 1.2 : 1.1,
            onChanged: () {
              _debounceOnChanged.call(() {
                if (!isComposing) {
                  _submitUpdateTaskDescription(textController.text);
                }
              });
            },
            onSubmitted: () {
              _submitUpdateTaskDescription(textController.text);

              if (widget.onSubmitted != null) {
                widget.onSubmitted?.call();
              } else {
                Actions.invoke(context, const NextFocusIntent());
              }
            },
          ),
        ),
        if (showTrash)
          ChecklistCellDeleteButton(
            onPressed: () => context
                .read<ChecklistCellBloc>()
                .add(ChecklistCellEvent.deleteTask(widget.task.data.id)),
          ),
      ],
    );
  }

  Map<ShortcutActivator, Intent> _buildShortcuts() {
    return {
      SingleActivator(
        LogicalKeyboardKey.enter,
        meta: Platform.isMacOS,
        control: !Platform.isMacOS,
      ): const _SelectTaskIntent(),
      if (!isComposing)
        const SingleActivator(LogicalKeyboardKey.enter):
            const _UpdateTaskDescriptionIntent(),
      if (!isComposing)
        const SingleActivator(LogicalKeyboardKey.escape):
            const _EndEditingTaskIntent(),
    };
  }

  Map<Type, Action<Intent>> _buildActions() {
    return {
      _SelectTaskIntent: CallbackAction<_SelectTaskIntent>(
        onInvoke: (_SelectTaskIntent intent) {
          context
              .read<ChecklistCellBloc>()
              .add(ChecklistCellEvent.selectTask(widget.task.data.id));
          return;
        },
      ),
      _UpdateTaskDescriptionIntent:
          CallbackAction<_UpdateTaskDescriptionIntent>(
        onInvoke: (_UpdateTaskDescriptionIntent intent) {
          textFieldFocusNode.unfocus();
          widget.onSubmitted?.call();
          return;
        },
      ),
      _EndEditingTaskIntent: CallbackAction<_EndEditingTaskIntent>(
        onInvoke: (_EndEditingTaskIntent intent) {
          textFieldFocusNode.unfocus();
          return;
        },
      ),
    };
  }

  void _submitUpdateTaskDescription(String description) => context
      .read<ChecklistCellBloc>()
      .add(ChecklistCellEvent.updateTaskName(widget.task.data, description));
}

/// Creates a new task after entering the description and pressing enter.
/// This can be cancelled by pressing escape
@visibleForTesting
class NewTaskItem extends StatefulWidget {
  const NewTaskItem({super.key, required this.focusNode});

  final FocusNode focusNode;

  @override
  State<NewTaskItem> createState() => _NewTaskItemState();
}

class _NewTaskItemState extends State<NewTaskItem> {
  final textController = TextEditingController();

  bool isCreateButtonEnabled = false;
  bool isComposing = false;

  @override
  void initState() {
    super.initState();
    textController.addListener(_onTextChanged);
    if (widget.focusNode.canRequestFocus) {
      widget.focusNode.requestFocus();
    }
  }

  void _onTextChanged() =>
      setState(() => isComposing = !textController.value.composing.isCollapsed);

  @override
  void dispose() {
    textController.removeListener(_onTextChanged);
    textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: BoxConstraints(minHeight: GridSize.popoverItemHeight),
      child: Row(
        children: [
          const HSpace(8),
          Expanded(
            child: CallbackShortcuts(
              bindings: isComposing
                  ? const {}
                  : {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          _createNewTask(context),
                    },
              child: TextField(
                focusNode: widget.focusNode,
                controller: textController,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: null,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 6.0,
                    horizontal: 2.0,
                  ),
                  hintText: LocaleKeys.grid_checklist_addNew.tr(),
                ),
                onSubmitted: (_) => _createNewTask(context),
                onChanged: (_) => setState(
                  () => isCreateButtonEnabled = textController.text.isNotEmpty,
                ),
              ),
            ),
          ),
          FlowyTextButton(
            LocaleKeys.grid_checklist_submitNewTask.tr(),
            fontSize: 11,
            fillColor: isCreateButtonEnabled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).disabledColor,
            hoverColor: isCreateButtonEnabled
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).disabledColor,
            fontColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            onPressed: isCreateButtonEnabled
                ? () {
                    context.read<ChecklistCellBloc>().add(
                          ChecklistCellEvent.createNewTask(textController.text),
                        );
                    widget.focusNode.requestFocus();
                    textController.clear();
                  }
                : null,
          ),
        ],
      ),
    );
  }

  void _createNewTask(BuildContext context) {
    final taskDescription = textController.text;
    if (taskDescription.isNotEmpty) {
      context
          .read<ChecklistCellBloc>()
          .add(ChecklistCellEvent.createNewTask(taskDescription));
      textController.clear();
    }
    widget.focusNode.requestFocus();
  }
}
