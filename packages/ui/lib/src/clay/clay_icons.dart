import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

/// أيقونات النظام: المستديرة السميكة (`_rounded`) من Material، بأسماء
/// تدل على معناها في المدرسة، فتبقى متسقة في التطبيقات الثلاثة.
abstract final class ClayIcons {
  // التنقل
  static const IconData home = Icons.home_rounded;
  static const IconData more = Icons.grid_view_rounded;
  static const IconData back = Icons.arrow_forward_rounded;
  static const IconData notifications = Icons.notifications_rounded;
  static const IconData settings = Icons.settings_rounded;

  // الأشخاص
  static const IconData students = Icons.school_rounded;
  static const IconData teachers = Icons.person_rounded;
  static const IconData parents = Icons.family_restroom_rounded;
  static const IconData workers = Icons.badge_rounded;

  // الدراسة
  static const IconData groups = Icons.groups_rounded;
  static const IconData subjects = Icons.menu_book_rounded;
  static const IconData rooms = Icons.meeting_room_rounded;
  static const IconData schedule = Icons.calendar_month_rounded;
  static const IconData attendance = Icons.fact_check_rounded;
  static const IconData waiting = Icons.hourglass_bottom_rounded;
  static const IconData grades = Icons.grade_rounded;
  static const IconData files = Icons.folder_rounded;

  // المال
  static const IconData payments = Icons.payments_rounded;
  static const IconData receipt = Icons.receipt_long_rounded;
  static const IconData expenses = Icons.shopping_bag_rounded;
  static const IconData dues = Icons.account_balance_wallet_rounded;
  static const IconData transport = Icons.directions_bus_rounded;

  // التواصل
  static const IconData chat = Icons.chat_bubble_rounded;
  static const IconData sms = Icons.sms_rounded;
  static const IconData assistant = Icons.auto_awesome_rounded;

  // الإجراءات
  static const IconData add = Icons.add_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData delete = Icons.delete_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData scan = Icons.qr_code_scanner_rounded;
  static const IconData qr = Icons.qr_code_2_rounded;
  static const IconData camera = Icons.photo_camera_rounded;
  static const IconData print = Icons.print_rounded;
  static const IconData share = Icons.ios_share_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData stats = Icons.bar_chart_rounded;
  static const IconData backup = Icons.cloud_upload_rounded;
  static const IconData audit = Icons.history_rounded;
}
