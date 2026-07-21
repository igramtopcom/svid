import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';
import '../config/brand_config.dart';
import '../constants/app_durations.dart';

/// Design System Theme — brand-aware shape tokens
/// Svid: angular (3px), flat — Nocturne Cinematic
/// VidCombo: rounded (12px cards, pill buttons), subtle elevation — Arctic Command
class AppTheme {
  AppTheme._();

  static ThemeData get lightTheme {
    final textTheme = AppTypography.textTheme;
    final colorScheme = AppColors.lightColorScheme;
    final bc = BrandConfig.current;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.lightBg,
      focusColor: colorScheme.primary.withValues(alpha: AppOpacity.pressed),

      // AppBar — flat, clean
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.lightSurface1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.appBarTitle.copyWith(color: colorScheme.onSurface),
      ),

      // Card — brand radius + elevation + conditional border
      cardTheme: CardThemeData(
        elevation: bc.cardElevation,
        color: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(bc.cardRadius),
          side: bc.hasCardBorder
              ? BorderSide(color: AppColors.lightBorder.withValues(alpha: AppOpacity.overlay))
              : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.lightBorder.withValues(alpha: AppOpacity.overlay),
        thickness: 1,
        space: 1,
      ),

      // Input — brand radius
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurface1,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: AppColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: AppColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        hintStyle: AppTypography.inputHint.copyWith(color: colorScheme.onSurface.withValues(alpha: AppOpacity.medium)),
      ),

      // ElevatedButton — brand radius
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          elevation: 0,
          textStyle: AppTypography.buttonPrimary,
        ),
      ),

      // TextButton — brand radius
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          textStyle: AppTypography.buttonSecondary,
        ),
      ),

      // OutlinedButton — brand radius
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          side: BorderSide(color: AppColors.lightBorder),
          textStyle: AppTypography.buttonSecondary,
        ),
      ),

      // IconButton — brand radius
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // Dialog — brand radius
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        elevation: 4,
      ),

      // Tooltip — brand popup radius
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(bc.popupRadius),
        ),
        textStyle: AppTypography.metadata.copyWith(color: colorScheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: AppDurations.tooltipWaitDuration,
      ),

      // Chip — brand chip radius (pill for VidCombo)
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.chipRadius)),
        side: BorderSide(color: AppColors.lightBorder),
      ),

      // Switch — brand colors
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Checkbox — angular, brand
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Radio — brand
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Slider — brand
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
      ),

      // SegmentedButton — brand radius
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          ),
        ),
      ),

      // TabBar
      tabBarTheme: TabBarThemeData(
        labelStyle: AppTypography.navItemSelected,
        unselectedLabelStyle: AppTypography.navItem,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
      ),

      // ProgressIndicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: AppColors.lightSurface3,
        linearMinHeight: 3,
      ),

      // Scrollbar — brand popup radius
      scrollbarTheme: ScrollbarThemeData(
        radius: Radius.circular(bc.popupRadius),
        thickness: WidgetStateProperty.all(6),
        thumbColor: WidgetStateProperty.all(AppColors.lightBorder),
      ),

      // PopupMenu — brand popup radius
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(bc.popupRadius),
          side: BorderSide(color: AppColors.lightBorder.withValues(alpha: AppOpacity.overlay)),
        ),
        elevation: 4,
      ),

      // DropdownMenu — brand input + popup radius
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(bc.inputRadius),
            borderSide: BorderSide(color: AppColors.lightBorder),
          ),
        ),
        menuStyle: MenuStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bc.popupRadius),
              side: BorderSide(color: AppColors.lightBorder.withValues(alpha: AppOpacity.overlay)),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(AppColors.lightSurface1),
          elevation: WidgetStateProperty.all(4),
        ),
      ),

      // Menu — context menus, brand popup radius
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bc.popupRadius),
              side: BorderSide(color: AppColors.lightBorder.withValues(alpha: AppOpacity.overlay)),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(AppColors.lightSurface1),
          elevation: WidgetStateProperty.all(4),
        ),
      ),

      // BottomSheet — brand card radius
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(bc.cardRadius)),
        ),
      ),

      // DatePicker — brand dialog radius
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        headerBackgroundColor: colorScheme.primary,
        headerForegroundColor: colorScheme.onPrimary,
        dayShape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // TimePicker — brand dialog radius
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.lightSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
      ),

      // FilledButton — brand radius
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // FAB — brand button radius
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
      ),

      // SnackBar — brand card radius
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(bc.cardRadius)),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Badge — brand
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.primary,
        textColor: colorScheme.onPrimary,
      ),

      // MaterialBanner
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: AppColors.lightSurface1,
      ),
    );
  }

  static ThemeData get darkTheme {
    final textTheme = AppTypography.textTheme;
    final colorScheme = AppColors.darkColorScheme;
    final bc = BrandConfig.current;

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.darkBg,
      focusColor: colorScheme.primary.withValues(alpha: AppOpacity.pressed),

      // AppBar
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.darkSurface1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.appBarTitle.copyWith(color: colorScheme.onSurface),
      ),

      // Card — brand radius + elevation + conditional border
      cardTheme: CardThemeData(
        elevation: bc.cardElevation,
        color: AppColors.darkSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(bc.cardRadius),
          side: bc.hasCardBorder
              ? BorderSide(color: AppColors.darkBorder.withValues(alpha: AppOpacity.overlay))
              : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: AppColors.darkBorder.withValues(alpha: AppOpacity.overlay),
        thickness: 1,
        space: 1,
      ),

      // Input — brand radius
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(bc.inputRadius),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        hintStyle: AppTypography.inputHint.copyWith(color: colorScheme.onSurface.withValues(alpha: AppOpacity.scrim)),
      ),

      // ElevatedButton — brand radius
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          elevation: 0,
          textStyle: AppTypography.buttonPrimary,
        ),
      ),

      // TextButton — brand radius
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          textStyle: AppTypography.buttonSecondary,
        ),
      ),

      // OutlinedButton — brand radius
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          side: BorderSide(color: AppColors.darkBorder),
          textStyle: AppTypography.buttonSecondary,
        ),
      ),

      // IconButton — brand radius
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // Dialog — brand radius
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        elevation: 4,
      ),

      // Tooltip — brand popup radius
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(bc.popupRadius),
        ),
        textStyle: AppTypography.metadata.copyWith(color: colorScheme.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: AppDurations.tooltipWaitDuration,
      ),

      // Chip — brand chip radius (pill for VidCombo)
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.chipRadius)),
        side: BorderSide(color: AppColors.darkBorder),
      ),

      // Switch — crimson active
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Checkbox — angular, crimson
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Radio — crimson
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? colorScheme.primary : null),
      ),

      // Slider — crimson
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        thumbColor: colorScheme.primary,
      ),

      // SegmentedButton — brand radius
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
          ),
        ),
      ),

      // TabBar
      tabBarTheme: TabBarThemeData(
        labelStyle: AppTypography.navItemSelected,
        unselectedLabelStyle: AppTypography.navItem,
        indicatorSize: TabBarIndicatorSize.label,
        dividerHeight: 0,
      ),

      // ProgressIndicator
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: AppColors.darkSurface3,
        linearMinHeight: 3,
      ),

      // Scrollbar — brand popup radius
      scrollbarTheme: ScrollbarThemeData(
        radius: Radius.circular(bc.popupRadius),
        thickness: WidgetStateProperty.all(6),
        thumbColor: WidgetStateProperty.all(AppColors.darkBorder),
      ),

      // PopupMenu — brand popup radius
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.darkSurface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(bc.popupRadius),
          side: BorderSide(color: AppColors.darkBorder.withValues(alpha: AppOpacity.overlay)),
        ),
        elevation: 4,
      ),

      // DropdownMenu — brand input + popup radius
      dropdownMenuTheme: DropdownMenuThemeData(
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(bc.inputRadius),
            borderSide: BorderSide(color: AppColors.darkBorder),
          ),
        ),
        menuStyle: MenuStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bc.popupRadius),
              side: BorderSide(color: AppColors.darkBorder.withValues(alpha: AppOpacity.overlay)),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(AppColors.darkSurface2),
          elevation: WidgetStateProperty.all(4),
        ),
      ),

      // Menu — context menus, brand popup radius
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(bc.popupRadius),
              side: BorderSide(color: AppColors.darkBorder.withValues(alpha: AppOpacity.overlay)),
            ),
          ),
          backgroundColor: WidgetStateProperty.all(AppColors.darkSurface2),
          elevation: WidgetStateProperty.all(4),
        ),
      ),

      // BottomSheet — brand card radius
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(bc.cardRadius)),
        ),
      ),

      // DatePicker — brand dialog radius
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.darkSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        headerBackgroundColor: colorScheme.primary,
        headerForegroundColor: colorScheme.onPrimary,
        dayShape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // TimePicker — brand dialog radius
      timePickerTheme: TimePickerThemeData(
        backgroundColor: AppColors.darkSurface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        hourMinuteShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
        dayPeriodShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.dialogRadius)),
      ),

      // FilledButton — brand radius
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(80, 40),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        ),
      ),

      // FAB — brand button radius
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(bc.buttonRadius)),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        elevation: 2,
      ),

      // SnackBar — brand card radius
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(bc.cardRadius)),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // Badge — brand
      badgeTheme: BadgeThemeData(
        backgroundColor: colorScheme.primary,
        textColor: colorScheme.onPrimary,
      ),

      // MaterialBanner
      bannerTheme: MaterialBannerThemeData(
        backgroundColor: AppColors.darkSurface1,
      ),
    );
  }
}
