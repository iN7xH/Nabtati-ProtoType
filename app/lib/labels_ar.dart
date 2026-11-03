// labels_ar.dart - Arabic names for the crops and diseases the API returns.
// The API always answers in English keys (e.g. crop "tomato", disease "late_blight");
// the app translates them here for display.

const Map<String, String> cropNamesAr = {
  'tomato': 'بندورة',
  'potato': 'بطاطا',
  'pepper': 'فلفل',
  'cucumber': 'خيار',
};

const Map<String, String> diseaseNamesAr = {
  'healthy': 'سليم',
  'early_blight': 'اللفحة المبكرة',
  'late_blight': 'اللفحة المتأخرة',
  'bacterial_spot': 'التبقع البكتيري',
  'septoria_leaf_spot': 'تبقع الأوراق السبتوري',
  'leaf_mold': 'عفن الأوراق',
  'yellow_leaf_curl_virus': 'فيروس تجعد واصفرار الأوراق',
  'mosaic_virus': 'فيروس الموزاييك',
  'spider_mites': 'العنكبوت الأحمر',
  'target_spot': 'التبقع الهدفي',
  'downy_mildew': 'البياض الزغبي',
  'gummy_stem_blight': 'لفحة الساق الصمغية',
  'anthracnose': 'الأنثراكنوز',
};

/// Arabic name if we have one, otherwise the English key made readable
/// ("new_disease" -> "new disease"), so an unexpected label never breaks the screen.
String cropAr(String key) => cropNamesAr[key] ?? key.replaceAll('_', ' ');

String diseaseAr(String key) => diseaseNamesAr[key] ?? key.replaceAll('_', ' ');
