import '../app/school_directory.dart';
import '../domain/phone.dart';

/// دليل مدارس وهمي للاختبارات: قائمة مُعلنة، وطاقم كل رقم، وعطل اختياري.
class FakeSchoolDirectory implements SchoolDirectory {
  FakeSchoolDirectory({
    this.schools = const [],
    Map<String, List<DirectorySchool>> staff = const {},
    this.failure,
  }) : staff = {
         for (final entry in staff.entries)
           PhoneNumbers.normalize(entry.key): entry.value,
       };

  /// المدارس المُعلنة.
  List<DirectorySchool> schools;

  /// مدارس طاقم كل رقم هاتف (بصيغة محلية).
  Map<String, List<DirectorySchool>> staff;

  /// إن وُجد يرميه كل استدعاء كأن الاتصال تعذّر.
  DirectoryFailure? failure;

  int listCalls = 0;
  final List<String> resolved = [];

  @override
  Future<List<DirectorySchool>> listSchools() async {
    listCalls++;
    final failed = failure;
    if (failed != null) throw DirectoryException(failed);
    return schools;
  }

  @override
  Future<List<DirectorySchool>> resolveByPhone(String phone) async {
    resolved.add(phone);
    final failed = failure;
    if (failed != null) throw DirectoryException(failed);
    return staff[PhoneNumbers.normalize(phone)] ?? const [];
  }
}
