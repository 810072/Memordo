// lib/layout/right_sidebar/graph_sidebar.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../viewmodels/graph_viewmodel.dart';
import '../../viewmodels/graph_customization_settings.dart';

// --- 스타일 상수 ---
class _SidebarStyles {
  static const double horizontalPadding = 16.0;
  static const double verticalPadding = 16.0;
  static const double sectionSpacing = 24.0;
  static const double itemSpacing = 12.0;
  static const double labelBottomSpacing = 8.0;
  static const double colorPreviewSize = 36.0;
  static const double inputHeight = 36.0;
}

class GraphSidebar extends StatelessWidget {
  const GraphSidebar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final graphViewModel = context.watch<GraphViewModel>();
    final customSettings = context.watch<GraphCustomizationSettings>();
    final isDarkMode = theme.brightness == Brightness.dark;

    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color;
    final mutedTextColor = theme.textTheme.bodyMedium?.color?.withOpacity(0.65);
    final borderColor = theme.dividerColor;
    final primaryColor = theme.primaryColor;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(
              horizontal: _SidebarStyles.horizontalPadding,
            ),
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "그래프 뷰 옵션",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),

          // Scrollable Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: _SidebarStyles.horizontalPadding,
                vertical: _SidebarStyles.verticalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 필터링 섹션
                  _buildSectionTitle('필터', mutedTextColor),
                  const SizedBox(height: 6),
                  _buildFilterRadioItem(
                    context,
                    theme,
                    graphViewModel,
                    '전체',
                    GraphFilterMode.all,
                  ),
                  _buildFilterRadioItem(
                    context,
                    theme,
                    graphViewModel,
                    '고립된 노트',
                    GraphFilterMode.isolated,
                  ),
                  _buildFilterRadioItem(
                    context,
                    theme,
                    graphViewModel,
                    '연결된 노트',
                    GraphFilterMode.connected,
                  ),
                  const SizedBox(height: 6),
                  Divider(color: borderColor),
                  const SizedBox(height: 6),

                  // 색상 설정 섹션
                  _buildSectionTitle('색상 설정', mutedTextColor),
                  const SizedBox(height: _SidebarStyles.itemSpacing + 4),
                  _buildColorSettingItem(
                    context: context,
                    label: "배경 색상",
                    currentColor: customSettings.backgroundColor,
                    onColorChanged: customSettings.setBackgroundColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 6),
                  _buildColorSettingItem(
                    context: context,
                    label: "연결선 색상",
                    currentColor: customSettings.linkColor,
                    onColorChanged: customSettings.setLinkColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 6),
                  Divider(color: borderColor),
                  const SizedBox(height: 6),

                  // 슬라이더 섹션
                  _buildSliderSettingItem(
                    context: context,
                    label: "연결선 투명도",
                    value: customSettings.linkOpacity,
                    min: 0,
                    max: 1,
                    step: 0.01,
                    onChanged: customSettings.setLinkOpacity,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    activeTrackColor: primaryColor,
                    inactiveTrackColor: Colors.grey.shade300,
                    thumbColor: Colors.white,
                    thumbBorderColor: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 0),
                  _buildSliderSettingItem(
                    context: context,
                    label: "연결선 두께",
                    value: customSettings.linkWidth,
                    min: 0.5,
                    max: 5,
                    step: 0.1,
                    onChanged: customSettings.setLinkWidth,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    activeTrackColor: primaryColor,
                    inactiveTrackColor: Colors.grey.shade300,
                    thumbColor: Colors.white,
                    thumbBorderColor: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 0),
                  Divider(color: borderColor),
                  const SizedBox(height: 6),

                  // 노드 색상 섹션
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "노드 색상",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: _SidebarStyles.itemSpacing),
                  _buildColorSettingItem(
                    context: context,
                    label: "고립된 노트 (0개)",
                    isNodeColor: true,
                    currentColor: customSettings.isolatedNodeColor,
                    onColorChanged: customSettings.setIsolatedNodeColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: _SidebarStyles.itemSpacing),
                  _buildColorSettingItem(
                    context: context,
                    label: "연결 1-2개",
                    isNodeColor: true,
                    currentColor: customSettings.lowConnectionColor,
                    onColorChanged: customSettings.setLowConnectionColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: _SidebarStyles.itemSpacing),
                  _buildColorSettingItem(
                    context: context,
                    label: "연결 3-5개",
                    isNodeColor: true,
                    currentColor: customSettings.mediumConnectionColor,
                    onColorChanged: customSettings.setMediumConnectionColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: _SidebarStyles.itemSpacing),
                  _buildColorSettingItem(
                    context: context,
                    label: "연결 6개 이상",
                    isNodeColor: true,
                    currentColor: customSettings.highConnectionColor,
                    onColorChanged: customSettings.setHighConnectionColor,
                    textColor: textColor,
                    mutedTextColor: mutedTextColor,
                    borderColor: borderColor,
                    primaryColor: primaryColor,
                    isDarkMode: isDarkMode,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Footer with Reset Button
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _SidebarStyles.horizontalPadding,
              vertical: 16.0,
            ),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.rotate_left, size: 16),
              label: const Text("기본값"),
              onPressed: () {
                customSettings.resetToDefaults(isDarkMode);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
                foregroundColor: textColor,
                side: BorderSide(color: borderColor),
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildSectionTitle(String title, Color? mutedTextColor) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: mutedTextColor,
      ),
    );
  }

  Widget _buildFilterRadioItem(
    BuildContext context,
    ThemeData theme,
    GraphViewModel viewModel,
    String title,
    GraphFilterMode mode,
  ) {
    final bool isSelected = viewModel.filterMode == mode;
    final bool isDisabled = viewModel.isLoading;
    final Color? textColor = theme.textTheme.bodyLarge?.color;
    final Color? mutedTextColor = theme.textTheme.bodyMedium?.color
        ?.withOpacity(0.65);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => viewModel.setFilterMode(mode),
        borderRadius: BorderRadius.circular(4.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Radio<GraphFilterMode>(
                  value: mode,
                  groupValue: viewModel.filterMode,
                  onChanged:
                      isDisabled
                          ? null
                          : (GraphFilterMode? value) {
                            if (value != null) viewModel.setFilterMode(value);
                          },
                  activeColor: theme.primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color:
                      isDisabled
                          ? mutedTextColor
                          : (isSelected ? theme.primaryColor : textColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSliderSettingItem({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
    Color? textColor,
    Color? mutedTextColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? thumbColor,
    Color? thumbBorderColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'monospace',
                color: mutedTextColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4.0,
            activeTrackColor: activeTrackColor,
            inactiveTrackColor: inactiveTrackColor,
            thumbColor: thumbColor,
            overlayColor: activeTrackColor?.withOpacity(0.2),
            thumbShape: _CustomThumbShape(
              borderColor: thumbBorderColor,
              radius: 7.0,
            ),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: step > 0 ? ((max - min) / step).round() : null,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // --- ✨ 수정: 심플한 Color Picker UI (팔레트 제거) ---
  Widget _buildColorSettingItem({
    required BuildContext context,
    required String label,
    required Color currentColor,
    required ValueChanged<Color> onColorChanged,
    bool isNodeColor = false,
    Color? textColor,
    Color? mutedTextColor,
    required Color borderColor,
    required Color primaryColor,
    required bool isDarkMode,
  }) {
    final hexController = TextEditingController(
      text:
          '#${currentColor.value.toRadixString(16).substring(2).toUpperCase()}',
    );
    hexController.selection = TextSelection.fromPosition(
      TextPosition(offset: hexController.text.length),
    );

    void handleHexInputChange(String value) {
      String hex = value.startsWith('#') ? value.substring(1) : value;
      if (hex.length == 6) {
        try {
          final colorInt = int.tryParse('FF$hex', radix: 16);
          if (colorInt != null) {
            final newColor = Color(colorInt);
            if (newColor.value != currentColor.value) onColorChanged(newColor);
          }
        } catch (e) {
          /* 무시 */
        }
      }
    }

    final labelStyle =
        isNodeColor
            ? TextStyle(fontSize: 12, color: mutedTextColor)
            : TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: textColor,
            );
    final double spacingAfterLabel =
        isNodeColor ? 6.0 : _SidebarStyles.labelBottomSpacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        SizedBox(height: spacingAfterLabel),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: _SidebarStyles.colorPreviewSize,
              height: _SidebarStyles.colorPreviewSize,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(6.0),
                border: Border.all(color: borderColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: _SidebarStyles.inputHeight,
                child: TextField(
                  controller: hexController,
                  onSubmitted: handleHexInputChange,
                  maxLength: 7,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^#?[0-9a-fA-F]{0,6}'),
                    ),
                    TextInputFormatter.withFunction(
                      (oldValue, newValue) => TextEditingValue(
                        text: newValue.text.toUpperCase(),
                        selection: newValue.selection,
                      ),
                    ),
                  ],
                  decoration: InputDecoration(
                    counterText: "",
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6.0),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6.0),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6.0),
                      borderSide: BorderSide(color: primaryColor, width: 1.5),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Custom Thumb Shape
class _CustomThumbShape extends SliderComponentShape {
  final Color? borderColor;
  final double borderWidth;
  final double radius;
  _CustomThumbShape({
    this.borderColor,
    this.borderWidth = 1.0,
    this.radius = 7.0,
  });
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    final ColorTween colorTween = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor ?? Colors.white,
    );
    final Color color = colorTween.evaluate(enableAnimation)!;
    final size = getPreferredSize(enableAnimation.value > 0, isDiscrete);
    canvas.drawCircle(center, size.width / 2, Paint()..color = color);
    if (borderColor != null) {
      canvas.drawCircle(
        center,
        size.width / 2,
        Paint()
          ..color = borderColor!
          ..strokeWidth = borderWidth
          ..style = PaintingStyle.stroke,
      );
    }
  }
}
